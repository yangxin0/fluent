package main

import (
	"encoding/json"
	"strings"
	"testing"
)

const sample = `{
  "baseURL": "https://api.example.com/v1",
  "terminalCellWidth": 9.7,
  "fuzzyPinyin": ["zh=z",
                  "an=ang"],
  "nested": {"a": [1, {"b": "}"}]},
  "note": "a \"quoted\" , brace }"
}
`

func edit(t *testing.T, text, key string, value any) string {
	t.Helper()
	out, err := setKey([]byte(text), key, value)
	if err != nil {
		t.Fatalf("setKey(%q): %v", key, err)
	}
	var check map[string]any
	if err := json.Unmarshal(out, &check); err != nil {
		t.Fatalf("not JSON after setting %q:\n%s", key, out)
	}
	return string(out)
}

func TestReplacingAValueKeepsEverythingElse(t *testing.T) {
	if got := edit(t, sample, "terminalCellWidth", 8.5); got != strings.Replace(sample, "9.7", "8.5", 1) {
		t.Errorf("got:\n%s", got)
	}
	got := edit(t, sample, "note", "plain")
	if !strings.Contains(got, "\"note\": \"plain\"\n}") ||
		!strings.Contains(got, `"nested": {"a": [1, {"b": "}"}]},`) {
		t.Errorf("got:\n%s", got)
	}
}

func TestAMissingKeyGoesAfterTheLastOneWithTheSameIndent(t *testing.T) {
	if got := edit(t, sample, "chinese", "pinyin"); !strings.HasSuffix(got, "brace }\",\n  \"chinese\": \"pinyin\"\n}\n") {
		t.Errorf("got:\n%s", got)
	}
	if got := edit(t, "{}", "k", true); got != "{\n  \"k\": true\n}" {
		t.Errorf("got %q", got)
	}
	if got := edit(t, `{"a":0}`, "k", 1.0); got != `{"a":0, "k": 1}` {
		t.Errorf("got %q", got)
	}
}

func TestNilRemovesTheKey(t *testing.T) {
	if got := edit(t, sample, "baseURL", nil); !strings.HasPrefix(got, "{\n  \"terminalCellWidth\": 9.7,") {
		t.Errorf("first:\n%s", got)
	}
	if got := edit(t, sample, "fuzzyPinyin", nil); strings.Contains(got, "zh=z") {
		t.Errorf("middle:\n%s", got)
	}
	if got := edit(t, sample, "note", nil); !strings.HasSuffix(got, "}]}\n}\n") {
		t.Errorf("last:\n%s", got)
	}
	if got := edit(t, `{"a": 1}`, "a", nil); got != "{}" {
		t.Errorf("only: %q", got)
	}
	if got := edit(t, `{"a": 1}`, "b", nil); got != `{"a": 1}` {
		t.Errorf("absent: %q", got)
	}
}

func TestValuesAreWrittenAsTheFileWouldHaveThem(t *testing.T) {
	cases := []struct {
		value any
		want  string
	}{
		{350.0, "350"},
		{9.7, "9.7"},
		{false, "false"},
		{"a/b <c> & \"d\"", `"a/b <c> & \"d\""`},
		{"中文", `"中文"`},
		{[]any{"zh=z", "an=ang"}, `["zh=z", "an=ang"]`},
		{[]any{}, `[]`},
		{map[string]any{"b": 1.0, "a": "x"}, `{"a":"x","b":1}`},
	}
	for _, c := range cases {
		if got, err := encodeValue(c.value); err != nil || got != c.want {
			t.Errorf("encodeValue(%#v) = %s, %v; want %s", c.value, got, err, c.want)
		}
	}
}

func TestOnlyAnObjectIsEdited(t *testing.T) {
	for _, text := range []string{`[1]`, `"s"`, `null`, `{"a":`, ``} {
		if _, err := setKey([]byte(text), "a", 1.0); err == nil {
			t.Errorf("%q: want an error", text)
		}
	}
}

func TestCRLFFilesKeepTheirLineEnds(t *testing.T) {
	text := "{\r\n  \"a\": 1,\r\n  \"b\": 2\r\n}\r\n"
	if got := edit(t, text, "c", 3.0); got != "{\r\n  \"a\": 1,\r\n  \"b\": 2,\r\n  \"c\": 3\r\n}\r\n" {
		t.Errorf("got %q", got)
	}
	if got := edit(t, text, "a", 5.0); got != "{\r\n  \"a\": 5,\r\n  \"b\": 2\r\n}\r\n" {
		t.Errorf("got %q", got)
	}
}
