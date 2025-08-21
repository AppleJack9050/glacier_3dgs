#!/usr/bin/env bash
set -euo pipefail

# ============================================================
# COLMAP -> Undistortion -> 3D Gaussian Splatting (GraphDECO)
# Fully parameterized Bash pipeline with argument parsing.
# All code annotations are in English.
# ============================================================

# ------------------ Defaults ------------------
DATA_ROOT="/home/otter77/Pictures/glacier_clean"
COLMAP_BIN="colmap"
GS_REPO_DIR="/home/otter77/Documents/gsplat/examples"
GPU_ID="0"

# Flags
FLAG_SKIP_COLMAP=0
FLAG_SKIP_CONVERT=0
FLAG_SKIP_RENDER=0
FLAG_NO_INSTALL=0

# ------------------ Helpers -------------------
info() { echo -e "\033[1;32m[INFO]\033[0m $*"; }
warn() { echo -e "\033[1;33m[WARN]\033[0m $*"; }
err()  { echo -e "\033[1;31m[ERR ]\033[0m $*"; }

usage() {
  cat <<EOF
Usage: $(basename "$0") [options]

  --data PATH             Dataset root directory (default: ${DATA_ROOT})
  --colmap-bin PATH       Path to COLMAP executable (default: ${COLMAP_BIN})
  --gs-repo PATH          Path to graphdeco-inria/gaussian-splatting repo (default: ${GS_REPO_DIR})
  --gpu ID                CUDA device id (default: ${GPU_ID})

  --skip-colmap           Skip the entire COLMAP stage (assume undistorted outputs exist)
  --no-install            Do not run 'pip install -r requirements.txt'

  -h, --help              Show this help

Examples:
  # i will write it later
EOF
}

# ------------------ Parse args ----------------
while [[ $# -gt 0 ]]; do
  case "$1" in
    --data)         DATA_ROOT="$2"; shift 2;;
    --colmap-bin)   COLMAP_BIN="$2"; shift 2;;
    --gs-repo)      GS_REPO_DIR="$2"; shift 2;;
    --gpu)          GPU_ID="$2"; shift 2;;
    --skip-colmap)  FLAG_SKIP_COLMAP=1; shift;;
    --no-install)   FLAG_NO_INSTALL=1; shift;;
    -h|--help)      usage; exit 0;;
    *) err "Unknown option: $1"; usage; exit 1;;
  esac
done

# ------------------ Paths layout ----------------
SCENE_DIR="$DATA_ROOT/$SCENE_NAME"
DISTORTED_DIR="$SCENE_DIR/distorted"
SPARSE_DIR="$DISTORTED_DIR/sparse"
DB_PATH="$DISTORTED_DIR/database.db"
UNDISTORTED_DIR="$SCENE_DIR"   # GraphDECO convert.py expects undistorted under scene root

if [[ -z "$IMAGES_DIR" ]]; then
  IMAGES_DIR="$DATA_ROOT/$SCENE_NAME/input"
fi

# ------------------ Summary --------------------
info "Scene name        : $SCENE_NAME"
info "Dataset root      : $DATA_ROOT"
info "Images dir        : $IMAGES_DIR"
info "COLMAP binary     : $COLMAP_BIN"
info "3DGS repo         : $GS_REPO_DIR"
info "GPU id            : $GPU_ID"
info "Training iters    : $TRAIN_STEPS"
info "Match mode        : $MATCH_MODE"
info "Skip COLMAP       : $FLAG_SKIP_COLMAP"
info "Skip convert      : $FLAG_SKIP_CONVERT"
info "Skip render       : $FLAG_SKIP_RENDER"
info "No pip install    : $FLAG_NO_INSTALL"

# ------------------ Basic checks ---------------
if [[ $FLAG_SKIP_COLMAP -eq 0 ]]; then
  if ! command -v "$COLMAP_BIN" >/dev/null 2>&1; then
    err "COLMAP not found: $COLMAP_BIN"; exit 1
  fi
fi

if [[ ! -d "$IMAGES_DIR" && $FLAG_SKIP_COLMAP -eq 0 ]]; then
  err "Images directory not found: $IMAGES_DIR"
  err "Place your raw images (jpg/png) under this path or pass --images."
  exit 1
fi

mkdir -p "$IMAGES_DIR" "$DISTORTED_DIR" "$SPARSE_DIR"

# ------------------ 3DGS repo ------------------
if [[ ! -d "$GS_REPO_DIR" ]]; then
  info "Cloning graphdeco-inria/gaussian-splatting..."
  git clone https://github.com/graphdeco-inria/gaussian-splatting.git "$GS_REPO_DIR"
fi

if [[ $FLAG_NO_INSTALL -eq 0 && -f "$GS_REPO_DIR/requirements.txt" ]]; then
  info "Installing Python requirements for 3DGS..."
  pip install -r "$GS_REPO_DIR/requirements.txt"
else
  info "Skipping Python requirements installation."
fi

# ------------------ COLMAP stage ----------------
if [[ $FLAG_SKIP_COLMAP -eq 0 ]]; then
  info "COLMAP: feature extraction..."
  "$COLMAP_BIN" feature_extractor \
    --database_path "$DB_PATH" \
    --image_path "$IMAGES_DIR" \
    --ImageReader.single_camera 0 \
    --SiftExtraction.use_gpu 1

  if [[ "$MATCH_MODE" == "sequential" ]]; then
    info "COLMAP: sequential matcher..."
    "$COLMAP_BIN" sequential_matcher \
      --database_path "$DB_PATH" \
      --SiftMatching.use_gpu 1
  else
    info "COLMAP: exhaustive matcher..."
    "$COLMAP_BIN" exhaustive_matcher \
      --database_path "$DB_PATH" \
      --SiftMatching.use_gpu 1
  fi

  info "COLMAP: mapper (sparse reconstruction)..."
  "$COLMAP_BIN" mapper \
    --database_path "$DB_PATH" \
    --image_path "$IMAGES_DIR" \
    --output_path "$SPARSE_DIR"

  # Choose the largest/first model from mapper (usually '0')
  if [[ ! -d "$SPARSE_DIR/0" ]]; then
    err "No sparse model found at: $SPARSE_DIR/0"
    err "Check mapper output under $SPARSE_DIR"
    exit 1
  fi

  info "COLMAP: undistorting to pinhole intrinsics..."
  "$COLMAP_BIN" image_undistorter \
    --image_path "$IMAGES_DIR" \
    --input_path "$SPARSE_DIR/0" \
    --output_path "$UNDISTORTED_DIR" \
    --output_type COLMAP

  # After undistortion:
  # - $UNDISTORTED_DIR/images
  # - $UNDISTORTED_DIR/sparse (cameras.txt, images.txt, points3D.txt)
else
  warn "Skipping COLMAP stage as requested (--skip-colmap)."
fi

# ------------------ convert.py -----------------
if [[ $FLAG_SKIP_CONVERT -eq 0 ]]; then
  info "Preparing dataset via GraphDECO convert.py..."
  pushd "$GS_REPO_DIR" >/dev/null
  CUDA_VISIBLE_DEVICES="$GPU_ID" python convert.py -s "$SCENE_DIR"
  popd >/dev/null
else
  warn "Skipping convert.py as requested (--skip-convert)."
fi

# ------------------ train.py -------------------
info "Training 3D Gaussian Splatting..."
pushd "$GS_REPO_DIR" >/dev/null
CUDA_VISIBLE_DEVICES="$GPU_ID" python simple_trainer.py default --data_dir 
popd >/dev/null