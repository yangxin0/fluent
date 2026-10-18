package main

import (
	"bytes"
	"encoding/json"
	"errors"
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
	encoded, err := encodeValue(value)
	if err != nil {
		return nil, err
	}
	if index >= 0 {
		m := members[index]
		return splice(m.valueStart, m.valueEnd, encoded), nil
	}
	name, _ := encodeValue(key)
	entry := name + ": " + encoded
	if len(members) == 0 {
		return splice(open+1, open+1, "\n  "+entry+"\n"), nil
	}
	indent := string(text[open+1 : members[0].keyStart])
	if indent == "" {
		indent = " "
	}
	last := members[len(members)-1]
	return splice(last.valueEnd, last.valueEnd, ","+indent+entry), nil
}

// encodeValue is value as JSON on one line: strings with only what JSON
// needs escaped, arrays as `[a, b]`, numbers in their shortest form.
func encodeValue(value any) (string, error) {
	if items, ok := value.([]any); ok {
		parts := make([]string, len(items))
		for i, item := range items {
			s, err := encodeValue(item)
			if err != nil {
				return "", err
			}
			parts[i] = s
		}
		return "[" + strings.Join(parts, ", ") + "]", nil
	}
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
