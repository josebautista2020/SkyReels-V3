#!/usr/bin/env bash
set -euo pipefail

# EP0002 runner for SkyReels-V3 Reference-to-Video.
# Requires a CUDA GPU machine with this repository installed and model access.
#
# Required environment variables:
#   TOBY_IMG=/path/to/Toby.png
#   LUNA_IMG=/path/to/Luna.png
#   PARK_IMG=/path/to/Park.png
#
# Optional environment variables:
#   OUT_DIR=./result/ep0002_skyreels
#   MODEL_ID=Skywork/SkyReels-V3-Reference2Video
#   RESOLUTION=540P        # 480P, 540P, or 720P
#   CLIP_DURATION=8        # per scene; 8 clips are trimmed to 60s master
#   SEED=42002
#   LOW_VRAM=1             # 1 adds --low_vram
#   OFFLOAD=1              # 1 adds --offload
#   AUDIO_WAV=/path/to/ep0002-technical-silent-audio.wav
#   SUBTITLES_SRT=/path/to/ep0002-subtitles.srt

TOBY_IMG="${TOBY_IMG:?TOBY_IMG is required}"
LUNA_IMG="${LUNA_IMG:?LUNA_IMG is required}"
PARK_IMG="${PARK_IMG:?PARK_IMG is required}"

OUT_DIR="${OUT_DIR:-./result/ep0002_skyreels}"
MODEL_ID="${MODEL_ID:-Skywork/SkyReels-V3-Reference2Video}"
RESOLUTION="${RESOLUTION:-540P}"
CLIP_DURATION="${CLIP_DURATION:-8}"
SEED="${SEED:-42002}"
LOW_VRAM="${LOW_VRAM:-1}"
OFFLOAD="${OFFLOAD:-1}"

mkdir -p "$OUT_DIR/clips"

REF_IMGS="${TOBY_IMG},${LUNA_IMG},${PARK_IMG}"
GEN_DIR="result/reference_to_video"
mkdir -p "$GEN_DIR"

common_args=(
  --task_type reference_to_video
  --model_id "$MODEL_ID"
  --ref_imgs "$REF_IMGS"
  --duration "$CLIP_DURATION"
  --resolution "$RESOLUTION"
)

if [[ "$LOW_VRAM" == "1" ]]; then
  common_args+=(--low_vram)
fi
if [[ "$OFFLOAD" == "1" ]]; then
  common_args+=(--offload)
fi

prompts=(
  "Vertical 9:16 cinematic children's cartoon in a bright safe neighborhood puppy park. Toby, a golden puppy wearing a blue hoodie and red backpack, finds a red ball beside a playground swing. Luna, a cream puppy with a purple bandana, is not yet in frame. Smooth natural puppy movement, expressive face, no text, no watermark."
  "Vertical 9:16 animated kids cartoon. Luna, a cream puppy with a purple bandana, joins Toby near the swing and notices a small name tag on the red ball. Toby listens thoughtfully. Colorful playground, friendly daylight, coherent character proportions, smooth motion, no text."
  "Vertical 9:16 cinematic cartoon. Toby holds the red ball gently and decides they should find its owner. Luna nods supportively. Warm park background, soft camera movement, clear body language, wholesome tone, no text or logo."
  "Vertical 9:16 children's animation. Toby and Luna walk together through the park asking kindly about the lost red ball. The red ball remains visible, puppies move naturally, grass and benches in background, smooth continuous motion."
  "Vertical 9:16 animated puppy adventure. Toby and Luna search near park benches and playground paths, looking attentive and kind. The scene remains bright, safe, cheerful, with gentle camera tracking and no scary elements."
  "Vertical 9:16 wholesome cartoon. Toby and Luna find the child owner of the red ball in the park. Keep the child generic and safe, focus on the puppies and the red ball. Happy discovery moment, natural movement, no text."
  "Vertical 9:16 cinematic kids cartoon. Toby smiles and returns the red ball politely while Luna stands proudly beside him. Warm emotional moment, bright park, expressive puppy animation, no text or watermark."
  "Vertical 9:16 joyful ending. Toby and Luna play happily together in the sunny puppy park after doing the right thing. Red ball bouncing gently, smooth motion, cheerful safe children's cartoon style, no text."
)

clip_paths=()
for i in "${!prompts[@]}"; do
  scene_num=$(printf "%02d" "$((i + 1))")
  seed_for_scene=$((SEED + i))
  before_file_list=$(mktemp)
  after_file_list=$(mktemp)
  find "$GEN_DIR" -maxdepth 1 -type f -name '*.mp4' -printf '%T@ %p\n' | sort > "$before_file_list" || true

  echo "Generating EP0002 scene ${scene_num} with seed ${seed_for_scene}..."
  python3 generate_video.py "${common_args[@]}" \
    --seed "$seed_for_scene" \
    --prompt "${prompts[$i]}"

  find "$GEN_DIR" -maxdepth 1 -type f -name '*.mp4' -printf '%T@ %p\n' | sort > "$after_file_list" || true
  new_clip=$(comm -13 "$before_file_list" "$after_file_list" | tail -n 1 | cut -d' ' -f2-)
  rm -f "$before_file_list" "$after_file_list"

  if [[ -z "${new_clip:-}" || ! -f "$new_clip" ]]; then
    echo "Could not find generated clip for scene ${scene_num}" >&2
    exit 1
  fi

  target="$OUT_DIR/clips/ep0002_scene_${scene_num}.mp4"
  cp "$new_clip" "$target"
  clip_paths+=("$target")
  echo "Scene ${scene_num} saved to ${target}"
done

concat_file="$OUT_DIR/concat.txt"
: > "$concat_file"
for clip in "${clip_paths[@]}"; do
  printf "file '%s'\n" "$(realpath "$clip")" >> "$concat_file"
done

silent_master="$OUT_DIR/ep0002_skyreels_silent_60s.mp4"
ffmpeg -y -f concat -safe 0 -i "$concat_file" \
  -t 60 \
  -c:v libx264 -preset veryfast -crf 18 -pix_fmt yuv420p -r 24 \
  "$silent_master"

final_master="$OUT_DIR/ep0002_skyreels_master_60s.mp4"
if [[ -n "${AUDIO_WAV:-}" && -f "$AUDIO_WAV" ]]; then
  if [[ -n "${SUBTITLES_SRT:-}" && -f "$SUBTITLES_SRT" ]]; then
    ffmpeg -y -i "$silent_master" -i "$AUDIO_WAV" \
      -vf "subtitles='${SUBTITLES_SRT}':force_style='FontSize=12,BorderStyle=1,Outline=2,Alignment=2,MarginV=80'" \
      -c:v libx264 -preset veryfast -crf 18 \
      -c:a aac -b:a 128k -shortest "$final_master"
  else
    ffmpeg -y -i "$silent_master" -i "$AUDIO_WAV" \
      -c:v copy -c:a aac -b:a 128k -shortest "$final_master"
  fi
else
  cp "$silent_master" "$final_master"
fi

ffprobe -v error -show_entries format=duration:stream=index,codec_type,width,height,avg_frame_rate \
  -of json "$final_master"

echo "EP0002 SkyReels master ready: $final_master"
