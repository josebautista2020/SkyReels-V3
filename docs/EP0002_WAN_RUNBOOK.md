# EP0002 Wan Runbook

This is the lower-cost path for generating EP0002 with real motion. It uses Alibaba's open Wan video model instead of relying on still-image zoom/pan renders.

## Decision

Use Wan first, SkyReels second.

Reason: SkyReels reference-to-video is still a strong route for multi-reference character consistency, but the Wan2.2 `TI2V-5B` path is more practical for a sub-5 USD smoke test because upstream documents it running on a 24 GB GPU with CPU/offload options.

## Important correction

Qwen and Kimi are useful LLMs, but they are not the video engine here.

- Qwen can help extend prompts.
- Kimi can help write or refine prompts.
- Wan generates the video.

## Recommended GPU

Start with one of these:

- RTX 4090 24 GB
- RTX A5000 24 GB
- NVIDIA L4 24 GB
- RTX A6000 48 GB
- L40/L40S 48 GB

For a first smoke test, prefer RunPod or Vast over GCP if the goal is speed and low spend. GCP is cleaner for governed infrastructure, but quota and driver setup can slow the test down.

## Build Docker Image

On a GPU host with Docker and NVIDIA Container Toolkit:

```bash
git clone https://github.com/josebautista2020/SkyReels-V3.git
cd SkyReels-V3
git checkout codex/ep0002-skyreels-runner

docker build -f docker/Dockerfile.wan22 -t skyreels-v3:wan22-cuda128 .
```

Validate GPU access before running the model:

```bash
docker run --rm --gpus all nvidia/cuda:12.8.0-base-ubuntu24.04 nvidia-smi
```

If this fails, the issue is the host GPU/driver/container runtime, not the EP0002 script.

## Required EP0002 Assets

Set these to absolute host paths:

```bash
export TOBY_IMG="/absolute/path/Toby.png"
export LUNA_IMG="/absolute/path/Luna.png"
export PARK_IMG="/absolute/path/Park.png"
```

The Wan runner creates a single reference board from the three images because Wan `TI2V` accepts one guide image. This is a compromise. It gives Wan visual anchors for Toby, Luna, and the park, but it is not as semantically clean as SkyReels multi-reference input.

## Smoke Test Under 5 USD

Run one scene first:

```bash
export MAX_SCENES=1
export SIZE="1280*704"
export DOWNLOAD_MODEL=1
bash scripts/docker_run_ep0002_wan.sh
```

Expected output:

```text
result/ep0002_wan/ep0002_wan_smoke_1_scene_master.mp4
```

The first run may spend time downloading model weights. Reusing the Hugging Face cache volume reduces cost on retries.

## Scale Up Gradually

If the one-scene result has real motion and acceptable character style, run two scenes:

```bash
export MAX_SCENES=2
bash scripts/docker_run_ep0002_wan.sh
```

Only after that, run all eight scenes:

```bash
export MAX_SCENES=8
bash scripts/docker_run_ep0002_wan.sh
```

Expected full output:

```text
result/ep0002_wan/ep0002_wan_60s_master.mp4
```

## Direct Runner Without Docker

If Wan2.2 is already installed on the GPU host:

```bash
export WAN_DIR="/workspace/Wan2.2"
export CKPT_DIR="/workspace/Wan2.2/Wan2.2-TI2V-5B"
export DOWNLOAD_MODEL=1
export MAX_SCENES=1
bash scripts/run_ep0002_wan_ti2v.sh
```

## Cost Guardrails

Do not start with `MAX_SCENES=8`.

The expensive parts are:

- model download time
- dependency build time if the image is not prebuilt
- failed runs from VRAM/OOM
- full-episode retries after poor visual output

The safe order is:

1. Docker build once.
2. GPU visibility check.
3. `MAX_SCENES=1`.
4. Review motion and style.
5. `MAX_SCENES=2`.
6. Full eight-scene run.

## When To Return To SkyReels

Use SkyReels if Wan loses character consistency or treats the reference board like a collage. SkyReels' multi-reference flow is more appropriate for Toby + Luna + park, but it may need a larger GPU or more tuning.
