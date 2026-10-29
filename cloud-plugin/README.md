# Cloud Plugin

Operational skills for cloud providers: renting compute for a test or
benchmark, keeping spend bounded, and tearing everything down afterwards.
Google Cloud is the only provider covered today.

Long-lived infrastructure belongs in `terraform-plugin`; GKE cluster access
in `kubernetes-plugin`; CI authentication to a cloud in `github-actions-plugin`.

## Naming Convention

Skill names carry the provider as a prefix, so one plugin can hold several
providers without the names colliding or becoming ambiguous:

| Prefix | Provider |
|--------|----------|
| `gcp-` | Google Cloud |
| `hetzner-` | Hetzner Cloud (reserved; no skills yet) |

A skill is unprefixed only when it applies to every provider it describes
(for example, a cost or teardown discipline stated once and cited by the
provider skills). A skill that covers one provider in practice takes that
provider's prefix even when the idea would generalize.

## Skills

| Skill | Description |
|-------|-------------|
| `gcp-throwaway-vm` | Throwaway Compute Engine VMs for controlled benchmarks — project per run, budget and teardown order, zone fallback, booting an older GCP kernel |

## Installation

```bash
claude plugin install cloud-plugin@laurigates-claude-plugins
```

## License

MIT
