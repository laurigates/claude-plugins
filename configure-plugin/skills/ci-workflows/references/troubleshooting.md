# CI Workflow Troubleshooting

Used when a workflow checked against **Compliance Requirements** fails at runtime: build, multi-platform, and cache diagnostics.

## Build Failing

- Check Dockerfile syntax
- Verify build args are passed correctly
- Check cache invalidation issues

## Multi-Platform Issues

- Ensure Dockerfile is platform-agnostic
- Use official multi-arch base images
- Avoid architecture-specific binaries

## Cache Not Working

- Verify `cache-from` and `cache-to` are set
- Check GitHub Actions cache limits (10GB)
- Consider registry-based caching for large images
