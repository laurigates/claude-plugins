# Cold-Read Gate - Rendered Context

What to tell the cold reader to ignore when the artifact is published into a
surface (PR comment, review thread, dashboard, chat) that renders state around it.

## The reader is context-free; your audience may not be

The gate removes context on purpose, and for a bug report filed into an empty
tracker that matches the real reader well. It matches badly whenever the
artifact is published *into a surface that renders state around it* — a PR or
issue comment, a review thread, a dashboard card, a chat message under a link
preview. There the real reader sees the page; the cold reader sees a bare file.
The gate then asks for explanations the surface already supplies, and acting on
them inflates the artifact with duplication.

> Observed 2026-09-02 (`Comfy-Org/ComfyUI_frontend#13280`): round-one readers
> asked what the fork-PR approval gate was and whether the four named workflows
> were the whole set. Answering both produced a closing paragraph that restated
> the merge box sitting directly below the comment — "17 workflows awaiting
> approval / This workflow requires approval from a maintainer", GitHub's own
> explainer link, and the required checks by name. The comment lost 58% of its
> words when a human asked whether that paragraph needed to exist.

- **Name the rendered context in the `Ignore:` list**, concretely enough that
  the reader stops asking: the merge box, check names and states, review
  status, branch names, labels, diff size.
- **A verdict scores sentences, never whether a paragraph should exist.** Both
  this gate and a prose linter judge what is on the page. Neither asks what
  should be cut, so a `needs-revision` acted on literally makes an artifact
  longer — check the word count across rounds, and treat growth as a signal to
  re-read rather than a sign of progress.
- **Disclosed limitations are not defects.** A reader will often restate a
  caveat the author volunteered as a reason to hesitate. Tell it to judge
  clarity, not merge-readiness, or it converts your honesty into a `needs-revision`.

For the GitHub-specific inventory of what the page renders, see
`repos-claude-config` `.claude/rules/pr-comment-vs-ui-affordances.md`.
