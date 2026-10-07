# Verify Before Filing — Verdict Vocabulary

Open this when interpreting a Phase 1 verdict or writing the Phase 4 disposition
annotation for a candidate.

## Verdict Vocabulary Notes

| Verdict | Meaning | Typical doc annotation |
|---|---|---|
| `still-present` | Reproduced at HEAD + latest tag | filed URL |
| `partially-fixed` | Upstream fixed some instances; file the remainder, cite their own fix as the pattern | filed URL (narrowed) |
| `fixed-upstream` | Shipped in a release — note which | version + local follow-up |
| `obsolete-version` | The affected line is superseded/retired | superseded note |
| `claim-invalid` | The original diagnosis was wrong | retraction + what was actually true |
| `could-not-verify` | Evidence unreachable | human follow-up task |

`claim-invalid` is not failure — it's the workflow catching your own docs
drifting from reality. Correct the doc in the same pass.
