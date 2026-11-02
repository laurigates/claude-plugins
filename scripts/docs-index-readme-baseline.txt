# Skill directories named nowhere in their plugin README, accepted when
# Check 10 of scripts/check-docs-index.sh landed (#3164). <plugin>/<skill>
# per line. An entry whose skill gets named in its README, or whose skill is
# removed, is a readme_baseline_stale finding: delete it, so this list only
# shrinks. Never add a new omission here; name the skill in the README instead.
agent-patterns-plugin/exclusive-lock-dispatch
agent-patterns-plugin/wave-based-dispatch
agents-plugin/agents-analyze
blueprint-plugin/adr-relationships
blueprint-plugin/blueprint-migration
blueprint-plugin/document-detection
container-plugin/go-containers
container-plugin/nodejs-containers
container-plugin/python-containers
css-plugin/lightning-css
hooks-plugin/hooks-permission-request-hook
kubernetes-plugin/kubectl-debugging
project-plugin/project-skill-scripts
terraform-plugin/infrastructure-terraform
tools-plugin/binary-analysis
typescript-plugin/bun-lockfile-update
typescript-plugin/nodejs-development
