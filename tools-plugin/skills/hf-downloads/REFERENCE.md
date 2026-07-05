# Hugging Face Downloads — Reference

Supporting scripts for the `hf-downloads` skill. Loaded on demand.

## Real Download-Access Probe (Gated Repos)

`api.model_info(<gated-repo>)` returns repo metadata regardless of whether the
token can download the actual files, so it is **not** a reliable access probe.
HEAD the resolved file URL with the token — a `200` (with a `Content-Length` in
GB) confirms real download access; a `401`/`403` means the token is stale or the
account never accepted the gate.

```sh
python -c "
import urllib.request
from huggingface_hub import HfFolder
token = HfFolder.get_token()
url = 'https://huggingface.co/<repo>/resolve/main/<file>'
req = urllib.request.Request(url, method='HEAD')
req.add_header('Authorization', f'Bearer {token}')
try:
    with urllib.request.urlopen(req, timeout=30) as r:
        print(f'{r.status} {int(r.headers.get(\"Content-Length\",0))/1e9:.2f} GB')
except urllib.error.HTTPError as e:
    print(f'{e.code} {e.reason}')
"
```

If the <https://huggingface.co/settings/gated-repos> page shows `Accepted` but
this HEAD returns `401`/`403`, regenerate the token at
<https://huggingface.co/settings/tokens>, `hf auth login` with the new token, and
copy it to `$HF_HOME/token` if `HF_HOME` is set (per the token-location
divergence in the skill body).

## Pre-Download Size Check

HEAD the download URL before committing to a very large transfer, then confirm
the destination disk has at least **2×** that free (staging + final), or **1×**
if `HF_HOME` is on the destination disk itself.

```sh
.venv/bin/python -c "
from huggingface_hub import hf_hub_url
import urllib.request
url = hf_hub_url('<repo>', '<file>')
with urllib.request.urlopen(urllib.request.Request(url, method='HEAD')) as r:
    print(f'{int(r.headers.get(\"Content-Length\", 0))/1e9:.2f} GB')
"
```

Check the destination disk with `df -h /big/disk` and compare against the printed
size.

## Post-Download Size Verification

After a background download completes, verify each file's on-disk size against the
HEAD-reported `Content-Length` before trusting the transfer:

```sh
stat -c '%s' /destination/<file>
```

A `hf download` exit code of 1 with the `.safetensors` files present at full size
usually means the **post-download cache cleanup** ran out of root disk, not that
the transfer itself failed — verify sizes before re-downloading.
