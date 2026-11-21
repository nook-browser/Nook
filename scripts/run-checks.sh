#!/bin/bash
# Runs every check in the repo and exits non-zero if any fails: the Swift check programs, the
# NookTabsCore package tests, the Rust crate tests and the node scripts.
#   scripts/run-checks.sh [name ...]   only the checks whose name contains one of the words
#   NOOK_CHECKS_LOCAL=1                also run the checks that cannot run unattended
#   NOOK_CHECKS_JOBS=n                 parallel compiles (default: one per core)
# Each Swift check's command comes from the swiftc line in its header comment; only the output
# path is rewritten, and the compiles run in parallel before the checks run one at a time.
set -u
cd "$(dirname "$0")/.." || exit 2
root=$PWD
export PATH="$HOME/.cargo/bin:$PATH"

# ---- compile one check (called through xargs) ----
if [ "${1:-}" = "--compile" ]; then
  [ -n "${2:-}" ] || exit 0
  u=$WORK/u/$2
  start=$(date +%s)
  OUT=$WORK/bin/$2 eval "$(cat "$u/pre" "$u/compile")" >"$u/compile.log" 2>&1
  echo $? >"$u/compile.rc"
  echo $(($(date +%s) - start)) >"$u/compile.secs"
  exit 0
fi

work=$(mktemp -d "${TMPDIR:-/tmp}/nook-checks.XXXXXX") || exit 2
trap 'rm -rf "$work"' EXIT
mkdir -p "$work/cmd" "$work/u" "$work/bin"
export WORK=$work
njobs=${NOOK_CHECKS_JOBS:-$(sysctl -n hw.ncpu 2>/dev/null || echo 2)}
pass=0 fail=0 skip=0 failed=""
started=$(date +%s)

filters="$*"
want() {
  [ -z "$filters" ] && return 0
  local w
  for w in $filters; do case $1 in *"$w"*) return 0 ;; esac; done
  return 1
}

# Missing tool: a failure in CI, where it means the image changed, a skip on a dev machine.
tool_missing() {
  if [ -n "${CI:-}" ]; then finish FAIL "$1" "$2 not found"; else finish SKIP "$1" "$2 not found"; fi
}

# finish STATUS NAME DETAIL [LOG]: one line per check, and the log of a failure under it.
finish() {
  printf '%-5s %s%s\n' "$1" "$2" "${3:+  ($3)}"
  case $1 in
    PASS) pass=$((pass + 1)) ;;
    SKIP) skip=$((skip + 1)) ;;
    FAIL)
      fail=$((fail + 1)); failed="$failed
  $2"
      if [ -n "${4:-}" ] && [ -s "$4" ]; then
        echo "------ output of $2"
        tail -n 200 "$4"
        echo "------"
      fi ;;
  esac
}

# limited SECS LOG CMD...: run with a time limit; 142 means it timed out.
limited() {
  local secs=$1 log=$2; shift 2
  { perl -e 'alarm shift; exec @ARGV or die "exec: $!\n"' "$secs" "$@" >"$log" 2>&1; } 2>/dev/null
}

rc_detail() {
  if [ "$1" = 142 ]; then echo "timed out after $2 s"
  elif [ "$1" -gt 128 ]; then echo "exit $1, signal $(($1 - 128))"
  else echo "exit $1"; fi
}

# extra NAME LIMIT TOOL CMD...: a check that is not a single Swift program.
extra() {
  local name=$1 limit=$2 tool=$3 log s rc; shift 3
  want "$name" || return 0
  if ! command -v "$tool" >/dev/null 2>&1; then tool_missing "$name" "$tool"; return 0; fi
  log=$work/extra.log
  s=$(date +%s)
  limited "$limit" "$log" "$@"; rc=$?
  if [ $rc -eq 0 ]; then finish PASS "$name" "$(($(date +%s) - s)) s"
  else finish FAIL "$name" "$(rc_detail $rc "$limit")" "$log"; fi
}

# local_only NAME REASON TOOL CMD...: a check that cannot run unattended, skipped unless NOOK_CHECKS_LOCAL=1.
local_only() {
  local name=$1 reason=$2; shift 2
  want "$name" || return 0
  if [ -z "${NOOK_CHECKS_LOCAL:-}" ]; then finish SKIP "$name" "local-only: $reason"; return 0; fi
  extra "$name" 600 "$@"
}

# ---- the Swift checks ----
# Header command -> $work/cmd/<file>: any `X=...` lines above the swiftc line, then the swiftc line.
header_command() {
  awk '
    !/^\/\// { exit }
    {
      s = $0; sub(/^\/\/[ \t]*/, "", s)
      if (join != "") { s = join " " s; join = "" }
      if (s ~ /\\[ \t]*$/) { sub(/[ \t]*\\[ \t]*$/, "", s); join = s; next }
      n++; line[n] = s
    }
    END {
      if (join != "") { n++; line[n] = join }
      for (i = 1; i <= n; i++) if (line[i] ~ /^swiftc /) break
      if (i > n) exit
      j = i - 1
      while (j >= 1 && line[j] ~ /^[A-Za-z_][A-Za-z0-9_]*=/) j--
      for (k = j + 1; k <= i; k++) print line[k]
    }' "$1"
}

# Literal replace of the header's output path with $OUT.
out_path() {
  awk -v t="$1" '{ o = ""; while ((i = index($0, t)) > 0) { o = o substr($0, 1, i - 1) "$OUT"; $0 = substr($0, i + length(t)) } print o $0 }'
}

files=$(ls Packages/*/Checks/*.swift scripts/tests/*.swift 2>/dev/null)
for f in $files; do header_command "$f" >"$work/cmd/$(echo "$f" | tr / _)"; done

units=""
n=0
for f in $files; do
  want "$f" || continue
  cmd=$work/cmd/$(echo "$f" | tr / _)
  base=${f##*/}
  # A helper another check compiles, or a program a driver script runs, is not a check itself.
  if [ ! -s "$cmd" ] && grep -q -F "$base" "$work"/cmd/* scripts/tests/*.sh scripts/tests/*.py 2>/dev/null; then continue; fi
  n=$((n + 1)); id=$(printf %03d $n); u=$work/u/$id; mkdir "$u"
  echo "$f" >"$u/name"
  units="$units $id"
  last=$(tail -n 1 "$cmd")
  compile=${last% && *}
  run=${last##* && }
  tok=$(echo "$compile" | sed -n 's/.* -o \([^ ][^ ]*\).*/\1/p')
  if [ ! -s "$cmd" ]; then echo "no swiftc command in the header comment" >"$u/bad"; continue; fi
  if [ "$compile" = "$last" ] || [ -z "$tok" ]; then echo "header command needs '-o <path> && <path>'" >"$u/bad"; continue; fi
  run=$(echo "$run" | sed 's/ \[[^]]*\]$//')   # a doc placeholder like [list-directory]
  sed '$d' "$cmd" | out_path "$tok" >"$u/pre"
  echo "$compile" | out_path "$tok" >"$u/compile"
  echo "$run" | out_path "$tok" >"$u/run"
done

if [ -n "$units" ]; then
  echo "compiling $(echo $units | wc -w | tr -d ' ') Swift checks, $njobs at a time"
  for id in $units; do [ -f "$work/u/$id/compile" ] && echo "$id"; done |
    xargs -n 1 -P "$njobs" "$root/scripts/run-checks.sh" --compile
fi

for id in $units; do
  u=$work/u/$id
  name=$(cat "$u/name")
  if [ -f "$u/bad" ]; then finish FAIL "$name" "$(cat "$u/bad")"; continue; fi
  c=$(cat "$u/compile.rc" 2>/dev/null || echo 1); cs=$(cat "$u/compile.secs" 2>/dev/null || echo 0)
  if [ "$c" != 0 ]; then finish FAIL "$name" "compile failed, $cs s" "$u/compile.log"; continue; fi
  s=$(date +%s)
  OUT=$work/bin/$id eval "limited 120 \"\$u/run.log\" $(cat "$u/run")"; rc=$?
  r=$(($(date +%s) - s))
  if [ $rc -eq 0 ]; then finish PASS "$name" "compile $cs s, run $r s"
  else finish FAIL "$name" "$(rc_detail $rc 120), compile $cs s" "$u/run.log"; fi
done

# ---- everything else ----
extra "Packages/NookTabsCore swift test" 600 swift \
  swift test --package-path Packages/NookTabsCore --scratch-path "$root/build/NookTabsCore-spm"
# Same target dir as AdblockRustFFI/build.sh: a target/ under Nook/ breaks the Xcode build.
extra "Nook/ThirdParty/AdblockRustFFI cargo test" 900 cargo \
  env CARGO_TARGET_DIR="${CARGO_TARGET_DIR:-$root/build/AdblockRustFFI-target}" \
  cargo test --release --locked --manifest-path Nook/ThirdParty/AdblockRustFFI/Cargo.toml
for s in check-redirects check-scriptlet-globals check-extension-compat; do
  extra "scripts/$s.mjs" 120 node node "scripts/$s.mjs"
done
extra "scripts/tests/history-regression.sh" 300 xcrun /bin/bash scripts/tests/history-regression.sh
local_only "scripts/tests/check-browser-windows.py" \
  "needs a Debug build in build-prototype and launches app copies through LaunchServices" \
  python3 python3 scripts/tests/check-browser-windows.py build-prototype

echo
echo "$pass passed, $fail failed, $skip skipped in $(($(date +%s) - started)) s"
[ -n "$failed" ] && echo "Failed:$failed"
[ "$fail" -eq 0 ]
