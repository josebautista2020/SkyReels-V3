#!/usr/bin/env bash
set -euo pipefail

IMAGE="${IMAGE:-skyreels-v3:wan22-cuda128}"
CONTAINER_NAME="${CONTAINER_NAME:-ep0002-wan}"
WORKDIR_IN_CONTAINER="/workspace/SkyReels-V3"

: "${TOBY_IMG:?Set TOBY_IMG to an absolute host path}"
: "${LUNA_IMG:?Set LUNA_IMG to an absolute host path}"
: "${PARK_IMG:?Set PARK_IMG to an absolute host path}"

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ASSET_DIR="${ASSET_DIR:-$(dirname "$TOBY_IMG")}" 
OUT_DIR="${OUT_DIR:-result/ep0002_wan}"
MAX_SCENES="${MAX_SCENES:-1}"
SIZE="${SIZE:-1280*704}"
DOWNLOAD_MODEL="${DOWNLOAD_MODEL:-1}"

if ! command -v docker >/dev/null 2>&1; then
  echo "Docker is not installed on this host." >&2
  exit 2
fi

if ! docker run --rm --gpus all nvidia/cuda:12.8.0-base-ubuntu24.04 nvidia-smi >/dev/null 2>&1; then
  echo "Docker cannot access an NVIDIA GPU. Check drivers and NVIDIA Container Toolkit." >&2
  exit 2
fi

docker run --rm -it --gpus all \
  --name "$CONTAINER_NAME" \
  -v "$REPO_DIR:$WORKDIR_IN_CONTAINER" \
  -v "$ASSET_DIR:/workspace/ep0002-assets:ro" \
  -v "${HF_CACHE_DIR:-$HOME/.cache/huggingface}:/workspace/.cache/huggingface" \
  -w "$WORKDIR_IN_CONTAINER" \
  -e TOBY_IMG="/workspace/ep0002-assets/$(basename "$TOBY_IMG")" \
  -e LUNA_IMG="/workspace/ep0002-assets/$(basename "$LUNA_IMG")" \
  -e PARK_IMG="/workspace/ep0002-assets/$(basename "$PARK_IMG")" \
  -e OUT_DIR="$OUT_DIR" \
  -e MAX_SCENES="$MAX_SCENES" \
  -e SIZE="$SIZE" \
  -e DOWNLOAD_MODEL="$DOWNLOAD_MODEL" \
  -e WAN_DIR="/workspace/Wan2.2" \
  "$IMAGE" \
  bash scripts/run_ep0002_wan_ti2v.sh
