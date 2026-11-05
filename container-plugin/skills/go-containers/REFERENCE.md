# Go Container Optimization - Reference

Background, measurements and supporting files for the `go-containers` skill.

## The Optimization Journey: Early Steps

### Step 1: The Problem - Full Debian Base (846MB)

```dockerfile
# ❌ BAD: Includes full Go toolchain, Debian system, unnecessary tools
FROM golang:1.23
WORKDIR /app
COPY . .
RUN go build -o main .
EXPOSE 8080
CMD ["./main"]
```

**Issues**:
- Full Debian base (~116MB)
- Complete Go compiler and toolchain (~730MB)
- System libraries, package managers, shells
- None of this is needed at runtime

**Image size: 846MB**

### Step 2: Switch to Alpine (312MB)

```dockerfile
# ✅ BETTER: Alpine reduces OS overhead
FROM golang:1.23-alpine
WORKDIR /app
COPY . .
RUN go build -o main .
EXPOSE 8080
CMD ["./main"]
```

**Improvements**:
- Alpine Linux (~5MB base vs ~116MB Debian)
- Still includes full Go toolchain (unnecessary at runtime)

**Image size: 312MB** (63% reduction)

### Step 3: Multi-Stage Build (15MB)

```dockerfile
# ✅ GOOD: Separate build from runtime
# Build stage
FROM golang:1.23-alpine AS builder
WORKDIR /app
COPY go.mod go.sum ./
RUN go mod download
COPY . .
RUN go build -o main .

# Runtime stage
FROM alpine:latest
WORKDIR /app
COPY --from=builder /app/main .
EXPOSE 8080
CMD ["./main"]
```

**Improvements**:
- Build artifacts excluded from final image
- Only Alpine + binary in final image
- Faster deployments and pulls

**Image size: 15MB** (95% reduction from 312MB)

## Performance Impact

| Metric | Debian (846MB) | Alpine (15MB) | Scratch (2.5MB) | Improvement |
|--------|----------------|---------------|-----------------|-------------|
| **Image Size** | 846MB | 15MB | 2.5MB | 99.7% reduction |
| **Pull Time** | 52s | 4s | 1s | 98% faster |
| **Build Time** | 3m 20s | 2m 15s | 1m 45s | 47% faster |
| **Startup Time** | 2.1s | 1.2s | 0.8s | 62% faster |
| **Memory Usage** | 480MB | 180MB | 128MB | 73% reduction |
| **Storage Cost** | $0.48/mo | $0.01/mo | $0.001/mo | 99.8% reduction |

## Go-Specific .dockerignore

```
# Version control
.git
.gitignore
.gitattributes

# Go artifacts
vendor/
*.exe
*.exe~
*.dll
*.so
*.dylib
*.test
*.out
go.work
go.work.sum

# Development files
.vscode/
.idea/
*.swp
*.swo
*~
.DS_Store

# Documentation
README.md
*.md
docs/
LICENSE

# CI/CD
.github/
.gitlab-ci.yml
.travis.yml
Jenkinsfile

# Environment files
.env
.env.*
*.env

# Build artifacts
dist/
build/
bin/
tmp/
temp/

# Logs
*.log
logs/

# Test files (if not needed in image)
*_test.go
testdata/

# Docker files
Dockerfile*
docker-compose*.yml
.dockerignore
```
