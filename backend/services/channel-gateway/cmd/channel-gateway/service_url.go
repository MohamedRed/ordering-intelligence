package main

import (
	"net/url"
	"strings"
)

func serviceURL(base string, segments ...string) string {
	trimmedBase := strings.TrimRight(strings.TrimSpace(base), "/")
	if len(segments) == 0 {
		return trimmedBase
	}
	escaped := make([]string, 0, len(segments))
	for _, segment := range segments {
		escaped = append(escaped, url.PathEscape(strings.TrimSpace(segment)))
	}
	return trimmedBase + "/" + strings.Join(escaped, "/")
}
