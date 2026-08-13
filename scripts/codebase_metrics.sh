#!/usr/bin/env bash

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "${ROOT_DIR}"

swift_files=()
while IFS= read -r file; do
  swift_files+=("${file}")
done < <(rg --files \
  GymTrainingApp \
  GymTrainingWatchApp \
  GymTrainingWatchWidget \
  Shared \
  GymTrainingAppTests \
  GymTrainingAppUITests \
  GymTrainingWatchAppUITests \
  -g '*.swift' | sort)

echo "Swift files: ${#swift_files[@]}"
echo "Swift lines: $(wc -l "${swift_files[@]}" | awk 'END { print $1 }')"
echo
echo "Largest Swift files:"
wc -l "${swift_files[@]}" | sort -nr | sed -n '2,16p'
echo
echo "Files over 800 lines:"
wc -l "${swift_files[@]}" | awk '$1 > 800 && $2 != "total" { print }' | sort -nr
