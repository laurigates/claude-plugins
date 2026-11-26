# __NAME__

| Field | Value |
|---|---|
| Question | __QUESTION__ |
| Ref | __REF__ |
| Requires OS | __OS__ |
| Run | `just run __SLUG__` |

## Verdicts

| STATUS | Meaning | Next step |
|---|---|---|
__CODES_TABLE__
| INCONCLUSIVE | The control failed or the test decided nothing | Read `results/`, fix the setup |
| SKIP | Wrong OS for this probe | Run it on the named OS |
| ERROR | A required tool is missing | Install it and re-run |

Raw output lands in `results/`; `results/summary.txt` holds the header and verdict block.
