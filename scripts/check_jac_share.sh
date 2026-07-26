#!/usr/bin/env bash
set -euo pipefail

project_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$project_dir"

jac_bytes=0
source_bytes=0

while IFS= read -r -d '' file; do
  bytes="$(wc -c < "$file" | tr -d ' ')"
  source_bytes=$((source_bytes + bytes))
  case "$file" in
    *.jac) jac_bytes=$((jac_bytes + bytes)) ;;
  esac
done < <(
  find . \
    -path './.git' -prune -o \
    -path './.jac' -prune -o \
    -path './.venv' -prune -o \
    -path './node_modules' -prune -o \
    -type f \
    \( -name '*.jac' -o -name '*.py' -o -name '*.js' -o -name '*.jsx' \
       -o -name '*.ts' -o -name '*.tsx' -o -name '*.css' -o -name '*.sh' \) \
    -print0
)

if (( source_bytes == 0 )); then
  echo "No source files found."
  exit 1
fi

share=$((jac_bytes * 10000 / source_bytes))
printf 'Jac share: %d.%02d%% (%d of %d source bytes)\n' \
  "$((share / 100))" "$((share % 100))" "$jac_bytes" "$source_bytes"

if (( share <= 5000 )); then
  echo "Jac must remain more than 50% of source bytes."
  exit 1
fi
