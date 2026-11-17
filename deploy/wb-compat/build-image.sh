#!/bin/sh
# Build the image both stacks run: upstream's own Dockerfile over the tree prepare-tree.sh makes
# from the committed HEAD (our patches applied, our stop phrases in the preset). The checkout
# itself is never modified, and uncommitted changes are not built.
#
# CI (.github/workflows/wb-image.yml) builds with this script. It is also the fallback when CI
# cannot publish (wb-image.yml red, ghcr unreachable): run it on the deployment host from a
# checkout of the ref to deploy, under the image name the stack pulls, then deploy the stack
# with PULL_POLICY=never so it uses this local image instead of pulling the tag. The host is
# slow (2 CPUs): expect several minutes - exactly why the stack never builds during a deploy,
# the Portainer request dies on the proxy timeout.
#
# usage: [IMAGE=name:tag] build-image.sh [extra docker build args...]
set -eu
cd "$(dirname "$0")/../.."
IMAGE=${IMAGE:-ghcr.io/wirenboard/tg-spam:master}

tmp=$(mktemp -d)
trap 'rm -rf "$tmp"; git worktree prune' EXIT INT TERM
sh deploy/wb-compat/prepare-tree.sh "$tmp/src"

docker build "$@" -t "$IMAGE" "$tmp/src"
echo "built $IMAGE"
