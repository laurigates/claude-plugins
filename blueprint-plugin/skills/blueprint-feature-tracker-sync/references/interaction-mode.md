# feature-tracker-sync — Interaction Mode (quiet vs. interactive)

When `EFFECTIVE_INTERACTION_MODE=quiet` **and** this invocation was
automation-initiated (autopilot, session bookend, drift-nudge follow-up — not
a slash command the user typed), skip closing navigation menus ("what next?" /
"create another?" style): apply the safe default and end with a one-line
receipt instead. Quiet mode never skips confirmation gates that guard writes —
only navigation menus. A direct user invocation always behaves fully
interactively (explicit intent overrides quiet; see ADR-0020).
