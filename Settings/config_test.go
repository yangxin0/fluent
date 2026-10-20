package main

import (
	"encoding/json"
	"os"
	"path/filepath"
	"sort"
	"testing"
)

// The sample configs in docs/config-examples, which the input method's
// Swift tests read too (ConfigExamplesTests): both apps must make the same
// of each file, since they share no code (docs/config.md).
func TestConfigExamples(t *testing.T) {
	folder := filepath.Join("..", "docs", "config-examples")
	raw, err := os.ReadFile(filepath.Join(folder, "expected.json"))
	if err != nil {
		t.Fatal(err)
	}
	var expected map[string]struct {
		Configured bool
		Problem    *string
	}
	if err := json.Unmarshal(raw, &expected); err != nil || len(expected) == 0 {
		t.Fatalf("expected.json: %v", err)
	}
	names := make([]string, 0, len(expected))
	for name := range expected {
		names = append(names, name)
	}
	sort.Strings(names)
	for _, name := range names {
		data, err := os.ReadFile(filepath.Join(folder, name))
		if err != nil {
			t.Fatal(err)
		}
		got, want := check(data), expected[name]
		wantProblem := ""
		if want.Problem != nil {
			wantProblem = *want.Problem
		}
		if got.configured != want.Configured || got.problem != wantProblem {
			t.Errorf("%s: configured %v, problem %q; want %v, %q",
				name, got.configured, got.problem, want.Configured, wantProblem)
		}
	}
}

func TestEnsureWritesThePrivateTemplateOnce(t *testing.T) {
	home := t.TempDir()
	c := defaultConfigFile(home)
	c.ensure()
	info, err := os.Stat(c.path)
	if err != nil {
		t.Fatal(err)
	}
	if info.Mode().Perm() != 0o600 {
		t.Errorf("mode %v, want 0600", info.Mode().Perm())
	}
	dir, _ := os.Stat(filepath.Dir(c.path))
	if dir.Mode().Perm() != 0o700 {
		t.Errorf("folder mode %v, want 0700", dir.Mode().Perm())
	}
	data, _ := os.ReadFile(c.path)
	if string(data) != template {
		t.Errorf("template:\n%s", data)
	}
	os.WriteFile(c.path, []byte(`{"mine": true}`), 0o600)
	c.ensure()
	if data, _ := os.ReadFile(c.path); string(data) != `{"mine": true}` {
		t.Errorf("ensure replaced an existing file: %s", data)
	}
}

func TestEnsureCarriesTheConfigFromBeforeTheRename(t *testing.T) {
	home := t.TempDir()
	c := defaultConfigFile(home)
	os.MkdirAll(filepath.Dir(c.legacy), 0o755)
	os.WriteFile(c.legacy, []byte(`{"old": 1}`), 0o644)
	c.ensure()
	if data, _ := os.ReadFile(c.path); string(data) != `{"old": 1}` {
		t.Errorf("got %s", data)
	}
	if _, err := os.Stat(c.legacy); err != nil {
		t.Error("the old file should stay")
	}
}

func TestSetEditsOneKeyThroughASymlink(t *testing.T) {
	home := t.TempDir()
	c := defaultConfigFile(home)
	dotfiles := filepath.Join(home, "dotfiles", "fluent.json")
	os.MkdirAll(filepath.Dir(dotfiles), 0o700)
	os.WriteFile(dotfiles, []byte("{\n  \"model\": \"m\",\n  \"debounceMs\": 350\n}\n"), 0o644)
	os.MkdirAll(filepath.Dir(c.path), 0o700)
	if err := os.Symlink(dotfiles, c.path); err != nil {
		t.Fatal(err)
	}
	if err := c.set("chinese", "pinyin"); err != nil {
		t.Fatal(err)
	}
	if info, _ := os.Lstat(c.path); info.Mode()&os.ModeSymlink == 0 {
		t.Error("the link was replaced")
	}
	data, _ := os.ReadFile(dotfiles)
	want := "{\n  \"model\": \"m\",\n  \"debounceMs\": 350,\n  \"chinese\": \"pinyin\"\n}\n"
	if string(data) != want {
		t.Errorf("got:\n%s", data)
	}
	if info, _ := os.Stat(dotfiles); info.Mode().Perm() != 0o600 {
		t.Errorf("mode %v, want 0600", info.Mode().Perm())
	}
}

func TestSetLeavesAFileThatIsNotAnObject(t *testing.T) {
	home := t.TempDir()
	c := defaultConfigFile(home)
	os.MkdirAll(filepath.Dir(c.path), 0o700)
	os.WriteFile(c.path, []byte(`{"model": `), 0o600)
	if c.set("model", "m") == nil {
		t.Error("set should fail")
	}
	if data, _ := os.ReadFile(c.path); string(data) != `{"model": ` {
		t.Errorf("file changed: %s", data)
	}
}

func TestPrivatizeTakesAwayOthersAccess(t *testing.T) {
	home := t.TempDir()
	c := defaultConfigFile(home)
	os.MkdirAll(filepath.Dir(c.path), 0o700)
	os.WriteFile(c.path, []byte(`{}`), 0o644)
	os.Chmod(c.path, 0o644)
	c.privatize()
	if info, _ := os.Stat(c.path); info.Mode().Perm() != 0o600 {
		t.Errorf("mode %v, want 0600", info.Mode().Perm())
	}
}

// The input method has the same built-in prompts; both apps' tests check
// them against docs/default-prompts.json.
func TestDefaultPromptsMatchTheSharedFile(t *testing.T) {
	raw, err := os.ReadFile(filepath.Join("..", "docs", "default-prompts.json"))
	if err != nil {
		t.Fatal(err)
	}
	var shared map[string]string
	if err := json.Unmarshal(raw, &shared); err != nil {
		t.Fatal(err)
	}
	if len(shared) != len(defaultPrompts)+1 || shared["outputRule"] != outputRule {
		t.Errorf("shared file: %v", shared)
	}
	for mode, prompt := range defaultPrompts {
		if shared[mode] != prompt {
			t.Errorf("%s:\n%q\nwant\n%q", mode, prompt, shared[mode])
		}
	}
	if got := instructions("fix", " \n"); got != defaultPrompts["fix"]+"\n\n"+outputRule {
		t.Errorf("built-in: %q", got)
	}
	if got := instructions("polish", " Friendly.\n"); got != "Friendly.\n\n"+outputRule {
		t.Errorf("your own: %q", got)
	}
}
