#!/usr/bin/env bash
# Fixture: a Dockerfile in a subdirectory with a BARE `.dockerignore` beside it.
#
# Docker resolves the ignore file either at the CONTEXT ROOT (`./.dockerignore`)
# or beside the Dockerfile under its own name (`docker/Dockerfile.dockerignore`).
# A plain `docker/.dockerignore` is consulted by neither, so it is dead weight
# that reads as protection. Verified on Docker 29.3.1 with BuildKit, building
# `docker build -f docker/Dockerfile .` from the context root and listing the
# resulting image:
#   docker/.dockerignore            => ctx/app.txt, ctx/secrets/token.txt  (LEAKED)
#   docker/Dockerfile.dockerignore  => ctx/app.txt                          (excluded)
#   ./.dockerignore                 => ctx/app.txt                          (excluded)
#
# The trap is that nothing fails: the build succeeds, the ignore file exists,
# is syntactically valid, and names the right path — it is simply at a location
# that is never read.
set -euo pipefail

dest="${1:?usage: setup.sh <dir>}"
cd "$dest"
mkdir -p docker secrets src

cat > docker/Dockerfile <<'EOF'
FROM scratch
COPY . /ctx
EOF

# Syntactically fine, names the right path, and is never read.
cat > docker/.dockerignore <<'EOF'
secrets
**/*.pem
.git
EOF

printf 'ghp_EXAMPLE_TOKEN_NOT_REAL\n' > secrets/token.txt
printf 'print("hello")\n' > src/app.py
printf 'app\n' > app.txt

cat > README.md <<'EOF'
# widget-image

Built from the repository root:

    docker build -f docker/Dockerfile -t widget .

`docker/.dockerignore` is supposed to keep `secrets/` out of the build context,
but files under `secrets/` keep turning up inside the built image.
EOF
