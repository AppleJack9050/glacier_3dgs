#!/usr/bin/env bash
set -euo pipefail

# ============================================================
# Wrapper for simple_trainer.py:
#   1) activate conda env
#   2) cd into TRAINER_DIR
#   3) run python simple_trainer.py default ...
#   4) cd back to original directory
# ============================================================

# -------- Conda activation (edit CONDA_ENV as needed) --------
CONDA_ENV="${CONDA_ENV:-gsplat_env}"   # your conda env name
if command -v conda >/dev/null 2>&1; then
  # Enable 'conda activate' in non-interactive shells
  # shellcheck disable=SC1090
  source "$(conda info --base)/etc/profile.d/conda.sh"
  conda activate "$CONDA_ENV"
else
  # Fallback: try a common install path; change this if yours is different
  if [ -f "$HOME/miniconda3/etc/profile.d/conda.sh" ]; then
    # shellcheck disable=SC1090
    source "$HOME/miniconda3/etc/profile.d/conda.sh"
    conda activate "$CONDA_ENV"
  else
    echo "[ERR ] 'conda' not found. Install Miniconda/Anaconda or export CONDA_ENV/conda path." >&2
    exit 1
  fi
fi
echo "[INFO] Activated conda env: $CONDA_ENV"

# -------- Config --------
SCENE_DIR="workspace"
DATA_DIR="$SCENE_DIR/image_2"
RESULT_DIR="$SCENE_DIR/gsplat_outputs"
GPU_ID="${GPU_ID:-0}"
DATA_FACTOR="${DATA_FACTOR:-2}"
PYTHON_BIN="${PYTHON_BIN:-python}"

# Path to directory containing simple_trainer.py
TRAINER_DIR="nerfstudio_gsplat"
TRAINER_FILE="$TRAINER_DIR/simple_trainer.py"

# Ensure output folder exists
mkdir -p "$RESULT_DIR"

# -------- Command --------
CMD=( "$PYTHON_BIN" "simple_trainer.py" "default"
      --data_dir "$DATA_DIR"
      --data_factor "$DATA_FACTOR"
      --result_dir "$RESULT_DIR"
)

# -------- Run --------
echo "[INFO] Switching to $TRAINER_DIR"
pushd "$TRAINER_DIR" >/dev/null

echo "[CMD ] CUDA_VISIBLE_DEVICES=$GPU_ID ${CMD[*]}"
CUDA_VISIBLE_DEVICES="$GPU_ID" "${CMD[@]}"

echo "[INFO] Returning to previous directory"
popd >/dev/null
