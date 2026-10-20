package main

import (
	"bytes"
	"encoding/json"
	"errors"
	"slices"
	"strings"
)

// setKey edits one top-level key of a JSON object as text, so the rest of
// the file keeps its order, spacing and number formatting (9.7 stays 9.7):
// the key is replaced, added after the last one with the first one's
// indent, or removed when value is nil. value is what encoding/json decodes
// into: nil, bool, float64, string, []any or map[string]any.
func setKey(text []byte, key string, value any) ([]byte, error) {
	var object map[string]any
	if json.Unmarshal(text, &object) != nil || object == nil {
		return nil, errors.New("not a JSON object")
	}
	open, close, members := scanMembers(text)
	index := -1
	for i, m := range members {
		if m.key == key {
			index = i
		}
	}
	splice := func(from, to int, insert string) []byte {
		out := append([]byte{}, text[:from]...)
		out = append(out, insert...)
		return append(out, text[to:]...)
	}

	if value == nil {
		switch {
		case index < 0:
			return text, nil
		case index > 0: // `, "key": value`
			return splice(members[index-1].valueEnd, members[index].valueEnd, ""), nil
		case len(members) > 1: // `"key": value, `
			return splice(members[0].keyStart, members[1].keyStart, ""), nil
		default:
			return splice(open+1, close, ""), nil
		}
	}
	indent := "\n  "
	if len(members) > 0 {
		indent = string(text[open+1 : members[0].keyStart])
	}
	encoded, err := encodeValue(value, indent)
	if err != nil {
		return nil, err
	}
	if index >= 0 {
		m := members[index]
		return splice(m.valueStart, m.valueEnd, encoded), nil
	}
	name, _ := encodeValue(key, "")
	entry := name + ": " + encoded
	if len(members) == 0 {
		return splice(open+1, open+1, indent+entry+"\n"), nil
	}
	if indent == "" {
		indent = " "
	}
	last := members[len(members)-1]
	return splice(last.valueEnd, last.valueEnd, ","+indent+entry), nil
}

// firstKeys come first in an object (a provider), in the order the pages
// show them; the other keys follow sorted.
var firstKeys = []string{"name", "api", "baseURL", "apiKey", "model"}

// encodeValue is value as JSON: strings with only what JSON needs escaped,
// arrays as `[a, b]`, objects as `{"a": 1}`, numbers in their shortest form.
// It takes one line, except where the file gives its keys lines of their
// own (indent, the text before a key, holds a line break): there an object gets
// a line per key, and a list of objects a line per object.
func encodeValue(value any, indent string) (string, error) {
	var parts []string
	var objects bool
	switch v := value.(type) {
	case []any:
		objects = len(v) > 0
		for _, item := range v {
			_, isObject := item.(map[string]any)
			objects = objects && isObject
			s, err := encodeValue(item, "")
			if err != nil {
				return "", err
			}
			parts = append(parts, s)
		}
	case map[string]any:
		keys := make([]string, 0, len(v))
		for key := range v {
			keys = append(keys, key)
		}
		slices.SortFunc(keys, func(a, b string) int {
			i, j := slices.Index(firstKeys, a), slices.Index(firstKeys, b)
			switch {
			case i >= 0 && j >= 0:
				return i - j
			case i >= 0:
				return -1
			case j >= 0:
				return 1
			}
			return strings.Compare(a, b)
		})
		for _, key := range keys {
			name, _ := encodeValue(key, "")
			s, err := encodeValue(v[key], "")
			if err != nil {
				return "", err
			}
			parts = append(parts, name+": "+s)
		}
	default:
		return encodeScalar(value)
	}
	open, close := "[", "]"
	if _, ok := value.(map[string]any); ok {
		open, close = "{", "}"
	}
	if len(parts) > 0 && strings.Contains(indent, "\n") && (open == "{" || objects) {
		inner := indent + "  "
		return open + inner + strings.Join(parts, ","+inner) + indent + close, nil
	}
	return open + strings.Join(parts, ", ") + close, nil
}

// encodeScalar is a string, number, bool or null as JSON.
func encodeScalar(value any) (string, error) {
	var buf bytes.Buffer
	enc := json.NewEncoder(&buf)
	enc.SetEscapeHTML(false)
	if err := enc.Encode(value); err != nil {
		return "", err
	}
	return strings.TrimSuffix(buf.String(), "\n"), nil
}

type member struct {
	key                            string
	keyStart, valueStart, valueEnd int
}

// scanMembers finds the top-level members of text, known to be a JSON
// object, with their byte offsets, and the offsets of its braces. JSON's
// structure is all ASCII, so bytes are enough: no byte of a multibyte
// character is a quote, a brace or a comma.
func scanMembers(text []byte) (open, close int, members []member) {
	i := 0
	space := func() {
		for i < len(text) && (text[i] == ' ' || text[i] == '\t' || text[i] == '\n' || text[i] == '\r') {
			i++
		}
	}
	str := func() {
		i++ // opening quote
		for i < len(text) && text[i] != '"' {
			if text[i] == '\\' {
				i++
			}
			i++
		}
		i++
	}
	value := func() {
		switch text[i] {
		case '"':
			str()
		case '{', '[':
			depth := 0
			for i < len(text) {
				switch text[i] {
				case '"':
					str()
					continue
				case '{', '[':
					depth++
				case '}', ']':
					depth--
				}
				i++
				if depth == 0 {
					return
				}
			}
		default: // a number or a literal
			for i < len(text) && !strings.ContainsRune(" \t\n\r,}]", rune(text[i])) {
				i++
			}
		}
	}

	space()
	open = i
	i++
	for {
		space()
		switch text[i] {
		case '}':
			return open, i, members
		case ',':
			i++
			continue
		}
		keyStart := i
		str()
		var key string
		json.Unmarshal(text[keyStart:i], &key)
		space()
		i++ // the colon
		space()
		valueStart := i
		value()
		members = append(members, member{key, keyStart, valueStart, i})
	}
}
