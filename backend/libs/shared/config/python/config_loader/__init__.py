from __future__ import annotations

import json
import os
from functools import lru_cache
from pathlib import Path
from typing import Any, Dict, Mapping, MutableMapping

ConfigValue = Any
ConfigDefinition = Dict[str, Any]
ServiceSchema = Dict[str, ConfigDefinition]
ConfigSchema = Dict[str, ServiceSchema]

_SCHEMA_PATH = Path(__file__).resolve().parents[2] / "schema" / "schema.json"


class ConfigurationError(ValueError):
    """Raised when configuration validation fails."""


@lru_cache(maxsize=1)
def _load_schema() -> ConfigSchema:
    if not _SCHEMA_PATH.exists():
        raise FileNotFoundError(f"Configuration schema not found at {_SCHEMA_PATH}")
    with _SCHEMA_PATH.open("r", encoding="utf-8") as handle:
        return json.load(handle)


def _coerce(value: str | None, definition: ConfigDefinition) -> ConfigValue:
    expected_type = definition.get("type")
    if expected_type == "string" or expected_type is None:
        return value
    if expected_type == "number":
        if value is None or value == "":
            return None
        try:
            if "." in value:
                return float(value)
            return int(value)
        except ValueError as exc:  # pragma: no cover - defensive
            raise ConfigurationError(str(exc)) from exc
    if expected_type == "boolean":
        if value is None:
            return None
        normalized = value.strip().lower()
        if normalized in {"true", "1", "yes", "y"}:
            return True
        if normalized in {"false", "0", "no", "n"}:
            return False
        raise ConfigurationError(f"Invalid boolean value '{value}'")
    raise ConfigurationError(f"Unsupported configuration type '{expected_type}'")


def load_config(
    service_name: str, env: Mapping[str, str] | None = None
) -> MutableMapping[str, ConfigValue]:
    schema = _load_schema()
    if service_name not in schema:
        raise ConfigurationError(f"Unknown service '{service_name}'")

    service_schema = schema[service_name]
    source_env = env or os.environ
    errors: list[str] = []
    config: Dict[str, ConfigValue] = {}

    for key, definition in service_schema.items():
        env_key = definition.get("env", key)
        raw_value = source_env.get(env_key)

        try:
            coerced = _coerce(raw_value, definition)
        except ConfigurationError as exc:
            errors.append(f"{env_key}: {exc}")
            continue

        if coerced is None:
            if "default" in definition:
                coerced = definition["default"]
            elif definition.get("required", False):
                errors.append(f"Missing required configuration value '{env_key}'")
                continue

        config[key] = coerced

    if errors:
        joined = "\n - ".join(errors)
        raise ConfigurationError(
            f"Configuration errors for service '{service_name}':\n - {joined}"
        )

    return config


def get_schema() -> ConfigSchema:
    """Return the raw configuration schema."""

    return _load_schema().copy()


__all__ = [
    "ConfigurationError",
    "load_config",
    "get_schema",
]
