# session-end — Auto-surfacing

## Auto-surfacing

A Stop hook (`hooks/session-end-nudge.sh`) offers this skill at most
once per session when the user's own messages carry a wind-down phrase.
It is offer-only and stays silent when this skill (or wrap/distill) is
already in the transcript. Pre-silence:
`touch ~/.cache/claude-session-end-nudge/<session_id>`.
