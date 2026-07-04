# Claude API integration notes (for ClaudeCoach)

Swift has no official Anthropic SDK — use raw HTTP via URLSession. These notes are
current as of 2026-07; follow them over training-data memory (several API shapes
changed in 2025–2026).

## Request

- `POST https://api.anthropic.com/v1/messages`
- Headers: `x-api-key: <key>`, `anthropic-version: 2023-06-01`, `content-type: application/json`
- Model: default **`claude-opus-4-8`** (exact string, no date suffix). Make the model id a
  constant that can be overridden via config; `claude-sonnet-5` is the cheaper fallback
  tier if the user ever wants it. Do NOT use retired ids like `claude-3-5-sonnet-*`.
- `max_tokens`: 2048 is plenty for a coaching plan.
- Do NOT send `temperature`, `top_p`, `top_k` (removed on Opus 4.8 — request returns 400).
- Do NOT send a `thinking` field (omitting it runs without thinking on Opus 4.8, which is
  what we want for a fast structured-coaching call).
- Do NOT prefill an assistant turn (400 on current models).

## Forced structured output

Use `output_config.format` with a JSON schema — this guarantees the first content block
is a `text` block containing valid JSON matching the schema (no tool-use round trip
needed):

```json
{
  "model": "claude-opus-4-8",
  "max_tokens": 2048,
  "system": "<swing model + coaching principles + voice>",
  "messages": [{"role": "user", "content": "<compact metrics JSON>"}],
  "output_config": {
    "format": {
      "type": "json_schema",
      "schema": {
        "type": "object",
        "properties": {
          "verdict": {"type": "string"},
          "goals": {
            "type": "array",
            "items": {
              "type": "object",
              "properties": {
                "priority": {"type": "integer"},
                "title": {"type": "string"},
                "detail": {"type": "string"},
                "metricLabel": {"type": "string"},
                "current": {"type": "string"},
                "target": {"type": "string"},
                "drill": {"type": "string"},
                "drillDetail": {"type": "string"}
              },
              "required": ["priority","title","detail","metricLabel","current","target","drill","drillDetail"],
              "additionalProperties": false
            }
          }
        },
        "required": ["verdict","goals"],
        "additionalProperties": false
      }
    }
  }
}
```

Schema rules: every object needs `additionalProperties: false` and `required`; numeric
(`minimum`/`maximum`) and string-length constraints are NOT supported — enforce goal-count
(2–4) in the prompt text and clamp client-side.

## Response

```json
{"content": [{"type": "text", "text": "{...coaching JSON...}"}],
 "stop_reason": "end_turn", "usage": {...}}
```

- Parse `content[].type == "text"` → `text` is the JSON document; decode into CoachingPlan.
- Check `stop_reason` before parsing: `"max_tokens"` → truncated (treat as failure, fall
  back to rules); `"refusal"` → treat as failure (do not retry same content).

## Errors + retry

| HTTP | Meaning | Action |
|---|---|---|
| 400 | bad request (e.g. sampling params, bad schema) | fail → rules fallback, log status only |
| 401/403 | bad key/permissions | fail → rules fallback |
| 429 | rate limited | one retry after `retry-after` header seconds (cap 10s) |
| 500/529 | server overload | one retry with ~2s backoff |

- URLSession timeoutIntervalForRequest = 15s. Any failure → CoachingService falls back to
  RuleBasedCoach. Never log the API key, the system prompt, or the full request body.

## Prompt-caching note (optional, cheap win)

The system prompt (swing model + principles) is identical across calls — mark it as a
cacheable block: `"system": [{"type": "text", "text": "...", "cache_control": {"type": "ephemeral"}}]`.
Minimum cacheable prefix on Opus 4.8 is 4096 tokens; if our system prompt is smaller it
silently won't cache — harmless either way.
