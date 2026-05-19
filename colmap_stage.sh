#!/usr/bin/env bash
set -euo pipefail

# ============================================================
# COLMAP sparse reconstruction (NO undistortion)
#
# Layout inside SCENE_DIR:
#   image/        -> raw input images (you put images here)
#   sparse/       -> mapper outputs (binary models, e.g., 0/, 1/, ...)
#   database.db   -> COLMAP database
#
# Notes:
# - Exhaustive matcher is used.
# - You can set OVERWRITE=1 to clean previous outputs.
# - You can override colmap binary via COLMAP_BIN=/path/to/colmap
# ============================================================

# ---------------- Config ----------------
SCENE_DIR="${1:?Usage: $0 /path/to/scene_dir}"
COLMAP_BIN="${COLMAP_BIN:-colmap}"
OVERWRITE="${OVERWRITE:-0}"

# ---------------- Paths -----------------
IMG_DIR="$SCENE_DIR/image"      # input images
SPARSE_DIR="$SCENE_DIR/sparse"  # mapper output (binary reconstructions)
DB_PATH="$SCENE_DIR/database.db"

# ---------------- Helpers ----------------
info(){ echo -e "\033[1;32m[INFO]\033[0m $*"; }
warn(){ echo -e "\033[1;33m[WARN]\033[0m $*"; }
err(){  echo -e "\033[1;31m[ERR ]\033[0m $*"; }

# ---------------- Preflight ----------------
mkdir -p "$IMG_DIR" "$SPARSE_DIR"

command -v "$COLMAP_BIN" >/dev/null 2>&1 || { err "COLMAP not found: $COLMAP_BIN"; exit 1; }
[[ -d "$IMG_DIR" ]] || { err "Raw image dir not found: $IMG_DIR"; exit 1; }

shopt -s nullglob
imgs=("$IMG_DIR"/*)
if [[ ${#imgs[@]} -eq 0 ]]; then
  err "No images in $IMG_DIR"; exit 1
fi
shopt -u nullglob

if [[ "$OVERWRITE" == "1" ]]; then
  info "OVERWRITE=1 -> removing old artifacts"
  rm -f "$DB_PATH"
  rm -rf "$SPARSE_DIR"
  mkdir -p "$SPARSE_DIR"
fi

info "Scene dir  : $SCENE_DIR"
info "Input imgs : $IMG_DIR"
info "Database   : $DB_PATH"
info "Sparse out : $SPARSE_DIR"

# ---------------- Step 1: Feature extraction ----------------
info "COLMAP: feature_extractor..."
"$COLMAP_BIN" feature_extractor \
  --database_path "$DB_PATH" \
  --image_path "$IMG_DIR"

# ---------------- Step 2: Exhaustive matching ----------------
info "COLMAP: exhaustive_matcher..."
"$COLMAP_BIN" exhaustive_matcher \
  --database_path "$DB_PATH"

# ---------------- Step 3: Sparse reconstruction (mapper) -----
info "COLMAP: mapper (sparse reconstruction)..."
"$COLMAP_BIN" mapper \
  --database_path "$DB_PATH" \
  --image_path "$IMG_DIR" \
  --output_path "$SPARSE_DIR"

if [[ ! -d "$SPARSE_DIR/0" ]]; then
  err "No reconstruction found at $SPARSE_DIR/0. Check mapper logs."; exit 1
fi

info "Done."
info "Raw images      : $IMG_DIR"
info "Database        : $DB_PATH"
info "Sparse (binary) : $SPARSE_DIR  (models: 0/, 1/, ...)"
