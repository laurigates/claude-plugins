
BUGS = json.loads(r"""[{"file": "inventory/batching.py", "line": 17, "category": "off-by-one"}, {"file": "inventory/stock.py", "line": 24, "category": "concurrency"}, {"file": "inventory/search.py", "line": 14, "category": "injection"}, {"file": "inventory/tags.py", "line": 8, "category": "mutable-default"}, {"file": "inventory/importer.py", "line": 30, "category": "error-handling"}, {"file": "inventory/reservations.py", "line": 28, "category": "timezone"}]""")
HARMLESS = json.loads(r"""[{"file": "inventory/batching.py", "line": 24}, {"file": "inventory/stock.py", "line": 38}, {"file": "inventory/search.py", "line": 19}]""")
CATS = json.loads(r"""["off-by-one", "concurrency", "injection", "mutable-default", "error-handling", "timezone", "resource-leak", "null-handling", "performance", "other"]""")
TOL = 3


def norm(path):
    p = str(path).replace("\\", "/").strip()
    while p.startswith("./"):
        p = p[2:]
    if p.startswith("repo/"):
        p = p[5:]
    return p


try:
    with open(os.path.join(WD, "findings.json"), encoding="utf-8") as fh:
        raw = json.load(fh)
    if not isinstance(raw, list):
        raise ValueError("findings.json must be a list")
    findings = []
    for f in raw:
        try:
            findings.append((norm(f["file"]), int(f["line"]), str(f.get("category", "")).strip().lower()))
        except Exception:
            pass
except Exception:
    findings = None


def near(f, target, tol=TOL):
    return f[0] == target["file"] and abs(f[1] - target["line"]) <= tol


for b in BUGS:
    tag = f"{b['file']}:{b['line']} {b['category']}"
    case(f"found {tag}", lambda b=b: findings is not None and any(near(f, b) for f in findings))
    case(f"category {tag}", lambda b=b: findings is not None and any(near(f, b) and f[2] == b["category"] for f in findings), weight=0.5)
for h in HARMLESS:
    case(f"no finding on harmless change {h['file']}:{h['line']}",
         lambda h=h: findings is not None and not any(near(f, h, 1) for f in findings))
case("findings.json present and well-formed", lambda: findings is not None and len(findings) > 0)
# Unmatched findings (not near any planted bug or harmless change) beyond 2 cost 0.05 each.
stray = 0
if findings:
    stray = sum(1 for f in findings
                if not any(near(f, t) for t in BUGS) and not any(near(f, t, 1) for t in HARMLESS))
total = sum(w for _, _, w in results)
base = sum(w for _, ok, w in results if ok) / total
done(score=base - 0.05 * max(0, stray - 2), extra={"stray_findings": stray})
