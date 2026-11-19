#!/bin/sh
# Merge an upstream umputun/tg-spam release into the current branch: the way this fork takes
# upstream changes. Run it on a fresh branch off master, push, open a pull request into master,
# and merge it once wb-image.yml is green (stack config, upstream files untouched, the tests of
# the patched packages, the image build, the options the stacks set):
#
#   git fetch origin
#   git switch -c upstream-v1.30.0 origin/master
#   sh deploy/wb-compat/merge-upstream.sh v1.30.0     # without a tag: the newest release
#   git push -u origin HEAD
#
# The merge cannot conflict outside .github/workflows: every upstream file is untouched in this
# fork (check-upstream-files.sh), ours live in deploy/wb-compat, docker-compose.portainer.yml
# and .github/workflows/wb-*.yml. Upstream's workflows are not kept here, so whatever upstream
# changed there is dropped. deploy/wb-compat/UPSTREAM_VERSION moves to the new release.
set -eu
cd "$(dirname "$0")/../.."
up=https://github.com/umputun/tg-spam.git

if ! git diff --quiet || ! git diff --cached --quiet; then
  echo "uncommitted changes: commit or stash them first" >&2
  exit 1
fi

tag=${1:-$(git ls-remote --tags --refs "$up" | sed -n 's|.*refs/tags/\(v[0-9]*\.[0-9]*\.[0-9]*\)$|\1|p' |
  sort -V | tail -n 1)}
current=$(tr -d ' \r\n' < deploy/wb-compat/UPSTREAM_VERSION)
if [ "$tag" = "$current" ]; then
  echo "already on upstream $tag"
  exit 0
fi
for t in "$tag" "$current"; do
  git rev-parse -q --verify "refs/tags/$t^{commit}" > /dev/null ||
    git fetch -q --no-tags "$up" "refs/tags/$t:refs/tags/$t"
done
echo "merging upstream $tag, this branch is on $current"

# a squash merge of an earlier update leaves master with the files of the release it is on but
# not its history, and the merge below would replay that release as conflicts. With the files
# checked to be exactly that release, recording it as merged is the truth
sh deploy/wb-compat/check-upstream-files.sh
if ! git merge-base --is-ancestor "$current" HEAD; then
  git merge -q -s ours --no-edit -m "Record upstream $current as merged" "$current"
fi

git merge --no-ff --no-commit "$tag" > /dev/null 2>&1 || true
# .github/workflows keeps only this fork's own workflows
for f in $( { git diff --name-only --diff-filter=U -- .github/workflows
              git diff --cached --name-only HEAD -- .github/workflows; } | sort -u); do
  if git cat-file -e "HEAD:$f" 2>/dev/null; then
    git checkout HEAD -- "$f"
  else
    git rm -q -f --cached --ignore-unmatch -- "$f"
    rm -f -- "$f"
  fi
  echo "kept this fork's .github/workflows: $f"
done

conflicts=$(git diff --name-only --diff-filter=U)
if [ -n "$conflicts" ]; then
  echo "conflicts outside .github/workflows, an upstream file was changed in this fork:" >&2
  printf '%s\n' "$conflicts" >&2
  echo "resolve them in upstream's favour, then: echo $tag > deploy/wb-compat/UPSTREAM_VERSION," \
    "git add -A, git commit" >&2
  exit 1
fi

echo "$tag" > deploy/wb-compat/UPSTREAM_VERSION
git add deploy/wb-compat/UPSTREAM_VERSION
git commit -q -m "Merge upstream $tag"
echo "merged upstream $tag. Push this branch and open a pull request into master of"
echo "wirenboard/tg-spam (GitHub offers umputun/tg-spam as the base by default)."
