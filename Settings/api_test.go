package main

import (
	"encoding/json"
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
