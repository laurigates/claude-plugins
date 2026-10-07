# comfy-node — Pipeline Overview

The end-to-end shape this orchestrator automates, as a diagram, and where its single human gate sits. Entry point: [`../SKILL.md`](../SKILL.md).

## The shape it automates

```mermaid
flowchart LR
  idea["idea"] --> sc["scaffold.py"] --> gh["gh repo create<br/>+ seed main"] --> gop["gitops PR<br/>(entry + import block)"]
  gop --> gate["👤 merge gitops PR"] --> apply["tofu-apply on release:<br/>adopt + secrets + protection"] --> rm["remove import block"] --> impl["implement + release"]
  classDef g fill:#1b4332,stroke:#2d6a4f,color:#fff
  classDef m fill:#6a040f,stroke:#9d0208,color:#fff
  class sc,gh,gop,apply,rm g
  class gate,impl m
```

Everything left of the gate is one orchestrated pass. There is **no scaffold
PR** — the seed goes straight to `main` (see Phase 3 for why). The single gate
(merging the gitops PR) is intentionally human — it feeds the apply pipeline on
shared infra state (release-please cuts a gitops release, whose publication
triggers the `tofu-apply.yml` GitHub Actions workflow). Never merge it on the
user's behalf.
