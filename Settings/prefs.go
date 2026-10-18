package main

import (
	"encoding/json"
	"os"
	"path/filepath"
	"sync"
)

// The Settings app's own preferences, apart from the input method's config:
// the pages' language and the window's size.
type prefs struct {
	Language string `json:"language,omitempty"` // "system", "en" or "zh"
	Width    int    `json:"width,omitempty"`
	Height   int    `json:"height,omitempty"`
}

type prefsFile struct {
	path string
	mu   sync.Mutex
}

func newPrefsFile(home string) *prefsFile {
	return &prefsFile{path: filepath.Join(home, "Library", "Application Support", "Fluent", "Settings.json")}
}

func (f *prefsFile) load() prefs {
	f.mu.Lock()
	defer f.mu.Unlock()
	var p prefs
	if data, err := os.ReadFile(f.path); err == nil {
		json.Unmarshal(data, &p)
	}
	if p.Language == "" {
		p.Language = "system"
	}
	return p
}

func (f *prefsFile) update(change func(*prefs)) {
	p := f.load()
	change(&p)
	f.mu.Lock()
	defer f.mu.Unlock()
	data, _ := json.MarshalIndent(p, "", "  ")
	if os.MkdirAll(filepath.Dir(f.path), 0o700) == nil {
		os.WriteFile(f.path, append(data, '\n'), 0o600)
	}
}
