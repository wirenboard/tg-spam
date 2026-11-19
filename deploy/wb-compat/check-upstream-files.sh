#!/bin/sh
# Assert that every upstream file in HEAD is byte for byte the upstream release named in
# deploy/wb-compat/UPSTREAM_VERSION. Ours lives only in deploy/wb-compat,
# docker-compose.portainer.yml and .github/workflows; a change anywhere else is what would
# make the next upstream merge conflict, so it fails here instead. Code changes to the bot go
# to deploy/wb-compat/patches.
#
# wb-upstream-sync.yml also relies on it: after a squash merge master has a release's files
# but not its history, and only this check makes it safe to record the release as merged.
set -eu
cd "$(dirname "$0")/../.."

tag=$(tr -d ' \r\n' < deploy/wb-compat/UPSTREAM_VERSION)
if ! git rev-parse -q --verify "refs/tags/$tag^{commit}" > /dev/null; then
  git fetch -q --no-tags https://github.com/umputun/tg-spam.git "refs/tags/$tag:refs/tags/$tag"
fi

changed=$(git diff --name-only "$tag" HEAD -- . ':(exclude)deploy/wb-compat' \
  ':(exclude)docker-compose.portainer.yml' ':(exclude).github/workflows')
if [ -n "$changed" ]; then
  echo "FAIL: these files differ from upstream $tag (ours belong in deploy/wb-compat, code changes in its patches/):" >&2
  printf '%s\n' "$changed" >&2
  exit 1
fi
echo "upstream files are exactly $tag"
