#!/usr/bin/env bash
set -euo pipefail

# EP0002 Wan2.2 TI2V runner.
# Goal: generate real video motion with a 24 GB-class GPU before spending on larger models.

: "${TOBY_IMG:?Set TOBY_IMG to Toby reference image path}"
: "${LUNA_IMG:?Set LUNA_IMG to Luna reference image path}"
: "${PARK_IMG:?Set PARK_IMG to park reference image path}"

WAN_DIR="${WAN_DIR:-/workspace/Wan2.2}"
WAN_REPO_URL="${WAN_REPO_URL:-https://github.com/Wan-Video/Wan2.2.git}"
OUT_DIR="${OUT_DIR:-result/ep0002_wan}"
CKPT_DIR="${CKPT_DIR:-${WAN_DIR}/Wan2.2-TI2V-5B}"
MODEL_ID="${MODEL_ID:-Wan-AI/Wan2.2-TI2V-5B}"
TASK="${TASK:-ti2v-5B}"
SIZE="${SIZE:-1280*704}"
MAX_SCENES="${MAX_SCENES:-1}"
SEED="${SEED:-20260928}"
DOWNLOAD_MODEL="${DOWNLOAD_MODEL:-0}"
OFFLOAD_MODEL="${OFFLOAD_MODEL:-True}"
CONVERT_MODEL_DTYPE="${CONVERT_MODEL_DTYPE:-1}"
T5_CPU="${T5_CPU:-1}"
AUDIO_WAV="${AUDIO_WAV:-}"
SUBTITLES_SRT="${SUBTITLES_SRT:-}"

if ! [[ "$MAX_SCENES" =~ ^[0-9]+$ ]] || [ "$MAX_SCENES" -lt 1 ] || [ "$MAX_SCENES" -gt 8 ]; then
  echo "MAX_SCENES must be an integer from 1 to 8. Current value: $MAX_SCENES" >&2
  exit 2
fi

for asset in "$TOBY_IMG" "$LUNA_IMG" "$PARK_IMG"; do
  if [ ! -f "$asset" ]; then
    echo "Missing asset: $asset" >&2
    exit 2
  fi
done

mkdir -p "$OUT_DIR/clips"

if [ ! -d "$WAN_DIR" ]; then
  echo "Cloning Wan2.2 into $WAN_DIR"
  git clone --depth 1 "$WAN_REPO_URL" "$WAN_DIR"
fi

if [ ! -f "$WAN_DIR/generate.py" ]; then
  echo "Wan generate.py not found under $WAN_DIR" >&2
  exit 2
fi

if [ ! -d "$CKPT_DIR" ]; then
  if [ "$DOWNLOAD_MODEL" = "1" ]; then
    echo "Downloading $MODEL_ID to $CKPT_DIR"
    python3 -m pip install -q "huggingface_hub[cli]"
    huggingface-cli download "$MODEL_ID" --local-dir "$CKPT_DIR"
  else
    echo "Model checkpoint not found: $CKPT_DIR" >&2
    echo "Set DOWNLOAD_MODEL=1 to fetch it, or set CKPT_DIR to an existing Wan2.2-TI2V-5B directory." >&2
    exit 2
  fi
fi

REFERENCE_BOARD="$OUT_DIR/ep0002_wan_reference_board.png"
python3 - "$TOBY_IMG" "$LUNA_IMG" "$PARK_IMG" "$REFERENCE_BOARD" <<'PY'
import sys
from pathlib import Path
try:
    from PIL import Image, ImageOps
except Exception as exc:
    raise SystemExit(f"Pillow is required to build the reference board: {exc}")

toby_path, luna_path, park_path, out_path = map(Path, sys.argv[1:5])
W, H = 1280, 704
park = Image.open(park_path).convert("RGB")
park = ImageOps.fit(park, (W, H), method=Image.Resampling.LANCZOS)
canvas = park.convert("RGBA")

def paste_character(path, box):
    img = Image.open(path).convert("RGBA")
    img.thumbnail((box[2] - box[0], box[3] - box[1]), Image.Resampling.LANCZOS)
    x = box[0] + ((box[2] - box[0]) - img.width) // 2
    y = box[3] - img.height
    canvas.alpha_composite(img, (x, y))

paste_character(toby_path, (110, 215, 500, 680))
paste_character(luna_path, (780, 215, 1170, 680))
canvas.convert("RGB").save(out_path, quality=95)
print(out_path)
PY

PROMPTS=(
"A bright 3D animated children's cartoon in a neighborhood puppy park. Toby, a golden puppy with a red backpack, and Luna, a cream puppy with a purple bandana, run into the park with joyful natural motion. Smooth camera dolly, wagging tails, playful expressions, colorful morning light, cinematic animation, kid-safe, coherent characters."
"Toby opens his red backpack and finds a small lost toy car near the playground. Luna sniffs the grass and points toward tiny pawprints. The puppies move naturally, ears bouncing, soft camera pan, bright cheerful park, fluent animation, no text, no logos."
"The puppies follow the pawprints around a sandbox and under a bench. Toby looks curious and Luna smiles with confidence. Gentle tracking shot, lively body movement, expressive faces, consistent golden and cream puppies, colorful 3D cartoon style."
"A small shy puppy appears behind flowers, worried about the missing toy. Toby and Luna approach kindly and slow down. Warm emotional beat, subtle head tilts, natural blinking, smooth motion, bright family-friendly animation."
"Toby, Luna, and the shy puppy search together near the slide. Leaves move in the breeze, the puppies trot and look around with coordinated motion. Playful adventure mood, clean 3D animation, stable characters, no cuts inside the shot."
"Luna spots the toy car beside a tree root. Toby carefully picks it up with excitement while the shy puppy jumps happily. Smooth camera push-in, expressive puppy faces, joyful motion, bright park background, kid-safe cartoon."
"The puppies return the toy and celebrate with a small dance in the park. Toby's red backpack bounces, Luna's purple bandana flutters, everyone moves fluently. Colorful 3D animation, warm sunlight, coherent character design."
"Final happy scene: Toby and Luna wave goodbye at the park gate after helping their new friend. Gentle cinematic pullback, tails wagging, soft smiles, smooth natural animation, bright children's cartoon ending."
)

pushd "$WAN_DIR" >/dev/null

for idx in $(seq 1 "$MAX_SCENES"); do
  prompt="${PROMPTS[$((idx-1))]}"
  clip_out="$(realpath "${OLDPWD}/${OUT_DIR}/clips/ep0002_wan_scene_$(printf '%02d' "$idx").mp4")"
  before_list="$(mktemp)"
  after_list="$(mktemp)"
  find . -type f -name '*.mp4' -print | sort > "$before_list"

  cmd=(python3 generate.py --task "$TASK" --size "$SIZE" --ckpt_dir "$CKPT_DIR" --image "$(realpath "${OLDPWD}/${REFERENCE_BOARD}")" --prompt "$prompt")
  if [ "$OFFLOAD_MODEL" = "True" ] || [ "$OFFLOAD_MODEL" = "true" ] || [ "$OFFLOAD_MODEL" = "1" ]; then
    cmd+=(--offload_model True)
  fi
  if [ "$CONVERT_MODEL_DTYPE" = "1" ]; then
    cmd+=(--convert_model_dtype)
  fi
  if [ "$T5_CPU" = "1" ]; then
    cmd+=(--t5_cpu)
  fi
  if python3 generate.py --help 2>/dev/null | grep -q -- '--base_seed'; then
    cmd+=(--base_seed "$((SEED + idx))")
  fi

  echo "Generating Wan EP0002 scene $idx/$MAX_SCENES"
  "${cmd[@]}"

  find . -type f -name '*.mp4' -print | sort > "$after_list"
  new_file="$(comm -13 "$before_list" "$after_list" | tail -n 1)"
  rm -f "$before_list" "$after_list"
  if [ -z "$new_file" ]; then
    new_file="$(find . -type f -name '*.mp4' -printf '%T@ %p\n' | sort -n | tail -n 1 | cut -d' ' -f2-)"
  fi
  if [ -z "$new_file" ] || [ ! -f "$new_file" ]; then
    echo "Could not locate generated MP4 for scene $idx" >&2
    exit 3
  fi
  cp "$new_file" "$clip_out"
done

popd >/dev/null

CONCAT_LIST="$OUT_DIR/concat.txt"
: > "$CONCAT_LIST"
for clip in "$OUT_DIR"/clips/ep0002_wan_scene_*.mp4; do
  printf "file '%s'\n" "$(realpath "$clip")" >> "$CONCAT_LIST"
done

if [ "$MAX_SCENES" -lt 8 ]; then
  STEM="ep0002_wan_smoke_${MAX_SCENES}_scene"
else
  STEM="ep0002_wan_60s"
fi

SILENT_MASTER="$OUT_DIR/${STEM}_silent.mp4"
FINAL_MASTER="$OUT_DIR/${STEM}_master.mp4"

ffmpeg -y -f concat -safe 0 -i "$CONCAT_LIST" -c copy "$SILENT_MASTER"

if [ -n "$AUDIO_WAV" ] && [ -f "$AUDIO_WAV" ] && [ "$MAX_SCENES" -eq 8 ]; then
  ffmpeg -y -i "$SILENT_MASTER" -i "$AUDIO_WAV" -t 60 -map 0:v:0 -map 1:a:0 -c:v copy -c:a aac -shortest "$FINAL_MASTER"
else
  cp "$SILENT_MASTER" "$FINAL_MASTER"
fi

if [ -n "$SUBTITLES_SRT" ] && [ -f "$SUBTITLES_SRT" ] && [ "$MAX_SCENES" -eq 8 ]; then
  SUB_MASTER="$OUT_DIR/${STEM}_subtitled.mp4"
  ffmpeg -y -i "$FINAL_MASTER" -vf "subtitles=${SUBTITLES_SRT}" -c:a copy "$SUB_MASTER"
  FINAL_MASTER="$SUB_MASTER"
fi

ffprobe -hide_banner "$FINAL_MASTER"
echo "EP0002 Wan output: $FINAL_MASTER"
