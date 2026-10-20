package main

import (
	"bufio"
	"bytes"
	"context"
	"encoding/json"
	"errors"
	"fmt"
	"io"
	"math"
	"net"
	"net/http"
	"net/url"
	"strings"
	"sync/atomic"
	"time"
)

// The Test and Try buttons: one small request, the way the input method
// makes its own (an OpenAI Responses or Chat Completions endpoint,
// streamed), so a working test means a working input method.

const (
	testInput        = "helo wrld"
	testInstructions = "Fix grammar, spelling and punctuation only, keeping the wording. " +
		"Reply with the corrected text and nothing else."
	// codexVersion is the Codex CLI version some gateways are told.
	codexVersion = "0.152.1"
)

// endpoint is one LLM provider (docs/config.md) and how long its reply
// may stay silent.
type endpoint struct {
	name                           string
	api                            string // "responses" or "chat"
	baseURL, apiKey, model, effort string
	timeout                        time.Duration
}

// configured: the provider has a real API key.
func (e endpoint) configured() bool {
	return e.baseURL != "" && e.model != "" && e.apiKey != "" && e.apiKey != placeholderKey
}

// endpointOf reads one entry of `providers`, or the top level of a config
// from before them (which has no name and speaks the Responses API). Pasted
// values often bring a stray space or newline along; a wrong type reads as
// empty.
func endpointOf(m map[string]any, entry bool) endpoint {
	text := func(key string) string {
		s, _ := m[key].(string)
		return strings.TrimSpace(s)
	}
	e := endpoint{api: "responses", baseURL: text("baseURL"), apiKey: text("apiKey"), model: text("model"),
		timeout: 10 * time.Second}
	e.effort, _ = m["reasoningEffort"].(string)
	if entry {
		e.name = text("name")
		if strings.ToLower(text("api")) == "chat" {
			e.api = "chat"
		}
	}
	return e
}

// providers are the entries of `providers` that are objects.
func providers(object map[string]any) []endpoint {
	list, _ := object["providers"].([]any)
	var out []endpoint
	for _, v := range list {
		if m, ok := v.(map[string]any); ok {
			out = append(out, endpointOf(m, true))
		}
	}
	return out
}

// activeEndpoint is the provider in use: the one `provider` names, else the
// first; with no providers, the top-level keys.
func activeEndpoint(object map[string]any) endpoint {
	list := providers(object)
	if len(list) == 0 {
		return endpointOf(object, false)
	}
	if name, ok := object["provider"].(string); ok {
		for _, e := range list {
			if e.name == strings.TrimSpace(name) {
				return e
			}
		}
	}
	return list[0]
}

// timeoutOf is the config's timeoutSeconds, clamped; a wrong type leaves
// the default.
func timeoutOf(object map[string]any) time.Duration {
	if f, ok := object["timeoutSeconds"].(float64); ok && !math.IsInf(f, 0) {
		return time.Duration(min(max(f, 1), 300) * float64(time.Second))
	}
	return 10 * time.Second
}

// endpointFrom is the provider in use in the config file.
func endpointFrom(data []byte) endpoint {
	var object map[string]any
	json.Unmarshal(data, &object)
	e := activeEndpoint(object)
	e.timeout = timeoutOf(object)
	return e
}

// identifiesAsCodex: some gateways admit GPT models to the Responses API
// only from coding agents they know; other providers must not be told.
func identifiesAsCodex(model string) bool {
	m := strings.ToLower(model)
	return strings.HasPrefix(m, "gpt") || strings.Contains(m, "codex")
}

// rewrite sends input with instructions and returns the reply's text, or
// the error worded as the candidate bar would put it.
func rewrite(ctx context.Context, e endpoint, instructions, input string) (string, error) {
	base := strings.TrimRight(e.baseURL, "/")
	path := "/responses"
	body := map[string]any{"model": e.model, "stream": true}
	if e.api == "chat" {
		path = "/chat/completions"
		body["messages"] = []map[string]string{
			{"role": "system", "content": instructions}, {"role": "user", "content": input}}
		if e.effort != "" {
			body["reasoning_effort"] = e.effort
		}
	} else {
		body["instructions"], body["input"] = instructions, input
		if e.effort != "" {
			body["reasoning"] = map[string]any{"effort": e.effort}
		}
	}
	if u, err := url.Parse(base + path); err != nil || u.Scheme == "" || u.Host == "" {
		return "", fmt.Errorf("Invalid base URL: %s", e.baseURL)
	}
	payload, _ := json.Marshal(body)

	// Silence, not length, times out: the clock restarts with every read.
	ctx, cancel := context.WithCancel(ctx)
	defer cancel()
	var silent atomic.Bool
	watchdog := time.AfterFunc(e.timeout, func() { silent.Store(true); cancel() })
	defer watchdog.Stop()
	heard := func() { watchdog.Reset(e.timeout) }

	req, _ := http.NewRequestWithContext(ctx, http.MethodPost, base+path, bytes.NewReader(payload))
	req.Header.Set("Content-Type", "application/json")
	req.Header.Set("Accept", "text/event-stream")
	req.Header.Set("Authorization", "Bearer "+e.apiKey)
	if e.api != "chat" && identifiesAsCodex(e.model) {
		req.Header.Set("originator", "codex_cli_rs")
		req.Header.Set("User-Agent", "codex_cli_rs/"+codexVersion)
	}
	res, err := http.DefaultClient.Do(req)
	if err != nil {
		return "", humanize(err, silent.Load())
	}
	defer res.Body.Close()
	heard()
	if res.StatusCode < 200 || res.StatusCode > 299 {
		raw, _ := io.ReadAll(io.LimitReader(res.Body, 2000))
		message := errorMessage(raw)
		if r := []rune(message); len(r) > 200 {
			message = string(r[:200])
		}
		if message == "" {
			return "", fmt.Errorf("HTTP %d", res.StatusCode)
		}
		return "", fmt.Errorf("HTTP %d: %s", res.StatusCode, message)
	}
	text, err := readStream(res.Body, heard, e.api)
	if err != nil {
		return "", humanize(err, silent.Load())
	}
	return text, nil
}

// readStream reads a Responses or Chat Completions event stream to its end:
// the output text, or the error it reports. A stream that stops before
// saying it is finished (a proxy's timeout, a dropped connection) is an
// error, never half a reply.
func readStream(r io.Reader, heard func(), api string) (string, error) {
	lines := bufio.NewScanner(r)
	lines.Buffer(make([]byte, 64*1024), 4*1024*1024)
	lines.Split(scanSSELines)
	var event string
	var data []string
	var text strings.Builder
	deltas := false
	for lines.Scan() {
		heard()
		line := lines.Text()
		if line != "" {
			field, value, _ := strings.Cut(line, ":")
			value = strings.TrimPrefix(value, " ")
			switch field {
			case "event":
				event = value
			case "data":
				data = append(data, value)
			}
			continue
		}
		if len(data) == 0 && event == "" {
			continue
		}
		payload := strings.TrimSpace(strings.Join(data, "\n"))
		name := event
		event, data = "", nil
		if payload == "[DONE]" {
			return text.String(), nil
		}
		var obj map[string]any
		if json.Unmarshal([]byte(payload), &obj) != nil {
			continue
		}
		if api == "chat" {
			if done, err := chatChunk(obj, &text); done || err != nil {
				return text.String(), err
			}
			continue
		}
		kind, _ := obj["type"].(string)
		if kind == "" {
			kind = name
		}
		switch kind {
		case "response.output_text.delta":
			if d, _ := obj["delta"].(string); d != "" {
				deltas = true
				text.WriteString(d)
			}
		case "response.output_text.done":
			// the whole text, for providers that send no deltas
			if full, _ := obj["text"].(string); !deltas {
				text.WriteString(full)
			}
			return text.String(), nil
		case "response.completed":
			return text.String(), nil
		case "response.incomplete":
			response, _ := obj["response"].(map[string]any)
			details, _ := response["incomplete_details"].(map[string]any)
			if reason, ok := details["reason"].(string); ok {
				return "", errors.New("reply incomplete: " + reason)
			}
			return "", errors.New("reply incomplete")
		case "response.failed", "response.error", "error":
			return "", errors.New(eventError(obj))
		}
	}
	if err := lines.Err(); err != nil {
		return "", err
	}
	return "", errors.New("reply cut off")
}

// chatChunk adds a Chat Completions chunk's `choices[0].delta.content` to
// text; done once a chunk has a `finish_reason`. Reasoning text
// (`reasoning_content`) is not part of the reply.
func chatChunk(obj map[string]any, text *strings.Builder) (done bool, err error) {
	if _, ok := obj["error"]; ok {
		return false, errors.New(eventError(obj))
	}
	choices, _ := obj["choices"].([]any)
	if len(choices) == 0 {
		return false, nil
	}
	choice, _ := choices[0].(map[string]any)
	delta, _ := choice["delta"].(map[string]any)
	content, _ := delta["content"].(string)
	text.WriteString(content)
	switch reason, _ := choice["finish_reason"].(string); reason {
	case "":
		return false, nil
	case "length", "content_filter":
		return false, errors.New("reply incomplete: " + reason)
	}
	return true, nil
}

// scanSSELines splits at LF, CRLF or a lone CR, as server-sent events allow.
func scanSSELines(data []byte, atEOF bool) (int, []byte, error) {
	for i, b := range data {
		switch b {
		case '\n':
			return i + 1, data[:i], nil
		case '\r':
			if i+1 == len(data) && !atEOF {
				return 0, nil, nil // a CRLF split across reads
			}
			if i+1 < len(data) && data[i+1] == '\n' {
				return i + 2, data[:i], nil
			}
			return i + 1, data[:i], nil
		}
	}
	if atEOF && len(data) > 0 {
		return len(data), data, nil
	}
	return 0, nil, nil
}

func eventError(obj map[string]any) string {
	if e, ok := obj["error"].(map[string]any); ok {
		if m, ok := e["message"].(string); ok {
			return m
		}
	}
	if m, ok := obj["message"].(string); ok {
		return m
	}
	if r, ok := obj["response"].(map[string]any); ok {
		if e, ok := r["error"].(map[string]any); ok {
			if m, ok := e["message"].(string); ok {
				return m
			}
		}
	}
	return "API error"
}

// errorMessage is the `error.message` of a JSON error body, else the body.
func errorMessage(body []byte) string {
	var obj map[string]any
	if json.Unmarshal(body, &obj) == nil {
		if e, ok := obj["error"].(map[string]any); ok {
			if m, ok := e["message"].(string); ok {
				return m
			}
		}
		if s, ok := obj["error"].(string); ok {
			return s
		}
		if s, ok := obj["message"].(string); ok {
			return s
		}
	}
	return strings.TrimSpace(string(body))
}

// humanize words a network error as the candidate bar does.
func humanize(err error, silent bool) error {
	var dns *net.DNSError
	var op *net.OpError
	switch {
	case silent:
		return errors.New("timed out")
	case errors.As(err, &dns), errors.As(err, &op) && op.Op == "dial":
		return errors.New("offline")
	}
	var u *url.Error
	if errors.As(err, &u) {
		return u.Err
	}
	return err
}
