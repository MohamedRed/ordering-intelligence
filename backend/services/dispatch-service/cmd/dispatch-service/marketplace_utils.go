package main

import (
	"encoding/json"
	"strconv"
	"strings"
)

func toInt(value any) int {
	switch v := value.(type) {
	case int:
		return v
	case int64:
		return int(v)
	case float64:
		return int(v)
	case float32:
		return int(v)
	case json.Number:
		i, _ := v.Int64()
		return int(i)
	case string:
		if strings.TrimSpace(v) == "" {
			return 0
		}
		if i, err := strconv.Atoi(strings.TrimSpace(v)); err == nil {
			return i
		}
	}
	return 0
}
