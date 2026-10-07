# session-wrap — Auto-surfacing

A Stop hook (`hooks/session-end-nudge.sh`) offers
`session-plugin:session-end` (which can route here) once per session on
genuine user wind-down phrasing. It stays silent while this skill is
running. Pre-silence for a session:
`touch ~/.cache/claude-session-end-nudge/<session_id>`.
