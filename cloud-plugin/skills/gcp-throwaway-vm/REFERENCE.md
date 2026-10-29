# Throwaway GCP VMs — Reference

Scripts generalized from a 2026-10 filesystem-benchmark run. Every script is
`bash` and passes `--account`/`--project` explicitly through one array, so the
active `gcloud` configuration is never read or changed.

```bash
GC=(--project=<bench-project-id> --account=<you@example.com>)
```

## Budget Alert

Not run as written: these commands were reconstructed from the session's
commands and `gcloud billing budgets create --help`. A currency suffix on
`--budget-amount` is optional; if given, it must match the billing account's
currency. Point
`--billing-project` at a long-lived project with `billingbudgets.googleapis.com`
enabled, so the budget can still be deleted after the throwaway project is gone.

```bash
BA=<billing-account-id>          # without the billingAccounts/ prefix
BP=<long-lived-project-id>       # has billingbudgets.googleapis.com enabled
gcloud billing budgets create --billing-account="$BA" --billing-project="$BP" --account=<you@example.com> \
    --display-name="bench <bench-project-id>" --budget-amount=<amount><CUR> \
    --threshold-rule=percent=0.5 --threshold-rule=percent=1.0 \
    --filter-projects=projects/<bench-project-id>
gcloud billing budgets list --billing-account="$BA" --billing-project="$BP" --account=<you@example.com> --format='value(name,displayName)'
```

## Create

Tries each zone until one has capacity; prints the error code of each failure.

```bash
#!/usr/bin/env bash
set -uo pipefail
GC=(--project=<bench-project-id> --account=<you@example.com>)
ZONES=(europe-north1-b europe-north1-c europe-north1-a)

create() {
    local name=$1 family=$2 zone err
    err=$(mktemp)
    for zone in "${ZONES[@]}"; do
        echo "== $name in $zone"
        if gcloud compute instances create "$name" "${GC[@]}" --zone="$zone" \
            --machine-type=n2-standard-8 --image-family="$family" --image-project=ubuntu-os-cloud \
            --boot-disk-size=30GB --boot-disk-type=pd-balanced \
            --create-disk=name="$name-data",size=100GB,type=pd-ssd,auto-delete=yes,device-name=data \
            --format='value(name,zone.basename(),status)' 2>"$err"; then
            return 0
        fi
        grep -oE "code: [A-Z_]+|was not found" "$err" | head -1
    done
    return 1
}

create bench-jammy ubuntu-2204-lts
create bench-noble ubuntu-2404-lts-amd64
```

`code: ZONE_RESOURCE_POOL_EXHAUSTED` moves on to the next zone. `was not found`
means the image family is retired; no zone will help.

## Wait for SSH

The first `gcloud compute ssh` after key generation can exit 255. Poll with a
bound. `--quiet` gives a newly generated key an empty passphrase, so the hidden
`ssh-keygen` prompt cannot stall the loop. This function and the reboot loop in
§ Older Kernel are generalized from the run, not copied from a script that ran.

```bash
wait_ssh() {  # wait_ssh <vm> <zone>
    local i
    for i in $(seq 1 30); do
        gcloud compute ssh "$1" --zone="$2" "${GC[@]}" --quiet --command=true 2>/dev/null && return 0
        sleep 10
    done
    echo "ssh to $1 not ready after 30 tries" >&2; return 1
}
```

## Older Kernel

Run on the guest (e.g. `gcloud compute ssh <vm> ... --command='bash -s' < jammy-kernel.sh`).
Installs the 22.04 GCP-flavour 5.15 kernel and makes GRUB boot it next.

```bash
#!/usr/bin/env bash
set -euo pipefail
sudo apt-get -qq update
sudo DEBIAN_FRONTEND=noninteractive apt-get -qq install -y linux-image-gcp-lts-22.04 >/dev/null
K=$(ls /boot/vmlinuz-5.15.*-gcp | sort -V | tail -1 | sed 's|/boot/vmlinuz-||')
echo "installed kernel: $K"
sudo sed -i 's/^GRUB_DEFAULT=.*/GRUB_DEFAULT=saved/' /etc/default/grub
for f in /etc/default/grub.d/*.cfg; do sudo sed -i 's/^GRUB_DEFAULT=.*/GRUB_DEFAULT=saved/' "$f"; done
sudo update-grub 2>/dev/null
grep -q "Ubuntu, with Linux $K'" /boot/grub/grub.cfg || { echo "no menu entry for $K" >&2; exit 1; }
sudo grub-set-default "Advanced options for Ubuntu>Ubuntu, with Linux $K"
sudo grub-editenv list
```

Then reboot as a separate step and confirm the boot happened and picked the
kernel:

```bash
before=$(gcloud compute ssh <vm> --zone=<z> "${GC[@]}" --command='uptime -s')
gcloud compute ssh <vm> --zone=<z> "${GC[@]}" --command='sudo reboot' || true  # exits 255 as the link drops
until now=$(gcloud compute ssh <vm> --zone=<z> "${GC[@]}" --command='uptime -s' 2>/dev/null) && [ -n "$now" ] && [ "$now" != "$before" ]; do sleep 10; done
gcloud compute ssh <vm> --zone=<z> "${GC[@]}" --command='uname -r'
```

Add a bound to the `until` loop in unattended runs. If the VM never answers,
read `gcloud compute instances get-serial-port-output <vm> --zone=<z> "${GC[@]}"`.

## Teardown

```bash
#!/usr/bin/env bash
set -uo pipefail
GC=(--project=<bench-project-id> --account=<you@example.com>)

gcloud compute instances delete bench-jammy --zone=<z1> "${GC[@]}" --quiet
gcloud compute instances delete bench-noble --zone=<z2> "${GC[@]}" --quiet

for r in instances disks addresses snapshots; do
    out=$(gcloud compute "$r" list "${GC[@]}" --format='value(name)') || { echo "LIST FAILED: $r" >&2; exit 1; }
    [ -z "$out" ] || { echo "LEFTOVER $r: $out" >&2; exit 1; }
done
echo "compute resources: none"

# Budget first (see SKILL.md § 2), then the project.
gcloud billing budgets delete <budget-id> --billing-account=<billing-account-id> \
    --billing-project=<long-lived-project-id> --account=<you@example.com> --quiet
gcloud projects delete <bench-project-id> --account=<you@example.com> --quiet
gcloud projects describe <bench-project-id> --account=<you@example.com> --format='value(lifecycleState)'  # DELETE_REQUESTED
gcloud config list
```
