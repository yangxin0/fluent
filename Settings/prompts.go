package main

import "strings"

// The modes' built-in prompts, as the input method has them
// (Sources/FluentCore/Mode.swift). Both apps' tests check them against
// docs/default-prompts.json. The config's `prompts` may replace one; the
// output rule always follows.

var defaultPrompts = map[string]string{
	"fix": "You correct English text. Fix grammar, spelling, and punctuation only. " +
		"Change nothing else; keep the author's wording and tone. " +
		"If the text is already correct, return it unchanged.",
	"polish": "You improve English text. Rewrite it as a fluent native English speaker would: " +
		"natural word choice, idiomatic phrasing, same meaning and register.",
	"translate": "You turn rough input into clear English. The input may be fragmentary, ungrammatical, " +
		"or mix Chinese and English. Infer the intended message and write it as clear, natural English.",
}

const outputRule = "Output ONLY the resulting text. No quotes, no explanations. Preserve the author's meaning."

// instructions are what the model is told for mode: prompt (the built-in
// one when it is blank), a blank line, then the output rule.
func instructions(mode, prompt string) string {
	prompt = strings.TrimSpace(prompt)
	if prompt == "" {
		prompt = defaultPrompts[mode]
	}
	return prompt + "\n\n" + outputRule
}
