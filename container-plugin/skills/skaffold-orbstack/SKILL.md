---
name: skaffold-orbstack
description: |
  OrbStack-optimized Skaffold workflows for local Kubernetes development without port-forward.
  Use when configuring Skaffold with OrbStack, accessing services via LoadBalancer or Ingress,
  or when the user mentions OrbStack, k8s.orb.local, service access, or eliminating port-forward.
---

# Skaffold with OrbStack - Port-Forward-Free Development

## Overview

OrbStack provides superior local Kubernetes networking compared to other tools (minikube, kind, Docker Desktop). Services are accessible directly from macOS without port-forward.

## Key OrbStack Advantages

| Feature | OrbStack | minikube/kind |
|---------|----------|---------------|
| LoadBalancer auto-provision | ✅ Yes | ❌ Needs MetalLB |
| Wildcard DNS (`*.k8s.orb.local`) | ✅ Yes | ❌ No |
| cluster.local from host | ✅ Yes | ❌ No |
| Pod IP direct access | ✅ Yes | ❌ No |
| Auto HTTPS certificates | ✅ Yes | ❌ No |

## Service Access Methods

### Method 1: LoadBalancer Services (Simplest)

Change service type from ClusterIP to LoadBalancer:

```yaml
apiVersion: v1
kind: Service
metadata:
  name: my-app
spec:
  type: LoadBalancer  # OrbStack auto-provisions external IP
  ports:
    - port: 80
      targetPort: 8080
  selector:
    app: my-app
```

**Access**: `curl http://my-app.default.svc.cluster.local` from macOS

### Method 2: Ingress with Wildcard DNS (Recommended)

**One-time setup - Install Ingress controller:**

```bash
# Ingress-NGINX (recommended)
kubectl apply -f https://raw.githubusercontent.com/kubernetes/ingress-nginx/controller-v1.8.1/deploy/static/provider/cloud/deploy.yaml

# OR Traefik
helm repo add traefik https://traefik.github.io/charts
helm install traefik traefik/traefik
```

**Create Ingress for your service:**

```yaml
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: my-app
spec:
  ingressClassName: nginx
  rules:
    - host: my-app.k8s.orb.local
      http:
        paths:
          - path: /
            pathType: Prefix
            backend:
              service:
                name: my-app
                port:
                  number: 80
```

**Access**: `http://my-app.k8s.orb.local` (auto-resolves)

### Method 3: Direct Service DNS (cluster.local)

OrbStack exposes cluster DNS to macOS:

```bash
# Access any service directly
curl http://my-app.default.svc.cluster.local:8080

# Full DNS pattern
curl http://<service>.<namespace>.svc.cluster.local:<port>
```

## Skaffold Configuration for OrbStack

### Minimal skaffold.yaml (No Port-Forward Needed)

```yaml
apiVersion: skaffold/v4beta11
kind: Config
metadata:
  name: my-app

build:
  local:
    push: false
    useBuildkit: true
  artifacts:
    - image: my-app
      docker:
        dockerfile: Dockerfile

deploy:
  kubeContext: orbstack
  kubectl:
    manifests:
      - k8s/*.yaml
  statusCheck: true
  statusCheckDeadlineSeconds: 180

# Port-forward REMOVED - use LoadBalancer/Ingress instead
```

### Profile: Local with Ingress

```yaml
profiles:
  - name: local-ingress
    deploy:
      kubeContext: orbstack
      kubectl:
        manifests:
          - k8s/base/*.yaml
          - k8s/ingress/*.yaml  # Ingress resources
```

### Profile: Services-Only (Frontend Local Dev)

```yaml
profiles:
  - name: services-only
    build:
      artifacts: []  # Don't build frontend
    deploy:
      kubeContext: orbstack
      kubectl:
        manifests:
          - k8s/namespace.yaml
          - k8s/database/*.yaml
          - k8s/api/*.yaml
```

Access backend at `http://api.k8s.orb.local` while running `npm run dev` locally.

## Kubernetes Manifest Templates

### LoadBalancer Service Template

```yaml
# k8s/service.yaml
apiVersion: v1
kind: Service
metadata:
  name: {{ .name }}
  labels:
    app: {{ .name }}
spec:
  type: LoadBalancer
  ports:
    - name: http
      port: 80
      targetPort: {{ .containerPort | default 8080 }}
  selector:
    app: {{ .name }}
```

### Ingress Template

```yaml
# k8s/ingress.yaml
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: {{ .name }}
  annotations:
    nginx.ingress.kubernetes.io/rewrite-target: /
spec:
  ingressClassName: nginx
  rules:
    - host: {{ .name }}.k8s.orb.local
      http:
        paths:
          - path: /
            pathType: Prefix
            backend:
              service:
                name: {{ .name }}
                port:
                  number: 80
```

## Migration: Port-Forward to LoadBalancer

### Before (Traditional)

```yaml
# skaffold.yaml with port-forward
portForward:
  - resourceType: service
    resourceName: api
    port: 8080
    localPort: 8080
    address: 127.0.0.1
  - resourceType: service
    resourceName: frontend
    port: 3000
    localPort: 3000
    address: 127.0.0.1
```

```bash
skaffold dev  # Services at localhost:8080, localhost:3000
```

### After (OrbStack Native)

```yaml
# k8s/services.yaml - Change service types
apiVersion: v1
kind: Service
metadata:
  name: api
spec:
  type: LoadBalancer  # Changed from ClusterIP
  ports:
    - port: 8080
---
apiVersion: v1
kind: Service
metadata:
  name: frontend
spec:
  type: LoadBalancer  # Changed from ClusterIP
  ports:
    - port: 3000
```

```yaml
# skaffold.yaml - Remove portForward section entirely
deploy:
  kubeContext: orbstack
  kubectl:
    manifests:
      - k8s/*.yaml
# No portForward needed!
```

```bash
skaffold dev  # Services at api.default.svc.cluster.local:8080
              #            frontend.default.svc.cluster.local:3000
```

## Common Patterns

### Database Access

```yaml
# k8s/postgresql.yaml
apiVersion: v1
kind: Service
metadata:
  name: postgresql
spec:
  type: LoadBalancer  # Access from local tools (DBeaver, pgAdmin)
  ports:
    - port: 5432
```

**Connection string**: `postgres://user:pass@postgresql.default.svc.cluster.local:5432/db`  <!-- pragma: allowlist secret -->

### Multi-Service Application

```yaml
# k8s/ingress.yaml - Single Ingress for all services
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: app-ingress
spec:
  ingressClassName: nginx
  rules:
    - host: api.k8s.orb.local
      http:
        paths:
          - path: /
            pathType: Prefix
            backend:
              service:
                name: api
                port:
                  number: 8080
    - host: web.k8s.orb.local
      http:
        paths:
          - path: /
            pathType: Prefix
            backend:
              service:
                name: frontend
                port:
                  number: 3000
    - host: admin.k8s.orb.local
      http:
        paths:
          - path: /
            pathType: Prefix
            backend:
              service:
                name: admin-panel
                port:
                  number: 8000
```

## Security Considerations

### Default: Localhost Only

OrbStack restricts services to localhost by default - safe on untrusted networks.

### Expose to LAN (Use with Caution)

Settings → Kubernetes → "Expose services to local network devices"

Only enable when:
- Testing from mobile devices on same network
- Sharing local environment with team
- On trusted network

## Troubleshooting

### Service Not Accessible

1. Check service type: `kubectl get svc`
2. Verify LoadBalancer has EXTERNAL-IP (not `<pending>`)
3. Test DNS: `nslookup my-app.default.svc.cluster.local`

### Ingress Not Working

1. Verify Ingress controller is running:
   ```bash
   kubectl -n ingress-nginx get pods
   ```
2. Check Ingress controller has LoadBalancer IP:
   ```bash
   kubectl -n ingress-nginx get svc
   ```
3. Verify Ingress resource:
   ```bash
   kubectl describe ingress my-app
   ```

### DNS Resolution Issues

```bash
# Test cluster DNS from macOS
nslookup my-service.default.svc.cluster.local

# If short names fail, use full domain
# ❌ my-service.default.svc
# ✅ my-service.default.svc.cluster.local
```

### Pod IP Direct Access (Debugging)

```bash
# Get pod IP
kubectl get pods -o wide

# Connect directly (OrbStack routes pod network to macOS)
curl http://10.42.0.15:8080
```

## Quick Setup Checklist

1. [ ] Install Ingress controller (one-time)
2. [ ] Change service types to LoadBalancer
3. [ ] Create Ingress resources for pretty URLs
4. [ ] Remove `portForward` from skaffold.yaml
5. [ ] Set `kubeContext: orbstack` in deploy config
6. [ ] Update local .env/config to use `.k8s.orb.local` URLs

## Commands Reference

```bash
# Start development (no --port-forward needed)
skaffold dev --kube-context=orbstack

# Run specific profile
skaffold dev -p services-only --kube-context=orbstack

# Check service accessibility
kubectl get svc -o wide

# Verify Ingress
kubectl get ingress
```
