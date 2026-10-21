package main

import (
	"encoding/json"
	"errors"
	"fmt"
	"io/fs"
	"os"
	"path/filepath"
	"strings"
)

// The config file the input method reads (docs/config.md). Settings edits
// it one key at a time; the input method notices the new modification time
// on its next keystroke, so writing it is all there is to applying a change.

const placeholderKey = "sk-REPLACE_ME"

// editableKeys are the keys the pages may set. The top-level endpoint keys
// are only ever removed, once `providers` takes over from them.
var editableKeys = map[string]bool{
	"baseURL": true, "apiKey": true, "model": true, "reasoningEffort": true,
	"providers": true, "provider": true, "prompts": true,
	"debounceMs": true, "timeoutSeconds": true, "appearance": true, "toggleNotice": true,
	"candidateBarSize": true, "candidateTextSize": true, "candidatePageSize": true, "prefixKeys": true,
	"terminalMode": true, "terminalApps": true, "terminalCellWidth": true,
	"chinese": true, "pinyinAbbreviations": true, "fuzzyPinyin": true,
}

// requiredKeys, in the order a problem names the first one wrong. Only a
// config without providers needs them.
var requiredKeys = []string{"baseURL", "apiKey", "model"}

const template = `{
  "baseURL": "https://api.openai.com/v1",
  "apiKey": "` + placeholderKey + `",
  "model": "gpt-4o-mini",
  "appearance": "auto",
  "terminalMode": "auto",
  "chinese": "pinyin",
  "debounceMs": 350,
  "timeoutSeconds": 10
}`

type configFile struct {
	path   string // ~/.config/fluent/config.json
	legacy string // ~/.config/english-input/config.json, from before the rename
}

func defaultConfigFile(home string) configFile {
	return configFile{
		path:   filepath.Join(home, ".config", "fluent", "config.json"),
		legacy: filepath.Join(home, ".config", "english-input", "config.json"),
	}
}

// target is the file itself: through a symlink (a dotfiles repo), so an
// edit lands where the user keeps it and the link stays.
func (c configFile) target() string {
	if p, err := filepath.EvalSymlinks(c.path); err == nil {
		return p
	}
	return c.path
}

// ensure writes a starter config when there is none, carrying over the one
// from before the rename if that exists. Readable by the user only: it will
// hold an API key.
func (c configFile) ensure() {
	if _, err := os.Lstat(c.path); !errors.Is(err, fs.ErrNotExist) {
		return
	}
	if err := os.MkdirAll(filepath.Dir(c.path), 0o700); err != nil {
		return
	}
	data := []byte(template)
	if old, err := os.ReadFile(c.legacy); err == nil {
		data = old
	}
	f, err := os.OpenFile(c.path, os.O_WRONLY|os.O_CREATE|os.O_EXCL, 0o600)
	if err != nil {
		return
	}
	f.Write(data)
	f.Close()
}

func (c configFile) read() ([]byte, error) { return os.ReadFile(c.path) }

// stamp is the file's modification time, which changes whenever it is
// saved: the pages reload the values when it does.
func (c configFile) stamp() float64 {
	info, err := os.Stat(c.target())
	if err != nil {
		return 0
	}
	return float64(info.ModTime().UnixNano()) / 1e9
}

// set gives key value (nil removes it), editing only that key's text. It
// fails when the file isn't a JSON object, which is then left as it is.
func (c configFile) set(key string, value any) error {
	c.ensure()
	data, err := c.read()
	if err != nil {
		return err
	}
	out, err := setKey(data, key, value)
	if err != nil {
		return err
	}
	return writePrivate(c.target(), out)
}

// writePrivate replaces path with data in one step (a temporary file
// renamed over it), readable by the user only.
func writePrivate(path string, data []byte) error {
	tmp, err := os.CreateTemp(filepath.Dir(path), ".config-*.json")
	if err != nil {
		return err
	}
	defer os.Remove(tmp.Name())
	if _, err := tmp.Write(data); err != nil {
		tmp.Close()
		return err
	}
	if err := tmp.Chmod(0o600); err != nil {
		tmp.Close()
		return err
	}
	if err := tmp.Close(); err != nil {
		return err
	}
	return os.Rename(tmp.Name(), path)
}

// privatize takes away group and other access to the file, as the input
// method does when it reads it.
func (c configFile) privatize() {
	path := c.target()
	if info, err := os.Stat(path); err == nil && info.Mode().Perm()&0o077 != 0 {
		os.Chmod(path, info.Mode().Perm()&0o700)
	}
}

// health is what the input method makes of the file: whether it can rewrite
// with it, and if the file can't be used at all, why.
type health struct {
	configured bool
	problem    string // "" when the file loads, or doesn't exist
}

func check(data []byte) health {
	var top any
	if err := json.Unmarshal(data, &top); err != nil {
		return health{problem: "not valid JSON"}
	}
	object, ok := top.(map[string]any)
	if !ok {
		return health{problem: "not a JSON object"}
	}
	if len(providers(object)) > 0 {
		return health{configured: activeEndpoint(object).configured()}
	}
	values := map[string]string{}
	for _, key := range requiredKeys {
		raw, present := object[key]
		if !present {
			return health{problem: fmt.Sprintf("%q is missing", key)}
		}
		s, isString := raw.(string)
		if !isString {
			return health{problem: fmt.Sprintf("%q has the wrong type", key)}
		}
		// Pasted values often bring a stray space or newline along.
		values[key] = strings.TrimSpace(s)
	}
	return health{configured: values["baseURL"] != "" && values["model"] != "" &&
		values["apiKey"] != "" && values["apiKey"] != placeholderKey}
}
