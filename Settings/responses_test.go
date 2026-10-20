package main

import (
	"context"
	"encoding/json"
	"fmt"
	"io"
	"net/http"
	"net/http/httptest"
	"strings"
	"testing"
	"time"
)

// server answers every request with reply, after checking it.
func server(t *testing.T, reply func(w http.ResponseWriter, r *http.Request)) endpoint {
	t.Helper()
	s := httptest.NewServer(http.HandlerFunc(reply))
	t.Cleanup(s.Close)
	return endpoint{baseURL: s.URL + "/v1/", apiKey: "sk-test", model: "gpt-5-mini", timeout: 2 * time.Second}
}

func stream(events ...string) func(http.ResponseWriter, *http.Request) {
	return func(w http.ResponseWriter, _ *http.Request) {
		w.Header().Set("Content-Type", "text/event-stream")
		for _, e := range events {
			io.WriteString(w, e)
		}
	}
}

func TestRewriteSendsTheRequestTheInputMethodSends(t *testing.T) {
	var got map[string]any
	var header http.Header
	var path string
	e := server(t, func(w http.ResponseWriter, r *http.Request) {
		path, header, got = r.URL.Path, r.Header, nil
		json.NewDecoder(r.Body).Decode(&got)
		stream(`data: {"type":"response.completed"}`+"\n\n")(w, r)
	})
	e.effort = "low"
	if _, err := rewrite(context.Background(), e, testInstructions, "helo"); err != nil {
		t.Fatal(err)
	}
	if path != "/v1/responses" {
		t.Errorf("path %q", path)
	}
	if header.Get("Authorization") != "Bearer sk-test" || header.Get("originator") != "codex_cli_rs" ||
		!strings.HasPrefix(header.Get("User-Agent"), "codex_cli_rs/") {
		t.Errorf("headers %v", header)
	}
	if got["model"] != "gpt-5-mini" || got["input"] != "helo" || got["stream"] != true ||
		got["reasoning"].(map[string]any)["effort"] != "low" {
		t.Errorf("body %v", got)
	}

	e.model = "deepseek-chat"
	e.effort = ""
	rewrite(context.Background(), e, testInstructions, "helo")
	if header.Get("originator") != "" {
		t.Error("only GPT and Codex models identify as Codex")
	}
	if _, ok := got["reasoning"]; ok {
		t.Error("no effort, no reasoning")
	}
}

func TestRewriteReadsTheStream(t *testing.T) {
	cases := []struct {
		name   string
		events []string
		want   string
		err    string
	}{
		{"deltas", []string{
			"event: response.output_text.delta\ndata: {\"delta\":\"Hello \"}\n\n",
			"data: {\"type\":\"response.output_text.delta\",\"delta\":\"world\"}\r\n\r\n",
			"data: {\"type\":\"response.output_text.done\",\"text\":\"Hello world\"}\n\n",
		}, "Hello world", ""},
		{"the whole text only", []string{
			": a comment\n\n",
			"data: {\"type\":\"response.output_text.done\",\"text\":\"Hello world\"}\r\r",
		}, "Hello world", ""},
		{"chat style end", []string{"data: {\"type\":\"response.output_text.delta\",\"delta\":\"Hi\"}\n\n", "data: [DONE]\n\n"}, "Hi", ""},
		{"error event", []string{"data: {\"type\":\"error\",\"error\":{\"message\":\"model not found\"}}\n\n"}, "", "model not found"},
		{"failed", []string{"data: {\"type\":\"response.failed\",\"response\":{\"error\":{\"message\":\"overloaded\"}}}\n\n"}, "", "overloaded"},
		{"incomplete", []string{"data: {\"type\":\"response.incomplete\",\"response\":{\"incomplete_details\":{\"reason\":\"max_output_tokens\"}}}\n\n"}, "", "reply incomplete: max_output_tokens"},
		{"cut off", []string{"data: {\"type\":\"response.output_text.delta\",\"delta\":\"Hel\"}\n\n"}, "", "reply cut off"},
	}
	for _, c := range cases {
		t.Run(c.name, func(t *testing.T) {
			text, err := rewrite(context.Background(), server(t, stream(c.events...)), testInstructions, "helo")
			if c.err != "" {
				if err == nil || err.Error() != c.err {
					t.Fatalf("err %v, want %q", err, c.err)
				}
				return
			}
			if err != nil || text != c.want {
				t.Fatalf("got %q, %v; want %q", text, err, c.want)
			}
		})
	}
}

func TestRewriteSaysWhatTheServerSaid(t *testing.T) {
	e := server(t, func(w http.ResponseWriter, _ *http.Request) {
		w.WriteHeader(http.StatusUnauthorized)
		io.WriteString(w, `{"error":{"message":"Incorrect API key provided"}}`)
	})
	if _, err := rewrite(context.Background(), e, testInstructions, "helo"); err == nil || err.Error() != "HTTP 401: Incorrect API key provided" {
		t.Errorf("got %v", err)
	}
	e = server(t, func(w http.ResponseWriter, _ *http.Request) {
		w.WriteHeader(http.StatusBadGateway)
		io.WriteString(w, strings.Repeat("x", 500))
	})
	if _, err := rewrite(context.Background(), e, testInstructions, "helo"); err == nil || err.Error() != "HTTP 502: "+strings.Repeat("x", 200) {
		t.Errorf("got %v", err)
	}
}

func TestSilenceTimesOutButALongReplyDoesNot(t *testing.T) {
	slow := func(gap time.Duration, n int) func(http.ResponseWriter, *http.Request) {
		return func(w http.ResponseWriter, r *http.Request) {
			w.Header().Set("Content-Type", "text/event-stream")
			for i := 0; i < n; i++ {
				fmt.Fprintf(w, "data: {\"type\":\"response.output_text.delta\",\"delta\":\"%d\"}\n\n", i)
				w.(http.Flusher).Flush()
				select {
				case <-time.After(gap):
				case <-r.Context().Done():
					return
				}
			}
			io.WriteString(w, "data: {\"type\":\"response.completed\"}\n\n")
		}
	}
	e := server(t, slow(100*time.Millisecond, 5))
	e.timeout = 300 * time.Millisecond // shorter than the reply, longer than each gap
	if text, err := rewrite(context.Background(), e, testInstructions, "helo"); err != nil || text != "01234" {
		t.Errorf("got %q, %v", text, err)
	}
	e = server(t, slow(time.Second, 2))
	e.timeout = 200 * time.Millisecond
	if _, err := rewrite(context.Background(), e, testInstructions, "helo"); err == nil || err.Error() != "timed out" {
		t.Errorf("got %v", err)
	}
}

func TestRewriteWordsNetworkTrouble(t *testing.T) {
	e := endpoint{baseURL: "http://127.0.0.1:1/v1", apiKey: "k", model: "m", timeout: 2 * time.Second}
	if _, err := rewrite(context.Background(), e, testInstructions, "helo"); err == nil || err.Error() != "offline" {
		t.Errorf("refused: got %v", err)
	}
	e.baseURL = "not a url"
	if _, err := rewrite(context.Background(), e, testInstructions, "helo"); err == nil || !strings.HasPrefix(err.Error(), "Invalid base URL") {
		t.Errorf("bad URL: got %v", err)
	}
}

func TestEndpointFromTheConfig(t *testing.T) {
	e := endpointFrom([]byte(`{"baseURL":" https://x/v1 ","apiKey":"k\n","model":"m","reasoningEffort":3,"timeoutSeconds":900}`))
	if e.baseURL != "https://x/v1" || e.apiKey != "k" || e.model != "m" || e.effort != "" || e.timeout != 300*time.Second {
		t.Errorf("got %+v", e)
	}
	if e := endpointFrom([]byte(`{"timeoutSeconds":"slow"}`)); e.timeout != 10*time.Second {
		t.Errorf("default timeout: got %v", e.timeout)
	}
}

func TestChatProvidersGetChatCompletions(t *testing.T) {
	var got map[string]any
	var header http.Header
	var path string
	e := server(t, func(w http.ResponseWriter, r *http.Request) {
		path, header, got = r.URL.Path, r.Header, nil
		json.NewDecoder(r.Body).Decode(&got)
		stream(
			`data: {"choices":[{"delta":{"role":"assistant","content":""},"finish_reason":null}]}`+"\n\n",
			`data: {"choices":[{"delta":{"reasoning_content":"Hmm"},"finish_reason":null}]}`+"\n\n",
			`data: {"choices":[{"delta":{"content":"Hello"},"finish_reason":null}]}`+"\n\n",
			`data: {"choices":[{"delta":{"content":" world"},"finish_reason":"stop"}]}`+"\n\n",
		)(w, r)
	})
	e.api, e.effort = "chat", "low"
	text, err := rewrite(context.Background(), e, "inst", "helo")
	if err != nil || text != "Hello world" {
		t.Fatalf("got %q, %v", text, err)
	}
	if path != "/v1/chat/completions" || header.Get("originator") != "" {
		t.Errorf("path %q, headers %v", path, header)
	}
	messages, _ := json.Marshal(got["messages"])
	if string(messages) != `[{"content":"inst","role":"system"},{"content":"helo","role":"user"}]` ||
		got["reasoning_effort"] != "low" || got["stream"] != true || got["input"] != nil {
		t.Errorf("body %v", got)
	}
}

func TestRewriteReadsAChatStream(t *testing.T) {
	cases := []struct {
		name   string
		events []string
		want   string
		err    string
	}{
		{"done", []string{"data: {\"choices\":[{\"delta\":{\"content\":\"Hi\"}}]}\n\n", "data: [DONE]\n\n"}, "Hi", ""},
		{"too long", []string{"data: {\"choices\":[{\"delta\":{},\"finish_reason\":\"length\"}]}\n\n"}, "", "reply incomplete: length"},
		{"error", []string{"data: {\"error\":{\"message\":\"bad key\"}}\n\n"}, "", "bad key"},
		{"cut off", []string{"data: {\"choices\":[{\"delta\":{\"content\":\"Hel\"}}]}\n\n"}, "", "reply cut off"},
	}
	for _, c := range cases {
		t.Run(c.name, func(t *testing.T) {
			e := server(t, stream(c.events...))
			e.api = "chat"
			text, err := rewrite(context.Background(), e, "inst", "helo")
			if c.err != "" {
				if err == nil || err.Error() != c.err {
					t.Fatalf("err %v, want %q", err, c.err)
				}
				return
			}
			if err != nil || text != c.want {
				t.Fatalf("got %q, %v; want %q", text, err, c.want)
			}
		})
	}
}

func TestTheProviderInUse(t *testing.T) {
	config := `{"providers": ["junk",
		{"name": " Work ", "baseURL": "https://work/v1", "apiKey": "sk-REPLACE_ME", "model": "gpt-5-mini"},
		{"name": "DeepSeek", "api": "Chat", "baseURL": " https://api.deepseek.com ", "apiKey": "k", "model": "deepseek-chat",
		 "reasoningEffort": "low"}],
		"provider": %s, "baseURL": "https://ignored/v1", "timeoutSeconds": 20}`
	e := endpointFrom([]byte(fmt.Sprintf(config, `"DeepSeek"`)))
	if e.name != "DeepSeek" || e.api != "chat" || e.baseURL != "https://api.deepseek.com" || e.effort != "low" ||
		e.timeout != 20*time.Second || !e.configured() {
		t.Errorf("named: %+v", e)
	}
	for _, provider := range []string{`"Gone"`, `3`, `"Work"`} {
		if e := endpointFrom([]byte(fmt.Sprintf(config, provider))); e.name != "Work" || e.api != "responses" || e.configured() {
			t.Errorf("provider %s: %+v", provider, e)
		}
	}
}
