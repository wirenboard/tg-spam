#!/bin/sh
# Build the image both stacks run: upstream's own Dockerfile over a copy of this checkout,
# prepared by prepare-tree.sh (our patches applied, our stop phrases added to the preset).
# The checkout itself is never modified.
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
trap 'rm -rf "$tmp"' EXIT INT TERM

# tracked and new files as they are in the working tree, without .git and ignored files
git ls-files -z --cached --others --exclude-standard |
  tar --null --ignore-failed-read -T - -cf - | tar -xf - -C "$tmp"
sh deploy/wb-compat/prepare-tree.sh "$tmp"

docker build "$@" -t "$IMAGE" "$tmp"
echo "built $IMAGE"
