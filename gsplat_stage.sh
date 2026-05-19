#!/usr/bin/env bash
set -euo pipefail

# ============================================================
# Wrapper for simple_trainer.py (NO changes to python code):
#   - stage: SCENE_DIR/image_2/images     from SCENE_DIR/image
#   - stage: SCENE_DIR/image_2/images_2   (needed by trainer) -> link to images
#   - stage: SCENE_DIR/image_2/sparse     -> link to SCENE_DIR/sparse
#   - run trainer
#   - ALWAYS cleanup: remove SCENE_DIR/image_2 after run
# ============================================================

# -------- Conda activation (edit CONDA_ENV as needed) --------
CONDA_ENV="${CONDA_ENV:-gsplat_env}"   # your conda env name
if command -v conda >/dev/null 2>&1; then
  # shellcheck disable=SC1090
  source "$(conda info --base)/etc/profile.d/conda.sh"
  conda activate "$CONDA_ENV"
else
  if [ -f "$HOME/miniconda3/etc/profile.d/conda.sh" ]; then
    # shellcheck disable=SC1090
    source "$HOME/miniconda3/etc/profile.d/conda.sh"
    conda activate "$CONDA_ENV"
  else
    echo "[ERR ] 'conda' not found." >&2
    exit 1
  fi
fi
echo "[INFO] Activated conda env: $CONDA_ENV"

# -------- Args --------
if [ $# -lt 1 ]; then
  echo "Usage: $0 <SCENE_DIR>" >&2
  exit 2
fi

# -------- Config --------
SCENE_DIR="$1"
DATA_DIR="$SCENE_DIR/image_2"

# Always delete image_2 after run (set DELETE_IMAGE_2=0 to keep it)
DELETE_IMAGE_2="${DELETE_IMAGE_2:-1}"

# What simple_trainer.py expects (based on your error)
IMG_DST_MAIN="$DATA_DIR/images"
IMG_DST_2="$DATA_DIR/images_2"

# Your actual scene layout
IMG_SRC="$SCENE_DIR/image"
SPARSE_SRC="$SCENE_DIR/sparse"
SPARSE_DST="$DATA_DIR/sparse"

RESULT_DIR="$SCENE_DIR/gsplat_outputs"
GPU_ID="${GPU_ID:-0}"
DATA_FACTOR="${DATA_FACTOR:-2}"
PYTHON_BIN="${PYTHON_BIN:-python}"

TRAINER_DIR="/home/otter77/git_project/gsplat/examples"

mkdir -p "$RESULT_DIR"

# -------- Staging & cleanup flags --------
CREATED_DATA_DIR=0
CREATED_IMAGES_MAIN=0
CREATED_IMAGES_2=0
CREATED_SPARSE_LINK=0
PUSHD_DONE=0

cleanup() {
  if [ "$PUSHD_DONE" -eq 1 ]; then
    popd >/dev/null || true
  fi

  # ALWAYS remove <SCENE_DIR>/image_2 if DELETE_IMAGE_2=1
  if [ "$DELETE_IMAGE_2" -eq 1 ]; then
    # ---- Safety guard: only allow deleting <SCENE_DIR>/image_2 ----
    scene_real="$(readlink -f "$SCENE_DIR" 2>/dev/null || echo "$SCENE_DIR")"
    data_real="$(readlink -f "$DATA_DIR" 2>/dev/null || echo "$DATA_DIR")"

    if [[ -n "$scene_real" && -n "$data_real" && "$data_real" == "$scene_real/image_2" ]]; then
      if [ -e "$DATA_DIR" ]; then
        echo "[INFO] Removing staged directory: $DATA_DIR"
        rm -rf "$DATA_DIR"
      fi
    else
      echo "[WARN] Refusing to remove unsafe path:"
      echo "       SCENE_DIR=$SCENE_DIR (resolved: $scene_real)"
      echo "       DATA_DIR=$DATA_DIR  (resolved: $data_real)"
    fi
    return
  fi

  # If DELETE_IMAGE_2=0, fall back to selective cleanup
  if [ "$CREATED_SPARSE_LINK" -eq 1 ]; then
    echo "[INFO] Removing staged link: $SPARSE_DST"
    rm -rf "$SPARSE_DST"
  fi

  if [ "$CREATED_IMAGES_2" -eq 1 ]; then
    echo "[INFO] Removing staged directory/link: $IMG_DST_2"
    rm -rf "$IMG_DST_2"
  fi

  if [ "$CREATED_IMAGES_MAIN" -eq 1 ]; then
    echo "[INFO] Removing staged directory: $IMG_DST_MAIN"
    rm -rf "$IMG_DST_MAIN"
  fi

  if [ "$CREATED_DATA_DIR" -eq 1 ]; then
    echo "[INFO] Removing staged directory: $DATA_DIR"
    rm -rf "$DATA_DIR"
  fi
}

trap cleanup EXIT INT TERM

# -------- Preconditions --------
if [ ! -d "$IMG_SRC" ]; then
  echo "[ERR ] Source image folder not found: $IMG_SRC" >&2
  exit 1
fi

if [ ! -d "$SPARSE_SRC" ]; then
  echo "[ERR ] COLMAP sparse folder not found: $SPARSE_SRC" >&2
  echo "       Expected e.g. $SPARSE_SRC/0/cameras.bin" >&2
  exit 1
fi

# -------- Stage base folder --------
if [ ! -d "$DATA_DIR" ]; then
  mkdir -p "$DATA_DIR"
  CREATED_DATA_DIR=1
fi

# -------- Stage images -> image_2/images --------
if [ ! -d "$IMG_DST_MAIN" ]; then
  echo "[INFO] Creating $IMG_DST_MAIN by copying from $IMG_SRC"
  mkdir -p "$IMG_DST_MAIN"
  cp -a "$IMG_SRC"/. "$IMG_DST_MAIN"/
  CREATED_IMAGES_MAIN=1
else
  echo "[INFO] Found existing $IMG_DST_MAIN (will not delete it after run)"
fi

# -------- Stage images_2 -> required by trainer --------
# Prefer symlink to save space; if symlink fails, fall back to copy.
if [ -e "$IMG_DST_2" ]; then
  echo "[INFO] Found existing $IMG_DST_2 (will not modify it)"
else
  echo "[INFO] Creating $IMG_DST_2 (required by trainer)"
  (
    cd "$DATA_DIR"
    # Try symlink first: images_2 -> images
    if ln -s "images" "images_2" 2>/dev/null; then
      :
    else
      # Fallback: copy (works everywhere)
      mkdir -p "images_2"
      cp -a "images"/. "images_2"/
    fi
  )
  CREATED_IMAGES_2=1
fi

# -------- Stage sparse link --------
if [ -e "$SPARSE_DST" ]; then
  echo "[INFO] Found existing $SPARSE_DST (will not modify it)"
else
  echo "[INFO] Linking $SPARSE_DST -> $SPARSE_SRC"
  ln -s "$SPARSE_SRC" "$SPARSE_DST"
  CREATED_SPARSE_LINK=1
fi

# -------- Command --------
CMD=( "$PYTHON_BIN" "simple_trainer.py" "default"
      --data_dir "$DATA_DIR"
      --data_factor "$DATA_FACTOR"
      --result_dir "$RESULT_DIR"
)

# -------- Run --------
echo "[INFO] Switching to $TRAINER_DIR"
pushd "$TRAINER_DIR" >/dev/null
PUSHD_DONE=1

echo "[CMD ] CUDA_VISIBLE_DEVICES=$GPU_ID ${CMD[*]}"
CUDA_VISIBLE_DEVICES="$GPU_ID" "${CMD[@]}"