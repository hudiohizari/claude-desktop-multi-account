#!/bin/bash
# Cut a release: ./scripts/release.sh 0.2.0
#
# VERSION is the single source of truth. This bumps it, commits, tags and pushes;
# the tag then triggers .github/workflows/release.yml, which builds and publishes.
set -euo pipefail
cd "$(dirname "$0")/.."

new="${1:?usage: scripts/release.sh <version>, for example 0.2.0}"
if ! printf '%s' "$new" | grep -Eq '^[0-9]+\.[0-9]+\.[0-9]+$'; then
  echo "version must look like 1.2.3" >&2
  exit 1
fi

if [ -n "$(git status --porcelain)" ]; then
  echo "working tree is dirty, commit first" >&2
  exit 1
fi

current=$(tr -d '[:space:]' < VERSION)
if [ "$new" = "$current" ]; then
  echo "VERSION is already $new" >&2
  exit 1
fi

swift test
printf '%s\n' "$new" > VERSION
./build.sh >/dev/null

git add VERSION
git commit -q -m "chore: release v$new"
git tag -a "v$new" -m "v$new"
git push origin HEAD "v$new"

echo "pushed v$new, release workflow will build and publish it"
