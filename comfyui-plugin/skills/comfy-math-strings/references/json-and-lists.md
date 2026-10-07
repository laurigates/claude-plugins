# ComfyUI math & strings — JSON and Lists (Crystools)

Loading and extracting JSON, and building lists, with Crystools nodes. Entry point: [`../SKILL.md`](../SKILL.md).

## JSON & lists (Crystools)

| Node | Use |
|---|---|
| `CJsonFile` | Load a JSON file from disk; emits the parsed structure as a JSON object |
| `CJsonExtractor` | Extract values from a JSON object via dot-path / JSONPath syntax |
| `CListAny` | Build / pass a list of any type |
| `CListString` | Build a list of strings (sometimes more convenient than concatenation) |

Typical use: load a config JSON, extract one value, feed into a
downstream node. The Crystools JSON nodes don't do JSON-write; for
that, save text via bjornulf `SaveText` or use the `MathExpression`
escape hatch.
