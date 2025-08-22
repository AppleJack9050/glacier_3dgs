#!/usr/bin/env bash
set -euo pipefail

# ============================================================
# Orchestrator to run:
#   1) COLMAP stage script (your first snippet)
#   2) 3DGS stage script (your second snippet)
#
# ============================================================

# ---------------- User knobs ----------------
# The scene working directory containing: image/, image_2/, sparse/, database.db
SCENE_DIR="$1"

# Paths to your two stage scripts (make sure both are executable)
COLMAP_SCRIPT="${COLMAP_SCRIPT:-$PWD/colmap_stage.sh}"   # your first script filename
G3DS_SCRIPT="${G3DS_SCRIPT:-$PWD/gsplat_stage.sh}"       # your second script filename

# ---------------- Helpers -------------------
info(){ echo -e "\033[1;32m[INFO]\033[0m $*"; }
warn(){ echo -e "\033[1;33m[WARN]\033[0m $*"; }
err(){  echo -e "\033[1;31m[ERR ]\033[0m $*"; }

# ---------------- Sanity checks -------------
[[ -x "$COLMAP_SCRIPT" ]] || { err "COLMAP script not found or not executable: $COLMAP_SCRIPT"; exit 1; }
[[ -x "$G3DS_SCRIPT"   ]] || { err "3DGS script not found or not executable: $G3DS_SCRIPT"; exit 1; }

[[ -d "$SCENE_DIR" ]] || { err "SCENE_DIR not found: $SCENE_DIR"; exit 1; }
[[ -d "$SCENE_DIR/image" ]] || { err "Missing folder: $SCENE_DIR/image"; exit 1; }

# ---------------- 1) Run COLMAP stage ----------------
info "Running COLMAP stage: $COLMAP_SCRIPT  (SCENE_DIR=$SCENE_DIR)"
"$COLMAP_SCRIPT" "$SCENE_DIR"

# ---------------- 3) Run 3DGS stage ------------------
info "Running 3DGS stage: $G3DS_SCRIPT"
"$G3DS_SCRIPT" "$SCENE_DIR"

info "All done ✅"
