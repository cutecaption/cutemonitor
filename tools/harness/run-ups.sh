#!/usr/bin/env bash
# Runs the UPS plugin's entry scripts offline against the fake Noctalia runtime:
# the service first (its recorded states feed the others), then the desktop
# widget, bar item and panel. Prints each run's summary; exits non-zero if any
# run fails or reports issues. Output goes to tools/harness/out/ (disposable).
set -euo pipefail

here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
plugin="${PLUGIN_DIR:-$here/../../cutemonitor-ups}" # override to check a copy
rules="$here/noctalia-5.2.1"
out="$here/out"
mkdir -p "$out"

build() { # entry driver [scenarios]
  local extra=()
  [[ $# -ge 3 ]] && extra=(--scenarios "$3")
  python3 -I "$here/build.py" --plugin "$plugin" --entry "$1" --rules "$rules" \
    --driver "$here/ups/$2.luau" "${extra[@]}" --out "$out/run_$2.luau" >/dev/null
}

status=0
run() { # name
  if ! luau "$out/run_$1.luau" >"$out/$1.out" 2>&1; then
    echo "$1: FAILED (see $out/$1.out)"
    tail -5 "$out/$1.out"
    status=1
    return
  fi
  grep -E '^== |renders:' "$out/$1.out" | sed "s/^/$1: /"
  grep -q -E '^== .*: 0 issue\(s\)' "$out/$1.out" || status=1
}

build service service
run service
python3 -I "$here/scenarios.py" "$out/service.out" "$out/scenarios.luau"
for name in desktop bar panel; do
  build "$name" "$name" "$out/scenarios.luau"
  run "$name"
done
build desktop dates "$out/scenarios.luau"
run dates
exit $status
