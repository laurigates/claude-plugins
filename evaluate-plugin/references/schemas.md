# Evaluation Data Schemas

JSON schemas for all data structures used in the evaluation workflow.

## evals.json — Evaluation Test Cases

Defines test cases for a skill. Lives alongside the SKILL.md it tests. **Version-controlled.**

```json
{
  "skill_name": "string — skill identifier (kebab-case)",
  "skill_path": "string — relative path to SKILL.md",
  "evals": [
    {
      "id": "string — unique eval identifier (e.g., eval-001)",
      "description": "string — what this test validates",
      "prompt": "string — the user prompt to simulate",
      "expectations": [
        "string — assertion that the output should satisfy"
      ],
      "context_files": [
        "string — optional files to make available during evaluation"
      ],
      "tags": [
        "string — categorization tags for filtering"
      ]
    }
  ]
}
```

### Field Details

| Field | Required | Description |
|-------|----------|-------------|
| `skill_name` | Yes | Matches the `name` field in SKILL.md frontmatter |
| `skill_path` | Yes | Relative path from repository root |
| `evals[].id` | Yes | Unique within the file, used in result directories |
| `evals[].description` | Yes | Human-readable description of what's being tested |
| `evals[].prompt` | Yes | The simulated user request |
| `evals[].expectations` | Yes | List of assertion strings (grader checks these) |
| `evals[].context_files` | No | Files to include in evaluation context |
| `evals[].tags` | No | Tags for filtering (e.g., `basic`, `edge-case`) |

### Writing Good Assertions

| Assertion Quality | Example |
|-------------------|---------|
| Too vague | "Output is correct" |
| Too specific | "Output contains exactly 'feat(auth): add OAuth2'" |
| Good | "Commit message starts with feat(" |
| Good | "Output includes issue reference #42" |
| Good | "Created file contains at least 3 test cases" |

### Typed Checks (deterministic grading)

Each item in `expectations` is **either** a plain string (graded by the LLM
`eval-grader` — the `judge` path) **or** a typed object that
`scripts/grade_deterministic.py` grades with zero model tokens. Mixing both in
one `expectations` array is supported and backward compatible.

```json
{
  "assertion": "string — human-readable assertion (also shown to the judge)",
  "check": "regex | substring | substring_all | absent_regex | judge",
  "pattern": "string — regex (for regex / absent_regex)",
  "value": "string — substring to find (for substring)",
  "values": ["string — all must be present (for substring_all)"],
  "scope": "full | subject | body  — default full",
  "flags": "string — any of imsx, regex flags (for regex / absent_regex)"
}
```

| `check` | Passes when | Required field |
|---------|-------------|----------------|
| `regex` | `pattern` matches within `scope` | `pattern` |
| `substring` | `value` appears within `scope` | `value` |
| `substring_all` | every entry in `values` appears within `scope` | `values` |
| `absent_regex` | `pattern` does **not** match within `scope` | `pattern` |
| `judge` | deferred to the LLM grader (default for bare strings) | — |

`scope`: `subject` = first non-empty line, `body` = text after the first blank
line, `full` = whole output. Prefer typed checks for anything mechanically
verifiable; reserve `judge` for genuinely fuzzy expectations (tone, mood,
"provides context"). See
[`docs/cross-model-evaluation.md`](../docs/cross-model-evaluation.md).

## grading.json — Grading Output

Produced by the `eval-grader` agent for each eval run. **Gitignored.**

```json
{
  "eval_id": "string — matches evals[].id",
  "skill_path": "string — path to SKILL.md",
  "expectations": [
    {
      "assertion": "string — the assertion text from evals.json",
      "passed": "boolean",
      "evidence": "string — specific evidence from transcript/artifacts",
      "confidence": "string — high | medium | low"
    }
  ],
  "summary": {
    "passed": "number — count of passed assertions",
    "failed": "number — count of failed assertions",
    "total": "number — total assertions",
    "pass_rate": "number — 0.0 to 1.0"
  },
  "claims": [
    {
      "claim": "string — implicit claim extracted from output",
      "verified": "boolean",
      "evidence": "string — verification evidence"
    }
  ],
  "eval_feedback": "string | null — suggestions for improving eval cases",
  "metrics": {
    "tool_calls": "number — count of tool invocations",
    "output_chars": "number — total output character count",
    "errors": "number — count of errors during execution"
  }
}
```

## benchmark.json — Aggregated Benchmark Results

Aggregated across runs for a single skill. **Gitignored.**

```json
{
  "metadata": {
    "skill_path": "string",
    "timestamp": "string — ISO-8601",
    "num_evals": "number",
    "num_runs_per_eval": "number",
    "configurations": ["with_skill", "baseline"]
  },
  "results": [
    {
      "eval_id": "string",
      "config": "string — with_skill | baseline",
      "runs": [
        {
          "run_id": "string",
          "grading": "object — grading.json contents",
          "timing": {
            "duration_ms": "number",
            "total_tokens": "number"
          }
        }
      ]
    }
  ],
  "summary": {
    "with_skill": {
      "mean_pass_rate": "number — 0.0 to 1.0",
      "stddev_pass_rate": "number",
      "min_pass_rate": "number",
      "max_pass_rate": "number",
      "mean_duration_ms": "number"
    },
    "baseline": {
      "mean_pass_rate": "number — 0.0 to 1.0 (null if no baseline)",
      "stddev_pass_rate": "number",
      "min_pass_rate": "number",
      "max_pass_rate": "number",
      "mean_duration_ms": "number"
    },
    "delta": {
      "pass_rate_improvement": "number — with_skill - baseline",
      "duration_overhead_ms": "number — with_skill - baseline"
    }
  },
  "analyst_notes": [
    "string — observations from aggregation"
  ]
}
```

## comparison.json — Blind Comparison Output

Produced by the `eval-comparator` agent. **Gitignored.**

```json
{
  "eval_id": "string",
  "winner": "string — A | B | tie",
  "reasoning": "string — why the winner is better",
  "scores": {
    "A": { "content": "number 1-5", "structure": "number 1-5", "overall": "number 2-10" },
    "B": { "content": "number 1-5", "structure": "number 1-5", "overall": "number 2-10" }
  },
  "quality_assessment": {
    "A": {
      "strengths": ["string"],
      "weaknesses": ["string"]
    },
    "B": {
      "strengths": ["string"],
      "weaknesses": ["string"]
    }
  },
  "expectations": [
    {
      "assertion": "string",
      "A_passed": "boolean",
      "B_passed": "boolean"
    }
  ]
}
```

## analysis.json — Analysis Output

Produced by the `eval-analyzer` agent. **Gitignored.**

```json
{
  "mode": "string — comparison | benchmark",
  "skill_path": "string",
  "comparison": {
    "winner": "string — with_skill | baseline",
    "instruction_following_score": "number — 1 to 10",
    "strengths": ["string"],
    "weaknesses": ["string"],
    "suggestions": [
      {
        "priority": "string — high | medium | low",
        "category": "string — instructions | description | examples | error_handling | tools | structure | references",
        "suggestion": "string — actionable improvement",
        "evidence": "string — data supporting the suggestion"
      }
    ]
  },
  "patterns": [
    "string — data-grounded observations"
  ]
}
```

## history.json — Improvement Iteration Tracking

Tracks skill improvements over evaluation cycles. **Gitignored.**

```json
{
  "skill_path": "string",
  "start_time": "string — ISO-8601",
  "current_best_version": "string — e.g., v3",
  "iterations": [
    {
      "version": "string — e.g., v1",
      "parent_version": "string | null",
      "timestamp": "string — ISO-8601",
      "pass_rate": "number — 0.0 to 1.0",
      "changes_made": "string — summary of changes"
    }
  ]
}
```

## model-matrix.json — Cross-Model Results

Records with-skill and baseline pass rates for one skill across pinned models.
Consumed by `scripts/render_matrix_report.py`. **Gitignored** (the rendered
report and stored history are the durable artifacts). See
[`docs/cross-model-evaluation.md`](../docs/cross-model-evaluation.md).

```json
{
  "metadata": {
    "skill_path": "string",
    "generated_at": "string — ISO-8601",
    "previous_run": "string | null — ISO-8601 of the last sweep, for Δ vs prev",
    "models": [
      { "alias": "string — opus | sonnet | haiku", "model_id": "string — pinned id, e.g. claude-opus-4-8" }
    ]
  },
  "evals": [
    {
      "eval_id": "string",
      "by_model": {
        "<alias>": { "with_skill": "number 0.0-1.0", "baseline": "number 0.0-1.0" }
      }
    }
  ],
  "summary": {
    "by_model": {
      "<alias>": {
        "with_skill": "number — mean pass rate across evals",
        "baseline": "number — mean baseline pass rate",
        "delta": "number — with_skill - baseline",
        "prev_delta": "number | null — delta from previous_run, drives the ▲/▼ marker"
      }
    }
  }
}
```

The renderer derives per-model verdicts (`earns its keep`, `possibly redundant`,
`fighting the model`, `ineffective`, `marginal`) from `with_skill`/`baseline`,
and raises a portability flag when the opus−haiku with-skill spread is ≥20
points.

## plugin-benchmark.json — Plugin-Level Aggregation

Aggregated across all skills in a plugin. **Gitignored.**

```json
{
  "metadata": {
    "plugin_name": "string",
    "timestamp": "string — ISO-8601",
    "skills_evaluated": "number",
    "skills_total": "number"
  },
  "skills": [
    {
      "skill_name": "string",
      "skill_path": "string",
      "num_evals": "number",
      "mean_pass_rate": "number — 0.0 to 1.0",
      "status": "string — PASS (>=80%) | PARTIAL (50-79%) | FAIL (<50%)"
    }
  ],
  "summary": {
    "overall_pass_rate": "number — 0.0 to 1.0",
    "skills_passing": "number",
    "skills_partial": "number",
    "skills_failing": "number"
  }
}
```
