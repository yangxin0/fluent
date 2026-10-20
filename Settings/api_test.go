package main

import (
	"encoding/json"
	"io"
	"net/http"
	"net/http/httptest"
	"os"
	"path/filepath"
	"strings"
	"testing"
	"testing/fstest"
)

// call posts args to the pages' API and decodes the reply.
func call(t *testing.T, h http.Handler, op string, args any) (int, map[string]any) {
	t.Helper()
	body, _ := json.Marshal(args)
	rec := httptest.NewRecorder()
	h.ServeHTTP(rec, httptest.NewRequest(http.MethodPost, "/api/"+op, strings.NewReader(string(body))))
	var reply map[string]any
	json.Unmarshal(rec.Body.Bytes(), &reply)
	return rec.Code, reply
}

func TestConfigOverTheAPI(t *testing.T) {
	home := t.TempDir()
	h := newHost(home, "test").handler(fstest.MapFS{})

	_, values := call(t, h, "config.get", nil)
	if values["apiKey"] != placeholderKey || values["debounceMs"] != 350.0 {
		t.Fatalf("a missing config gets the template: %v", values)
	}
	if _, reply := call(t, h, "config.set", map[string]any{"key": "fuzzyPinyin", "value": []string{"zh=z"}}); reply["ok"] != true {
		t.Fatalf("set: %v", reply)
	}
	call(t, h, "config.set", map[string]any{"key": "debounceMs", "value": nil})
	data, _ := os.ReadFile(filepath.Join(home, ".config", "fluent", "config.json"))
	if !strings.Contains(string(data), `"fuzzyPinyin": ["zh=z"]`) || strings.Contains(string(data), "debounceMs") {
		t.Errorf("file:\n%s", data)
	}
	if code, _ := call(t, h, "config.set", map[string]any{"key": "rm -rf", "value": 1}); code != http.StatusBadRequest {
		t.Errorf("an unknown key: %d", code)
	}
}

func TestPrefsOverTheAPI(t *testing.T) {
	h := newHost(t.TempDir(), "test").handler(fstest.MapFS{})
	if _, p := call(t, h, "prefs.get", nil); p["language"] != "system" || p["system"] == "" {
		t.Errorf("defaults: %v", p)
	}
	call(t, h, "prefs.set", map[string]any{"language": "zh"})
	if _, p := call(t, h, "prefs.get", nil); p["language"] != "zh" {
		t.Errorf("after set: %v", p)
	}
}

func TestTheAPIServesThePagesAndRefusesOtherOps(t *testing.T) {
	h := newHost(t.TempDir(), "test").handler(fstest.MapFS{"index.html": {Data: []byte("<title>Fluent</title>")}})
	rec := httptest.NewRecorder()
	h.ServeHTTP(rec, httptest.NewRequest(http.MethodGet, "/", nil))
	if !strings.Contains(rec.Body.String(), "<title>Fluent</title>") {
		t.Errorf("index: %d %q", rec.Code, rec.Body.String())
	}
	if code, _ := call(t, h, "nope", nil); code != http.StatusBadRequest {
		t.Errorf("unknown op: %d", code)
	}
	if code, _ := call(t, h, "open", map[string]any{"what": "/etc/passwd"}); code != http.StatusBadRequest {
		t.Errorf("open only knows its targets: %d", code)
	}
}

func TestTryAndTestOverTheAPI(t *testing.T) {
	var got map[string]any
	provider := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		got = nil
		json.NewDecoder(r.Body).Decode(&got)
		w.Header().Set("Content-Type", "text/event-stream")
		io.WriteString(w, `data: {"choices":[{"delta":{"content":"Hello there."},"finish_reason":"stop"}]}`+"\n\n")
	}))
	t.Cleanup(provider.Close)
	home := t.TempDir()
	path := filepath.Join(home, ".config", "fluent", "config.json")
	os.MkdirAll(filepath.Dir(path), 0o700)
	os.WriteFile(path, []byte(`{"providers": [{"name": "Local", "api": "chat", "baseURL": "`+provider.URL+`/v1",
		"apiKey": "k", "model": "m"}]}`), 0o600)
	h := newHost(home, "test").handler(fstest.MapFS{})

	_, reply := call(t, h, "try", map[string]any{"mode": "polish", "input": " hi ", "prompt": "Be nice."})
	messages, _ := got["messages"].([]any)
	if reply["ok"] != true || reply["text"] != "Hello there." || reply["input"] != "hi" || len(messages) != 1 ||
		messages[0].(map[string]any)["content"] != "Be nice.\n\n"+outputRule+"\n\nhi" {
		t.Errorf("try: %v, sent %v", reply, got)
	}
	call(t, h, "try", map[string]any{"mode": "translate", "input": "hi"})
	if messages, _ := got["messages"].([]any); messages[0].(map[string]any)["content"] != instructions("translate", "")+"\n\nhi" {
		t.Errorf("built-in prompt: sent %v", got)
	}
	if _, reply := call(t, h, "try", map[string]any{"mode": "shout", "input": "hi"}); reply["ok"] != false {
		t.Errorf("unknown mode: %v", reply)
	}

	// Test asks with the provider the page sends, saved or not.
	_, reply = call(t, h, "test", map[string]any{"provider": map[string]any{
		"name": "Draft", "api": "chat", "baseURL": provider.URL + "/v1", "apiKey": "k2", "model": "m2"}})
	if reply["ok"] != true || got["model"] != "m2" {
		t.Errorf("test: %v, sent %v", reply, got)
	}
	_, reply = call(t, h, "test", map[string]any{"provider": map[string]any{"name": "Blank"}})
	if reply["code"] != "notConfigured" {
		t.Errorf("an unfinished provider: %v", reply)
	}

	_, defaults := call(t, h, "prompts.defaults", nil)
	if defaults["fix"] != defaultPrompts["fix"] || defaults["outputRule"] != outputRule {
		t.Errorf("defaults: %v", defaults)
	}
}
