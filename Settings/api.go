package main

import (
	"context"
	"encoding/json"
	"errors"
	"io/fs"
	"net/http"
	"os"
	"os/exec"
	"path/filepath"
	"strings"
	"time"

	"github.com/wailsapp/wails/v3/pkg/application"
)

// The pages talk to the app over a small JSON API served next to them, as
// magpie's do: `await fluent(op, args)` in app.js is a POST to /api/<op>.

const repository = "https://github.com/yangxin0/fluent"

// inputSourcesSettings is System Settings ▸ Keyboard, where Input Sources is.
const inputSourcesSettings = "x-apple.systempreferences:com.apple.Keyboard-Settings.extension"

type host struct {
	home    string
	config  configFile
	prefs   *prefsFile
	window  application.Window // for the forget dialog
	version string
}

func newHost(home, version string) *host {
	return &host{home: home, config: defaultConfigFile(home), prefs: newPrefsFile(home), version: version}
}

func (h *host) handler(pages fs.FS) http.Handler {
	mux := http.NewServeMux()
	mux.Handle("GET /", http.FileServerFS(pages))
	mux.HandleFunc("POST /api/{op}", func(w http.ResponseWriter, r *http.Request) {
		var args map[string]any
		json.NewDecoder(r.Body).Decode(&args)
		reply, err := h.call(r.Context(), r.PathValue("op"), args)
		if err != nil {
			http.Error(w, err.Error(), http.StatusBadRequest)
			return
		}
		w.Header().Set("Content-Type", "application/json")
		json.NewEncoder(w).Encode(reply)
	})
	return mux
}

type object = map[string]any

func (h *host) call(ctx context.Context, op string, args object) (any, error) {
	switch op {
	case "status":
		return h.status(), nil
	case "config.get":
		h.config.ensure()
		var values object
		if data, err := h.config.read(); err == nil {
			json.Unmarshal(data, &values)
		}
		if values == nil {
			values = object{}
		}
		return values, nil
	case "config.set":
		key, _ := args["key"].(string)
		if !editableKeys[key] {
			return nil, errors.New("unknown key")
		}
		return object{"ok": h.config.set(key, args["value"]) == nil}, nil
	case "test":
		return h.test(ctx), nil
	case "learned.forget":
		return object{"ok": h.forgetLearned(args)}, nil
	case "prefs.get":
		return object{"language": h.prefs.load().Language, "system": preferredLanguage()}, nil
	case "prefs.set":
		if language, ok := args["language"].(string); ok {
			h.prefs.update(func(p *prefs) { p.Language = language })
		}
		return object{"ok": true}, nil
	case "open":
		var target string
		switch args["what"] {
		case "inputSources":
			target = inputSourcesSettings
		case "config":
			h.config.ensure()
			target = h.config.path
		case "repository":
			target = repository
		default:
			return nil, errors.New("unknown target")
		}
		return object{"ok": exec.Command("open", target).Run() == nil}, nil
	}
	return nil, errors.New("unknown op " + op)
}

// inputMethod is where `make install` puts the input method.
func (h *host) inputMethod() string {
	return filepath.Join(h.home, "Library", "Input Methods", "Fluent-Input.app")
}

func exists(path string) bool {
	_, err := os.Stat(path)
	return err == nil
}

// status is the Setup page's checklist, and what else the pages show.
func (h *host) status() object {
	h.config.privatize()
	state := health{}
	if data, err := h.config.read(); err == nil {
		state = check(data)
	}
	resources := filepath.Join(h.inputMethod(), "Contents", "Resources")
	var problem any
	if state.problem != "" {
		problem = state.problem
	}
	return object{
		"installed":     exists(h.inputMethod()),
		"enabled":       inputSourceAdded(),
		"selected":      inputSourceSelected(),
		"configured":    state.configured,
		"configProblem": problem,
		"dictionaries":  exists(filepath.Join(resources, "xiaohe.lexicon")) && exists(filepath.Join(resources, "english.txt")),
		"learned":       learnedCount(h.home),
		"configStamp":   h.config.stamp(),
		"configPath":    "~" + strings.TrimPrefix(h.config.path, h.home),
		"version":       h.version,
	}
}

// test makes one request with the saved settings.
func (h *host) test(ctx context.Context) object {
	data, err := h.config.read()
	state := health{}
	if err == nil {
		state = check(data)
	}
	switch {
	case state.problem != "":
		return object{"ok": false, "code": "configError", "error": state.problem}
	case !state.configured:
		return object{"ok": false, "code": "notConfigured", "error": ""}
	}
	started := time.Now()
	text, err := rewrite(ctx, endpointFrom(data), testInput)
	if err != nil {
		return object{"ok": false, "error": err.Error()}
	}
	return object{"ok": true, "input": testInput, "text": strings.TrimSpace(text),
		"ms": time.Since(started).Milliseconds()}
}

// forgetLearned asks first, in the pages' language (they send the
// wording), then deletes the file and tells a running input method to drop
// its copy.
func (h *host) forgetLearned(args object) bool {
	text := func(key, fallback string) string {
		if s, ok := args[key].(string); ok && s != "" {
			return s
		}
		return fallback
	}
	answer := make(chan bool, 1)
	dialog := application.Get().Dialog.Question().
		SetTitle(text("title", "Forget learned words?")).
		SetMessage(text("detail", ""))
	forget := dialog.AddButton(text("confirm", "Forget")).OnClick(func() { answer <- true })
	cancel := dialog.AddButton(text("cancel", "Cancel")).OnClick(func() { answer <- false })
	dialog.SetDefaultButton(forget).SetCancelButton(cancel)
	if h.window != nil {
		dialog.AttachToWindow(h.window)
	}
	dialog.Show()
	if !<-answer {
		return false
	}
	if err := os.Remove(learnedPath(h.home)); err != nil && !errors.Is(err, fs.ErrNotExist) {
		return false
	}
	postDistributed(forgetNotification)
	return true
}
