#!/bin/sh
# Print the newest umputun/tg-spam release tag, e.g. v1.29.1. Only plain vX.Y.Z tags count,
# so a pre-release tag is never picked.
set -eu
git ls-remote --tags --refs https://github.com/umputun/tg-spam.git |
  sed -n 's|.*refs/tags/\(v[0-9]*\.[0-9]*\.[0-9]*\)$|\1|p' | sort -V | tail -n 1
