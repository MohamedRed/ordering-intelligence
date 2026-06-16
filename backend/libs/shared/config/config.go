package sharedconfig

import (
	"embed"
	"encoding/json"
	"errors"
	"fmt"
	"os"
	"strconv"
	"strings"
)

//go:embed schema/schema.json
var schemaFile embed.FS

var cachedSchema Schema

// ConfigDefinition describes a single configuration option.
type ConfigDefinition struct {
	Type        string      `json:"type"`
	Required    bool        `json:"required"`
	Default     interface{} `json:"default"`
	Description string      `json:"description"`
	Sensitive   bool        `json:"sensitive"`
	Env         string      `json:"env"`
}

// ServiceSchema enumerates the configuration for a service.
type ServiceSchema map[string]ConfigDefinition

// Schema is the root configuration schema across services.
type Schema map[string]ServiceSchema

// Config represents validated configuration values.
type Config map[string]interface{}

func loadSchema() (Schema, error) {
	if cachedSchema != nil {
		return cachedSchema, nil
	}

	bytes, err := schemaFile.ReadFile("schema/schema.json")
	if err != nil {
		return nil, fmt.Errorf("failed reading schema: %w", err)
	}

	var schema Schema
	if err := json.Unmarshal(bytes, &schema); err != nil {
		return nil, fmt.Errorf("failed to unmarshal schema: %w", err)
	}

	cachedSchema = schema
	return schema, nil
}

// Load returns configuration for the provided service, validating according to schema.
// If env is nil, os.Environ is used.
func Load(service string, env map[string]string) (Config, error) {
	schema, err := loadSchema()
	if err != nil {
		return nil, err
	}

	serviceSchema, ok := schema[service]
	if !ok {
		return nil, fmt.Errorf("unknown service %q", service)
	}

	source := env
	if source == nil {
		source = make(map[string]string)
		for _, entry := range os.Environ() {
			parts := strings.SplitN(entry, "=", 2)
			key := parts[0]
			var value string
			if len(parts) > 1 {
				value = parts[1]
			}
			source[key] = value
		}
	}

	errs := make([]string, 0)
	config := make(Config)

	for key, definition := range serviceSchema {
		envKey := definition.Env
		if envKey == "" {
			envKey = key
		}

		raw, exists := source[envKey]
		value, err := coerce(raw, exists, definition)
		if err != nil {
			errs = append(errs, fmt.Sprintf("%s: %v", envKey, err))
			continue
		}

		if value == nil {
			if definition.Default != nil {
				value = definition.Default
				} else if definition.Required {
					errs = append(errs, "missing required value")
				continue
			}
		}

		if value != nil {
			config[key] = value
		}
	}

	if len(errs) > 0 {
		return nil, errors.New("configuration errors: " + strings.Join(errs, "; "))
	}

	return config, nil
}

func coerce(raw string, exists bool, definition ConfigDefinition) (interface{}, error) {
	switch definition.Type {
	case "string", "":
		if !exists || raw == "" {
			return nil, nil
			// string default handled by caller
		}
		return raw, nil
	case "number":
		if !exists || raw == "" {
			return nil, nil
		}
		if strings.Contains(raw, ".") {
			parsed, err := strconv.ParseFloat(raw, 64)
			if err != nil {
				return nil, err
			}
			return parsed, nil
		}
		parsed, err := strconv.ParseInt(raw, 10, 64)
		if err != nil {
			return nil, err
		}
		return parsed, nil
	case "boolean":
		if !exists || raw == "" {
			return nil, nil
		}
		switch strings.ToLower(raw) {
		case "true", "1", "yes", "y":
			return true, nil
		case "false", "0", "no", "n":
			return false, nil
		default:
			return nil, fmt.Errorf("invalid boolean value %q", raw)
		}
	default:
		return nil, fmt.Errorf("unsupported type %q", definition.Type)
	}
}

// Schema returns the full configuration schema.
func SchemaData() (Schema, error) {
	return loadSchema()
}
