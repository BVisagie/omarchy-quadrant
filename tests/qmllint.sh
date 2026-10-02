#!/usr/bin/env bash
# qmllint gate for Quadrant's QML.
#
# Quickshell resolves `qs.*` imports against the shell's root directory, so
# qmllint needs an import path that contains a `qs` entry pointing at
# $OMARCHY_PATH/shell. A temporary symlink provides that.
#
# Disabled categories:
#   unqualified       – the shell's own widgets rely on unqualified ids.
#   missing-property  – Style.font / Style.bar are QtObject groups the
#                       linter types as QObject, so every token read trips it.
#
# Usage: bash tests/qmllint.sh            (skips when no Omarchy shell is present)
set -euo pipefail

cd "$(dirname "${BASH_SOURCE[0]}")/.."

shell_dir=${OMARCHY_PATH:-/usr/share/omarchy}/shell
lint=""
for candidate in qmllint /usr/lib/qt6/bin/qmllint /usr/lib64/qt6/bin/qmllint; do
  if command -v "$candidate" >/dev/null 2>&1; then lint=$candidate; break; fi
done

if [[ -z $lint || ! -d $shell_dir/Ui ]]; then
  echo "qmllint: skipped (needs qmllint and an Omarchy shell at $shell_dir)"
  exit 0
fi

importdir=$(mktemp -d)
trap 'rm -rf "$importdir"' EXIT
ln -s "$shell_dir" "$importdir/qs"

files=()
while IFS= read -r f; do files+=("$f"); done < <(find . -path ./.git -prune -o -name '*.qml' -print | sort)

"$lint" -W 0 \
  --unqualified disable \
  --missing-property disable \
  --signal-handler-parameters disable \
  -I "$importdir" \
  "${files[@]}"
echo "qmllint: ${#files[@]} files clean"
