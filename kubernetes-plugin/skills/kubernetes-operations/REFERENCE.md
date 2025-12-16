# Kubernetes Operations Reference

Comprehensive reference for Kubernetes debugging, troubleshooting, Helm workflows, and advanced operations.

## Table of Contents

- [Context Management](#context-management)
- [Complete kubectl Command Reference](#complete-kubectl-command-reference)
- [Troubleshooting by Issue Type](#troubleshooting-by-issue-type)
- [Helm Workflows](#helm-workflows)
- [Advanced Operations](#advanced-operations)
- [Cluster Administration](#cluster-administration)

---

## Context Management

### Critical Safety Rule

**Always specify `--context` explicitly** in every kubectl command. Never rely on the current context.

This prevents accidental operations on the wrong cluster, which can lead to:
- Production outages from test deployments
- Data loss from delete operations
- Security incidents from misapplied configurations

### Listing Available Contexts

```bash
# List all contexts
kubectl config get-contexts

# Show current context (informational only - don't rely on this)
kubectl config current-context

# Get detailed cluster info for a context
kubectl --context=my-context cluster-info
```

### Command Pattern

Always use this pattern:

```bash
# Format: kubectl --context=<context-name> <command>
kubectl --context=gke_myproject_us-central1_prod get pods
kubectl --context=staging-cluster apply -f deployment.yaml
kubectl --context=local-dev delete pod test-pod
```

### Shell Helpers (Optional)

If you frequently work with specific clusters, create aliases:

```bash
# Fish shell
alias kprod='kubectl --context=production'
alias kstage='kubectl --context=staging'

# Then use:
kprod get pods
kstage apply -f manifest.yaml
```

### Why Not Use `kubectl config use-context`?

Switching context with `use-context` creates hidden state that can lead to errors:
- Another terminal may change the context while you're working
- Scripts may assume a different context
- Automation tools may interfere
- Long-running shells may have stale context

Explicit `--context` eliminates this entire class of errors.

---

## Complete kubectl Command Reference

### Resource Management

**Get/List Resources**
```bash
# Get resources
kubectl get pods                      # Current namespace
kubectl get pods -A                   # All namespaces
kubectl get pods -n namespace         # Specific namespace
kubectl get pods -o wide              # More details
kubectl get pods -o yaml              # YAML format
kubectl get pods -o json              # JSON format
kubectl get pods --show-labels        # Show labels
kubectl get pods -l app=nginx         # Filter by label

# Get with custom columns
kubectl get pods -o custom-columns=\
NAME:.metadata.name,\
STATUS:.status.phase,\
IP:.status.podIP

# Watch for changes
kubectl get pods -w                   # Watch mode
kubectl get pods --watch-only        # Only watch, no initial list

# Get multiple resource types
kubectl get pods,svc,deploy
kubectl get all                       # Most common resources
```

**Describe Resources**
```bash
# Detailed information
kubectl describe pod <pod-name>
kubectl describe svc <service-name>
kubectl describe node <node-name>

# Describe with selector
kubectl describe pods -l app=nginx

# Show only specific sections
kubectl describe pod <name> | grep -A 10 Events
kubectl describe pod <name> | grep -A 5 Conditions
```

**Create/Apply Resources**
```bash
# Create from file
kubectl create -f manifest.yaml
kubectl create -f directory/          # All manifests in dir
kubectl create -f https://example.com/manifest.yaml

# Apply (declarative)
kubectl apply -f manifest.yaml
kubectl apply -f directory/ -R        # Recursive
kubectl apply -k ./kustomize-dir      # Kustomize

# Dry run
kubectl apply -f manifest.yaml --dry-run=client
kubectl apply -f manifest.yaml --dry-run=server

# Show diff before applying
kubectl diff -f manifest.yaml

# Server-side apply (recommended for controllers)
kubectl apply -f manifest.yaml --server-side
```

**Delete Resources**
```bash
# Delete by name
kubectl delete pod <pod-name>
kubectl delete svc <service-name>

# Delete from file
kubectl delete -f manifest.yaml

# Delete with selector
kubectl delete pods -l app=nginx

# Delete all pods in namespace
kubectl delete pods --all

# Force delete stuck pod
kubectl delete pod <name> --force --grace-period=0

# Delete namespace (cascading delete)
kubectl delete namespace <name>
```

**Edit Resources**
```bash
# Edit in default editor
kubectl edit pod <pod-name>
kubectl edit deploy <deployment-name>

# Edit with specific editor
KUBE_EDITOR=vim kubectl edit pod <name>

# Update image
kubectl set image deployment/nginx nginx=nginx:1.21
kubectl set image deploy/* nginx=nginx:1.21  # All deployments

# Scale deployment
kubectl scale deployment nginx --replicas=5

# Autoscale
kubectl autoscale deployment nginx --min=2 --max=10 --cpu-percent=80
```

### Pod Operations

**Pod Lifecycle**
```bash
# Run pod
kubectl run nginx --image=nginx
kubectl run nginx --image=nginx --port=80
kubectl run nginx --image=nginx --dry-run=client -o yaml > pod.yaml

# Run interactive pod
kubectl run -it busybox --image=busybox --rm --restart=Never -- sh

# Execute command in pod
kubectl exec <pod> -- ls /
kubectl exec <pod> -- env

# Interactive shell
kubectl exec -it <pod> -- /bin/bash
kubectl exec -it <pod> -- /bin/sh
kubectl exec -it <pod> -c <container> -- sh  # Specific container

# Port forward
kubectl port-forward <pod> 8080:80
kubectl port-forward svc/<service> 8080:80
kubectl port-forward deploy/<deployment> 8080:80

# Copy files
kubectl cp <pod>:/path/to/file ./local-file
kubectl cp ./local-file <pod>:/path/to/file
kubectl cp <pod>:/path/to/file ./local-file -c <container>  # Specific container

# Attach to running container
kubectl attach <pod> -it
kubectl attach <pod> -c <container> -it
```

**Pod Logs**
```bash
# Basic logs
kubectl logs <pod>
kubectl logs <pod> -c <container>     # Specific container
kubectl logs <pod> --all-containers   # All containers

# Follow logs
kubectl logs -f <pod>

# Previous container logs
kubectl logs <pod> --previous
kubectl logs <pod> -c <container> --previous

# Timestamp logs
kubectl logs <pod> --timestamps

# Tail logs
kubectl logs <pod> --tail=100
kubectl logs <pod> --tail=100 -f

# Since time
kubectl logs <pod> --since=1h
kubectl logs <pod> --since-time=2024-01-01T00:00:00Z

# Multiple pods
kubectl logs -l app=nginx --all-containers
kubectl logs -l app=nginx -f --max-log-requests=10
```

### Deployment Management

**Deployments**
```bash
# Create deployment
kubectl create deployment nginx --image=nginx
kubectl create deployment nginx --image=nginx --replicas=3

# Expose deployment
kubectl expose deployment nginx --port=80 --type=ClusterIP

# Rollout management
kubectl rollout status deployment/nginx
kubectl rollout history deployment/nginx
kubectl rollout history deployment/nginx --revision=2

# Rollback
kubectl rollout undo deployment/nginx
kubectl rollout undo deployment/nginx --to-revision=2

# Pause/resume rollout
kubectl rollout pause deployment/nginx
kubectl rollout resume deployment/nginx

# Restart deployment
kubectl rollout restart deployment/nginx
```

**StatefulSets**
```bash
# Manage StatefulSet
kubectl scale statefulset mysql --replicas=5

# Delete pods one by one
kubectl delete pod mysql-0

# Force delete
kubectl delete pod mysql-0 --force --grace-period=0

# Update strategy
kubectl patch statefulset mysql -p '{"spec":{"updateStrategy":{"type":"RollingUpdate"}}}'
```

**DaemonSets**
```bash
# Get DaemonSet pods per node
kubectl get ds -o wide

# Update DaemonSet
kubectl set image ds/fluentd fluentd=fluentd:v2.0

# Rollout status
kubectl rollout status ds/fluentd
```

### Configuration & Secrets

**ConfigMaps**
```bash
# Create from literal
kubectl create configmap app-config --from-literal=key1=value1 --from-literal=key2=value2

# Create from file
kubectl create configmap app-config --from-file=config.ini
kubectl create configmap app-config --from-file=configs/  # Directory

# Create from env file
kubectl create configmap app-config --from-env-file=.env

# Get ConfigMap
kubectl get configmap app-config -o yaml

# Edit ConfigMap
kubectl edit configmap app-config
```

**Secrets**
```bash
# Create generic secret
kubectl create secret generic db-secret \
  --from-literal=username=admin \
  --from-literal=password=secret123

# Create from file
kubectl create secret generic tls-secret \
  --from-file=tls.crt=./cert.pem \
  --from-file=tls.key=./key.pem

# Create TLS secret
kubectl create secret tls tls-secret \
  --cert=./cert.pem \
  --key=./key.pem

# Create Docker registry secret
kubectl create secret docker-registry regcred \
  --docker-server=registry.example.com \
  --docker-username=user \
  --docker-password=pass \
  --docker-email=user@example.com

# Decode secret
kubectl get secret db-secret -o jsonpath='{.data.password}' | base64 -d

# Edit secret
kubectl edit secret db-secret
```

### Networking

**Services**
```bash
# Create service
kubectl expose pod nginx --port=80 --type=ClusterIP
kubectl expose deployment nginx --port=80 --type=LoadBalancer

# Get service endpoints
kubectl get endpoints <service>
kubectl get svc <service> -o wide

# Service types
kubectl create service clusterip nginx --tcp=80:80
kubectl create service nodeport nginx --tcp=80:80 --node-port=30080
kubectl create service loadbalancer nginx --tcp=80:80
```

**Ingress**
```bash
# Get ingress
kubectl get ingress
kubectl describe ingress <name>

# Create ingress
kubectl create ingress simple --rule="foo.com/bar=svc:8080"

# TLS ingress
kubectl create ingress tls --rule="foo.com/*=svc:8080,tls=secret"
```

**Network Policies**
```bash
# Get network policies
kubectl get networkpolicy
kubectl describe networkpolicy <name>

# Test network connectivity
kubectl run test --image=busybox -it --rm --restart=Never -- \
  wget -qO- --timeout=2 http://service-name
```

---

## Troubleshooting by Issue Type

### Pod Issues

**CrashLoopBackOff**
```bash
# Check recent logs
kubectl logs <pod> --previous

# Describe pod for events
kubectl describe pod <pod> | grep -A 20 Events

# Check resource limits
kubectl describe pod <pod> | grep -A 5 Limits

# Common causes:
# 1. Application crashes immediately
# 2. Failed liveness/readiness probes
# 3. Missing dependencies or config
# 4. Permission issues
```

**ImagePullBackOff / ErrImagePull**
```bash
# Check image name and tag
kubectl describe pod <pod> | grep Image

# Check image pull secrets
kubectl get secret <regcred> -o yaml

# Test image pull manually
kubectl run test --image=<image> --rm -it --restart=Never

# Common causes:
# 1. Wrong image name or tag
# 2. Missing image pull secret
# 3. Private registry auth issues
# 4. Network issues reaching registry
```

**Pending Pods**
```bash
# Check pod events
kubectl describe pod <pod> | grep -A 10 Events

# Check node resources
kubectl top nodes
kubectl describe nodes

# Check for taints and tolerations
kubectl describe node <node> | grep Taints

# Check PVC status (if used)
kubectl get pvc

# Common causes:
# 1. Insufficient resources (CPU/memory)
# 2. No nodes matching selector
# 3. PVC not bound
# 4. Node has taints without tolerations
```

**Evicted Pods**
```bash
# Find evicted pods
kubectl get pods -A | grep Evicted

# Get eviction reason
kubectl describe pod <pod> | grep Reason

# Delete evicted pods
kubectl get pods -A | grep Evicted | awk '{print $2 " -n " $1}' | xargs kubectl delete pod

# Check node pressure
kubectl describe nodes | grep -A 5 Conditions

# Common causes:
# 1. Node disk pressure
# 2. Node memory pressure
# 3. Node PID pressure
```

### Networking Issues

**Service Not Accessible**
```bash
# Check service exists
kubectl get svc <service>

# Check endpoints
kubectl get endpoints <service>

# Describe service
kubectl describe svc <service>

# Test from within cluster
kubectl run test --image=busybox -it --rm --restart=Never -- \
  wget -qO- --timeout=2 http://<service>.<namespace>.svc.cluster.local

# Test DNS resolution
kubectl run test --image=busybox -it --rm --restart=Never -- \
  nslookup <service>.<namespace>.svc.cluster.local

# Check network policies
kubectl get networkpolicy -A
kubectl describe networkpolicy <policy>

# Common causes:
# 1. No pods backing the service (check selectors)
# 2. Network policy blocking traffic
# 3. Incorrect service port configuration
# 4. DNS issues
```

**DNS Resolution Failing**
```bash
# Test DNS
kubectl run test --image=busybox -it --rm --restart=Never -- \
  nslookup kubernetes.default

# Check CoreDNS pods
kubectl get pods -n kube-system -l k8s-app=kube-dns

# Check CoreDNS logs
kubectl logs -n kube-system -l k8s-app=kube-dns

# Check CoreDNS ConfigMap
kubectl get configmap coredns -n kube-system -o yaml

# Restart CoreDNS
kubectl rollout restart deployment/coredns -n kube-system
```

**Ingress Not Working**
```bash
# Check ingress
kubectl describe ingress <name>

# Check ingress controller
kubectl get pods -n ingress-nginx
kubectl logs -n ingress-nginx -l app.kubernetes.io/name=ingress-nginx

# Check service backend
kubectl get svc <backend-service>
kubectl get endpoints <backend-service>

# Test service directly
kubectl port-forward svc/<backend-service> 8080:80

# Common causes:
# 1. Ingress controller not running
# 2. Incorrect backend service reference
# 3. TLS certificate issues
# 4. Host/path rules not matching
```

### Storage Issues

**PVC Pending**
```bash
# Check PVC status
kubectl describe pvc <pvc-name>

# Check StorageClass
kubectl get storageclass
kubectl describe storageclass <name>

# Check provisioner logs
kubectl logs -n kube-system -l app=<provisioner>

# Check events
kubectl get events --sort-by=.metadata.creationTimestamp

# Common causes:
# 1. No default StorageClass
# 2. Insufficient storage capacity
# 3. StorageClass provisioner not running
# 4. Access mode not supported
```

**Volume Mount Failures**
```bash
# Check pod events
kubectl describe pod <pod> | grep -A 10 Events

# Check PVC status
kubectl get pvc

# Check PV status
kubectl get pv

# Check node mounts (if accessible)
kubectl debug node/<node-name> -it --image=ubuntu

# Common causes:
# 1. PVC not bound
# 2. Wrong mount path or permissions
# 3. Volume already mounted elsewhere (ReadWriteOnce)
# 4. Node doesn't support volume type
```

### Resource Issues

**Out of Memory (OOM)**
```bash
# Check for OOM kills
kubectl describe pod <pod> | grep -i oom

# Check memory limits
kubectl get pod <pod> -o jsonpath='{.spec.containers[*].resources.limits.memory}'

# Check actual memory usage
kubectl top pod <pod>

# Review logs for memory issues
kubectl logs <pod> | grep -i memory

# Increase memory limit
kubectl set resources deployment <name> -c=<container> --limits=memory=2Gi
```

**CPU Throttling**
```bash
# Check CPU usage
kubectl top pod <pod>
kubectl top node

# Check CPU limits
kubectl get pod <pod> -o jsonpath='{.spec.containers[*].resources.limits.cpu}'

# Container metrics (if metrics-server available)
kubectl get --raw /apis/metrics.k8s.io/v1beta1/namespaces/<ns>/pods/<pod> | jq

# Adjust CPU limits
kubectl set resources deployment <name> -c=<container> --limits=cpu=2000m
```

---

## Helm Workflows

### Helm Basics

**Installation & Setup**
```bash
# Install Helm
curl https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 | bash

# Add repository
helm repo add stable https://charts.helm.sh/stable
helm repo add bitnami https://charts.bitnami.com/bitnami

# Update repositories
helm repo update

# Search charts
helm search repo nginx
helm search hub nginx
```

**Chart Management**
```bash
# Install chart
helm install myrelease bitnami/nginx
helm install myrelease bitnami/nginx --namespace mynamespace --create-namespace

# Install with custom values
helm install myrelease bitnami/nginx -f values.yaml
helm install myrelease bitnami/nginx --set replicaCount=3

# Dry run
helm install myrelease bitnami/nginx --dry-run --debug

# Install from local chart
helm install myrelease ./mychart

# Install from tarball
helm install myrelease chart.tgz
```

**Release Management**
```bash
# List releases
helm list
helm list -A                          # All namespaces
helm list -n namespace                # Specific namespace

# Get release info
helm get all myrelease
helm get values myrelease
helm get manifest myrelease
helm get notes myrelease

# Upgrade release
helm upgrade myrelease bitnami/nginx
helm upgrade myrelease bitnami/nginx -f values.yaml
helm upgrade myrelease bitnami/nginx --set image.tag=1.21

# Upgrade or install
helm upgrade --install myrelease bitnami/nginx

# Rollback
helm rollback myrelease
helm rollback myrelease 1             # To specific revision
helm rollback myrelease 1 --cleanup-on-fail

# History
helm history myrelease

# Uninstall
helm uninstall myrelease
helm uninstall myrelease --keep-history
```

### Creating Charts

**Chart Structure**
```bash
# Create new chart
helm create mychart

# Chart directory structure:
mychart/
   Chart.yaml              # Chart metadata
   values.yaml             # Default values
   templates/              # K8s manifests
      deployment.yaml
      service.yaml
      _helpers.tpl        # Template helpers
      NOTES.txt           # Post-install notes
   charts/                 # Dependencies
```

**Template Functions**
```yaml
# values.yaml
replicaCount: 3
image:
  repository: nginx
  tag: "1.21"

# templates/deployment.yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: {{ include "mychart.fullname" . }}
spec:
  replicas: {{ .Values.replicaCount }}
  template:
    spec:
      containers:
      - name: {{ .Chart.Name }}
        image: "{{ .Values.image.repository }}:{{ .Values.image.tag | default .Chart.AppVersion }}"
```

**Testing Charts**
```bash
# Lint chart
helm lint ./mychart

# Template chart (dry run)
helm template myrelease ./mychart
helm template myrelease ./mychart -f values.yaml

# Install with debug
helm install myrelease ./mychart --debug --dry-run

# Package chart
helm package ./mychart

# Test release
helm test myrelease
```

---

## Advanced Operations

### Debugging Tools

**Debug Containers**
```bash
# Debug running pod
kubectl debug <pod> -it --image=busybox --target=<container>

# Debug with ephemeral container
kubectl debug <pod> -it --image=ubuntu --share-processes --copy-to=<new-pod-name>

# Debug node
kubectl debug node/<node-name> -it --image=ubuntu

# Exec into container with debugging tools
kubectl run debug --image=nicolaka/netshoot -it --rm --restart=Never
```

**Resource Metrics**
```bash
# Node metrics
kubectl top nodes
kubectl top nodes --sort-by=cpu
kubectl top nodes --sort-by=memory

# Pod metrics
kubectl top pods -A
kubectl top pods -n namespace --sort-by=cpu
kubectl top pods -n namespace --containers

# Metrics API (raw)
kubectl get --raw /apis/metrics.k8s.io/v1beta1/nodes
kubectl get --raw /apis/metrics.k8s.io/v1beta1/pods
```

**Events**
```bash
# Get all events
kubectl get events --sort-by='.lastTimestamp'
kubectl get events --sort-by='.metadata.creationTimestamp'

# Filter events
kubectl get events --field-selector type=Warning
kubectl get events --field-selector involvedObject.name=<pod-name>

# Watch events
kubectl get events -w

# Events for specific resource
kubectl describe pod <pod> | grep -A 20 Events
```

### Advanced kubectl Techniques

**JSONPath Queries**
```bash
# Extract specific fields
kubectl get pods -o jsonpath='{.items[*].metadata.name}'
kubectl get pods -o jsonpath='{.items[*].status.podIP}'

# Complex queries
kubectl get pods -o jsonpath='{range .items[*]}{.metadata.name}{"\t"}{.status.phase}{"\n"}{end}'

# Nested fields
kubectl get pods -o jsonpath='{.items[*].spec.containers[*].image}'

# Filter with JSONPath
kubectl get pods -o json | jq '.items[] | select(.status.phase=="Running")'
```

**Custom Columns**
```bash
kubectl get pods -o custom-columns=\
NAME:.metadata.name,\
STATUS:.status.phase,\
IP:.status.podIP,\
NODE:.spec.nodeName

kubectl get nodes -o custom-columns=\
NAME:.metadata.name,\
CPU:.status.capacity.cpu,\
MEMORY:.status.capacity.memory
```

**Labels & Selectors**
```bash
# Add label
kubectl label pods <pod> env=prod

# Remove label
kubectl label pods <pod> env-

# Update label
kubectl label pods <pod> env=staging --overwrite

# Select by label
kubectl get pods -l env=prod
kubectl get pods -l 'env in (prod,staging)'
kubectl get pods -l 'env notin (dev,test)'
kubectl get pods -l env=prod,tier=frontend
```

**Annotations**
```bash
# Add annotation
kubectl annotate pods <pod> description="Production pod"

# Remove annotation
kubectl annotate pods <pod> description-

# View annotations
kubectl get pod <pod> -o jsonpath='{.metadata.annotations}'
```

---

## Cluster Administration

### Node Management

**Node Operations**
```bash
# Get nodes
kubectl get nodes
kubectl get nodes -o wide
kubectl describe node <node>

# Label nodes
kubectl label nodes <node> disktype=ssd
kubectl label nodes <node> disktype-            # Remove

# Taint nodes
kubectl taint nodes <node> key=value:NoSchedule
kubectl taint nodes <node> key=value:NoExecute
kubectl taint nodes <node> key:NoSchedule-      # Remove

# Cordon/uncordon
kubectl cordon <node>                           # Prevent scheduling
kubectl uncordon <node>                         # Allow scheduling

# Drain node
kubectl drain <node> --ignore-daemonsets --delete-emptydir-data
```

**Node Troubleshooting**
```bash
# Check node conditions
kubectl describe node <node> | grep -A 10 Conditions

# Check node capacity
kubectl describe node <node> | grep -A 10 Capacity

# Check kubelet status (on node)
systemctl status kubelet
journalctl -u kubelet -f

# Check node logs
kubectl logs -n kube-system <kubelet-pod>
```

### Namespace Management

```bash
# Create namespace
kubectl create namespace dev

# Set default namespace
kubectl config set-context --current --namespace=dev

# Delete namespace
kubectl delete namespace dev

# Resource quotas
kubectl create quota dev-quota --hard=cpu=10,memory=20Gi,pods=50 -n dev

# Limit ranges
kubectl create limitrange dev-limits \
  --default=cpu=500m,memory=512Mi \
  --default-request=cpu=100m,memory=128Mi \
  -n dev
```

### RBAC

```bash
# Create service account
kubectl create serviceaccount mysa

# Create role
kubectl create role pod-reader --verb=get,list,watch --resource=pods

# Create rolebinding
kubectl create rolebinding read-pods --role=pod-reader --serviceaccount=default:mysa

# Create clusterrole
kubectl create clusterrole cluster-admin --verb=* --resource=*

# Create clusterrolebinding
kubectl create clusterrolebinding admin-binding --clusterrole=cluster-admin --user=admin

# Check permissions
kubectl auth can-i create pods
kubectl auth can-i create pods --as=mysa
kubectl auth can-i --list
```

---

## Additional Resources

- **Kubernetes Documentation**: https://kubernetes.io/docs/
- **kubectl Cheat Sheet**: https://kubernetes.io/docs/reference/kubectl/cheatsheet/
- **Helm Documentation**: https://helm.sh/docs/
- **Kubernetes API Reference**: https://kubernetes.io/docs/reference/kubernetes-api/
- **kubectl Book**: https://kubectl.docs.kubernetes.io/
