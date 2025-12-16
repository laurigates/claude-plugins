# Kubernetes Plugin Setup

## What Was Created

The following files have been successfully created:

1. **Directory Structure**:
   ```
   /Users/lgates/repos/laurigates/claude-plugins/kubernetes-plugin/
   ├── .claude-plugin/
   │   └── plugin.json          ✓ Created
   ├── skills/                  ✓ Created (empty)
   ├── README.md                ✓ Created
   ├── SETUP.md                 ✓ Created (this file)
   └── install-skills.sh        ✓ Created
   ```

2. **plugin.json** - Plugin metadata with name, version, description, and keywords

3. **README.md** - Comprehensive documentation of all 7 skills and usage instructions

4. **install-skills.sh** - Installation script to copy skills from source directory

5. **SETUP.md** - This file with setup instructions

## What Needs to Be Done

### Step 1: Copy Skills to Plugin Directory

The skills directory is currently empty. Run the installation script to copy all 7 skills:

```bash
cd /Users/lgates/repos/laurigates/claude-plugins/kubernetes-plugin
chmod +x install-skills.sh
./install-skills.sh
```

This will copy the following skills from `/Users/lgates/.local/share/chezmoi/exact_dot_claude/skills/`:

1. **kubernetes-operations** - K8s cluster management and debugging
2. **helm-chart-development** - Create and package Helm charts
3. **helm-debugging** - Troubleshoot Helm deployment failures
4. **helm-release-management** - Install, upgrade, uninstall releases
5. **helm-release-recovery** - Rollback and recovery strategies
6. **helm-values-management** - Multi-environment value configuration
7. **argocd-login** - ArgoCD CLI authentication

### Alternative: Manual Copy

If the script doesn't work, copy manually:

```bash
cd /Users/lgates/repos/laurigates/claude-plugins/kubernetes-plugin
mkdir -p skills

# Copy each skill
for skill in kubernetes-operations helm-chart-development helm-debugging helm-release-management helm-release-recovery helm-values-management argocd-login; do
  cp -r /Users/lgates/.local/share/chezmoi/exact_dot_claude/skills/$skill skills/
done

# Verify
ls -la skills/
```

### Step 2: Verify Plugin Structure

After copying skills, verify the complete structure:

```bash
cd /Users/lgates/repos/laurigates/claude-plugins/kubernetes-plugin
find . -type f | sort
```

Expected output:
```
./.claude-plugin/plugin.json
./README.md
./SETUP.md
./install-skills.sh
./skills/argocd-login/SKILL.md
./skills/helm-chart-development/SKILL.md
./skills/helm-debugging/SKILL.md
./skills/helm-release-management/SKILL.md
./skills/helm-release-recovery/SKILL.md
./skills/helm-values-management/SKILL.md
./skills/kubernetes-operations/REFERENCE.md
./skills/kubernetes-operations/SKILL.md
```

### Step 3: Test Plugin

Test that the plugin loads correctly:

```bash
# Check plugin metadata
cat .claude-plugin/plugin.json

# Verify skills exist
ls -la skills/
```

## Skills Summary

Each skill provides specialized expertise:

| Skill | Purpose | Key Features |
|-------|---------|--------------|
| **kubernetes-operations** | K8s cluster ops | kubectl mastery, pod debugging, context safety, comprehensive REFERENCE.md |
| **helm-chart-development** | Chart creation | Scaffolding, templating, testing, packaging, schema validation |
| **helm-debugging** | Troubleshooting | Layered validation, template errors, resource conflicts, hook failures |
| **helm-release-management** | Release ops | Install, upgrade, rollback, multi-environment workflows |
| **helm-release-recovery** | Recovery | Rollback, stuck states, partial deployments, atomic prevention |
| **helm-values-management** | Configuration | Override precedence, multi-env, secret management, schema validation |
| **argocd-login** | GitOps auth | SSO authentication, gRPC-Web, post-login operations |

## Usage After Setup

Once skills are copied, the plugin is ready to use:

### Local Project Installation
```bash
# In your Kubernetes project
claude plugins add /Users/lgates/repos/laurigates/claude-plugins/kubernetes-plugin
```

### Global Installation
```bash
# Available in all projects
claude plugins add --global /Users/lgates/repos/laurigates/claude-plugins/kubernetes-plugin
```

### Verification
```bash
# List installed plugins
claude plugins list

# Check if kubernetes-plugin is loaded
claude plugins list | grep kubernetes
```

## Troubleshooting

### Issue: Skills directory is empty
**Solution**: Run `./install-skills.sh` or manually copy skills as described above

### Issue: Permission denied on script
**Solution**: `chmod +x install-skills.sh`

### Issue: Source skills not found
**Verify**: `ls -la /Users/lgates/.local/share/chezmoi/exact_dot_claude/skills/`

### Issue: Plugin not loading
**Check**:
1. Plugin structure matches expected layout
2. All skill SKILL.md files exist
3. plugin.json is valid JSON

## Next Steps

After completing the setup:

1. ✅ Run installation script or manual copy
2. ✅ Verify all 7 skills are present
3. ✅ Test plugin loading
4. ✅ Use with Claude Code for K8s/Helm tasks

## Support

For issues or questions:
- Check README.md for detailed skill documentation
- Review individual SKILL.md files in each skill directory
- Consult kubernetes-operations/REFERENCE.md for comprehensive kubectl reference
