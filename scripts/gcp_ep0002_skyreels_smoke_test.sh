#!/usr/bin/env bash
set -euo pipefail

# GCP helper for running a low-cost EP0002 SkyReels smoke test on a GPU VM.
# This script is intentionally conservative: it prepares commands and uses a
# short-lived VM naming convention, but it does not hide GPU costs. Run it from
# a workstation with gcloud authenticated and billing/quota enabled.
#
# Required env vars:
#   GCP_PROJECT=<your-project-id>
#   GCS_BUCKET=<bucket-containing-ep0002-assets>
#
# Expected asset paths in gs://$GCS_BUCKET/ep0002-assets/:
#   Toby.png
#   Luna.png
#   Park.png
#   ep0002-technical-silent-audio.wav       optional
#   ep0002-subtitles.srt                    optional
#
# Optional env vars:
#   ZONE=us-central1-a
#   MACHINE_TYPE=g2-standard-8
#   GPU_TYPE=nvidia-l4
#   GPU_COUNT=1
#   BOOT_DISK_SIZE=250GB
#   INSTANCE_NAME=skyreels-ep0002-smoke
#   BRANCH=codex/ep0002-skyreels-runner
#   RESOLUTION=480P
#   CLIP_DURATION=5
#   MAX_SCENES=1            # set 8 only after smoke test passes
#
# Cost discipline:
# - Start with RESOLUTION=480P, CLIP_DURATION=5, MAX_SCENES=1.
# - Stop/delete the VM immediately after collecting the output.
# - Full 60s generation should only run after a successful 1-2 clip smoke test.

: "${GCP_PROJECT:?GCP_PROJECT is required}"
: "${GCS_BUCKET:?GCS_BUCKET is required}"

ZONE="${ZONE:-us-central1-a}"
MACHINE_TYPE="${MACHINE_TYPE:-g2-standard-8}"
GPU_TYPE="${GPU_TYPE:-nvidia-l4}"
GPU_COUNT="${GPU_COUNT:-1}"
BOOT_DISK_SIZE="${BOOT_DISK_SIZE:-250GB}"
INSTANCE_NAME="${INSTANCE_NAME:-skyreels-ep0002-smoke}"
BRANCH="${BRANCH:-codex/ep0002-skyreels-runner}"
RESOLUTION="${RESOLUTION:-480P}"
CLIP_DURATION="${CLIP_DURATION:-5}"
MAX_SCENES="${MAX_SCENES:-1}"

cat > /tmp/skyreels-ep0002-startup.sh <<EOF
#!/usr/bin/env bash
set -euxo pipefail

apt-get update
apt-get install -y git git-lfs ffmpeg python3.12 python3.12-venv python3-pip

mkdir -p /opt/skyreels
cd /opt/skyreels
if [ ! -d SkyReels-V3 ]; then
  git clone --branch ${BRANCH} https://github.com/josebautista2020/SkyReels-V3.git
fi
cd SkyReels-V3

python3.12 -m venv .venv
source .venv/bin/activate
python -m pip install --upgrade pip
pip install -r requirements.txt

mkdir -p /opt/ep0002-assets
gsutil -m cp gs://${GCS_BUCKET}/ep0002-assets/* /opt/ep0002-assets/

export TOBY_IMG=/opt/ep0002-assets/Toby.png
export LUNA_IMG=/opt/ep0002-assets/Luna.png
export PARK_IMG=/opt/ep0002-assets/Park.png
export AUDIO_WAV=/opt/ep0002-assets/ep0002-technical-silent-audio.wav
export SUBTITLES_SRT=/opt/ep0002-assets/ep0002-subtitles.srt
export RESOLUTION=${RESOLUTION}
export CLIP_DURATION=${CLIP_DURATION}
export MAX_SCENES=${MAX_SCENES}
export LOW_VRAM=1
export OFFLOAD=1

bash scripts/run_ep0002_reference_to_video.sh

gsutil -m cp -r result/ep0002_skyreels gs://${GCS_BUCKET}/ep0002-skyreels-output/
EOF

chmod +x /tmp/skyreels-ep0002-startup.sh

gcloud config set project "$GCP_PROJECT"

gcloud compute instances create "$INSTANCE_NAME" \
  --zone "$ZONE" \
  --machine-type "$MACHINE_TYPE" \
  --accelerator "type=${GPU_TYPE},count=${GPU_COUNT}" \
  --maintenance-policy TERMINATE \
  --boot-disk-size "$BOOT_DISK_SIZE" \
  --image-family ubuntu-2404-lts-amd64 \
  --image-project ubuntu-os-cloud \
  --metadata-from-file startup-script=/tmp/skyreels-ep0002-startup.sh \
  --scopes cloud-platform

cat <<EOF

VM created: ${INSTANCE_NAME}

Watch startup logs:
  gcloud compute ssh ${INSTANCE_NAME} --zone ${ZONE} --command 'sudo tail -f /var/log/syslog'

Fetch output after completion:
  gsutil -m cp -r gs://${GCS_BUCKET}/ep0002-skyreels-output ./ep0002-skyreels-output

Delete VM immediately after test:
  gcloud compute instances delete ${INSTANCE_NAME} --zone ${ZONE}
EOF
