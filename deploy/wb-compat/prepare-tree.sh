#!/bin/sh
# Create the source tree the WB image is built from: an upstream umputun/tg-spam release as it
# is, with every patch in deploy/wb-compat/patches applied and our stop phrases added to the
# preset dictionary. This repository carries no upstream code, so a new upstream release needs
# nothing done here.
#
# Patches go in with git apply --3way. A patch records the blobs it was made against, so when
# upstream edits lines next to ours, git merges the change instead of failing on a context
# mismatch; those blobs come with upstream's history, fetched along with the tag. A patch that
# still does not apply fails here, and that is the signal to refresh it (README.md, "When a
# build fails").
#
# usage: prepare-tree.sh <upstream tag> <dir>
#   <dir> must not exist yet. The caller removes it and runs git worktree prune afterwards.
set -eu

src=$(cd "$(dirname "$0")" && pwd)
tag=${1:?usage: prepare-tree.sh <upstream tag> <new directory>}
dst=${2:?usage: prepare-tree.sh <upstream tag> <new directory>}
cd "$src/../.."

if ! git rev-parse -q --verify "refs/tags/$tag^{commit}" > /dev/null; then
  git fetch -q --no-tags https://github.com/umputun/tg-spam.git "refs/tags/$tag:refs/tags/$tag"
fi
git worktree add --quiet --detach "$dst" "refs/tags/$tag"

for p in "$src"/patches/*.patch; do
  [ -e "$p" ] || continue # no patches left: the image is plain upstream
  echo "applying $(basename "$p") to upstream $tag"
  if ! git -C "$dst" apply --3way "$p"; then
    echo "$(basename "$p") does not apply to upstream $tag, refresh it" >&2
    exit 1
  fi
done

# the preset dictionary only seeds a fresh volume (entrypoint.sh copies the preset when there is
# no tg-spam.db yet); both live bots keep their dictionary in their own database. upstream's
# phrases stay first, ours follow, blank lines and repeats dropped. the echo keeps upstream's last
# line, which has no trailing newline, from running into our first one
words="$dst/data/stop-words.txt"
{ cat "$words"; echo; cat "$src/data/stop-words.txt"; } | awk 'NF && !seen[$0]++' > "$words.wb"
mv "$words.wb" "$words"
echo "stop-words: $(wc -l < "$words") phrases in the preset"

# a plain source tree from here on: the build context and the test container must not see a
# .git pointing at a path that exists only on this machine
rm -f "$dst/.git"
