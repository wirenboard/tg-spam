#!/bin/sh
# Run the Go tests of the code the image is built from: a copy of this checkout prepared by
# prepare-tree.sh, inside the same build image upstream's Dockerfile compiles with, so the
# toolchain follows upstream's choice without any change here.
#
# Only the packages our patches touch are tested. Upstream tests its own releases; the full
# suite here would mostly re-run that, and one flaky upstream test would block the sync.
# Set TEST_PKGS to override, e.g. TEST_PKGS=./... to run everything.
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
trap 'rm -rf "$tmp"' EXIT INT TERM
git ls-files -z --cached --others --exclude-standard |
  tar --null --ignore-failed-read -T - -cf - | tar -xf - -C "$tmp"
sh deploy/wb-compat/prepare-tree.sh "$tmp"

builder=$(sed -n 's/^FROM \([^ ]*\).*/\1/p' Dockerfile | head -n 1)
echo "testing $pkgs with $builder"
# the go build cache lives in a named volume, so a rerun recompiles only what changed
docker run --rm -v "$tmp":/build -v tg-spam-wb-gocache:/root/.cache/go-build -w /build \
  -e PKGS="$pkgs" "$builder" sh -ec '
    unformatted=$(for p in $PKGS; do gofmt -l "${p%/}"/*.go; done)
    if [ -n "$unformatted" ]; then echo "not gofmt-formatted: $unformatted" >&2; exit 1; fi
    go vet $PKGS
    go test -count=1 $PKGS
  '
