#!/bin/sh
# Build the image both stacks run: upstream's own Dockerfile over the tree prepare-tree.sh makes
# from an upstream release (our patches applied, our stop phrases in the preset).
#
# CI (.github/workflows/wb-image.yml) builds with this script. It is also the fallback when CI
# cannot publish (ghcr unreachable): run it on the deployment host from a checkout of this
# repository, under the image name the stack pulls, then deploy the stack with
# PULL_POLICY=never so it uses this local image instead of pulling the tag. The host is slow
# (2 CPUs): expect several minutes - exactly why the stack never builds during a deploy, the
# Portainer request dies on the proxy timeout.
#
# usage: [UPSTREAM=v1.29.1] [IMAGE=name:tag] build-image.sh [extra docker build args...]
#   UPSTREAM defaults to the newest upstream release.
set -eu
cd "$(dirname "$0")/../.."
UPSTREAM=${UPSTREAM:-$(sh deploy/wb-compat/upstream-release.sh)}
IMAGE=${IMAGE:-ghcr.io/wirenboard/tg-spam:$UPSTREAM}

tmp=$(mktemp -d)
trap 'rm -rf "$tmp"; git worktree prune' EXIT INT TERM
sh deploy/wb-compat/prepare-tree.sh "$UPSTREAM" "$tmp/src"

docker build "$@" -t "$IMAGE" "$tmp/src"
echo "built $IMAGE from upstream $UPSTREAM"
