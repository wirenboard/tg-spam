#!/bin/sh
# Run the Go tests of the code the image is built from - the tree prepare-tree.sh makes from the
# committed HEAD - inside the same build image upstream's Dockerfile compiles with, so the
# toolchain follows upstream's choice with no change here.
#
# Only the packages our patches touch are tested, in -short mode: upstream tests its own
# releases, the full suite would mostly re-run that, and its container-based tests need a
# docker socket the test container does not have. Set TEST_PKGS to override, e.g. ./...
set -eu
cd "$(dirname "$0")/../.."

pkgs=${TEST_PKGS:-}
if [ -z "$pkgs" ]; then
  # packages of the Go files the patches change, e.g. app/events/admin.go -> ./app/events/
  pkgs=$(cat deploy/wb-compat/patches/*.patch 2>/dev/null |
    sed -n 's|^+++ b/\(.*\)/[^/]*\.go$|./\1/|p' | sort -u | tr '\n' ' ')
fi
if [ -z "$pkgs" ]; then
  echo "no patches, nothing of ours to test"
  exit 0
fi

tmp=$(mktemp -d)
trap 'rm -rf "$tmp"; git worktree prune' EXIT INT TERM
sh deploy/wb-compat/prepare-tree.sh "$tmp/src"

builder=$(sed -n 's/^FROM \([^ ]*\).*/\1/p' Dockerfile | head -n 1)
echo "testing $pkgs with $builder"
# the go build cache lives in a named volume, so a rerun recompiles only what changed
docker run --rm -v "$tmp/src":/build -v tg-spam-wb-gocache:/root/.cache/go-build -w /build \
  -e PKGS="$pkgs" "$builder" sh -ec '
    unformatted=$(for p in $PKGS; do gofmt -l "${p%/}"/*.go; done)
    if [ -n "$unformatted" ]; then echo "not gofmt-formatted: $unformatted" >&2; exit 1; fi
    go vet $PKGS
    go test -short -count=1 $PKGS
  '
