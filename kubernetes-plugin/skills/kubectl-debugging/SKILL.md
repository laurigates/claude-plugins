---
model: haiku
created: 2025-12-16
modified: 2025-12-16
reviewed: 2025-12-16
name: kubectl-debugging
description: |
  Debug Kubernetes pods, nodes, and workloads using kubectl debug. Covers ephemeral containers,
  pod copying, node debugging, debug profiles, and interactive troubleshooting sessions.
  Use when user mentions kubectl debug, debugging pods, ephemeral containers, node debugging,
  or interactive troubleshooting in Kubernetes clusters.
allowed-tools: Glob, Grep, Read, Bash(kubectl *), Bash(stern *), Edit, Write, TodoWrite, WebFetch
---

# kubectl debug - Interactive Kubernetes Debugging

Expert knowledge for debugging Kubernetes resources using `kubectl debug` - ephemeral containers, pod copies, and node access.

## Core Capabilities

**kubectl debug** automates common debugging tasks:

- **Ephemeral Containers**: Add debug containers to running pods without restart
- **Pod Copying**: Create modified copies for debugging (different images, commands)
- **Node Debugging**: Access node host namespaces and filesystem

## Context Safety (CRITICAL)

**Always specify `--context`** explicitly in every kubectl command:

```bash
# CORRECT: Explicit context
kubectl --context=prod-cluster debug mypod -it --image=busybox

# WRONG: Relying on current context
kubectl debug mypod -it --image=busybox  # Which cluster?
```

## Quick Reference

### Add Ephemeral Debug Container

```bash
# Interactive debugging with busybox
kubectl --context=my-context debug mypod -it --image=busybox

# Target specific container's process namespace
kubectl --context=my-context debug mypod -it --image=busybox --target=mycontainer

# Use a specific debug profile
kubectl --context=my-context debug mypod -it --image=busybox --profile=netadmin
```

### Copy Pod for Debugging

```bash
# Create debug copy
kubectl --context=my-context debug mypod -it --copy-to=mypod-debug --image=busybox

# Copy and change container image
kubectl --context=my-context debug mypod --copy-to=mypod-debug --set-image=app=busybox

# Copy and modify command
kubectl --context=my-context debug mypod -it --copy-to=mypod-debug --container=myapp -- sh

# Copy on same node
kubectl --context=my-context debug mypod -it --copy-to=mypod-debug --same-node --image=busybox
```

### Debug Node

```bash
# Interactive node debugging (host namespaces, filesystem at /host)
kubectl --context=my-context debug node/mynode -it --image=busybox

# With sysadmin profile for full capabilities
kubectl --context=my-context debug node/mynode -it --image=ubuntu --profile=sysadmin
```

## Debug Profiles

| Profile | Use Case | Capabilities |
|---------|----------|--------------|
| `legacy` | Default, unrestricted | Full access (backwards compatible) |
| `general` | General purpose | Moderate restrictions |
| `baseline` | Minimal restrictions | Pod security baseline |
| `netadmin` | Network troubleshooting | NET_ADMIN capability |
| `restricted` | High security environments | Strictest restrictions |
| `sysadmin` | System administration | SYS_PTRACE, SYS_ADMIN |

```bash
# Network debugging (tcpdump, netstat, ss)
kubectl --context=my-context debug mypod -it --image=nicolaka/netshoot --profile=netadmin

# System debugging (strace, perf)
kubectl --context=my-context debug mypod -it --image=ubuntu --profile=sysadmin
```

## Common Debug Images

| Image | Size | Use Case |
|-------|------|----------|
| `busybox` | ~1MB | Basic shell, common utilities |
| `alpine` | ~5MB | Shell with apk package manager |
| `ubuntu` | ~77MB | Full Linux with apt |
| `nicolaka/netshoot` | ~350MB | Network debugging (tcpdump, dig, curl, netstat) |
| `gcr.io/k8s-debug/debug` | Varies | Official Kubernetes debug image |

## Debugging Patterns

### Network Connectivity Issues

```bash
# Add netshoot container for network debugging
kubectl --context=my-context debug mypod -it \
  --image=nicolaka/netshoot \
  --profile=netadmin

# Inside container:
# - tcpdump -i any port 80
# - dig kubernetes.default
# - curl -v http://service:port
# - ss -tlnp
# - netstat -an
```

### Application Crashes

```bash
# Copy pod with different entrypoint to inspect
kubectl --context=my-context debug mypod -it \
  --copy-to=mypod-debug \
  --container=app \
  -- sh

# Inside: check filesystem, env vars, config files
```

### Process Inspection

```bash
# Target container's process namespace
kubectl --context=my-context debug mypod -it \
  --image=busybox \
  --target=mycontainer

# Inside: ps aux, /proc inspection
```

### Node-Level Issues

```bash
# Debug node with host access
kubectl --context=my-context debug node/worker-1 -it \
  --image=ubuntu \
  --profile=sysadmin

# Inside:
# - Host filesystem at /host
# - chroot /host for full access
# - journalctl, systemctl, dmesg
```

### Non-Destructive Debugging

```bash
# Create copy, keeping original running
kubectl --context=my-context debug mypod -it \
  --copy-to=mypod-debug \
  --same-node \
  --share-processes \
  --image=busybox

# Original pod continues serving traffic
# Debug copy shares storage if on same node
```

## Key Options

| Option | Description |
|--------|-------------|
| `-it` | Interactive TTY (required for shell access) |
| `--image` | Debug container image |
| `--container` | Name for the debug container |
| `--target` | Share process namespace with this container |
| `--copy-to` | Create a copy instead of ephemeral container |
| `--same-node` | Schedule copy on same node (with `--copy-to`) |
| `--set-image` | Change container images in copy |
| `--profile` | Security profile (legacy, netadmin, sysadmin, etc.) |
| `--share-processes` | Enable process namespace sharing (default: true with --copy-to) |
| `--replace` | Delete original pod when creating copy |

## Best Practices

1. **Use appropriate profiles** - Match capabilities to debugging needs
2. **Prefer ephemeral containers** - Less disruptive than pod copies
3. **Use `--copy-to` for invasive debugging** - Preserve original pod
4. **Clean up debug pods** - Delete copies after debugging
5. **Use `--same-node`** - For accessing shared storage/network conditions

## Cleanup

```bash
# List debug pod copies
kubectl --context=my-context get pods | grep -E "debug|copy"

# Delete debug pods
kubectl --context=my-context delete pod mypod-debug
```

## Requirements

- Kubernetes 1.23+ for ephemeral containers (stable)
- Kubernetes 1.25+ for debug profiles
- RBAC permissions for pods/ephemeralcontainers

For detailed option reference, examples, and troubleshooting patterns, see REFERENCE.md.
