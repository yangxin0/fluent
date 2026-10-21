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

// inputMonitoringSettings is Privacy & Security ▸ Input Monitoring.
const inputMonitoringSettings = "x-apple.systempreferences:com.apple.preference.security?Privacy_ListenEvent"

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
		return h.test(ctx, args), nil
	case "try":
		return h.try(ctx, args), nil
	case "prompts.defaults":
		defaults := object{"outputRule": outputRule}
		for mode, prompt := range defaultPrompts {
			defaults[mode] = prompt
		}
		return defaults, nil
	case "confirm":
		return object{"ok": h.ask(args, "Are you sure?", "OK")}, nil
	case "learned.forget":
		return object{"ok": h.forgetLearned(args)}, nil
	case "words.get":
		return object{"words": readEnglishWords(h.home)}, nil
	case "words.set":
		raw, _ := args["words"].([]any)
		list := make([]string, 0, len(raw))
		for _, w := range raw {
			if s, ok := w.(string); ok {
				list = append(list, s)
			}
		}
		return object{"ok": writeEnglishWords(h.home, list) == nil, "words": readEnglishWords(h.home)}, nil
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
		case "inputMonitoring":
			target = inputMonitoringSettings
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
		"installed":       exists(h.inputMethod()),
		"enabled":         inputSourceAdded(),
		"selected":        inputSourceSelected(),
		"configured":      state.configured,
		"configProblem":   problem,
		"dictionaries":    exists(filepath.Join(resources, "xiaohe.lexicon")) && exists(filepath.Join(resources, "english.txt")),
		"learned":         learnedCount(h.home),
		"wordsStamp":      englishWordsStamp(h.home),
		"inputMonitoring": inputMonitoring(h.home),
		"configStamp":     h.config.stamp(),
		"configPath":      "~" + strings.TrimPrefix(h.config.path, h.home),
		"version":         h.version,
	}
}

// endpointInUse is the config's provider in use, or the reply that says
// why there is none to ask.
func (h *host) endpointInUse() (endpoint, object) {
	data, err := h.config.read()
	if err != nil {
		return endpoint{}, object{"ok": false, "code": "notConfigured", "error": ""}
	}
	if problem := check(data).problem; problem != "" {
		return endpoint{}, object{"ok": false, "code": "configError", "error": problem}
	}
	return endpointFrom(data), nil
}

// test makes one small request: with the provider the page sends (the one
// being edited, saved or not), else the one in use.
func (h *host) test(ctx context.Context, args object) object {
	e, failed := h.endpointInUse()
	if failed != nil {
		return failed
	}
	if m, ok := args["provider"].(map[string]any); ok {
		timeout := e.timeout
		e = endpointOf(m, true)
		e.timeout = timeout
	}
	return run(ctx, e, testInstructions, testInput)
}

// try runs the page's sample through a mode's prompt (the text in the
// page's editor, else the built-in one) with the provider in use.
func (h *host) try(ctx context.Context, args object) object {
	mode, _ := args["mode"].(string)
	if _, ok := defaultPrompts[mode]; !ok {
		return object{"ok": false, "error": "unknown mode"}
	}
	e, failed := h.endpointInUse()
	if failed != nil {
		return failed
	}
	prompt, _ := args["prompt"].(string)
	input, _ := args["input"].(string)
	return run(ctx, e, instructions(mode, prompt), strings.TrimSpace(input))
}

func run(ctx context.Context, e endpoint, instructions, input string) object {
	if !e.configured() {
		return object{"ok": false, "code": "notConfigured", "error": ""}
	}
	started := time.Now()
	text, err := rewrite(ctx, e, instructions, input)
	if err != nil {
		return object{"ok": false, "error": err.Error()}
	}
	return object{"ok": true, "input": input, "text": strings.TrimSpace(text),
		"ms": time.Since(started).Milliseconds()}
}

// ask puts a question to the user in the pages' language (they send the
// wording) and says whether they confirmed.
func (h *host) ask(args object, title, confirm string) bool {
	text := func(key, fallback string) string {
		if s, ok := args[key].(string); ok && s != "" {
			return s
		}
		return fallback
	}
	answer := make(chan bool, 1)
	dialog := application.Get().Dialog.Question().
		SetTitle(text("title", title)).
		SetMessage(text("detail", ""))
	yes := dialog.AddButton(text("confirm", confirm)).OnClick(func() { answer <- true })
	no := dialog.AddButton(text("cancel", "Cancel")).OnClick(func() { answer <- false })
	dialog.SetDefaultButton(yes).SetCancelButton(no)
	if h.window != nil {
		dialog.AttachToWindow(h.window)
	}
	dialog.Show()
	return <-answer
}

// forgetLearned asks first, then deletes the file and tells a running input
// method to drop its copy.
func (h *host) forgetLearned(args object) bool {
	if !h.ask(args, "Forget learned words?", "Forget") {
		return false
	}
	if err := os.Remove(learnedPath(h.home)); err != nil && !errors.Is(err, fs.ErrNotExist) {
		return false
	}
	postDistributed(forgetNotification)
	return true
}
