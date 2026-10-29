---
name: gcp-throwaway-vm
description: "Throwaway GCE VMs for benchmarks: project per run, budget and teardown order, zone fallback, older GCP kernels. Use when renting a GCP VM to run a test, then deleting it."
allowed-tools: Bash, Read
created: 2026-10-29
modified: 2026-10-29
reviewed: 2026-10-29
---

# Throwaway GCP VMs for Controlled Tests

Rent one or more Compute Engine VMs for a benchmark or test that needs a
specific kernel, filesystem or core count, run it, and leave nothing billing
afterwards. The numbered sections are the order that worked; the traps are
the places it broke. Full scripts are in [REFERENCE.md](REFERENCE.md).

## 1. One Project per Run, Pinned to One Account

Create a dedicated project and delete it at the end. Project deletion is the
teardown backstop: it removes any VM, disk, address or firewall rule you missed.

```bash
A=--account=<you@example.com>; P=<bench-project-id>
gcloud projects create "$P" "$A"
BA=$(gcloud billing projects describe <existing-project> "$A" --format='value(billingAccountName)')
gcloud billing projects link "$P" --billing-account="${BA#billingAccounts/}" "$A"
gcloud services enable compute.googleapis.com --project="$P" "$A"
```

Pass `--account` (and `--project`) on **every** command instead of
`gcloud config set account` or switching configurations. The active
configuration may belong to another account (e.g. work) and stays untouched;
confirm with `gcloud config list` at the end.

## 2. Budget Alert: Delete It Before the Project

`gcloud billing budgets create`/`delete` need `--billing-project=<p>` pointing at
a project with `billingbudgets.googleapis.com` enabled. If that project is the
throwaway one and it is deleted first, `budgets delete` then fails with
`SERVICE_DISABLED` or `PERMISSION_DENIED` from every other project, and the
budget is orphaned on the billing account.

- Create the budget through a **long-lived** project that has the API enabled,
  or delete it **before** deleting the throwaway project.
- A "no match" from a `budgets list | grep` whose `list` call failed is not proof
  of deletion. Check the command's exit status and stderr
  (`agent-patterns-plugin:tool-result-traps`).

## 3. Check Quota Before Sizing

A new project's limits are lower than the regional numbers suggest:

```bash
gcloud compute project-info describe --project="$P" "$A" --format=json | jq '.quotas[] | select(.metric=="CPUS_ALL_REGIONS")'
gcloud compute regions describe europe-north1 --project="$P" "$A" --format=json | jq '.quotas[] | select(.metric=="CPUS" or .metric=="SSD_TOTAL_GB")'
```

Observed 2026-10 on a new personal project: `CPUS_ALL_REGIONS` 32, regional
`CPUS` 200, `SSD_TOTAL_GB` 500. The global 32 is the binding limit.

## 4. Create VMs With a Zone Fallback, in a Bash Script

`ZONE_RESOURCE_POOL_EXHAUSTED` is routine for mid-size machine types (seen for
`n2-standard-8` in `europe-north1-a`). Loop over the region's zones and stop at
the first success. Write the multi-step creation as a `bash` script, not a
one-liner: in zsh, `set -- $var` and `$GC_FLAGS` do not word-split
(`tools-plugin:zsh-gotchas`). See REFERENCE.md § Create.

A data disk created with
`--create-disk=name=<vm>-data,size=100GB,type=pd-ssd,auto-delete=yes,device-name=data`
appears in the guest as `/dev/disk/by-id/google-data`, a stable path for
`mkfs`/`mount` in the test script. `auto-delete=yes` removes it with the VM.

## 5. Image Families and Kernels

| Image family (`--image-project=ubuntu-os-cloud`) | Boots (2026-10) |
|---|---|
| `ubuntu-2204-lts` | `6.8.0-*-gcp` |
| `ubuntu-2404-lts-amd64` | `7.0.0-*-gcp` |
| `debian-11`, `ubuntu-2004` | retired, "not found" |

Check what exists before scripting:
`gcloud compute images list --filter='family~ubuntu' --format='value(family)' | sort -u`.

### Booting an Older Kernel: Use the GCP Flavour

To test on an older kernel line (e.g. 5.15 on 22.04), install the **GCP**
flavour: `linux-image-gcp-lts-22.04` gave `5.15.0-1120-gcp`. The generic
`linux-image-generic` 5.15 panics at boot:

```
Kernel panic - not syncing: VFS: Unable to mount root fs on unknown-block(0,0)
```

GCP Ubuntu images boot without an initrd, and the generic kernel builds its
disk drivers as modules. Select the kernel with `GRUB_DEFAULT=saved` in
`/etc/default/grub` **and** every `/etc/default/grub.d/*.cfg` (read after
`/etc/default/grub`, so a value there overrides it), `update-grub`, then
`grub-set-default "Advanced options for Ubuntu>Ubuntu, with Linux <ver>"`.
Script: REFERENCE.md § Older kernel.

Reboot as its own step and confirm: a `reboot` chained with `&&` after the setup
script did not happen. Check `uname -r` and `uptime -s` afterwards. When the VM
never comes back, read the serial console; that is where the 5.15 panic showed:

```bash
gcloud compute instances get-serial-port-output <vm> --zone=<z> --project="$P" "$A" | grep -E 'Linux version|Kernel panic'
```

## 6. SSH: Poll, Don't Sleep

The first `gcloud compute ssh` after it generates a key can exit 255 while the
key propagates. Retry in an `until` loop with a bound rather than a fixed
`sleep`; use the same loop after a reboot (REFERENCE.md § Wait for SSH).

## 7. Teardown, in This Order

1. Delete the instances (`gcloud compute instances delete ... --quiet`).
2. Confirm `instances`, `disks`, `addresses` and `snapshots` lists are empty,
   and that each `list` call exited 0.
3. Delete the budget (§ 2), while the project that enables its API still exists.
4. `gcloud projects delete "$P" "$A" --quiet`. The project then sits in
   `DELETE_REQUESTED` for 30 days (`gcloud projects describe "$P" "$A"
   --format='value(lifecycleState)'`).
5. `gcloud config list`: active account and project unchanged.

## Tooling Inside the Guest

Distribution packages can be too old for the test: Ubuntu 22.04's apt
`hyperfine` is 1.12 and has no `-N`. Install a current one with
`cargo install --locked hyperfine` when the flag is needed.

Observed 2026-10 (filesystem benchmarks on two `n2-standard-8` VMs with a
100 GB `pd-ssd` data disk each, ~1.5 h, personal account): the traps in this
skill come from that run. Cost was not measured.

## Agentic Optimizations

| Context | Command |
|---|---|
| Machine types in a zone | `gcloud compute machine-types list --zones=<z> --filter='name=n2-standard-8' --project="$P" "$A" --format='value(name)'` |
| VM state | `gcloud compute instances list --project="$P" "$A" --format='value(name,zone.basename(),status)'` |
| Leftover resources | `gcloud compute disks list --project="$P" "$A" --format='value(name)'` (also `addresses`, `snapshots`) |
| Booted kernel | `gcloud compute ssh <vm> --zone=<z> --project="$P" "$A" --command='uname -r; uptime -s'` |
| Project state | `gcloud projects describe "$P" "$A" --format='value(lifecycleState)'` |

## Related

- `tools-plugin:zsh-gotchas`: why the creation steps go in a bash script
- `agent-patterns-plugin:tool-result-traps`: an empty result from a failed list command
- `terraform-plugin:infrastructure-terraform`: for VMs that outlive one test run
