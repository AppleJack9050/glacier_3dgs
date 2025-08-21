#!/usr/bin/env bash
set -euo pipefail

# ============================================================
# Orchestrator to run:
#   1) COLMAP stage script (your first snippet)
#   2) 3DGS stage script (your second snippet)
#
# Features:
# - Accepts a custom SCENE_DIR. If SCENE_DIR != ./workspace, creates a
#   temporary symlink ./workspace -> SCENE_DIR so the 3DGS script works unmodified.
# - Does NOT re-run undistorter. Uses exactly your two scripts as-is.
# ============================================================

# ---------------- User knobs ----------------
# The scene working directory containing: image/, image_2/, sparse/, database.db
SCENE_DIR="${SCENE_DIR:-$PWD/workspace}"

# Paths to your two stage scripts (make sure both are executable)
COLMAP_SCRIPT="${COLMAP_SCRIPT:-$PWD/colmap_stage.sh}"   # your first script filename
G3DS_SCRIPT="${G3DS_SCRIPT:-$PWD/gsplat_stage.sh}"       # your second script filename

# Whether to auto-create a temporary symlink ./workspace -> $SCENE_DIR for stage 2
USE_TEMP_SYMLINK="${USE_TEMP_SYMLINK:-1}"

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

# ---------------- 2) Prepare for 3DGS stage ----------
# Your 3DGS script uses SCENE_DIR=\"workspace\" internally.
# If user specified a different SCENE_DIR, optionally map it via a symlink.
TEMP_LINK_CREATED=0
ABS_SCENE="$(cd "$SCENE_DIR" && pwd)"
ABS_WS="$(pwd)/workspace"

if [[ "$USE_TEMP_SYMLINK" == "1" ]]; then
  if [[ "$ABS_SCENE" != "$ABS_WS" ]]; then
    if [[ -L "$ABS_WS" ]]; then
      info "Existing symlink ./workspace detected (will replace)."
      rm -f "$ABS_WS"
    elif [[ -d "$ABS_WS" ]]; then
      warn "./workspace exists as a real directory; 3DGS script will use it as-is."
      warn "To target $SCENE_DIR, remove/rename ./workspace or set USE_TEMP_SYMLINK=0."
    else
      ln -s "$ABS_SCENE" "$ABS_WS"
      TEMP_LINK_CREATED=1
      info "Created temporary symlink: ./workspace -> $ABS_SCENE"
    fi
  fi
fi

# ---------------- 3) Run 3DGS stage ------------------
info "Running 3DGS stage: $G3DS_SCRIPT"
"$G3DS_SCRIPT"

# ---------------- Cleanup ---------------------------
if [[ "$TEMP_LINK_CREATED" == "1" ]]; then
  rm -f "$ABS_WS"
  info "Removed temporary symlink ./workspace"
fi

info "All done ✅"
