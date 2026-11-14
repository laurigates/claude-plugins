---
name: gcloud-skill
description: Fixture for test-skill-shell-commands.sh case I (heads not on the known-command list). Use when testing.
allowed-tools: Bash, Read
---

# Deploy with gcloud

```bash
gcloud run services list --region europe-north1
if gcloud auth print-access-token >/dev/null; then
  echo "authenticated"
fi
gcloud run deploy api \
  --source . \
  --region europe-north1
git commit -m "feat: deploy notes
body line here"
cat <<'EOF' > notes.txt
release notes for the deploy
EOF
[ -n "$TOKEN" ] && gcloud config list
^(feat|fix|chore)/[a-z0-9-]+$
requires-python = ">=3.10"
ZONES=(europe-north1-b europe-north1-c europe-north1-a)
```

```console
$ mycli status --json
ready to serve
```

A prose span with arguments: `frobnicate the widget`.
