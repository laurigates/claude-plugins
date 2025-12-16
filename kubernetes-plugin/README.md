# Kubernetes Plugin

Comprehensive Kubernetes and Helm operations plugin for Claude Code, providing expert knowledge for K8s cluster management, Helm chart development, and GitOps with ArgoCD.

## Overview

This plugin bundles all Kubernetes-related skills for managing cloud-native applications, including:
- Kubernetes cluster operations and debugging
- Helm chart development, testing, and packaging
- Helm release management and recovery
- Values configuration across environments
- ArgoCD CLI authentication

## Skills Included

### Kubernetes Operations
**File**: `skills/kubernetes-operations/SKILL.md`

Core Kubernetes cluster management, deployment, and troubleshooting with kubectl mastery.

**When to use**: User mentions Kubernetes, K8s, kubectl, pods, deployments, services, ingress, ConfigMaps, Secrets, or cluster operations.

**Capabilities**:
- Workload management (Deployments, StatefulSets, DaemonSets, Jobs, CronJobs)
- Networking (Services, Ingress, NetworkPolicies, DNS)
- Configuration & Storage (ConfigMaps, Secrets, PVs, PVCs)
- Pod debugging and troubleshooting
- Context safety (explicit --context usage)

**Reference**: Includes comprehensive `REFERENCE.md` with complete kubectl command reference and troubleshooting guides.

---

### Helm Chart Development
**File**: `skills/helm-chart-development/SKILL.md`

Create, test, and package Helm charts for Kubernetes applications.

**When to use**: User wants to create Helm charts, test templates, package charts, or publish to repositories.

**Capabilities**:
- Chart scaffolding with `helm create`
- Chart.yaml and values.yaml design
- Template development with best practices
- Chart validation and testing (lint, template, dry-run)
- Chart dependencies management
- Schema validation with values.schema.json
- Chart packaging and distribution

---

### Helm Debugging
**File**: `skills/helm-debugging/SKILL.md`

Debug and troubleshoot Helm deployment failures, template errors, and configuration issues.

**When to use**: User reports Helm errors, deployment failures, template rendering issues, or needs debugging assistance.

**Capabilities**:
- Layered validation approach (lint → template → dry-run → install → test)
- Template rendering and inspection
- YAML parse error resolution
- Value type error fixes
- Resource conflict resolution
- Image pull failure debugging
- CRD and hook troubleshooting
- Timeout and rollback handling

---

### Helm Release Management
**File**: `skills/helm-release-management/SKILL.md`

Day-to-day Helm release operations: install, upgrade, uninstall, and release tracking.

**When to use**: User requests deploying/installing Helm charts, upgrading releases, or managing deployments.

**Capabilities**:
- Install new releases with atomic rollback
- Upgrade releases with value management
- Release listing and filtering
- Release history and status inspection
- Multi-environment deployment workflows
- Value override precedence handling
- Pre-deployment validation

---

### Helm Release Recovery
**File**: `skills/helm-release-recovery/SKILL.md`

Recover from failed deployments, rollback releases, and fix stuck release states.

**When to use**: User needs rollback, reports stuck releases (pending-install/upgrade), or failed deployments.

**Capabilities**:
- Rollback to previous revisions
- Recovery from stuck release states
- Handling partial deployments
- Cascading failure recovery across environments
- History management and cleanup
- Atomic deployment prevention strategies
- Pre-upgrade backup procedures

---

### Helm Values Management
**File**: `skills/helm-values-management/SKILL.md`

Manage Helm values across environments with override precedence and secret management.

**When to use**: User needs environment-specific configs, values.yaml management, or configuration strategies.

**Capabilities**:
- Value override precedence (chart defaults → files → --set)
- Multi-environment value organization (dev/staging/prod)
- Values file layering and composition
- Secret management strategies
- Schema validation with values.schema.json
- Value syntax and type handling
- Template value rendering best practices

---

### ArgoCD Login
**File**: `skills/argocd-login/SKILL.md`

ArgoCD CLI authentication with SSO for GitOps workflows.

**When to use**: User mentions ArgoCD login, authentication, or accessing ArgoCD applications.

**Capabilities**:
- SSO authentication with gRPC-Web
- Post-login application management
- Cluster and project information access
- Session management and troubleshooting
- Integration with ArgoCD MCP tools

---

## Installation

### Manual Installation (Required)

Since the skills directory was not automatically populated, you need to manually copy the skills:

```bash
cd /Users/lgates/repos/laurigates/claude-plugins/kubernetes-plugin

# Copy all skills
for skill in kubernetes-operations helm-chart-development helm-debugging helm-release-management helm-release-recovery helm-values-management argocd-login; do
  cp -r /Users/lgates/.local/share/chezmoi/exact_dot_claude/skills/$skill skills/
done

# Verify skills were copied
ls -la skills/
```

Expected structure:
```
kubernetes-plugin/
├── .claude-plugin/
│   └── plugin.json
├── skills/
│   ├── kubernetes-operations/
│   │   ├── SKILL.md
│   │   └── REFERENCE.md
│   ├── helm-chart-development/
│   │   └── SKILL.md
│   ├── helm-debugging/
│   │   └── SKILL.md
│   ├── helm-release-management/
│   │   └── SKILL.md
│   ├── helm-release-recovery/
│   │   └── SKILL.md
│   ├── helm-values-management/
│   │   └── SKILL.md
│   └── argocd-login/
│       └── SKILL.md
└── README.md
```

## Usage

### Loading the Plugin

1. Install plugin in your project or globally:
   ```bash
   # In your project
   claude plugins add /Users/lgates/repos/laurigates/claude-plugins/kubernetes-plugin

   # Or globally
   claude plugins add --global /Users/lgates/repos/laurigates/claude-plugins/kubernetes-plugin
   ```

2. The plugin will automatically activate when you mention Kubernetes or Helm topics

### Skill Activation

Skills are automatically activated based on user queries:

- **"Deploy my app to Kubernetes"** → Activates `kubernetes-operations`
- **"Create a Helm chart"** → Activates `helm-chart-development`
- **"My Helm upgrade failed"** → Activates `helm-debugging` and `helm-release-recovery`
- **"Configure values for production"** → Activates `helm-values-management`
- **"Login to ArgoCD"** → Activates `argocd-login`

### Common Workflows

#### Deploy Application with Helm
1. Create chart: `helm-chart-development`
2. Validate chart: `helm-debugging`
3. Install release: `helm-release-management`
4. Verify deployment: `kubernetes-operations`

#### Troubleshoot Failed Deployment
1. Debug failure: `helm-debugging`
2. Inspect K8s resources: `kubernetes-operations`
3. Rollback if needed: `helm-release-recovery`

#### Multi-Environment Setup
1. Configure values: `helm-values-management`
2. Deploy to dev/staging/prod: `helm-release-management`
3. Monitor and debug: `kubernetes-operations` + `helm-debugging`

## Best Practices

### Context Safety
All skills emphasize **explicit context specification**:
```bash
# Always use --context
kubectl --context=prod-cluster get pods
helm --kube-context=prod-cluster status myapp
```

Never rely on current context to prevent accidental operations on wrong clusters.

### Atomic Deployments
Use atomic flags for production:
```bash
helm upgrade myapp ./chart --namespace prod --atomic --wait --timeout 10m
```

### Layered Validation
Always progress through validation layers:
```bash
helm lint ./chart --strict              # 1. Static analysis
helm template myapp ./chart --debug     # 2. Render locally
helm install myapp ./chart --dry-run    # 3. Server validation
helm install myapp ./chart --atomic     # 4. Actual deployment
helm test myapp                          # 5. Post-deploy tests
```

### Value Management
Organize values hierarchically:
```
values/
├── common.yaml         # Base values
├── dev.yaml           # Dev overrides
├── staging.yaml       # Staging overrides
└── production.yaml    # Production overrides
```

Deploy with layered values:
```bash
helm upgrade --install myapp ./chart \
  -f values/common.yaml \
  -f values/production.yaml \
  --atomic --wait
```

## Keywords

kubernetes, helm, k8s, deployments, charts, releases, kubectl, argocd, gitops, cloud-native, containers, pods, services, ingress, configmaps, secrets, statefulsets, daemonsets

## Version

1.0.0

## License

Same as Claude Code configuration
