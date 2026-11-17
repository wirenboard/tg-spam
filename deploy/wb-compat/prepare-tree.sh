#!/bin/sh
# Turn a copy of this checkout into the source the WB image is built from: apply every patch in
# deploy/wb-compat/patches and add our stop phrases to the preset dictionary.
#
# Every file outside deploy/wb-compat, the two stack compose files and .github/workflows is
# upstream's, byte for byte. That is what keeps an upstream release merge free of conflicts,
# so nothing of ours goes into those files in git: it is applied here, at build time, to a
# throwaway copy (build-image.sh and test-image-tree.sh make the copy).
#
# A patch that no longer applies fails the build, and that is the signal to refresh it: see
# "Updating from upstream" in README.md.
#
# usage: prepare-tree.sh <dir>   (a copy of the repository tree, never the checkout itself)
set -eu

src=$(cd "$(dirname "$0")" && pwd)
dst=${1:?usage: prepare-tree.sh <copy of the repository tree>}
cd "$dst"

if [ -d .git ]; then
  echo "refusing to patch a git checkout ($dst): pass a copy of the tree" >&2
  exit 1
fi

for p in "$src"/patches/*.patch; do
  [ -e "$p" ] || continue # no patches left: the image is plain upstream
  echo "applying $(basename "$p")"
  if ! git apply --check "$p"; then
    echo "$(basename "$p") does not apply to this upstream version, refresh it" >&2
    exit 1
  fi
  git apply "$p"
done

# the preset dictionary only seeds a fresh volume (entrypoint.sh copies the preset when there is
# no tg-spam.db yet); both live bots keep their dictionary in their own database. upstream's
# phrases stay first, ours follow, blank lines and repeats dropped. the echo keeps upstream's last
# line, which has no trailing newline, from running into our first one
{ cat data/stop-words.txt; echo; cat "$src/data/stop-words.txt"; } | awk 'NF && !seen[$0]++' > data/stop-words.txt.wb
mv data/stop-words.txt.wb data/stop-words.txt
echo "stop-words: $(wc -l < data/stop-words.txt) phrases in the preset"
