---
name: sgx-sealed-secret-recovery
description: Reason about whether an SGX/TEE-sealed secret is recoverable. Use when reverse-engineering a feature whose key lives in an SGX enclave, when a driver links sgx_urts, or deciding if a sealed blob unseals off-platform. Covers the CPU+MRSIGNER binding, the created-on-device inference, and what works.
user-invocable: false
allowed-tools: Read, Grep, Glob
created: 2026-11-17
modified: 2026-11-17
reviewed: 2026-11-17
---

# SGX / TEE Sealed-Secret Recovery

When a secret (a device key, a PSK, a license token) is held by an SGX enclave,
the driver only shuttles opaque sealed blobs and ciphertext. Before planning a
recovery, work out what the seal is actually bound to — most "copy the blob and
decrypt it" plans are dead on arrival, and a couple of non-obvious routes are
not.

## How to tell SGX is in play

- The driver imports `sgx_urts.dll` / `sgx_uae_service.dll` (Windows) or links
  the Linux SGX SDK; ships a `*.signed.dll` / `*.signed.so` enclave and a
  `sgx_white_list_cert.bin`.
- Strings: `EGETKEY`, `sgx_seal_data`/`sgx_unseal_data`, `MRSIGNER`, ECALL/OCALL
  names, an mbedTLS build *inside* the enclave.

## What the seal is bound to (and why copying the blob fails)

`sgx_seal_data` encrypts under a key from `EGETKEY`, derived from:

1. the **CPU's fused root key** (unique per physical CPU), plus
2. the **enclave identity** — `MRENCLAVE` (this exact enclave) or `MRSIGNER`
   (any enclave signed by the same vendor key), per the seal policy, plus
3. `CR_SGXOWNEREPOCH` (a platform-owner MSR) and the SVN.

Consequences:
- **`EGETKEY` only runs inside an enclave.** The OS, a driver, `/dev/mem`, DMA —
  none can issue it. Copying the sealed blob to another machine (or to Linux on
  the same box, from outside an enclave) yields nothing.
- **MRSIGNER-policy seals need the vendor's signing key.** To derive the key you
  must run an enclave whose `MRSIGNER` matches, i.e. one signed by the vendor.
  You can't forge `MRSIGNER` (it's `SHA-256` of the signer's public modulus)
  without their private key.
- A production enclave (`ATTRIBUTES.DEBUG=0` in the SIGSTRUCT) blocks
  `EDBGRD`/`EDBGWR`, so you can't single-step it or read EPC. **Check the
  SIGSTRUCT DEBUG bit** — a debug-signed enclave is fully readable.

## The created-on-device inference (the useful lever)

SGX cannot seal data off-device — `EGETKEY` is local. So a sealed blob that
exists on this machine was **necessarily created here**, which means the
plaintext secret passed through the enclave on this box at least once (factory
provisioning, first boot). Find that delivery path: the secret came from
somewhere the enclave could read — a provisioning server, the platform's CSME/ME
over a DH channel, an EC, a one-time ACPI hand-off. That source, not the sealed
blob, is where plaintext is reachable.

## Routes that can work

- **Capture the plaintext at its source**, below the enclave: pre-boot firmware,
  an EC that serves the key to pre-boot auth, the provisioning hand-off. This is
  usually the real answer.
- **Impersonate the enclave to a non-SGX peer.** If the enclave gets the secret
  from CSME/ME or another co-processor over a channel that *can't* do SGX local
  attestation (`EREPORT`), that peer may be unable to tell the real enclave from
  your client — worth checking the channel's authentication.
- **Run the genuine enclave yourself, on the same CPU.** You don't need to
  extract the key — load the vendor's signed enclave under your own loader (the
  seal key is CPU+MRSIGNER-bound and OS-independent; modern CPUs with Flexible
  Launch Control drop the Intel launch-whitelist barrier) and use it as a
  black-box endpoint. Hard in practice (cross-SDK/PE↔ELF enclave metadata,
  servicing its OCALLs and any co-processor channel), but it's a real route, not
  a dead end — don't dismiss it as "dual-boot only".

## Routes that don't

- Unsealing the blob off-platform or from outside an enclave — impossible.
- Reading the enclave from a hypervisor / Windows VM — SGX's threat model
  includes the hypervisor; the host cannot read guest EPC (see
  `device-passthrough-feasibility`).
- Side-channel key extraction (Foreshadow/L1TF, SGAxe, ÆPIC Leak) — real but
  **microcode-closed** on patched parts; only viable against a specific
  unpatched microcode state. Don't plan around it.

## Related

- `device-passthrough-feasibility` — why a VM can't peek into a guest enclave.
- `firmware-dump-region-map` / `ghidra-headless-decompile` — find the
  provisioning/CSME delivery path in firmware and the untrusted driver.
