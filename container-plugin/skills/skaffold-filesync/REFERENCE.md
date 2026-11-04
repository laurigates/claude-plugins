# Skaffold File Sync - Reference

Examples and debugging steps for the `skaffold-filesync` skill.

## Manual Sync Examples

### Static Assets Example

```yaml
sync:
  manual:
    # HTML files to nginx root
    - src: "static/*.html"
      dest: /usr/share/nginx/html

    # CSS with directory structure preserved
    - src: "static/css/**/*.css"
      dest: /usr/share/nginx/html/css
      strip: "static/css/"

    # Images
    - src: "static/images/**/*"
      dest: /usr/share/nginx/html/images
      strip: "static/images/"
```

### Node.js Hot Reload Example

```yaml
build:
  artifacts:
    - image: node-app
      sync:
        manual:
          - src: "src/**/*.ts"
            dest: /app/src
          - src: "src/**/*.tsx"
            dest: /app/src
          - src: "*.json"
            dest: /app
```

Pair with nodemon or ts-node-dev in container:

```dockerfile
CMD ["npx", "nodemon", "--watch", "/app/src", "src/index.ts"]
```

### Python Hot Reload Example

```yaml
build:
  artifacts:
    - image: python-app
      sync:
        manual:
          - src: "app/**/*.py"
            dest: /app
          - src: "templates/**/*.html"
            dest: /app/templates
            strip: "templates/"
```

Pair with Flask debug mode or uvicorn reload:

```dockerfile
CMD ["uvicorn", "main:app", "--reload", "--host", "0.0.0.0"]
```

## Full Configuration Examples

### Node.js Development Stack

```yaml
apiVersion: skaffold/v4beta13
kind: Config
metadata:
  name: node-app

build:
  local:
    push: false
    useBuildkit: true
  artifacts:
    - image: node-app
      context: .
      docker:
        dockerfile: Dockerfile
      sync:
        manual:
          - src: "src/**/*.ts"
            dest: /app/src
          - src: "src/**/*.tsx"
            dest: /app/src
          - src: "public/**/*"
            dest: /app/public

deploy:
  kubeContext: orbstack
  kubectl:
    manifests:
      - k8s/*.yaml
```

### Python FastAPI Stack

```yaml
apiVersion: skaffold/v4beta13
kind: Config
metadata:
  name: fastapi-app

build:
  local:
    push: false
  artifacts:
    - image: fastapi-app
      sync:
        manual:
          - src: "app/**/*.py"
            dest: /code/app
          - src: "templates/**/*.html"
            dest: /code/templates
            strip: "templates/"
          - src: "static/**/*"
            dest: /code/static
            strip: "static/"

deploy:
  kubeContext: orbstack
  kubectl:
    manifests:
      - k8s/*.yaml
```

### Go with Air (Hot Reload)

```yaml
apiVersion: skaffold/v4beta13
kind: Config
metadata:
  name: go-app

build:
  artifacts:
    - image: go-app
      sync:
        manual:
          - src: "**/*.go"
            dest: /app
          - src: "go.mod"
            dest: /app
          - src: "go.sum"
            dest: /app

deploy:
  kubeContext: orbstack
  kubectl:
    manifests:
      - k8s/*.yaml
```

With Air in Dockerfile:

```dockerfile
FROM golang:1.22-alpine
RUN go install github.com/cosmtrek/air@latest
WORKDIR /app
COPY . .
CMD ["air", "-c", ".air.toml"]
```

### Static Site with Nginx

```yaml
apiVersion: skaffold/v4beta13
kind: Config
metadata:
  name: static-site

build:
  artifacts:
    - image: static-site
      sync:
        manual:
          - src: "dist/**/*"
            dest: /usr/share/nginx/html
            strip: "dist/"

deploy:
  kubeContext: orbstack
  kubectl:
    manifests:
      - k8s/*.yaml
```

## Debugging Sync Issues

### Verify Sync Is Working

```bash
# Watch Skaffold output for sync messages
skaffold dev -v info

# Look for:
# Syncing 1 files for my-app:latest
# Watching for changes...
```

### Check Container Has tar

```bash
kubectl exec -it <pod> -- which tar
# Should output: /bin/tar or /usr/bin/tar
```

### Verify File Permissions

```bash
kubectl exec -it <pod> -- ls -la /app/src/
# Check files are writable by container user
```

### Test Manual Sync Path

```bash
# Verify destination exists in container
kubectl exec -it <pod> -- ls -la /app/

# Check container user
kubectl exec -it <pod> -- whoami
```

## Profiles for Sync vs Rebuild

```yaml
profiles:
  # Fast iteration - sync enabled
  - name: dev
    build:
      artifacts:
        - image: my-app
          sync:
            manual:
              - src: "src/**/*"
                dest: /app/src

  # CI/Production - no sync, full rebuilds
  - name: ci
    build:
      artifacts:
        - image: my-app
          # No sync configuration
```
