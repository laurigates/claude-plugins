"""Tests for the intent parser used by ``git-repo-agent new``.

The pure JSON-parsing logic (``_parse_model_response`` / ``_build_spec``)
is exercised directly. ``parse_intent`` itself is tested with a fake SDK
client so the tests don't depend on network.
"""

from __future__ import annotations

import asyncio
import json
from dataclasses import dataclass

import pytest

from git_repo_agent.creator import NewProjectSpec
from git_repo_agent.intent import (
    IntentParseError,
    _parse_model_response,
    parse_intent,
)


# ---------------------------------------------------------------------------
# _parse_model_response — JSON handling
# ---------------------------------------------------------------------------


def _valid_json(**over) -> str:
    payload = {
        "name": "Telegram Chat Bot",
        "description": "Bot that replies to users on Telegram.",
        "language": "python",
        "stack_indicators": ["python", "github-actions"],
    }
    payload.update(over)
    return json.dumps(payload)


class TestParseModelResponse:
    def test_happy_path(self):
        spec = _parse_model_response(
            idea="Telegram chat bot that replies to user messages",
            raw=_valid_json(),
        )
        assert spec.name == "Telegram Chat Bot"
        assert spec.slug == "telegram-chat-bot"
        assert spec.language == "python"
        assert spec.stack_indicators == ("python", "github-actions")
        assert "Bot that replies to users" in spec.description

    def test_strips_markdown_code_fence(self):
        raw = "```json\n" + _valid_json() + "\n```"
        spec = _parse_model_response(idea="foo", raw=raw)
        assert spec.name == "Telegram Chat Bot"

    def test_strips_plain_code_fence(self):
        raw = "```\n" + _valid_json() + "\n```"
        spec = _parse_model_response(idea="foo", raw=raw)
        assert spec.language == "python"

    def test_empty_response_raises(self):
        with pytest.raises(IntentParseError, match="empty"):
            _parse_model_response(idea="foo", raw="")

    def test_invalid_json_raises(self):
        with pytest.raises(IntentParseError, match="not valid JSON"):
            _parse_model_response(idea="foo", raw="this is not json")

    def test_non_object_raises(self):
        with pytest.raises(IntentParseError, match="expected object"):
            _parse_model_response(idea="foo", raw='["an", "array"]')

    def test_missing_name_raises(self):
        raw = json.dumps({"language": "python", "stack_indicators": ["python"]})
        with pytest.raises(IntentParseError, match="name"):
            _parse_model_response(idea="foo", raw=raw)

    def test_empty_name_raises(self):
        with pytest.raises(IntentParseError, match="name"):
            _parse_model_response(idea="foo", raw=_valid_json(name="   "))

    def test_description_defaults_to_idea_when_missing(self):
        raw = json.dumps({
            "name": "Foo",
            "language": "python",
            "stack_indicators": ["python"],
        })
        spec = _parse_model_response(idea="the original idea", raw=raw)
        assert spec.description == "the original idea"

    def test_unknown_language_coerced_to_default(self):
        spec = _parse_model_response(
            idea="foo",
            raw=_valid_json(language="cobol", stack_indicators=[]),
        )
        assert spec.language == "default"

    def test_language_inserted_into_indicators(self):
        spec = _parse_model_response(
            idea="foo",
            raw=_valid_json(language="rust", stack_indicators=["github-actions"]),
        )
        # rust is prepended to the indicator list.
        assert spec.stack_indicators[0] == "rust"
        assert "github-actions" in spec.stack_indicators

    def test_default_language_not_inserted(self):
        spec = _parse_model_response(
            idea="foo",
            raw=_valid_json(language="default", stack_indicators=["github-actions"]),
        )
        assert "default" not in spec.stack_indicators
        assert spec.stack_indicators == ("github-actions",)

    def test_unknown_indicators_silently_dropped(self):
        spec = _parse_model_response(
            idea="foo",
            raw=_valid_json(
                language="python",
                stack_indicators=["python", "quantum-computing", "github-actions"],
            ),
        )
        assert spec.stack_indicators == ("python", "github-actions")

    def test_stack_indicators_wrong_type_raises(self):
        raw = json.dumps({
            "name": "Foo",
            "language": "python",
            "stack_indicators": "python,github-actions",  # string, not list
        })
        with pytest.raises(IntentParseError, match="stack_indicators"):
            _parse_model_response(idea="foo", raw=raw)


# ---------------------------------------------------------------------------
# parse_intent with a fake SDK client
# ---------------------------------------------------------------------------


@dataclass
class _FakeTextBlock:
    text: str


@dataclass
class _FakeAssistantMessage:
    content: list


class _FakeClient:
    """Stand-in for ``ClaudeSDKClient`` used in ``parse_intent`` tests."""

    def __init__(self, response_json: str):
        self._response_json = response_json
        self.queries: list[str] = []

    async def __aenter__(self):
        return self

    async def __aexit__(self, exc_type, exc, tb):
        return False

    async def query(self, prompt: str) -> None:
        self.queries.append(prompt)

    async def receive_response(self):
        # Reuse the real SDK's AssistantMessage/TextBlock classes so the
        # isinstance() checks in parse_intent match.
        from claude_agent_sdk import AssistantMessage, TextBlock

        yield AssistantMessage(
            content=[TextBlock(text=self._response_json)],
            model="fake-model",
        )


def _make_fake_client_factory(response_json: str):
    def factory(options):
        return _FakeClient(response_json)
    return factory


class TestParseIntent:
    def test_happy_path_with_fake_client(self, monkeypatch):
        monkeypatch.setattr(
            "git_repo_agent.intent.ClaudeSDKClient",
            _make_fake_client_factory(_valid_json()),
        )
        spec = asyncio.run(parse_intent("Telegram chat bot"))
        assert spec.name == "Telegram Chat Bot"
        assert spec.slug == "telegram-chat-bot"
        assert spec.language == "python"

    def test_sdk_exception_raises_intent_parse_error(self, monkeypatch):
        class _BoomClient:
            def __init__(self, options):
                pass

            async def __aenter__(self):
                raise RuntimeError("no network")

            async def __aexit__(self, exc_type, exc, tb):
                return False

        monkeypatch.setattr(
            "git_repo_agent.intent.ClaudeSDKClient", _BoomClient,
        )
        with pytest.raises(IntentParseError, match="Could not reach Claude"):
            asyncio.run(parse_intent("anything"))
