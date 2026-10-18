package main

import (
	"bufio"
	"bytes"
	"context"
	"encoding/json"
	"errors"
	"fmt"
	"io"
	"math"
	"net"
	"net/http"
	"net/url"
	"strings"
	"sync/atomic"
	"time"
)

// The Test button: one small request with the saved settings, the way the
// input method makes its own (an OpenAI Responses-compatible endpoint,
// streamed), so a working test means a working input method.

const (
	testInput        = "helo wrld"
	testInstructions = "Fix grammar, spelling and punctuation only, keeping the wording. " +
		"Reply with the corrected text and nothing else."
	// codexVersion is the Codex CLI version some gateways are told.
	codexVersion = "0.152.1"
)

// endpoint is what a request needs from the config.
type endpoint struct {
	baseURL, apiKey, model, effort string
	timeout                        time.Duration // how long the reply may stay silent
}

func endpointFrom(data []byte) endpoint {
	var c struct {
		BaseURL, APIKey, Model string
		ReasoningEffort        any
		TimeoutSeconds         any
	}
	json.Unmarshal(data, &c)
	e := endpoint{
		baseURL: strings.TrimSpace(c.BaseURL),
		apiKey:  strings.TrimSpace(c.APIKey),
		model:   strings.TrimSpace(c.Model),
		timeout: 10 * time.Second,
	}
	// a wrong type for an optional key leaves it unset
	if s, ok := c.ReasoningEffort.(string); ok {
		e.effort = s
	}
	if f, ok := c.TimeoutSeconds.(float64); ok && !math.IsInf(f, 0) {
		e.timeout = time.Duration(min(max(f, 1), 300) * float64(time.Second))
	}
	return e
}

// identifiesAsCodex: some gateways admit GPT models to the Responses API
// only from coding agents they know; other providers must not be told.
func identifiesAsCodex(model string) bool {
	m := strings.ToLower(model)
	return strings.HasPrefix(m, "gpt") || strings.Contains(m, "codex")
}

// rewrite sends input and returns the reply's text, or the error worded as
// the candidate bar would put it.
func rewrite(ctx context.Context, e endpoint, input string) (string, error) {
	base := strings.TrimRight(e.baseURL, "/")
	if u, err := url.Parse(base + "/responses"); err != nil || u.Scheme == "" || u.Host == "" {
		return "", fmt.Errorf("Invalid base URL: %s", e.baseURL)
	}
	body := map[string]any{"model": e.model, "instructions": testInstructions, "input": input, "stream": true}
	if e.effort != "" {
		body["reasoning"] = map[string]any{"effort": e.effort}
	}
	payload, _ := json.Marshal(body)

	// Silence, not length, times out: the clock restarts with every read.
	ctx, cancel := context.WithCancel(ctx)
	defer cancel()
	var silent atomic.Bool
	watchdog := time.AfterFunc(e.timeout, func() { silent.Store(true); cancel() })
	defer watchdog.Stop()
	heard := func() { watchdog.Reset(e.timeout) }

	req, _ := http.NewRequestWithContext(ctx, http.MethodPost, base+"/responses", bytes.NewReader(payload))
	req.Header.Set("Content-Type", "application/json")
	req.Header.Set("Accept", "text/event-stream")
	req.Header.Set("Authorization", "Bearer "+e.apiKey)
	if identifiesAsCodex(e.model) {
		req.Header.Set("originator", "codex_cli_rs")
		req.Header.Set("User-Agent", "codex_cli_rs/"+codexVersion)
	}
	res, err := http.DefaultClient.Do(req)
	if err != nil {
		return "", humanize(err, silent.Load())
	}
	defer res.Body.Close()
	heard()
	if res.StatusCode < 200 || res.StatusCode > 299 {
		raw, _ := io.ReadAll(io.LimitReader(res.Body, 2000))
		message := errorMessage(raw)
		if r := []rune(message); len(r) > 200 {
			message = string(r[:200])
		}
		if message == "" {
			return "", fmt.Errorf("HTTP %d", res.StatusCode)
		}
		return "", fmt.Errorf("HTTP %d: %s", res.StatusCode, message)
	}
	text, err := readStream(res.Body, heard)
	if err != nil {
		return "", humanize(err, silent.Load())
	}
	return text, nil
}

// readStream reads a Responses event stream to its end: the output text, or
// the error it reports. A stream that stops before saying it is finished (a
// proxy's timeout, a dropped connection) is an error, never half a reply.
func readStream(r io.Reader, heard func()) (string, error) {
	lines := bufio.NewScanner(r)
	lines.Buffer(make([]byte, 64*1024), 4*1024*1024)
	lines.Split(scanSSELines)
	var event string
	var data []string
	var text strings.Builder
	deltas := false
	for lines.Scan() {
		heard()
		line := lines.Text()
		if line != "" {
			field, value, _ := strings.Cut(line, ":")
			value = strings.TrimPrefix(value, " ")
			switch field {
			case "event":
				event = value
			case "data":
				data = append(data, value)
			}
			continue
		}
		if len(data) == 0 && event == "" {
			continue
		}
		payload := strings.TrimSpace(strings.Join(data, "\n"))
		name := event
		event, data = "", nil
		if payload == "[DONE]" {
			return text.String(), nil
		}
		var obj map[string]any
		if json.Unmarshal([]byte(payload), &obj) != nil {
			continue
		}
		kind, _ := obj["type"].(string)
		if kind == "" {
			kind = name
		}
		switch kind {
		case "response.output_text.delta":
			if d, _ := obj["delta"].(string); d != "" {
				deltas = true
				text.WriteString(d)
			}
		case "response.output_text.done":
			// the whole text, for providers that send no deltas
			if full, _ := obj["text"].(string); !deltas {
				text.WriteString(full)
			}
			return text.String(), nil
		case "response.completed":
			return text.String(), nil
		case "response.incomplete":
			response, _ := obj["response"].(map[string]any)
			details, _ := response["incomplete_details"].(map[string]any)
			if reason, ok := details["reason"].(string); ok {
				return "", errors.New("reply incomplete: " + reason)
			}
			return "", errors.New("reply incomplete")
		case "response.failed", "response.error", "error":
			return "", errors.New(eventError(obj))
		}
	}
	if err := lines.Err(); err != nil {
		return "", err
	}
	return "", errors.New("reply cut off")
}

// scanSSELines splits at LF, CRLF or a lone CR, as server-sent events allow.
func scanSSELines(data []byte, atEOF bool) (int, []byte, error) {
	for i, b := range data {
		switch b {
		case '\n':
			return i + 1, data[:i], nil
		case '\r':
			if i+1 == len(data) && !atEOF {
				return 0, nil, nil // a CRLF split across reads
			}
			if i+1 < len(data) && data[i+1] == '\n' {
				return i + 2, data[:i], nil
			}
			return i + 1, data[:i], nil
		}
	}
	if atEOF && len(data) > 0 {
		return len(data), data, nil
	}
	return 0, nil, nil
}

func eventError(obj map[string]any) string {
	if e, ok := obj["error"].(map[string]any); ok {
		if m, ok := e["message"].(string); ok {
			return m
		}
	}
	if m, ok := obj["message"].(string); ok {
		return m
	}
	if r, ok := obj["response"].(map[string]any); ok {
		if e, ok := r["error"].(map[string]any); ok {
			if m, ok := e["message"].(string); ok {
				return m
			}
		}
	}
	return "API error"
}

// errorMessage is the `error.message` of a JSON error body, else the body.
func errorMessage(body []byte) string {
	var obj map[string]any
	if json.Unmarshal(body, &obj) == nil {
		if e, ok := obj["error"].(map[string]any); ok {
			if m, ok := e["message"].(string); ok {
				return m
			}
		}
		if s, ok := obj["error"].(string); ok {
			return s
		}
		if s, ok := obj["message"].(string); ok {
			return s
		}
	}
	return strings.TrimSpace(string(body))
}

// humanize words a network error as the candidate bar does.
func humanize(err error, silent bool) error {
	var dns *net.DNSError
	var op *net.OpError
	switch {
	case silent:
		return errors.New("timed out")
	case errors.As(err, &dns), errors.As(err, &op) && op.Op == "dial":
		return errors.New("offline")
	}
	var u *url.Error
	if errors.As(err, &u) {
		return u.Err
	}
	return err
}
