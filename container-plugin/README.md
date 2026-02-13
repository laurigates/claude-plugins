# Container Plugin

A comprehensive Claude plugin for container development and deployment workflows, focusing on Docker, Skaffold, and Kubernetes.

## Overview

This plugin provides expert knowledge and tooling for:
- Docker container development with security-first practices
- Multi-stage builds and image optimization
- Skaffold workflows for local Kubernetes development
- OrbStack-optimized configurations
- Deployment automation and handoff documentation
- 12-factor app methodology

## Contents

### Skills

#### container-development
Expert knowledge for containerization and orchestration with a focus on security-first, lean container images and 12-factor app methodology.

**Key Features:**
- Security-first philosophy (mandatory non-root users, minimal base images)
- Multi-stage Docker builds for production-ready images
- Image optimization and vulnerability scanning
- 12-factor app compliance
- Comprehensive reference documentation

**Use when:**
- Working with Docker, Dockerfiles, or Containerfiles
- Building container images
- Implementing container security best practices
- Following 12-factor app principles
- Optimizing container builds

**Reference Documentation:**
- Multi-stage build patterns
- 12-factor app principles implementation
- Security best practices
- Skaffold workflows
- Docker Compose patterns
- Performance optimization
- Advanced Dockerfile patterns

#### skaffold-orbstack
OrbStack-optimized Skaffold workflows for local Kubernetes development without port-forwarding.

**Key Features:**
- Port-forward-free development with OrbStack
- LoadBalancer auto-provisioning
- Wildcard DNS support (*.k8s.orb.local)
- Direct service access from macOS
- Ingress controller setup and configuration

**Use when:**
- Configuring Skaffold with OrbStack
- Accessing services via LoadBalancer or Ingress
- Eliminating port-forward complexity
- Setting up local Kubernetes development

**Advantages over minikube/kind:**
- Automatic LoadBalancer provisioning
- Native DNS resolution (cluster.local)
- Direct pod IP access from host
- Auto HTTPS certificates

#### skaffold-testing
Container image validation with Skaffold test and verify stages for robust CI/CD pipelines.

**Key Features:**
- Container structure tests for image hygiene
- Custom tests for security scanning (Grype, Trivy)
- Post-deployment verification with the verify stage
- Profile-based testing (quick vs thorough)
- Essential security test templates

**Use when:**
- Configuring pre-deploy image validation
- Setting up security scanning in CI
- Implementing post-deployment integration tests
- Creating robust container testing pipelines

**Testing Lifecycle:**
```
Build → Test → Deploy → Verify
         ↑               ↑
    Pre-deploy      Post-deploy
```

**Test Types:**
- `structureTests`: Validate image contents (files, commands, metadata)
- `custom`: Run arbitrary commands (security scans, unit tests)
- `verify`: Post-deployment integration tests

#### skaffold-filesync
Fast iterative development with Skaffold file sync - copy changed files to running containers without rebuilding images.

**Key Features:**
- Three sync modes: manual, infer, and auto
- Hot reload support for interpreted languages
- Static asset synchronization
- Directory stripping for complex layouts
- Zero-config support for Buildpacks and Jib

**Use when:**
- Optimizing the development loop
- Setting up hot reload in Kubernetes
- Syncing source code to running containers
- Avoiding unnecessary image rebuilds

**Sync Modes:**
| Mode | Best For |
|------|----------|
| `manual` | Full control, complex directory layouts |
| `infer` | Docker builds, derives destinations from Dockerfile |
| `auto` | Buildpacks, Jib - zero configuration |

**Speed Comparison:**
```
Without sync: Edit → Build → Deploy → Restart (~30-60s)
With sync:    Edit → Copy → Test (~1-2s)
```

#### deploy-release
Create and publish a new release with release-please automation.

**Features:**
- Manifest-based release configuration
- Automatic version number updates across files
- GitHub release integration

**Usage:**
```bash
claude chat --file ~/.claude/skills/deploy-release/SKILL.md <version> [--draft] [--prerelease]
```

#### deploy-handoff
Generate professional deployment handoff documentation for resources and services.

**Features:**
- Automatic repository and deployment context detection
- Professional formatting for handoff messages
- Comprehensive service documentation
- Developer handoff checklists
- Access information and monitoring links

**Usage:**
```bash
# Basic handoff for current project
claude chat --file ~/.claude/skills/deploy-handoff/SKILL.md

# Specific service handoff
claude chat --file ~/.claude/skills/deploy-handoff/SKILL.md "User API" "web-service"
```

**Output includes:**
- Service overview and technical details
- Access URLs and endpoints
- Documentation links
- Developer handoff checklist
- Support and contact information

## Installation

### Option 1: Copy to .claude directory (Manual)

```bash
# Copy the entire plugin directory
cp -r container-plugin ~/.claude/plugins/container-plugin
```

### Option 2: Symlink (Development)

```bash
# Create symlink for development
ln -s "$(pwd)/container-plugin" ~/.claude/plugins/container-plugin
```

### Option 3: chezmoi (Recommended)

If using chezmoi for dotfile management:

```bash
# Add to chezmoi source directory
cp -r container-plugin ~/.local/share/chezmoi/exact_dot_claude/plugins/exact_container-plugin

# Apply changes
chezmoi apply ~/.claude
```

## Usage

Once installed, the skills and commands are automatically available in Claude Code.

### Skills Activation

Skills are automatically activated when relevant keywords are detected:

**container-development:** Docker, Dockerfile, containers, docker-compose, multi-stage builds, container images, container security, 12-factor app

**skaffold-orbstack:** OrbStack, k8s.orb.local, Skaffold, service access, port-forward

**skaffold-testing:** skaffold test, skaffold verify, container-structure-test, image testing, security scanning, Grype, Trivy, pre-deploy validation

**skaffold-filesync:** file sync, hot reload, live reload, fast iteration, sync rules, copy files to container

### Skill Usage

Skills can be invoked using the Claude chat interface:

```bash
# Release automation
claude chat --file ~/.claude/skills/deploy-release/SKILL.md 1.0.0

# Deployment handoff
claude chat --file ~/.claude/skills/deploy-handoff/SKILL.md "My Service" "api"
```

## Security Philosophy

This plugin enforces strict security best practices:

### Mandatory Requirements
- **Non-root users:** ALL production containers MUST run as non-root
- **Minimal base images:** Alpine (~5MB) for Node.js/Go/Rust, slim (~50MB) for Python
- **Multi-stage builds:** Separate build and runtime environments
- **Vulnerability scanning:** Trivy or Grype integration in CI
- **Health checks:** Required for Kubernetes probes

### Image Size Guidelines
- Alpine base: ~5MB
- Debian slim: ~50-70MB
- Distroless: ~2MB (no shell)

## Best Practices

### Container Development
1. Use multi-stage builds to minimize image size
2. Run containers as non-root users
3. Pin specific image versions (avoid `latest`)
4. Implement health checks
5. Follow 12-factor app principles
6. Scan images for vulnerabilities

### Skaffold Workflows
1. Use OrbStack for superior local Kubernetes networking
2. Prefer LoadBalancer services over port-forwarding
3. Leverage Ingress for pretty URLs
4. Configure proper health checks and readiness probes
5. Use profiles for different environments

### Deployment
1. Generate comprehensive handoff documentation
2. Include monitoring and logging information
3. Document access URLs and endpoints
4. Provide developer checklists
5. Maintain professional communication style

## Dependencies

### Container Development
- Docker or compatible container runtime
- BuildKit (for cache mounts and optimizations)
- Trivy or Grype (for security scanning)

### Skaffold Testing
- container-structure-test binary
- Grype or Trivy (for vulnerability scanning)
- Skaffold v2.0+ (for verify stage)

### Skaffold Workflows
- OrbStack (recommended) or minikube/kind
- kubectl
- Skaffold
- Ingress controller (ingress-nginx or Traefik)

### Deployment Commands
- Git
- GitHub CLI (optional, for release automation)

## Related Resources

### Documentation
- [Docker Documentation](https://docs.docker.com/)
- [Dockerfile Best Practices](https://docs.docker.com/develop/develop-images/dockerfile_best-practices/)
- [12-Factor App](https://12factor.net/)
- [Skaffold Documentation](https://skaffold.dev/docs/)
- [OrbStack Documentation](https://docs.orbstack.dev/)

### Security
- [Docker Security Cheat Sheet](https://cheatsheetseries.owasp.org/cheatsheets/Docker_Security_Cheat_Sheet.html)
- [Container Security Best Practices](https://docs.docker.com/engine/security/)

## Version

1.0.0

## Keywords

container, docker, dockerfile, registry, skaffold, deployment, kubernetes, orbstack, 12-factor, multi-stage-builds, security, image-optimization, container-structure-test, grype, trivy, verify, image-testing, filesync, hot-reload, live-reload

## License

This plugin is part of the claude-plugins repository and follows the same license terms.

## Contributing

Contributions are welcome! Please ensure:
- New container patterns follow security best practices
- Documentation is comprehensive and clear
- Examples are tested and verified
- Skills include appropriate trigger keywords

## Support

For issues, questions, or contributions:
1. Check the reference documentation in each skill
2. Review the examples and patterns provided
3. Consult official documentation for Docker, Skaffold, and Kubernetes
4. Open an issue in the claude-plugins repository
