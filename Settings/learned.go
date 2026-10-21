package main

import (
	"encoding/json"
	"os"
	"path/filepath"
	"sort"
	"strconv"
	"strings"
)

// The words the input method has learned from the candidates picked
// (docs/config.md): a `#tick` line, then rows of
// `text<TAB>syllables<TAB>commits<TAB>dee<TAB>tick`.

// forgetNotification, posted to the distributed notification center, makes
// a running input method drop the learned words it holds in memory, which
// it would otherwise save back.
const forgetNotification = "com.yangxin.inputmethod.Fluent.forgetLearnedWords"

func learnedPath(home string) string {
	return filepath.Join(home, "Library", "Application Support", "Fluent", "xiaohe-user.tsv")
}

// countLearned counts the words in the file's text, each word once, skipping
// rows the input method would skip too.
func countLearned(text string) int {
	seen := map[[2]string]bool{}
	for _, line := range strings.FieldsFunc(text, func(r rune) bool { return r == '\n' || r == '\r' }) {
		fields := strings.Split(line, "\t")
		if strings.HasPrefix(line, "#tick\t") || len(fields) != 5 {
			continue
		}
		syllables := strings.Fields(fields[1])
		if len(syllables) == 0 || !numbers(fields[2:]) {
			continue
		}
		seen[[2]string{fields[0], strings.Join(syllables, " ")}] = true
	}
	return len(seen)
}

func numbers(fields []string) bool {
	for _, f := range fields {
		if _, err := strconv.ParseFloat(f, 64); err != nil {
			return false
		}
	}
	return true
}

func learnedCount(home string) int {
	data, err := os.ReadFile(learnedPath(home))
	if err != nil {
		return 0
	}
	return countLearned(string(data))
}

// Your English words (docs/config.md): words the input method keeps in
// English instead of reading them as pinyin, one per line. It adds the keys
// you insert as typed from the Chinese bar, and rereads the file when it
// changes.

func englishWordsPath(home string) string {
	return filepath.Join(home, "Library", "Application Support", "Fluent", "english-words.txt")
}

// normalizeWords keeps what the input method keeps: lowercased words of two
// or more letters a–z, each once, sorted.
func normalizeWords(list []string) []string {
	seen := map[string]bool{}
	out := []string{}
	for _, w := range list {
		w = strings.ToLower(strings.TrimSpace(w))
		if len(w) < 2 || strings.Trim(w, "abcdefghijklmnopqrstuvwxyz") != "" || seen[w] {
			continue
		}
		seen[w] = true
		out = append(out, w)
	}
	sort.Strings(out)
	return out
}

func readEnglishWords(home string) []string {
	data, _ := os.ReadFile(englishWordsPath(home))
	return normalizeWords(strings.FieldsFunc(string(data), func(r rune) bool { return r == '\n' || r == '\r' }))
}

func writeEnglishWords(home string, list []string) error {
	path := englishWordsPath(home)
	if err := os.MkdirAll(filepath.Dir(path), 0o755); err != nil {
		return err
	}
	text := ""
	for _, w := range normalizeWords(list) {
		text += w + "\n"
	}
	return writePrivate(path, []byte(text))
}

// englishWordsStamp changes whenever the file is written, by either app.
func englishWordsStamp(home string) float64 {
	info, err := os.Stat(englishWordsPath(home))
	if err != nil {
		return 0
	}
	return float64(info.ModTime().UnixNano()) / 1e9
}

// What the input method reports (docs/config.md): `inputMonitoring` says
// whether it may watch key presses, which prefix keys need in apps that
// keep them from input methods. It writes the file once it has asked.

func statusPath(home string) string {
	return filepath.Join(home, "Library", "Application Support", "Fluent", "status.json")
}

// inputMonitoring is true or false as the input method last reported it,
// nil when it hasn't.
func inputMonitoring(home string) any {
	data, err := os.ReadFile(statusPath(home))
	if err != nil {
		return nil
	}
	var status struct {
		InputMonitoring *bool `json:"inputMonitoring"`
	}
	if json.Unmarshal(data, &status) != nil || status.InputMonitoring == nil {
		return nil
	}
	return *status.InputMonitoring
}
