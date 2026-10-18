package main

import (
	"os"
	"path/filepath"
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
