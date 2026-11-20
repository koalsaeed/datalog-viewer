#!/usr/bin/env bash
# Builds the viewer page from viewer/viewer.html and the readers in prototype/readers.
#
#   viewer/build.sh                 writes assets/viewer/index.html (the page the Android app loads)
#   viewer/build.sh --check         fails if assets/viewer/index.html is not what the source builds
#   viewer/build.sh --prototype OUT F150.hpl MUSTANG.hpl
#                                   also writes the phone-frame prototype page with two HP Tuners
#                                   logs embedded as samples (private logs: never commit OUT)
set -euo pipefail
root=$(cd "$(dirname "$0")/.." && pwd)
tmp=$(mktemp -d); trap 'rm -rf "$tmp"' EXIT
app="$root/assets/viewer/index.html"

python3 -I "$root/viewer/scripts/integrate.py" "$root/viewer/viewer.html" "$tmp/prototype.html" "$root/prototype/readers" >/dev/null
python3 -I "$root/viewer/scripts/appify.py" "$tmp/prototype.html" "$tmp/index.html" >/dev/null

case "${1:-}" in
  --check)
    if cmp -s "$tmp/index.html" "$app"; then echo "assets/viewer/index.html is up to date"
    else echo "assets/viewer/index.html differs from what viewer/viewer.html builds: run viewer/build.sh" >&2; exit 1; fi ;;
  --prototype)
    python3 -I "$root/viewer/scripts/integrate.py" "$root/viewer/viewer.html" "$2" "$root/prototype/readers" "$3" "$4" >/dev/null
    cp "$tmp/index.html" "$app"; echo "wrote $app and $2" ;;
  *)
    cp "$tmp/index.html" "$app"; echo "wrote $app" ;;
esac
