package main

import (
	"bytes"
	"compress/gzip"
	"context"
	"crypto/rand"
	"encoding/binary"
	"encoding/json"
	"errors"
	"fmt"
	"io"
	"net/http"
	"strings"
	"time"

	"github.com/coder/websocket"
)

// Voice input (docs/config.md, `voice`): the engines the input method
// streams speech to. The input method records and recognizes; Settings
// edits the engines and tests one: a second of silence sent with its
// credentials shows whether the service takes them.

const (
	defaultResourceID = "volc.seedasr.sauc.duration"
	volcengineURL     = "wss://openspeech.bytedance.com/api/v3/sauc/bigmodel_async"
)

// voiceEngine is one entry of `voice.engines`, read the way the input
// method reads it: a missing or mistyped field is empty.
type voiceEngine struct {
	name, kind, apiKey, appID, accessToken, resourceID string
}

func voiceEngineOf(m map[string]any) voiceEngine {
	text := func(key string) string {
		s, _ := m[key].(string)
		return strings.TrimSpace(s)
	}
	e := voiceEngine{name: text("name"), kind: strings.ToLower(text("type")), apiKey: text("apiKey"),
		appID: text("appId"), accessToken: text("accessToken"), resourceID: text("resourceId")}
	if e.kind == "" {
		e.kind = "volcengine"
	}
	if e.resourceID == "" {
		e.resourceID = defaultResourceID
	}
	return e
}

// configured: an engine of a known type with credentials.
func (e voiceEngine) configured() bool {
	return e.kind == "volcengine" && (e.apiKey != "" || (e.appID != "" && e.accessToken != ""))
}

// headers are the handshake's: the new console's API key, else the old
// console's App ID and Access Token, the resource, and a fresh id.
func (e voiceEngine) headers(connectID string) http.Header {
	h := http.Header{}
	h.Set("X-Api-Resource-Id", e.resourceID)
	h.Set("X-Api-Connect-Id", connectID)
	h.Set("X-Api-Request-Id", connectID)
	if e.apiKey != "" {
		h.Set("X-Api-Key", e.apiKey)
	} else {
		h.Set("X-Api-App-Key", e.appID)
		h.Set("X-Api-Access-Key", e.accessToken)
	}
	return h
}

// The binary frames of 豆包流式语音识别: a 4-byte header (version and size,
// type and flags, serialization and compression, reserved), big-endian
// sizes, then the payload. Requests go uncompressed.

func frame(header [4]byte, payload []byte) []byte {
	b := append(header[:], 0, 0, 0, 0)
	binary.BigEndian.PutUint32(b[4:], uint32(len(payload)))
	return append(b, payload...)
}

func clientRequestFrame(payload []byte) []byte {
	return frame([4]byte{0x11, 0x10, 0x10, 0x00}, payload)
}

func audioFrame(pcm []byte, last bool) []byte {
	flags := byte(0x20)
	if last {
		flags = 0x22
	}
	return frame([4]byte{0x11, flags, 0x00, 0x00}, pcm)
}

// serverMessage is a reply: a result (last once final) or an error.
type serverMessage struct {
	last      bool
	payload   []byte
	isError   bool
	errorCode uint32
	errorText string
}

var errTruncated = errors.New("truncated frame")

func parseServerFrame(b []byte) (serverMessage, error) {
	if len(b) < 4 {
		return serverMessage{}, errTruncated
	}
	at := int(b[0]&0x0F) * 4
	kind, flags, compression := b[1]>>4, b[1]&0x0F, b[2]&0x0F
	word := func() (uint32, error) {
		if at+4 > len(b) {
			return 0, errTruncated
		}
		at += 4
		return binary.BigEndian.Uint32(b[at-4 : at]), nil
	}
	switch kind {
	case 0b1001:
		if flags&0b0001 != 0 {
			if _, err := word(); err != nil { // the sequence number
				return serverMessage{}, err
			}
		}
		size, err := word()
		if err != nil || at+int(size) > len(b) {
			return serverMessage{}, errTruncated
		}
		payload := b[at : at+int(size)]
		if compression == 1 {
			r, err := gzip.NewReader(bytes.NewReader(payload))
			if err != nil {
				return serverMessage{}, err
			}
			if payload, err = io.ReadAll(r); err != nil {
				return serverMessage{}, err
			}
		}
		return serverMessage{last: flags&0b0010 != 0, payload: payload}, nil
	case 0b1111:
		code, err := word()
		if err != nil {
			return serverMessage{}, err
		}
		size, err := word()
		if err != nil || at+int(size) > len(b) {
			return serverMessage{}, errTruncated
		}
		return serverMessage{isError: true, errorCode: code, errorText: string(b[at : at+int(size)])}, nil
	}
	return serverMessage{}, fmt.Errorf("unknown message type %d", kind)
}

// voiceRequest is the input method's request without hotwords: PCM at
// 16 kHz, the two-pass mode, punctuation and numbers as digits.
func voiceRequest() []byte {
	b, _ := json.Marshal(map[string]any{
		"user":  map[string]any{"uid": "fluent"},
		"audio": map[string]any{"format": "pcm", "codec": "raw", "rate": 16000, "bits": 16, "channel": 1},
		"request": map[string]any{"model_name": "bigmodel", "enable_nonstream": true, "enable_itn": true,
			"enable_punc": true, "result_type": "full"},
	})
	return b
}

func newID() string {
	b := make([]byte, 16)
	rand.Read(b)
	return fmt.Sprintf("%x-%x-%x-%x-%x", b[0:4], b[4:6], b[6:8], b[8:10], b[10:])
}

// emptyAudio is the service's code for audio with no speech in it: the
// credentials were taken.
const emptyAudio = 45000002

// testVoice sends one second of silence with the engine's credentials.
func testVoice(ctx context.Context, e voiceEngine) object {
	if !e.configured() {
		return object{"ok": false, "code": "notConfigured", "error": ""}
	}
	ctx, cancel := context.WithTimeout(ctx, 15*time.Second)
	defer cancel()
	started := time.Now()
	conn, resp, err := websocket.Dial(ctx, volcengineURL, &websocket.DialOptions{HTTPHeader: e.headers(newID())})
	logID := ""
	if resp != nil {
		logID = resp.Header.Get("X-Tt-Logid")
	}
	failed := func(message string) object {
		return object{"ok": false, "error": message, "logid": logID}
	}
	if err != nil {
		if resp != nil && resp.StatusCode != http.StatusSwitchingProtocols {
			body, _ := io.ReadAll(io.LimitReader(resp.Body, 300))
			return failed(strings.TrimSpace(fmt.Sprintf("HTTP %d %s", resp.StatusCode, body)))
		}
		return failed(err.Error())
	}
	defer conn.CloseNow()
	conn.SetReadLimit(1 << 20)
	silence := make([]byte, 6400) // 200 ms
	frames := [][]byte{clientRequestFrame(voiceRequest())}
	for i := 0; i < 5; i++ {
		frames = append(frames, audioFrame(silence, i == 4))
	}
	for _, f := range frames {
		if err := conn.Write(ctx, websocket.MessageBinary, f); err != nil {
			return failed(err.Error())
		}
	}
	for {
		_, data, err := conn.Read(ctx)
		if err != nil {
			return failed(err.Error())
		}
		msg, err := parseServerFrame(data)
		if err != nil {
			return failed(err.Error())
		}
		if msg.isError && msg.errorCode != emptyAudio {
			return failed(fmt.Sprintf("%d %s", msg.errorCode, msg.errorText))
		}
		if msg.isError || msg.last {
			conn.Close(websocket.StatusNormalClosure, "")
			return object{"ok": true, "ms": time.Since(started).Milliseconds(), "logid": logID}
		}
	}
}
