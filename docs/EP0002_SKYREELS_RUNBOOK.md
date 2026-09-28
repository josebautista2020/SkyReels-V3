# EP0002 SkyReels Runbook

This runbook prepares EP0002 for real video generation with SkyReels-V3, using the `reference_to_video` model and the existing character/location references:

- Toby: golden puppy, blue hoodie, red backpack
- Luna: cream puppy, purple bandana
- Park: bright neighborhood puppy park

## Why this path

The previous FFmpeg/Ken Burns render only adds camera motion over still images. SkyReels-V3 can generate actual motion from reference images and text prompts, so it is the better technical route for a fluid episode.

## Hardware reality

SkyReels-V3 is not a lightweight API call. It is an open-source video diffusion model.

Recommended by the upstream README:

- Python 3.12+
- CUDA 12.8+
- GPU with substantial VRAM
- Use `--low_vram` and lower resolution for GPUs under 24 GB VRAM

The EP0002 runner defaults to:

- `RESOLUTION=540P`
- `LOW_VRAM=1`
- `OFFLOAD=1`
- `MAX_SCENES=8`
- final trim to 60 seconds when all 8 scenes are generated

For cost control, run smoke tests first with:

- `RESOLUTION=480P`
- `CLIP_DURATION=5`
- `MAX_SCENES=1`

For best output, use a GPU with 24 GB+ VRAM. For practical lower-cost testing, start with an L4/A10-class GPU at `480P` or `540P`. For quality review, move to A100/H100-class GPUs if available.

## Setup

```bash
git clone https://github.com/josebautista2020/SkyReels-V3.git
cd SkyReels-V3
git checkout codex/ep0002-skyreels-runner
pip install -r requirements.txt
```

If `flash_attn` fails during install, use a CUDA/PyTorch-compatible wheel for the target GPU image rather than forcing a source compile.

## Required assets

Set these paths to the local reference images:

```bash
export TOBY_IMG="/path/to/Toby.png"
export LUNA_IMG="/path/to/Luna.png"
export PARK_IMG="/path/to/Park.png"
```

Optional technical audio/subtitles from Content Studio:

```bash
export AUDIO_WAV="/path/to/ep0002-technical-silent-audio.wav"
export SUBTITLES_SRT="/path/to/ep0002-subtitles.srt"
```

## Smoke Test First

Run a one-scene smoke test before spending GPU time on the full episode:

```bash
export RESOLUTION=480P
export CLIP_DURATION=5
export MAX_SCENES=1
export LOW_VRAM=1
export OFFLOAD=1
bash scripts/run_ep0002_reference_to_video.sh
```

Expected output:

```text
result/ep0002_skyreels/ep0002_skyreels_smoke_1_scene_master.mp4
```

If the first scene is visually acceptable, run 2 scenes:

```bash
export MAX_SCENES=2
bash scripts/run_ep0002_reference_to_video.sh
```

## Full EP0002 Run

Only run the full episode after smoke test approval:

```bash
export RESOLUTION=540P
export CLIP_DURATION=8
export MAX_SCENES=8
export LOW_VRAM=1
export OFFLOAD=1
bash scripts/run_ep0002_reference_to_video.sh
```

The final output is written to:

```text
result/ep0002_skyreels/ep0002_skyreels_60s_master.mp4
```

## GCP Helper

A conservative GCP helper is included:

```bash
export GCP_PROJECT="your-project-id"
export GCS_BUCKET="your-bucket"
export RESOLUTION=480P
export CLIP_DURATION=5
export MAX_SCENES=1
bash scripts/gcp_ep0002_skyreels_smoke_test.sh
```

Before running it, upload assets to:

```text
gs://$GCS_BUCKET/ep0002-assets/Toby.png
gs://$GCS_BUCKET/ep0002-assets/Luna.png
gs://$GCS_BUCKET/ep0002-assets/Park.png
```

Optional:

```text
gs://$GCS_BUCKET/ep0002-assets/ep0002-technical-silent-audio.wav
gs://$GCS_BUCKET/ep0002-assets/ep0002-subtitles.srt
```

The helper creates a GPU VM and writes output to:

```text
gs://$GCS_BUCKET/ep0002-skyreels-output/
```

Delete the VM immediately after the test.

## Cost guidance

SkyReels-V3 itself is open-source, but running it is not free unless you already own idle GPU capacity. Cost comes from GPU rental/time and model download/storage.

For one 60-second EP0002 test, expect multiple generated clips. The true cost depends on GPU type, queue speed, resolution, and retries. Do not assume it is cheaper than API generation unless the GPU is already available or the provider has low hourly rates.

## Quality caveat

This runner gives real generated motion, but each clip is generated independently. Character consistency should be stronger than pure text-to-video because we pass reference images, but it still needs human review. If clip-to-clip continuity is weak, the next step is to use SkyReels video extension from the best first clip instead of generating every scene independently.
