#!/usr/bin/env bash
# Builds a throwaway demo for the README GIF: a fake "acme/webapp" repo with one worktree per
# coding agent, a local bare "origin" that git sees as GitHub, and a fake `gh` that serves
# canned pull requests. Nothing touches the network or your real config.
#
#   demo/setup.sh /tmp/tuitree-demo   # then: vhs demo/demo.tape
set -euo pipefail

root=${1:?usage: demo/setup.sh <empty dir>}
rm -rf "$root"
mkdir -p "$root"
root=$(cd "$root" && pwd)
cd "$root"

export GIT_AUTHOR_NAME=demo GIT_AUTHOR_EMAIL=demo@example.com
export GIT_COMMITTER_NAME=demo GIT_COMMITTER_EMAIL=demo@example.com
export GIT_CONFIG_GLOBAL=/dev/null

g() { git -C "$1" "${@:2}"; }
commit() { g "$1" add -A && g "$1" commit -qm "$2"; }
subst() { sed "$1" "$2" > "$2.tmp" && mv "$2.tmp" "$2"; }
lines() { for i in $(seq 1 "$2"); do echo "$1 $i"; done; }

git init -q --bare -b main origin.git
git clone -q origin.git upstream 2>/dev/null
mkdir -p upstream/src
lines "// auth" 30 > upstream/src/auth.ts
lines "// search" 20 > upstream/src/search.ts
lines "// db" 40 > upstream/src/db.ts
lines "docs" 10 > upstream/README.md
commit upstream "initial"
g upstream push -q origin main

git clone -q origin.git webapp 2>/dev/null
url=https://github.com/acme/webapp.git
g webapp remote set-url origin "$url"
g webapp config "url.$root/origin.git.insteadOf" "$url"
g webapp config user.name demo
g webapp config user.email demo@example.com

add() { g webapp worktree add -q -b "$1" "../$2"; }
add agent/fix-auth-redirect claude-1
add agent/search-filters codex-2
add agent/db-pool-refactor claude-3
add agent/readme-install opencode-4

# claude-1: three commits, merges cleanly.
lines "// auth v2" 34 > claude-1/src/auth.ts; commit claude-1 "fix redirect loop"
lines "// auth test" 25 > claude-1/src/auth.test.ts; commit claude-1 "add redirect tests"
echo "// guard" >> claude-1/src/auth.ts; commit claude-1 "guard empty return_to"

# codex-2: touches search.ts, which upstream also edits below, so it conflicts.
subst 's/search 3/filters 3/' codex-2/src/search.ts; commit codex-2 "add filter params"
lines "// facet" 12 > codex-2/src/facets.ts; commit codex-2 "facet counts"

# claude-3: one commit plus uncommitted work in progress.
lines "// pool" 18 > claude-3/src/pool.ts; commit claude-3 "connection pool"
echo "// wip" >> claude-3/src/db.ts

# opencode-4: same change as upstream, so tuitree sees it as already merged.
echo "install: npm i" >> opencode-4/README.md; commit opencode-4 "install docs"

# upstream moves on: the opencode-4 change lands (squash merged), search.ts conflicts.
echo "install: npm i" >> upstream/README.md; commit upstream "install docs (#14)"
subst 's/search 3/upstream 3/' upstream/src/search.ts; commit upstream "rename search param"
g upstream push -q origin main

# Fake gh: open PR list, per-PR detail, and the per-branch GraphQL lookup.
mkdir -p gh-data bin
cat > gh-data/pr-list.json <<'JSON'
[
 {"number":17,"title":"Fix login redirect loop","headRefName":"agent/fix-auth-redirect","author":{"login":"claude-bot"},"isDraft":false,"changedFiles":2,"additions":60,"deletions":30},
 {"number":18,"title":"Search filters and facet counts","headRefName":"agent/search-filters","author":{"login":"codex-bot"},"isDraft":false,"changedFiles":2,"additions":13,"deletions":1},
 {"number":19,"title":"Pool database connections","headRefName":"agent/db-pool-refactor","author":{"login":"claude-bot"},"isDraft":true,"changedFiles":1,"additions":18,"deletions":0}
]
JSON
cat > gh-data/pr-17.json <<'JSON'
{"files":[
 {"path":"src/auth.ts","additions":35,"deletions":30,"changeType":"MODIFIED"},
 {"path":"src/auth.test.ts","additions":25,"deletions":0,"changeType":"ADDED"}
],
"comments":[
 {"author":{"login":"claude-bot"},"body":"Fixes the redirect loop when return_to is empty.\nAdded tests for the three redirect cases.","createdAt":"2026-11-07T14:00:00Z","isMinimized":false},
 {"author":{"login":"ci-bot"},"body":"All checks passed (42 tests).","createdAt":"2026-11-07T14:06:00Z","isMinimized":false}
],
"reviews":[
 {"author":{"login":"maintainer"},"body":"Rename return_to to next before merge.","state":"CHANGES_REQUESTED","submittedAt":"2026-11-07T15:00:00Z"},
 {"author":{"login":"maintainer"},"body":"","state":"APPROVED","submittedAt":"2026-11-07T16:30:00Z"}
]}
JSON
for n in 18 19; do echo '{"files":[],"comments":[],"reviews":[]}' > "gh-data/pr-$n.json"; done
pr() { # number branch state draft
  local head; head=$(g webapp rev-parse "$2" 2>/dev/null || echo 0000000)
  printf '[{"number":%s,"headRefName":"%s","headRefOid":"%s","state":"%s","isDraft":%s,"isCrossRepository":false,"createdAt":"2026-11-07T12:00:00Z"}]' \
    "$1" "$2" "$head" "$3" "$4" > "gh-data/head-${2//\//_}.json"
}
pr 17 agent/fix-auth-redirect OPEN false
pr 18 agent/search-filters OPEN false
pr 19 agent/db-pool-refactor OPEN true
pr 14 agent/readme-install MERGED false

cat > bin/gh <<SH
#!/bin/sh
data='$root/gh-data'
case "\$1 \$2" in
  "api graphql")
    printf '{"data":{"repository":{'
    printf '%s\n' "\$@" | grep -o 'b[0-9]*: pullRequests(headRefName: "[^"]*"' | {
      sep=''
      while IFS= read -r lookup; do
        alias=\${lookup%%:*}
        branch=\$(printf '%s' "\$lookup" | sed 's/.*headRefName: "\(.*\)"\$/\1/' | tr '/' '_')
        nodes=\$(cat "\$data/head-\$branch.json" 2>/dev/null || echo '[]')
        printf '%s"%s":{"nodes":%s}' "\$sep" "\$alias" "\$nodes"
        sep=','
      done
    }
    printf '}}}\n'
    exit 0 ;;
  "pr list") exec cat "\$data/pr-list.json" ;;
  "pr view") exec cat "\$data/pr-\$3.json" ;;
esac
echo "fake gh: unsupported: \$*" >&2
exit 1
SH
chmod +x bin/gh

mkdir -p config/tuitree
printf '[[projects]]\npath = "%s/webapp"\n' "$root" > config/tuitree/config.toml
echo "demo ready in $root"
