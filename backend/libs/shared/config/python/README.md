# Ordering Intelligence Config (Python)

Lightweight configuration loader shared across Ordering Intelligence Python services. It validates environment variables against the packaged copy of the canonical shared configuration schema and performs basic type coercion.

## Usage

```python
from config_loader import load_config

config = load_config("order-service")
print(config["ASR_PROVIDER"])
```

The loader raises `ValueError` when required variables are missing or incorrectly typed.
