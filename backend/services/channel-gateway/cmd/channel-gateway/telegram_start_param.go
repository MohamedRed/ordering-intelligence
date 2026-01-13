package main

import "strings"

func parseTelegramStartParam(value string) (string, bool) {
	raw := strings.TrimSpace(value)
	if raw == "" {
		return "", false
	}
	lower := strings.ToLower(raw)
	switch {
	case strings.HasPrefix(lower, "g:"):
		return strings.TrimSpace(raw[2:]), true
	case strings.HasPrefix(lower, "group:"):
		return strings.TrimSpace(raw[6:]), true
	case strings.HasPrefix(lower, "g_"):
		return strings.TrimSpace(raw[2:]), true
	case strings.HasPrefix(lower, "s:"):
		return strings.TrimSpace(raw[2:]), false
	case strings.HasPrefix(lower, "store:"):
		return strings.TrimSpace(raw[6:]), false
	case strings.HasPrefix(lower, "s_"):
		return strings.TrimSpace(raw[2:]), false
	default:
		return raw, false
	}
}
