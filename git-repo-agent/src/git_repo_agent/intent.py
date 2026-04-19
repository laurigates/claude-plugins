"""Natural-language project idea → ``NewProjectSpec`` via a Claude SDK one-shot.

Phase 1 of ``git-repo-agent new``. The command feeds the user's idea
(e.g. ``"Telegram chat bot that replies to user messages"``) into a small
single-turn ``ClaudeSDKClient`` session whose system prompt asks for a
strict JSON response. The JSON is parsed and validated into a
``NewProjectSpec`` the rest of the pipeline can trust.

If the model is unreachable or the response is malformed, this module
raises ``IntentParseError``. The ``new`` command hard-fails in that case
rather than attempting a name-only fallback — the whole point of the
one-shot command is to get a stack-appropriate scaffold, and a guessed
scaffold is worse than no scaffold at all.
"""

from __future__ import annotations

import json
import logging
import re
from typing import Any

from claude_agent_sdk import (
    AssistantMessage,
    ClaudeAgentOptions,
    ClaudeSDKClient,
    TextBlock,
)

from .creator import NewProjectSpec, slugify

logger = logging.getLogger(__name__)

_KNOWN_LANGUAGES: frozenset[str] = frozenset(
    {"python", "typescript", "javascript", "rust", "go", "default"}
)
_KNOWN_INDICATORS: frozenset[str] = frozenset(
    {
        "python", "typescript", "javascript", "rust", "go",
        "docker", "github-actions", "esp-idf", "esphome",
    }
)


class IntentParseError(RuntimeError):
    """Raised when the model returned nothing parseable or was unreachable."""


_SYSTEM_PROMPT = """You classify short software-project ideas.

Given an idea in one or two sentences, output ONLY a single JSON object
describing the project. No prose, no markdown fences, no explanation.

Fields:

- name: concise human-readable title case (not a sentence). Max 40 chars.
- description: one-sentence description for README + GitHub repo
  description. Max 140 chars.
- language: one of python, typescript, javascript, rust, go, default.
  Pick the most likely primary language. Use "default" only if none fits.
- stack_indicators: array of values from this exact set: python,
  typescript, javascript, rust, go, docker, github-actions, esp-idf,
  esphome. Always include the chosen language. Add docker only if
  containerisation is clearly central. Add github-actions for any
  project that will benefit from CI (default: yes, unless trivial).

Respond with JSON only.
"""


async def parse_intent(idea: str) -> NewProjectSpec:
    """Parse an idea string into a ``NewProjectSpec`` via the Claude API.

    Raises ``IntentParseError`` on any failure (connection, timeout,
    malformed JSON, missing required fields). The error message is meant
    to be surfaced to the user as-is.
    """
    options = ClaudeAgentOptions(
        system_prompt=_SYSTEM_PROMPT,
        max_turns=1,
        allowed_tools=[],
    )
    collected: list[str] = []
    try:
        async with ClaudeSDKClient(options) as client:
            await client.query(
                f"Project idea: {idea}\n\nRespond with the JSON object."
            )
            async for msg in client.receive_response():
                if isinstance(msg, AssistantMessage):
                    for block in msg.content:
                        if isinstance(block, TextBlock):
                            collected.append(block.text)
    except Exception as exc:  # pragma: no cover — network paths
        raise IntentParseError(
            f"Could not reach Claude API to parse project intent: {exc}. "
            "Re-run later or pass --name / --language explicitly."
        ) from exc

    return _parse_model_response(idea=idea, raw="".join(collected))


def _parse_model_response(*, idea: str, raw: str) -> NewProjectSpec:
    """Extract and validate the model's JSON response.

    Factored out so tests can exercise the parser without spinning up
    an SDK session.
    """
    text = raw.strip()
    if not text:
        raise IntentParseError("Model returned an empty response.")

    # The model occasionally wraps JSON in code fences despite instructions.
    # Strip a leading ```json / ``` and a trailing ```.
    text = re.sub(r"^```(?:json)?\s*", "", text)
    text = re.sub(r"\s*```\s*$", "", text)

    try:
        data = json.loads(text)
    except json.JSONDecodeError as exc:
        raise IntentParseError(
            f"Model response was not valid JSON: {exc}. "
            f"Response (first 200 chars): {text[:200]!r}"
        ) from exc

    if not isinstance(data, dict):
        raise IntentParseError(
            f"Model response was {type(data).__name__}, expected object."
        )

    return _build_spec(idea=idea, data=data)


def _build_spec(*, idea: str, data: dict[str, Any]) -> NewProjectSpec:
    name_raw = data.get("name")
    if not isinstance(name_raw, str) or not name_raw.strip():
        raise IntentParseError("Model output missing or empty 'name' field.")
    name = name_raw.strip()

    description_raw = data.get("description") or idea
    description = str(description_raw).strip()

    language = str(data.get("language") or "default").strip().lower()
    if language not in _KNOWN_LANGUAGES:
        logger.debug("Unknown language %r from model; coercing to 'default'.", language)
        language = "default"

    raw_indicators = data.get("stack_indicators") or []
    if not isinstance(raw_indicators, list):
        raise IntentParseError(
            f"'stack_indicators' must be a list, got {type(raw_indicators).__name__}."
        )
    indicators: list[str] = []
    for item in raw_indicators:
        norm = str(item).strip().lower()
        if norm in _KNOWN_INDICATORS and norm not in indicators:
            indicators.append(norm)
    if language != "default" and language not in indicators:
        indicators.insert(0, language)

    return NewProjectSpec(
        name=name,
        slug=slugify(name),
        description=description,
        idea=idea,
        language=language,
        stack_indicators=tuple(indicators),
        extra_plugins=(),
    )


__all__ = ["IntentParseError", "parse_intent"]
