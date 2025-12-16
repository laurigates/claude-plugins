# kubectl debug Reference

Comprehensive reference for debugging Kubernetes resources with `kubectl debug`.

## Table of Contents

- [Synopsis](#synopsis)
- [Complete Options Reference](#complete-options-reference)
- [Ephemeral Containers](#ephemeral-containers)
- [Pod Copying](#pod-copying)
- [Node Debugging](#node-debugging)
- [Debug Profiles Deep Dive](#debug-profiles-deep-dive)
- [Debug Images](#debug-images)
- [Advanced Patterns](#advanced-patterns)
- [Troubleshooting](#troubleshooting)

---

## Synopsis

```bash
kubectl debug (POD | TYPE[[.VERSION].GROUP]/NAME) [ -- COMMAND [args...] ]
```

The `kubectl debug` command provides automation for common debugging tasks:

- **Pods**: Add ephemeral containers or create modified copies
- **Nodes**: Create pods in host namespaces with filesystem access

---

## Complete Options Reference

### Debug-Specific Options

| Option | Type | Description |
|--------|------|-------------|
| `--arguments-only` | bool | Pass everything after `--` as Args instead of Command |
| `--attach` | bool | Wait for container to start and attach (default: false, true if `-i` set) |
| `-c, --container` | string | Container name for debug container |
| `--copy-to` | string | Create a copy of target Pod with this name |
| `--custom` | string | Path to JSON/YAML file with partial container spec |
| `--env` | stringToString | Environment variables to set (e.g., `--env FOO=bar`) |
| `-f, --filename` | strings | File identifying the resource to debug |
| `--image` | string | Container image for debug container |
| `--image-pull-policy` | string | Image pull policy (empty = server default) |
| `--keep-annotations` | bool | Keep original pod annotations (with `--copy-to`) |
| `--keep-init-containers` | bool | Run init containers (default: true, with `--copy-to`) |
| `--keep-labels` | bool | Keep original pod labels (with `--copy-to`) |
| `--keep-liveness` | bool | Keep liveness probes (with `--copy-to`) |
| `--keep-readiness` | bool | Keep readiness probes (with `--copy-to`) |
| `--keep-startup` | bool | Keep startup probes (with `--copy-to`) |
| `--profile` | string | Debug profile: legacy, general, baseline, netadmin, restricted, sysadmin |
| `-q, --quiet` | bool | Suppress informational messages |
| `--replace` | bool | Delete original Pod (with `--copy-to`) |
| `--same-node` | bool | Schedule copy on same node (with `--copy-to`) |
| `--set-image` | stringToString | Change container images (with `--copy-to`) |
| `--share-processes` | bool | Enable process namespace sharing (default: true, with `--copy-to`) |
| `-i, --stdin` | bool | Keep stdin open on container |
| `--target` | string | Target processes in this container (ephemeral container) |
| `-t, --tty` | bool | Allocate TTY for debug container |

### Global Options (Inherited)

| Option | Description |
|--------|-------------|
| `--context` | Kubeconfig context to use (ALWAYS specify this) |
| `-n, --namespace` | Namespace scope for this request |
| `--kubeconfig` | Path to kubeconfig file |
| `--as` | Username to impersonate |
| `--as-group` | Groups to impersonate |
| `--cluster` | Kubeconfig cluster to use |
| `--user` | Kubeconfig user to use |
| `--server` | Kubernetes API server address |
| `--token` | Bearer token for authentication |
| `--certificate-authority` | Path to CA certificate |
| `--insecure-skip-tls-verify` | Skip TLS verification |

---

## Ephemeral Containers

Ephemeral containers are temporary containers added to running pods for debugging purposes.

### How They Work

1. Added to running pod's spec without restart
2. Share pod's network, IPC, and optionally PID namespace
3. Cannot be removed once added (pod must be recreated)
4. Ideal for debugging without disrupting the application

### Basic Usage

```bash
# Add ephemeral container with busybox
kubectl --context=my-context debug mypod -it --image=busybox

# Named debug container
kubectl --context=my-context debug mypod -it --image=busybox -c debugger

# With environment variables
kubectl --context=my-context debug mypod -it --image=busybox --env DEBUG=1

# Target specific container's processes
kubectl --context=my-context debug mypod -it --image=busybox --target=app
```

### Process Namespace Sharing

With `--target`, the debug container shares the process namespace:

```bash
# Share process namespace with 'app' container
kubectl --context=my-context debug mypod -it --image=busybox --target=app

# Inside debug container:
# - ps aux shows processes from 'app' container
# - /proc/<pid>/* accessible for process inspection
# - strace, gdb can attach to processes
```

### Viewing Ephemeral Containers

```bash
# Check ephemeral containers on a pod
kubectl --context=my-context get pod mypod -o jsonpath='{.spec.ephemeralContainers[*].name}'

# Describe pod to see ephemeral container status
kubectl --context=my-context describe pod mypod

# Get full pod spec
kubectl --context=my-context get pod mypod -o yaml | grep -A 20 ephemeralContainers
```

### Limitations

- Cannot be removed (pod must be deleted/recreated)
- Cannot modify existing containers
- Non-root users in target may have limited capabilities
- Requires EphemeralContainers feature (stable in 1.23+)

---

## Pod Copying

Create a copy of a pod with modifications for debugging.

### Basic Copy

```bash
# Copy pod with debug container
kubectl --context=my-context debug mypod -it --copy-to=mypod-debug --image=busybox

# Copy keeps original running (non-destructive)
kubectl --context=my-context get pods
# NAME          READY   STATUS    RESTARTS   AGE
# mypod         1/1     Running   0          1h
# mypod-debug   2/2     Running   0          5s
```

### Modify Container Images

```bash
# Change single container image
kubectl --context=my-context debug mypod --copy-to=mypod-debug \
  --set-image=app=myapp:debug

# Change multiple container images
kubectl --context=my-context debug mypod --copy-to=mypod-debug \
  --set-image=app=myapp:debug,sidecar=sidecar:debug

# Change all container images
kubectl --context=my-context debug mypod --copy-to=mypod-debug \
  --set-image='*=busybox'
```

### Modify Container Command

```bash
# Override command for specific container
kubectl --context=my-context debug mypod -it --copy-to=mypod-debug \
  --container=app \
  -- sh

# Override with arguments only
kubectl --context=my-context debug mypod --copy-to=mypod-debug \
  --container=app \
  --arguments-only \
  -- --debug --verbose
```

### Scheduling Options

```bash
# Schedule on same node (access same storage, network conditions)
kubectl --context=my-context debug mypod -it --copy-to=mypod-debug \
  --same-node \
  --image=busybox

# Replace original pod (destructive)
kubectl --context=my-context debug mypod -it --copy-to=mypod-debug \
  --replace \
  --image=busybox
```

### Preserve or Remove Features

```bash
# Keep labels (for service inclusion)
kubectl --context=my-context debug mypod --copy-to=mypod-debug \
  --keep-labels \
  --image=busybox

# Skip init containers (faster startup)
kubectl --context=my-context debug mypod --copy-to=mypod-debug \
  --keep-init-containers=false \
  --image=busybox

# Keep probes (test health check behavior)
kubectl --context=my-context debug mypod --copy-to=mypod-debug \
  --keep-liveness \
  --keep-readiness \
  --image=busybox

# Disable process sharing
kubectl --context=my-context debug mypod --copy-to=mypod-debug \
  --share-processes=false \
  --image=busybox
```

---

## Node Debugging

Create a pod in the node's host namespaces for node-level debugging.

### Basic Node Debug

```bash
# Interactive node debugging
kubectl --context=my-context debug node/mynode -it --image=busybox

# With Ubuntu for more tools
kubectl --context=my-context debug node/mynode -it --image=ubuntu
```

### What You Get

- **Host Network Namespace**: See host network interfaces
- **Host PID Namespace**: See host processes
- **Host IPC Namespace**: Access host IPC
- **Host Filesystem**: Mounted at `/host`

### Common Node Debugging Tasks

```bash
# Inside node debug pod:

# Access host filesystem
ls /host
cat /host/etc/os-release
cat /host/var/log/syslog

# Full host access with chroot
chroot /host

# View host processes
ps aux

# Check node resources
cat /host/proc/meminfo
cat /host/proc/cpuinfo

# View system logs (after chroot)
journalctl -u kubelet
dmesg | tail -50

# Check systemd services
systemctl status kubelet
systemctl status containerd
```

### Node Debug Pod Cleanup

```bash
# List node debug pods
kubectl --context=my-context get pods -A | grep node-debugger

# Delete node debug pod
kubectl --context=my-context delete pod node-debugger-mynode-xxxxx -n default
```

---

## Debug Profiles Deep Dive

Debug profiles control security settings for debug containers.

### Profile Comparison

| Profile | securityContext | Capabilities |
|---------|-----------------|--------------|
| `legacy` | None (unrestricted) | None added |
| `general` | runAsNonRoot possible | None added |
| `baseline` | Follows baseline PSS | None added |
| `netadmin` | CAP_NET_ADMIN | NET_RAW, NET_ADMIN |
| `restricted` | Follows restricted PSS | None added |
| `sysadmin` | Privileged-like | SYS_PTRACE, SYS_ADMIN |

### Profile Use Cases

#### netadmin - Network Debugging

```bash
kubectl --context=my-context debug mypod -it \
  --image=nicolaka/netshoot \
  --profile=netadmin

# Enabled capabilities:
# - tcpdump, packet capture
# - iptables inspection
# - network namespace operations
```

#### sysadmin - System Debugging

```bash
kubectl --context=my-context debug mypod -it \
  --image=ubuntu \
  --profile=sysadmin

# Enabled capabilities:
# - strace, ptrace operations
# - system administration
# - full process inspection
```

#### restricted - High Security

```bash
kubectl --context=my-context debug mypod -it \
  --image=alpine \
  --profile=restricted

# Enforces:
# - Non-root user
# - Read-only root filesystem
# - Dropped capabilities
```

### Custom Profile (--custom)

```bash
# Create custom container spec
cat > debug-container.yaml << 'EOF'
securityContext:
  capabilities:
    add:
    - NET_ADMIN
    - SYS_PTRACE
  runAsUser: 0
  runAsGroup: 0
resources:
  limits:
    memory: "256Mi"
    cpu: "500m"
EOF

# Use custom spec
kubectl --context=my-context debug mypod -it \
  --image=ubuntu \
  --custom=debug-container.yaml
```

---

## Debug Images

### Lightweight Images

| Image | Size | Package Manager | Best For |
|-------|------|-----------------|----------|
| `busybox` | ~1MB | None | Basic shell, minimal utilities |
| `alpine` | ~5MB | apk | Shell with package manager |
| `gcr.io/distroless/base-debian12` | ~20MB | None | Minimal runtime |

### Full-Featured Images

| Image | Size | Package Manager | Best For |
|-------|------|-----------------|----------|
| `ubuntu` | ~77MB | apt | General debugging, apt packages |
| `debian` | ~120MB | apt | Full Debian environment |
| `fedora` | ~200MB | dnf | Full Fedora environment |

### Specialized Images

| Image | Size | Focus | Key Tools |
|-------|------|-------|-----------|
| `nicolaka/netshoot` | ~350MB | Network | tcpdump, dig, curl, nmap, iperf |
| `wbitt/network-multitool` | ~40MB | Network | curl, ping, dig, nslookup |
| `gcr.io/k8s-debug/debug` | Varies | General | Kubernetes-focused debugging |

### Building Custom Debug Image

```dockerfile
FROM alpine:3.19

# Common debugging tools
RUN apk add --no-cache \
    bash \
    curl \
    wget \
    jq \
    bind-tools \
    tcpdump \
    strace \
    netcat-openbsd \
    procps \
    htop \
    vim

CMD ["sleep", "infinity"]
```

---

## Advanced Patterns

### Debug Multiple Containers

```bash
# Add multiple debug containers
kubectl --context=my-context debug mypod -it --image=busybox -c debug1
kubectl --context=my-context debug mypod -it --image=nicolaka/netshoot -c debug2

# Each has access to pod's network
```

### Automated Debug Scripts

```bash
#!/bin/bash
# debug-pod.sh - Automated pod debugging

CONTEXT="${1:?Usage: debug-pod.sh CONTEXT POD [NAMESPACE]}"
POD="${2:?Usage: debug-pod.sh CONTEXT POD [NAMESPACE]}"
NAMESPACE="${3:-default}"

# Create debug pod copy
kubectl --context="$CONTEXT" debug "$POD" \
  -n "$NAMESPACE" \
  --copy-to="${POD}-debug" \
  --same-node \
  --image=nicolaka/netshoot \
  --profile=netadmin \
  -- sleep infinity

echo "Debug pod created: ${POD}-debug"
echo "Connect with: kubectl --context=$CONTEXT exec -it ${POD}-debug -n $NAMESPACE -- bash"
echo "Cleanup with: kubectl --context=$CONTEXT delete pod ${POD}-debug -n $NAMESPACE"
```

### Debug from File

```bash
# Debug pod defined in file
kubectl --context=my-context debug -f pod.yaml -it --image=busybox

# Useful for:
# - Debugging manifests before applying
# - Testing configurations
# - CI/CD pipeline debugging
```

### Debug with Specific User

```bash
# Create custom spec for user
cat > debug-user.yaml << 'EOF'
securityContext:
  runAsUser: 1000
  runAsGroup: 1000
EOF

kubectl --context=my-context debug mypod -it \
  --image=alpine \
  --custom=debug-user.yaml
```

### Capture Network Traffic

```bash
# Start debug container with netadmin profile
kubectl --context=my-context debug mypod -it \
  --image=nicolaka/netshoot \
  --profile=netadmin \
  -c tcpdump

# Inside container:
tcpdump -i any -w /tmp/capture.pcap port 80

# Copy capture out (from another terminal)
kubectl --context=my-context cp mypod:/tmp/capture.pcap ./capture.pcap -c tcpdump
```

### Strace a Process

```bash
# Start debug with sysadmin profile, targeting container
kubectl --context=my-context debug mypod -it \
  --image=ubuntu \
  --profile=sysadmin \
  --target=app

# Inside container:
apt update && apt install -y strace
strace -p 1  # Trace main process
```

---

## Troubleshooting

### Error: Unable to Create Ephemeral Container

**Symptom:**
```
error: ephemeralcontainers are disabled for this cluster
```

**Cause:** EphemeralContainers feature not enabled or old Kubernetes version.

**Solution:**
- Upgrade to Kubernetes 1.23+ (ephemeral containers stable)
- Use `--copy-to` instead for pod copying approach

### Error: Debug Container Does Not Have Required Permissions

**Symptom:**
```
Error: operation not permitted
```

**Cause:** Profile doesn't have required capabilities.

**Solution:**
```bash
# Use appropriate profile
kubectl --context=my-context debug mypod -it \
  --image=ubuntu \
  --profile=sysadmin  # or netadmin
```

### Error: Target Container Not Found

**Symptom:**
```
error: container "xyz" not found in pod
```

**Solution:**
```bash
# List containers in pod
kubectl --context=my-context get pod mypod -o jsonpath='{.spec.containers[*].name}'

# Use correct container name
kubectl --context=my-context debug mypod -it --image=busybox --target=correct-name
```

### Debug Pod Copy Not Starting

**Symptom:** Debug pod stays in Pending state.

**Causes:**
- Insufficient resources
- Node affinity/tolerations
- Image pull issues

**Solution:**
```bash
# Check pod events
kubectl --context=my-context describe pod mypod-debug

# Try without same-node constraint
kubectl --context=my-context debug mypod -it \
  --copy-to=mypod-debug \
  --image=busybox  # Remove --same-node

# Use smaller image
kubectl --context=my-context debug mypod -it \
  --copy-to=mypod-debug \
  --image=busybox  # Instead of ubuntu
```

### Cannot See Processes from Target Container

**Symptom:** `ps aux` only shows debug container processes.

**Cause:** Process namespace sharing not working or container exited.

**Solution:**
```bash
# Ensure target container is running
kubectl --context=my-context get pod mypod -o jsonpath='{.status.containerStatuses[*].ready}'

# Verify process sharing is enabled
kubectl --context=my-context get pod mypod -o yaml | grep shareProcessNamespace

# For pod copy, ensure sharing enabled
kubectl --context=my-context debug mypod -it \
  --copy-to=mypod-debug \
  --share-processes=true \
  --image=busybox
```

### Node Debug Pod Cleanup

**Symptom:** Node debug pods accumulate.

**Solution:**
```bash
# Find and delete all node debug pods
kubectl --context=my-context get pods -A -o name | grep node-debugger | \
  xargs -I {} kubectl --context=my-context delete {} -n default

# Or by label
kubectl --context=my-context delete pods -l app=node-debugger
```

---

## Related Skills

- **Kubernetes Operations** - General kubectl usage and troubleshooting
- **Helm Debugging** - Debugging Helm deployments
- **ArgoCD CLI Login** - GitOps debugging with ArgoCD

## References

- [kubectl debug documentation](https://kubernetes.io/docs/reference/kubectl/generated/kubectl_debug/)
- [Debug Running Pods](https://kubernetes.io/docs/tasks/debug/debug-application/debug-running-pod/)
- [Debug Nodes](https://kubernetes.io/docs/tasks/debug/debug-cluster/kubectl-node-debug/)
- [Ephemeral Containers](https://kubernetes.io/docs/concepts/workloads/pods/ephemeral-containers/)
- [Debug Profiles KEP](https://github.com/kubernetes/enhancements/tree/master/keps/sig-cli/1441-kubectl-debug)
