---
name: device-passthrough-feasibility
description: Decide whether hardware or a physical address range can be forwarded into a VM. Use when asked "can I pass through device X to a guest" or "alias physical address Y into the VM". Covers what's bindable, the /proc/iomem+e820 check, data-plane vs control-plane, and why a TEE defeats it.
user-invocable: false
allowed-tools: Bash(cat /proc/iomem), Bash(sudo cat /proc/iomem), Bash(sudo dmesg *), Bash(lspci *), Read, Grep, Glob
created: 2026-11-17
modified: 2026-11-17
reviewed: 2026-11-17
---

# Device & Physical-Memory Passthrough Feasibility

"Just forward the device to a Windows VM and let the real driver run" is a
common plan for driving uncooperative hardware. It works for *some* device
classes and fails silently for others. Classify before building.

## Is the device even passthrough-able?

VFIO (`vfio-pci`) binds and forwards a **PCI function** (or a USB device via
usb-host). If the thing you want isn't one of those, there is nothing to bind:

| Device shape | Forwardable? |
|---|---|
| PCI/PCIe function (has a BDF in `lspci`) | Yes — `vfio-pci`, IOMMU group permitting |
| USB device | Yes — `-device usb-host` by vid:pid |
| ACPI device on LPC/eSPI (EC mailbox, Super-IO, GPIO, shared-RAM window) | **No** — not a bindable function; you'd have to re-emulate the host transport as a QEMU device model |
| Embedded-controller / eSPI peripheral the host kernel owns and shares (battery, thermal, keyboard all on the same EC) | **No** — a guest can't commandeer a shared host device |

If the thing is an ACPI `\_SB.XXXX` device reached through EC commands + a
shared memory window + GPIO interrupts, "pass it through" means "reimplement the
driver's host side as a virtual device" — which is the work you were trying to
avoid.

## Classify a physical address range before aliasing it

You *can* alias a host-physical range into a guest (a KVM memslot backed by an
`mmap` of `/dev/mem`, exposed at a guest GPA, with the guest's ACPI pointing
there). Whether it's safe depends on how firmware classified it:

```sh
sudo cat /proc/iomem | grep -iE '<addr prefix>|reserved|System RAM'
sudo dmesg | grep -iE 'BIOS-e820'
```

- **`System RAM`** — the host kernel allocates from it; you cannot hand it to a
  guest.
- **`device reserved` / claimed by a named device** (e.g. `40200000-40207fff :
  GXFP51B7:00`) — firmware carved it out; the host doesn't use it as RAM, so
  aliasing is low-risk. This is the aliasing-friendly case.

## The two reasons aliasing usually doesn't get you what you want

1. **Data plane ≠ control plane.** Mapping a shared buffer into the guest does
   not make the producer *fill* it. If an embedded controller DMAs into that
   window on a command issued over the real EC/eSPI channel, the guest (which
   sees an emulated EC, not the real one) can't trigger the fill. Forwarding the
   buffer without forwarding the trigger is useless, and the trigger is the hard
   part.
2. **A hardware-fixed physical target can't be redirected.** If the producer
   writes to a *fixed host-physical address* (firmware-programmed), you can't
   point it at guest RAM; aliasing only makes the guest's *view* coincide with
   where the producer already writes. Often the host driver already maps that
   same window — so the guest gains nothing the host didn't have.

## If a TEE is involved, the VM boundary is the wrong layer

If the secret or the protected session lives in SGX/TEE (see
`sgx-sealed-secret-recovery`), running the vendor stack in a guest does not help:
the hypervisor is in the TEE's threat model, so the host **cannot** read the
guest enclave's memory, and during normal operation a shared window carries only
the TEE's ciphertext. The plaintext, if it ever appears in host-visible memory,
does so *below* the OS (pre-boot firmware), not at the VM boundary.

## The one-paragraph verdict to write

State: (1) the device class and whether it's bindable; (2) the iomem/e820
classification of any window; (3) whether the control plane (the trigger) is
forwardable, not just the data plane; (4) whether a TEE makes the whole thing
moot. If any of (1)/(3)/(4) fails, say so plainly rather than greenlighting a
QEMU device-model project that re-implements the driver.

## Related

- `sgx-sealed-secret-recovery` — why the TEE boundary defeats host/VM observation.
- `firmware-dump-region-map` / `ghidra-headless-decompile` — reverse the host
  transport if you must re-emulate it.
