#!/bin/sh
set -eu

SCRIPT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
MODEL_DIR="${CALORIE_CLIP_MODEL_DIR:-$SCRIPT_DIR/models/calorie_clip}"
BASE_URL="https://huggingface.co/jc-builds/CalorieCLIP/resolve/26b9bd644f65323fcddb68a86a2c0c5505c4bc81"

mkdir -p "$MODEL_DIR"

for file in calorie_clip.py config.json calorie_clip.pt; do
  if [ ! -s "$MODEL_DIR/$file" ]; then
    curl --fail --location --progress-bar "$BASE_URL/$file" --output "$MODEL_DIR/$file"
  fi
done

echo "CalorieCLIP installed in $MODEL_DIR"
