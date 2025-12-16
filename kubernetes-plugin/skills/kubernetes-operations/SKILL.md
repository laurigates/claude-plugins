---
name: kubernetes-operations
description: |
  Kubernetes operations including deployment, management, troubleshooting, kubectl mastery,
  and cluster stability. Covers K8s workloads, networking, storage, and debugging pods.
  Use when user mentions Kubernetes, K8s, kubectl, pods, deployments, services, ingress,
  ConfigMaps, Secrets, or cluster operations.
allowed-tools: Glob, Grep, Read, Bash, Edit, Write, TodoWrite, WebFetch
---

# Kubernetes Operations

Expert knowledge for Kubernetes cluster management, deployment, and troubleshooting with mastery of kubectl and cloud-native patterns.

## Core Expertise

**Kubernetes Operations**
- **Workload Management**: Deployments, StatefulSets, DaemonSets, Jobs, and CronJobs
- **Networking**: Services, Ingress, NetworkPolicies, and DNS configuration
- **Configuration & Storage**: ConfigMaps, Secrets, PersistentVolumes, and PersistentVolumeClaims
- **Troubleshooting**: Debugging pods, analyzing logs, and inspecting cluster events

## Cluster Operations Process

1. **Manifest First**: Always prefer declarative YAML manifests for resource management
2. **Validate & Dry-Run**: Use `kubectl apply --dry-run=client` to validate changes
3. **Inspect & Verify**: After applying changes, verify with `kubectl get`, `kubectl describe`, `kubectl logs`
4. **Monitor Health**: Continuously check status of nodes, pods, and services
5. **Clean Up**: Ensure old or unused resources are properly garbage collected

## Essential Commands

```bash
# Resource management
kubectl apply -f manifest.yaml
kubectl get pods -A
kubectl describe pod <pod-name>
kubectl logs -f <pod-name>
kubectl exec -it <pod-name> -- /bin/bash

# Debugging
kubectl get events --sort-by='.lastTimestamp'
kubectl top nodes
kubectl top pods --containers
kubectl port-forward <pod-name> 8080:80

# Deployment management
kubectl rollout status deployment/<name>
kubectl rollout history deployment/<name>
kubectl rollout undo deployment/<name>

# Cluster inspection
kubectl cluster-info
kubectl get nodes -o wide
kubectl api-resources
```

## Key Debugging Patterns

**Pod Debugging**
```bash
# Pod inspection
kubectl describe pod <pod-name>
kubectl get pod <pod-name> -o yaml
kubectl logs <pod-name> --previous

# Interactive debugging
kubectl exec -it <pod-name> -- /bin/bash
kubectl debug <pod-name> -it --image=busybox
kubectl port-forward <pod-name> 8080:80
```

**Networking Troubleshooting**
```bash
# Service debugging
kubectl get svc -o wide
kubectl get endpoints
kubectl describe svc <service>

# Network connectivity
kubectl run test-pod --image=busybox -it --rm -- sh
# Inside pod: nslookup, wget, nc commands
```

**Common Issues**
```bash
# CrashLoopBackOff debugging
kubectl logs <pod> --previous
kubectl describe pod <pod>
kubectl get events --field-selector involvedObject.name=<pod>

# Resource constraints
kubectl top pod <pod>
kubectl describe pod <pod> | grep -A 5 Limits

# State management
kubectl state list
kubectl state show <resource>
```

## Best Practices

**Context Safety (CRITICAL)**
- **Always specify `--context`** explicitly in every kubectl command
- Never rely on the current context - it may have been changed by another process
- Use `kubectl --context=<context-name> get pods` format for all operations
- This prevents accidental operations on the wrong cluster (e.g., running production commands against staging)

```bash
# CORRECT: Explicit context
kubectl --context=gke_myproject_us-central1_prod get pods
kubectl --context=staging-cluster apply -f deployment.yaml

# WRONG: Relying on current context
kubectl get pods  # Which cluster is this targeting?
```

**Resource Definitions**
- Use declarative YAML manifests
- Implement proper labels and selectors
- Define resource requests and limits
- Configure health checks (liveness/readiness probes)

**Security**
- Use NetworkPolicies to restrict traffic
- Implement RBAC for access control
- Store sensitive data in Secrets
- Run containers as non-root users

**Monitoring**
- Configure proper logging and metrics
- Set up alerts for critical conditions
- Use health checks and readiness probes
- Monitor resource usage and quotas

For detailed debugging commands, troubleshooting patterns, Helm workflows, and advanced K8s operations, see REFERENCE.md.
