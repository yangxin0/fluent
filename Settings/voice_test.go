package main

import (
	"bytes"
	"compress/gzip"
	"encoding/binary"
	"encoding/json"
	"testing"
)

func TestVoiceEngineReadsLikeTheInputMethod(t *testing.T) {
	e := voiceEngineOf(map[string]any{"name": " Doubao ", "apiKey": " k ", "resourceId": 3})
	if e.name != "Doubao" || e.kind != "volcengine" || e.apiKey != "k" || e.resourceID != defaultResourceID || !e.configured() {
		t.Errorf("got %+v", e)
	}
	old := voiceEngineOf(map[string]any{"type": "Volcengine", "appId": "1", "accessToken": "t"})
	if !old.configured() {
		t.Errorf("the old console's pair: %+v", old)
	}
	if voiceEngineOf(map[string]any{"type": "whisper", "apiKey": "k"}).configured() {
		t.Error("an unknown type is not set up")
	}
	if voiceEngineOf(map[string]any{"appId": "1"}).configured() {
		t.Error("an App ID alone is not set up")
	}
	if voiceEngineOf(nil).configured() {
		t.Error("nothing is not set up")
	}
}

func TestVoiceHeaders(t *testing.T) {
	h := voiceEngineOf(map[string]any{"apiKey": "k"}).headers("id")
	if h.Get("X-Api-Key") != "k" || h.Get("X-Api-App-Key") != "" || h.Get("X-Api-Resource-Id") != defaultResourceID || h.Get("X-Api-Connect-Id") != "id" {
		t.Errorf("API key: %v", h)
	}
	h = voiceEngineOf(map[string]any{"appId": "1", "accessToken": "t"}).headers("id")
	if h.Get("X-Api-App-Key") != "1" || h.Get("X-Api-Access-Key") != "t" || h.Get("X-Api-Key") != "" {
		t.Errorf("App ID and token: %v", h)
	}
}

func TestClientFrames(t *testing.T) {
	if got := clientRequestFrame([]byte("{}")); !bytes.Equal(got, []byte{0x11, 0x10, 0x10, 0x00, 0, 0, 0, 2, '{', '}'}) {
		t.Errorf("request: % x", got)
	}
	if got := audioFrame([]byte{1, 2}, false); !bytes.Equal(got, []byte{0x11, 0x20, 0, 0, 0, 0, 0, 2, 1, 2}) {
		t.Errorf("audio: % x", got)
	}
	if got := audioFrame(nil, true); !bytes.Equal(got, []byte{0x11, 0x22, 0, 0, 0, 0, 0, 0}) {
		t.Errorf("last: % x", got)
	}
}

func serverFrame(flags byte, sequence bool, compression byte, payload []byte) []byte {
	b := []byte{0x11, 0x90 | flags, 0x10 | compression, 0}
	if sequence {
		b = binary.BigEndian.AppendUint32(b, 7)
	}
	b = binary.BigEndian.AppendUint32(b, uint32(len(payload)))
	return append(b, payload...)
}

func TestServerFrames(t *testing.T) {
	msg, err := parseServerFrame(serverFrame(0b0001, true, 0, []byte(`{"result":{"text":"你好"}}`)))
	if err != nil || msg.last || msg.isError || string(msg.payload) != `{"result":{"text":"你好"}}` {
		t.Errorf("partial: %+v %v", msg, err)
	}
	if msg, err := parseServerFrame(serverFrame(0b0011, true, 0, []byte(`{}`))); err != nil || !msg.last {
		t.Errorf("final: %+v %v", msg, err)
	}
	var zipped bytes.Buffer
	w := gzip.NewWriter(&zipped)
	w.Write([]byte(`{"result":{"text":"ok"}}`))
	w.Close()
	if msg, err := parseServerFrame(serverFrame(0b0001, true, 1, zipped.Bytes())); err != nil || string(msg.payload) != `{"result":{"text":"ok"}}` {
		t.Errorf("gzip: %+v %v", msg, err)
	}
	e := binary.BigEndian.AppendUint32([]byte{0x11, 0xF0, 0x10, 0}, 45000001)
	e = binary.BigEndian.AppendUint32(e, 3)
	e = append(e, "bad"...)
	if msg, err := parseServerFrame(e); err != nil || !msg.isError || msg.errorCode != 45000001 || msg.errorText != "bad" {
		t.Errorf("error: %+v %v", msg, err)
	}
	if _, err := parseServerFrame([]byte{0x11, 0x91}); err == nil {
		t.Error("a truncated frame")
	}
	if _, err := parseServerFrame(serverFrame(0b0001, true, 0, []byte(`{}`))[:10]); err == nil {
		t.Error("a truncated payload")
	}
}

func TestVoiceRequestIsTheInputMethods(t *testing.T) {
	var request map[string]map[string]any
	if err := json.Unmarshal(voiceRequest(), &request); err != nil {
		t.Fatal(err)
	}
	if request["audio"]["format"] != "pcm" || request["audio"]["rate"] != 16000.0 || request["request"]["model_name"] != "bigmodel" || request["request"]["enable_nonstream"] != true {
		t.Errorf("got %v", request)
	}
}

func TestTestingAnEngineWithoutCredentials(t *testing.T) {
	if got := testVoice(t.Context(), voiceEngineOf(map[string]any{"name": "x"})); got["code"] != "notConfigured" {
		t.Errorf("got %v", got)
	}
}
