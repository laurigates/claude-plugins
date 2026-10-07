# interface-state — Troubleshooting and Install

Open this when an `ip` command errors, an address disappears after reboot, or
`ip` / `jq` is missing from the host.

## Troubleshooting

### `Object "a" is unknown, try "ip help"`

Very old iproute2, or a busybox `ip` applet. Spell the object out (`ip address`)
or check `ip -V` for the version.

### `RTNETLINK answers: Operation not permitted`

A mutating command run without root. Prefix with `sudo`.

### `RTNETLINK answers: File exists` on `ip route add`

The route (or a conflicting one) already exists. Use `ip route replace` to
overwrite atomically, or `ip route del` first.

### Address vanished after reboot

`ip addr add` is runtime-only. Persist it in the distro's network manager
(netplan YAML, NetworkManager connection, or systemd-networkd `.network`).

## Requirements

```bash
# iproute2 ships in the base system on essentially all Linux distros.
# If missing (minimal container images):

# Debian/Ubuntu
sudo apt install iproute2

# Alpine
apk add iproute2

# RHEL/Fedora
sudo dnf install iproute

# jq for JSON parsing (examples above)
sudo apt install jq        # or: apk add jq / dnf install jq
```
