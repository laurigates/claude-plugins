# Reverse-Engineering Plugin

Low-level reverse-engineering workflows: decompiling binaries, carving firmware
images apart, reasoning about hardware/VM passthrough and TEE-sealed secrets, and
reading ACPI tables. The skills grew out of recurring RE work across several
projects — a 1998 game port (`skullcaps`), Switch homebrew, and a laptop
firmware/fingerprint investigation — distilled into reusable form.

These cover the parts that are the same regardless of target: how to drive
Ghidra at scale, where things live in a flash dump, what a TEE actually protects,
and when a passthrough plan is dead on arrival. Domain-specific asset formats,
per-game bindings, and platform modding stay in their own repos.

Related skills elsewhere:

- `tools-plugin:binary-analysis` — `strings`/`binwalk`/`objdump`/entropy triage,
  the first pass before Ghidra or region-mapping.
- `tools-plugin:cli-smoke-recipes` — expose a format decoder/examiner as a CLI
  with a bulk-smoke recipe (the delivery surface for `re-deterministic-examiner`).
- `code-quality-plugin:debugging-methodology` — memory/perf/system debugging.
- `linux-plugin` / `macos-plugin` — platform power and suspend work that consumes
  `acpi-table-re`'s wake-source findings.
- `agent-patterns-plugin:exclusive-lock-dispatch` — the general pattern behind
  Ghidra's project lock.

## Skills

| Skill | Description |
|-------|-------------|
| `ghidra-headless-decompile` | Drive Ghidra headless: export decompiled C for every function to a greppable file, dump xrefs/call graphs. The Ghidra 12 Jython→PyGhidra break (scripts are Java now), `analyzeHeadless` invocation, the project lock, and pre-dump-then-dispatch |
| `firmware-dump-region-map` | Enumerate every region of a BIOS/SPI-flash dump (descriptor, ME/CSME, EC, BIOS) before carving one; extract LZMA-compressed UEFI volumes (why raw grep misses strings); the host-side-vs-device-side split of a feature |
| `acpi-table-re` | Decompile DSDT/SSDT with `iasl`: find a device by `_ADR`/`_HID`, read a `_DSM`, map wake sources (`_PRW`/GPE) for suspend/drain work, spot dead-code methods |
| `sgx-sealed-secret-recovery` | Whether a TEE-sealed secret is recoverable: the CPU+MRSIGNER binding, `EGETKEY`, the created-on-device inference, routes that work (capture at source, non-attesting peers, run the genuine enclave) vs don't (off-platform unseal, hypervisor peek, closed side channels) |
| `device-passthrough-feasibility` | Whether hardware or a physical address range can be forwarded into a VM: what's bindable, the `/proc/iomem`+e820 classification, data-plane vs control-plane, and why a TEE makes the VM boundary the wrong layer |
| `re-deterministic-examiner` | Build a deterministic examiner for a binary format instead of guessing its structure: slice into labelled units + a manifest, measure the slicing and refuse when underdetermined, keep it diffable and shell-reachable |
