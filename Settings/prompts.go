package main

import "strings"

// The modes' built-in prompts, as the input method has them
// (Sources/FluentCore/Mode.swift): Polish and Translate are
// nextai-translator's, Fix one in their style. Both apps' tests check them
// against docs/default-prompts.json. The config's `prompts` may replace one;
// the output rule always follows.

var defaultPrompts = map[string]string{
	"fix": "You are an expert proofreader. Please correct the grammar, spelling and punctuation " +
		"of the following sentences in English, changing nothing else.",
	"polish": "You are an expert translator, translate directly without explanation. " +
		"Please edit the following sentences in English to improve clarity, conciseness, " +
		"and coherence, making them match the expression of native speakers.",
	"translate": "You are a professional translator. Please translate to English",
}

const outputRule = "Only reply the result and nothing else."

// instructions are what the model is told for mode before the text: prompt
// (the built-in one when it is blank), a blank line, then the output rule.
func instructions(mode, prompt string) string {
	prompt = strings.TrimSpace(prompt)
	if prompt == "" {
		prompt = defaultPrompts[mode]
	}
	return prompt + "\n\n" + outputRule
}
