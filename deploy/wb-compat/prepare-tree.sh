#!/bin/sh
# Create the source tree the WB image is built from: the committed HEAD of this repository with
# every patch in deploy/wb-compat/patches applied and our stop phrases added to the preset
# dictionary. The checkout itself is never touched.
#
# Every file outside deploy/wb-compat, docker-compose.portainer.yml and .github/workflows is
# upstream's, byte for byte. That is what keeps an upstream release merge free of conflicts, so
# nothing of ours goes into those files in git: it is applied here, to a throwaway tree.
#
# Patches go in with git apply --3way. A patch records the blobs it was made against, so when
# upstream edits lines next to ours, git merges the change instead of failing on a context
# mismatch. That needs those blobs in the repository: CI checks out the full history. A patch
# that still does not apply fails here, and that is the signal to refresh it (README.md,
# "Updating from upstream").
#
# usage: prepare-tree.sh <dir>
#   <dir> must not exist yet. Only committed files are used. The caller removes <dir> and runs
#   git worktree prune afterwards.
set -eu

src=$(cd "$(dirname "$0")" && pwd)
dst=${1:?usage: prepare-tree.sh <new directory>}
cd "$src/../.."

git worktree add --quiet --detach "$dst" HEAD

for p in "$dst"/deploy/wb-compat/patches/*.patch; do
  [ -e "$p" ] || continue # no patches left: the image is plain upstream
  echo "applying $(basename "$p")"
  if ! git -C "$dst" apply --3way "$p"; then
    echo "$(basename "$p") does not apply to this upstream version, refresh it" >&2
    exit 1
  fi
done

# the preset dictionary only seeds a fresh volume (entrypoint.sh copies the preset when there is
# no tg-spam.db yet); both live bots keep their dictionary in their own database. upstream's
# phrases stay first, ours follow, blank lines and repeats dropped. the echo keeps upstream's last
# line, which has no trailing newline, from running into our first one
words="$dst/data/stop-words.txt"
{ cat "$words"; echo; cat "$dst/deploy/wb-compat/data/stop-words.txt"; } | awk 'NF && !seen[$0]++' > "$words.wb"
mv "$words.wb" "$words"
echo "stop-words: $(wc -l < "$words") phrases in the preset"

# a plain source tree from here on: the build context and the test container must not see a
# .git pointing at a path that exists only on this machine
rm -f "$dst/.git"
