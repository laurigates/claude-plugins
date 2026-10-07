# interface-state — Objects and Verbs

Open this when you need the full list of `ip` objects, their abbreviations, or
what each verb does.

## Quick Reference

### Objects

| Object | Abbrev | Purpose |
|--------|--------|---------|
| `address` | `a` | IP addresses on interfaces |
| `link` | `l` | L2 interface state, MAC, MTU |
| `route` | `r` | Routing tables |
| `neigh` | `n` | ARP/NDP neighbor cache |
| `rule` | `ru` | Policy routing rules |
| `maddr` | `m` | Multicast group membership |
| `netns` | | Network namespaces |
| `monitor` | | Live change stream |

### Common Verbs

| Verb | Meaning |
|------|---------|
| `show` (default) | Display entries |
| `add` | Create an entry (root) |
| `del` / `delete` | Remove an entry (root) |
| `set` | Modify link properties (root) |
| `replace` | Atomically add-or-update (root) |
| `flush` | Remove all matching entries (root) |
| `get` | Resolve a single lookup (`route get`) |
