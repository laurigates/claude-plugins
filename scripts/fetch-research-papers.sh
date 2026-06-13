#!/usr/bin/env bash
# Fetch recent AI/agent research from HuggingFace daily papers, arXiv, and lab
# blogs; normalize to a single JSON candidate array for the "Claude: Research
# radar" workflow (.github/workflows/research-radar.yml).
#
# The workflow hands the JSON to Claude, which judges each item's relevance to
# THIS plugin collection and opens at most one GitHub issue. This script is the
# deterministic pre-compute step — it does no relevance judgement of its own.
#
# Multi-format feed parsing (HF JSON + arXiv Atom XML + blog RSS/Atom) is done
# in an inline python3 block: pure bash/jq cannot parse the XML feeds, and
# python3 is present on GitHub runners and in the web sandbox. The bash wrapper
# owns flag parsing, network fetch, and the structured KEY=value summary
# (.claude/rules/structured-script-output.md).
#
# Usage:
#   fetch-research-papers.sh [--since-days N] [--seen-file PATH] [--out PATH]
#
#   --since-days N   Only keep items published within the last N days (default 8)
#   --seen-file P    Newline-delimited paper IDs already surfaced in prior
#                    issues; matching items are dropped. Default: none.
#   --out P          Write the JSON candidate array here (default /tmp/research-candidates.json)
#
# Exit 0 always (parallel-safe; see .claude/rules/parallel-safe-queries.md) —
# a per-source network failure degrades to fewer candidates, never an abort.
set -uo pipefail

since_days=8
seen_file=""
out_file="/tmp/research-candidates.json"

while [ $# -gt 0 ]; do
  case "$1" in
    --since-days) since_days="$2"; shift 2 ;;
    --seen-file) seen_file="$2"; shift 2 ;;
    --out) out_file="$2"; shift 2 ;;
    *) shift ;;
  esac
done

# arXiv categories most likely to surface agent / prompting / eval / SWE work.
arxiv_cats="cat:cs.AI+OR+cat:cs.CL+OR+cat:cs.LG+OR+cat:cs.SE+OR+cat:cs.HC"

# Lab / vendor research feeds. Best-effort: a 404 or non-feed response is
# skipped silently. Add feeds here as they prove reachable and useful.
blog_feeds=(
  "https://openai.com/blog/rss.xml"
  "https://www.anthropic.com/rss.xml"
)

work_dir="$(mktemp -d)"
trap 'rm -rf "$work_dir"' EXIT

# --- Fetch (each source isolated; failures are non-fatal) ---------------------
# Test seam: RR_FIXTURE_DIR stages hf.json / arxiv.xml / blog-*.xml so the
# normalize+dedup+date-filter logic can be exercised offline (see
# scripts/tests/test-fetch-research-papers.sh). When set, no network is touched.
if [ -n "${RR_FIXTURE_DIR:-}" ] && [ -d "${RR_FIXTURE_DIR:-}" ]; then
  cp "$RR_FIXTURE_DIR"/* "$work_dir/" 2>/dev/null || true
else
  curl -fsSL --max-time 45 \
    "https://huggingface.co/api/daily_papers" \
    -o "$work_dir/hf.json" 2>/dev/null || true

  curl -fsSL --max-time 45 \
    "http://export.arxiv.org/api/query?search_query=${arxiv_cats}&sortBy=submittedDate&sortOrder=descending&max_results=80" \
    -o "$work_dir/arxiv.xml" 2>/dev/null || true

  blog_idx=0
  for feed in "${blog_feeds[@]}"; do
    blog_idx=$((blog_idx + 1))
    curl -fsSL --max-time 30 "$feed" \
      -o "$work_dir/blog-${blog_idx}.xml" 2>/dev/null || true
  done
fi

# --- Normalize + dedup + date-filter (python3) --------------------------------
RR_WORK_DIR="$work_dir" \
RR_SINCE_DAYS="$since_days" \
RR_SEEN_FILE="$seen_file" \
RR_OUT="$out_file" \
python3 <<'PYEOF'
import datetime as dt
import glob
import json
import os
import re
import sys
import xml.etree.ElementTree as ET

work_dir = os.environ["RR_WORK_DIR"]
since_days = int(os.environ.get("RR_SINCE_DAYS") or "8")
seen_file = os.environ.get("RR_SEEN_FILE") or ""
out_file = os.environ["RR_OUT"]

# RR_TODAY pins "today" for deterministic offline tests; defaults to the real date.
_today_raw = os.environ.get("RR_TODAY") or ""
try:
    today = dt.date.fromisoformat(_today_raw) if _today_raw else dt.date.today()
except ValueError:
    today = dt.date.today()
cutoff = (today - dt.timedelta(days=since_days)).isoformat()

seen = set()
if seen_file and os.path.isfile(seen_file):
    with open(seen_file, encoding="utf-8", errors="replace") as fh:
        for line in fh:
            tok = line.strip()
            if tok:
                seen.add(tok)


def clean(text, limit=600):
    text = re.sub(r"\s+", " ", (text or "")).strip()
    return text[:limit]


def arxiv_id(raw):
    # http://arxiv.org/abs/2606.05922v1 -> 2606.05922
    m = re.search(r"(\d{4}\.\d{4,5})", raw or "")
    return m.group(1) if m else (raw or "").strip()


records = {}  # id -> record (dedup within this run too)


def add(rec):
    rid = rec.get("id")
    if not rid or rid in seen or rid in records:
        return
    if (rec.get("published") or "")[:10] < cutoff:
        return
    records[rid] = rec


# --- HuggingFace daily papers (JSON) ---
hf_path = os.path.join(work_dir, "hf.json")
if os.path.isfile(hf_path):
    try:
        with open(hf_path, encoding="utf-8", errors="replace") as fh:
            data = json.load(fh)
        for item in data if isinstance(data, list) else []:
            paper = item.get("paper") or {}
            pid = arxiv_id(paper.get("id") or item.get("id") or "")
            if not pid:
                continue
            published = (item.get("publishedAt") or paper.get("publishedAt") or "")[:10]
            add({
                "id": pid,
                "title": clean(paper.get("title") or item.get("title"), 300),
                "url": f"https://huggingface.co/papers/{pid}",
                "source": "huggingface",
                "published": published,
                "abstract": clean(paper.get("summary") or paper.get("abstract")),
                "upvotes": paper.get("upvotes") or item.get("upvotes") or 0,
            })
    except Exception as exc:  # noqa: BLE001 - best-effort source
        print(f"hf parse skipped: {exc}", file=sys.stderr)

# --- arXiv (Atom XML) ---
arxiv_path = os.path.join(work_dir, "arxiv.xml")
if os.path.isfile(arxiv_path):
    try:
        ns = {"a": "http://www.w3.org/2005/Atom"}
        root = ET.parse(arxiv_path).getroot()
        for entry in root.findall("a:entry", ns):
            raw_id = (entry.findtext("a:id", default="", namespaces=ns) or "")
            pid = arxiv_id(raw_id)
            if not pid:
                continue
            published = (entry.findtext("a:published", default="", namespaces=ns) or "")[:10]
            add({
                "id": pid,
                "title": clean(entry.findtext("a:title", default="", namespaces=ns), 300),
                "url": f"https://arxiv.org/abs/{pid}",
                "source": "arxiv",
                "published": published,
                "abstract": clean(entry.findtext("a:summary", default="", namespaces=ns)),
                "upvotes": 0,
            })
    except Exception as exc:  # noqa: BLE001 - best-effort source
        print(f"arxiv parse skipped: {exc}", file=sys.stderr)

# --- Lab blogs (RSS or Atom) ---
for blog_path in sorted(glob.glob(os.path.join(work_dir, "blog-*.xml"))):
    try:
        root = ET.parse(blog_path).getroot()
        # RSS: <rss><channel><item><link/><title/><description/><pubDate/>
        items = root.findall(".//item")
        for it in items:
            link = (it.findtext("link") or "").strip()
            if not link:
                continue
            published = ""
            pub = it.findtext("pubDate") or ""
            m = re.search(r"(\d{1,2})\s+(\w{3})\s+(\d{4})", pub)
            if m:
                try:
                    published = dt.datetime.strptime(
                        f"{m.group(1)} {m.group(2)} {m.group(3)}", "%d %b %Y"
                    ).date().isoformat()
                except ValueError:
                    published = ""
            add({
                "id": link,
                "title": clean(it.findtext("title"), 300),
                "url": link,
                "source": "blog",
                "published": published or today.isoformat(),
                "abstract": clean(it.findtext("description")),
                "upvotes": 0,
            })
        # Atom: <feed><entry><link href=.../><title/><summary/><published/>
        if not items:
            ns = {"a": "http://www.w3.org/2005/Atom"}
            for entry in root.findall("a:entry", ns):
                link_el = entry.find("a:link", ns)
                link = (link_el.get("href") if link_el is not None else "") or ""
                if not link:
                    continue
                published = (entry.findtext("a:published", default="", namespaces=ns)
                             or entry.findtext("a:updated", default="", namespaces=ns) or "")[:10]
                add({
                    "id": link,
                    "title": clean(entry.findtext("a:title", default="", namespaces=ns), 300),
                    "url": link,
                    "source": "blog",
                    "published": published or today.isoformat(),
                    "abstract": clean(entry.findtext("a:summary", default="", namespaces=ns)),
                    "upvotes": 0,
                })
    except Exception as exc:  # noqa: BLE001 - best-effort source
        print(f"blog parse skipped ({blog_path}): {exc}", file=sys.stderr)

candidates = sorted(
    records.values(),
    key=lambda r: (r.get("upvotes", 0), r.get("published", "")),
    reverse=True,
)

with open(out_file, "w", encoding="utf-8") as fh:
    json.dump(candidates, fh, ensure_ascii=False, indent=2)

# Per-source counts for the structured summary.
counts = {"huggingface": 0, "arxiv": 0, "blog": 0}
for rec in candidates:
    counts[rec["source"]] = counts.get(rec["source"], 0) + 1

with open(os.path.join(work_dir, "counts.env"), "w", encoding="utf-8") as fh:
    fh.write(f"TOTAL={len(candidates)}\n")
    fh.write(f"HF={counts['huggingface']}\n")
    fh.write(f"ARXIV={counts['arxiv']}\n")
    fh.write(f"BLOG={counts['blog']}\n")
PYEOF

# --- Structured summary (.claude/rules/structured-script-output.md) -----------
total=0; hf=0; arxiv=0; blog=0
if [ -f "$work_dir/counts.env" ]; then
  # shellcheck disable=SC1090
  while IFS='=' read -r k v; do
    case "$k" in
      TOTAL) total="$v" ;;
      HF) hf="$v" ;;
      ARXIV) arxiv="$v" ;;
      BLOG) blog="$v" ;;
    esac
  done < "$work_dir/counts.env"
fi

radar_status="OK"
[ "$total" -eq 0 ] && radar_status="WARN"

echo "=== RESEARCH RADAR ==="
echo "SINCE_DAYS=$since_days"
echo "OUT_FILE=$out_file"
echo "HF_COUNT=$hf"
echo "ARXIV_COUNT=$arxiv"
echo "BLOG_COUNT=$blog"
echo "CANDIDATE_COUNT=$total"
echo "STATUS=$radar_status"
echo "ISSUE_COUNT=0"
echo "=== END RESEARCH RADAR ==="

exit 0
