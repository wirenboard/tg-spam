#!/bin/sh
# Assert that every variable the two stack compose files pass to the bot is still an option of
# the given image. go-flags ignores an environment variable no option reads, so an upstream
# release that renames or drops an option would otherwise leave the bot running without that
# setting and nothing would say so.
#
# usage: check-image-options.sh <image>
set -eu
cd "$(dirname "$0")/../.."
image=${1:?usage: check-image-options.sh <image>}

help=$(docker run --rm --entrypoint /srv/tg-spam "$image" --help 2>&1 || true)
if ! printf '%s\n' "$help" | grep -q 'Application Options'; then
  echo "FAIL: $image did not print its options:" >&2
  printf '%s\n' "$help" | tail -n 20 >&2
  exit 1
fi
# without a terminal go-flags wraps the help at 80 columns, and a word too long for the
# description column is cut with "-" and continued after a blank line:
# "[$DISABLE_ADMIN_SPAM-", "", "_FORWARD]". One line, cuts joined back
help=$(printf '%s\n' "$help" | tr '\n' ' ' | sed 's/- \{1,\}//g')

fail=0
for f in docker-compose.portainer.yml deploy/wb-compat/docker-compose.update-channel.yml; do
  # keys of the service's environment block: six spaces, then NAME:
  for var in $(sed -n 's/^      \([A-Z][A-Z0-9_]*\):.*/\1/p' "$f" | sort -u); do
    case $var in
      TZ | TGSPAM_IN_DOCKER) continue ;; # read by the OS and the entrypoint, not by tg-spam
    esac
    if ! printf '%s\n' "$help" | grep -qF "[\$$var]"; then
      echo "FAIL: $f sets $var, but $image has no option reading it" >&2
      fail=1
    fi
  done
done

if [ "$fail" -eq 0 ]; then
  echo "every variable the stacks set is an option of $image"
fi
exit "$fail"
