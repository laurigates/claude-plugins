---
model: haiku
created: 2026-01-15
modified: 2026-01-15
reviewed: 2026-01-15
name: go-containers
description: |
  Go-specific container optimization patterns including static binary compilation,
  scratch/distroless base images, CGO handling, and systematic optimization journey
  from 846MB to 2.5MB (99.7% reduction). Covers ldflags, trimpath, and build flag
  optimizations specific to Go applications.
  Use when working with Go containers, Dockerfiles for Go apps, or optimizing Go image sizes.
allowed-tools: Bash, Read, Grep, Glob, Edit, Write, TodoWrite, WebSearch, WebFetch
---

# Go Container Optimization

Expert knowledge for building minimal, secure Go container images using static compilation, scratch/distroless base images, and Go-specific build optimizations.

## Core Expertise

**Go's Unique Advantages**:
- Compiles to single static binary (no runtime dependencies)
- Can run on `scratch` base (literally empty image)
- No interpreter, VM, or system libraries needed at runtime
- Enables smallest possible container images (2-5MB)

**Key Capabilities**:
- Static binary compilation with CGO_ENABLED=0
- Binary stripping with ldflags (-w, -s)
- Scratch and distroless base images
- CA certificate handling for HTTPS
- CGO considerations when C libraries are required

## The Optimization Journey: 846MB → 2.5MB

This demonstrates systematic optimization achieving 99.7% size reduction:

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

### Step 4: Strip Binary & Optimize Build Flags (8MB)

```dockerfile
# ✅ BETTER: Optimized build flags
# Build stage
FROM golang:1.23-alpine AS builder
WORKDIR /app
COPY go.mod go.sum ./
RUN go mod download
COPY . .

# Optimized build with stripping
RUN CGO_ENABLED=0 GOOS=linux go build \
    -a \
    -installsuffix cgo \
    -ldflags="-w -s" \
    -trimpath \
    -o main .

# Runtime stage with CA certificates
FROM alpine:latest
RUN apk --no-cache add ca-certificates
WORKDIR /app
COPY --from=builder /app/main .
EXPOSE 8080
CMD ["./main"]
```

**Build Flag Explanations**:

| Flag | Purpose | Impact |
|------|---------|--------|
| `CGO_ENABLED=0` | Disable CGO, create static binary | Removes dynamic library dependencies |
| `-a` | Force rebuild of all packages | Ensures clean build |
| `-installsuffix cgo` | Separate output directory | Prevents cache conflicts |
| `-ldflags="-w -s"` | Strip debug info and symbol table | Reduces binary size significantly |
| `-w` | Omit DWARF debug information | ~30% size reduction |
| `-s` | Omit symbol table and debug info | Additional ~10% reduction |
| `-trimpath` | Remove file system paths | Security: no local path leakage |

**Additions**:
- CA certificates for HTTPS requests
- Fully static binary (no dynamic dependencies)

**Image size: 8MB** (47% reduction from 15MB)

### Step 5: Scratch or Distroless (2.5MB)

**Option A: Scratch (Absolute Minimum)**

```dockerfile
# Build stage
FROM golang:1.23-alpine AS builder
WORKDIR /app
COPY go.mod go.sum ./
RUN go mod download
COPY . .

# Optimized static build
RUN CGO_ENABLED=0 GOOS=linux go build \
    -a \
    -installsuffix cgo \
    -ldflags="-w -s" \
    -trimpath \
    -o main .

# Runtime stage - scratch (empty image)
FROM scratch

# Copy CA certificates from builder
COPY --from=builder /etc/ssl/certs/ca-certificates.crt /etc/ssl/certs/

# Copy binary
COPY --from=builder /app/main /main

EXPOSE 8080
CMD ["/main"]
```

**Image size: 2.5MB** (68% reduction from 8MB)

**Option B: Distroless (Slightly Larger, Easier Debugging)**

```dockerfile
# Build stage (same as above)
FROM golang:1.23-alpine AS builder
WORKDIR /app
COPY go.mod go.sum ./
RUN go mod download
COPY . .
RUN CGO_ENABLED=0 GOOS=linux go build \
    -a \
    -ldflags="-w -s" \
    -trimpath \
    -o main .

# Runtime stage - distroless
FROM gcr.io/distroless/static-debian12

COPY --from=builder /app/main /main
EXPOSE 8080
CMD ["/main"]
```

**Distroless advantages**:
- Includes CA certificates automatically
- Minimal OS files (passwd, nsswitch.conf)
- No shell (security benefit)
- Slightly larger (~2-3MB more) but includes useful metadata

**Image size: ~4-5MB**

## Performance Impact

| Metric | Debian (846MB) | Alpine (15MB) | Scratch (2.5MB) | Improvement |
|--------|----------------|---------------|-----------------|-------------|
| **Image Size** | 846MB | 15MB | 2.5MB | 99.7% reduction |
| **Pull Time** | 52s | 4s | 1s | 98% faster |
| **Build Time** | 3m 20s | 2m 15s | 1m 45s | 47% faster |
| **Startup Time** | 2.1s | 1.2s | 0.8s | 62% faster |
| **Memory Usage** | 480MB | 180MB | 128MB | 73% reduction |
| **Storage Cost** | $0.48/mo | $0.01/mo | $0.001/mo | 99.8% reduction |

## Security Impact

| Image Type | Vulnerabilities | Attack Surface |
|------------|-----------------|----------------|
| **Debian-based** | 63 CVEs | Full OS, shell, package manager, utilities |
| **Alpine-based** | 12 CVEs | Minimal OS, shell, package manager |
| **Scratch** | 0 CVEs | Binary only, no OS |
| **Distroless** | 0-2 CVEs | Binary + minimal runtime, no shell |

**Security benefits of scratch/distroless**:
- No shell → no shell injection attacks
- No package manager → no supply chain attacks
- No OS utilities → minimal attack surface
- No unnecessary libraries → fewer vulnerabilities

## When to Use Each Approach

| Use Case | Recommended Base | Reason |
|----------|------------------|--------|
| **Production services** | Scratch or Distroless | Minimal size, maximum security |
| **Services with C dependencies** | Alpine (with CGO) | Requires system libraries |
| **Development/debugging** | Alpine | Need shell access for troubleshooting |
| **Legacy apps** | Debian slim | Compatibility requirements |

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

## Binary Size Analysis

```bash
# Build with different optimization levels
go build -o main-default .
go build -ldflags="-w" -o main-w .
go build -ldflags="-s" -o main-s .
go build -ldflags="-w -s" -o main-ws .

# Compare sizes
ls -lh main-*

# Typical results for a medium Go app:
# main-default: 12.5MB (with debug info + symbols)
# main-w:        8.7MB (no debug info)
# main-s:       10.2MB (no symbol table)
# main-ws:       7.8MB (both stripped)

# Further analyze binary
go tool nm main-default | wc -l  # Count symbols
file main-ws                      # Verify static linking
ldd main-ws                       # Should show "not a dynamic executable"
```

## Advanced: CGO Considerations

When your Go application uses CGO (C libraries, database drivers like SQLite, etc.), you cannot use `scratch` base images.

```dockerfile
# When CGO is required (database drivers, C libraries)
FROM golang:1.23-alpine AS builder

# Install C dependencies
RUN apk add --no-cache gcc musl-dev

WORKDIR /app
COPY go.mod go.sum ./
RUN go mod download
COPY . .

# Build with CGO enabled
RUN CGO_ENABLED=1 GOOS=linux go build \
    -ldflags="-w -s -linkmode external -extldflags '-static'" \
    -o main .

# Runtime needs musl
FROM alpine:latest
RUN apk --no-cache add ca-certificates
COPY --from=builder /app/main .
CMD ["./main"]
```

**Note**: With CGO, Alpine is the minimal option (~7-10MB final image).

## Common Go Database Drivers

| Driver | CGO Required | Minimum Base |
|--------|--------------|--------------|
| `github.com/lib/pq` (PostgreSQL) | No | Scratch |
| `github.com/go-sql-driver/mysql` | No | Scratch |
| `github.com/mattn/go-sqlite3` | Yes | Alpine |
| `modernc.org/sqlite` (pure Go) | No | Scratch |

## Agentic Optimizations

Go-specific container commands for fast development:

| Context | Command | Purpose |
|---------|---------|---------|
| **Quick build** | `go build -ldflags="-w -s" -o app .` | Build stripped binary |
| **Check size** | `ls -lh app` | Verify binary size |
| **Test static** | `ldd app` | Verify no dynamic deps |
| **Container build** | `DOCKER_BUILDKIT=1 docker build -t app .` | Fast build with cache |
| **Size check** | `docker images app --format "{{.Size}}"` | Check final image size |
| **Layer analysis** | `docker history app:latest --human` | See layer sizes |

## Best Practices

**Always**:
- Use `CGO_ENABLED=0` unless you need C libraries
- Strip binaries with `-ldflags="-w -s"`
- Use `-trimpath` to remove filesystem paths
- Prefer `scratch` or `distroless` for production
- Version pin Go and base images (never use `latest`)

**Never**:
- Ship the Go compiler in production images
- Use full Debian/Ubuntu bases for Go apps
- Include debug symbols in production binaries
- Run as root user (even in scratch, use `USER 65534`)

## Related Skills

- `container-development` - General container patterns, multi-stage builds, security
- `nodejs-containers` - Node.js-specific container optimizations
- `python-containers` - Python-specific container optimizations
