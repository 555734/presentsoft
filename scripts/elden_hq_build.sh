#!/usr/bin/env bash
set -euo pipefail
mkdir -p pack/video pack/audio pack/audit/frames pack/meta render

PIPED=(
  'https://pipedapi.kavin.rocks'
  'https://pipedapi.syncpundit.io'
  'https://api-piped.mha.fi'
  'https://piped-api.garudalinux.org'
)
INVIDIOUS=(
  'https://inv.nadeko.net'
  'https://invidious.nerdvpn.de'
  'https://yt.chocolatemoo53.com'
  'https://invidious.tiekoetter.com'
)

proxy_fetch() {
  label="$1"; id="$2"
  echo "===== $label $id ====="
  rm -f "pack/video/${label}_src"* "pack/video/${label}.mp4" 2>/dev/null || true

  # Piped gives proxied YouTube source streams. Select 720p-1080p video-only stream.
  for base in "${PIPED[@]}"; do
    api="$base/streams/$id"
    echo "PIPED $api"
    if curl -fsSL --connect-timeout 8 --max-time 35 "$api" -o /tmp/streams.json; then
      url=$(jq -r '[.videoStreams[]? | select((.height // 0) >= 720 and (.height // 0) <= 1080)] | sort_by(.height,.bitrate) | reverse | .[0].url // empty' /tmp/streams.json)
      height=$(jq -r '[.videoStreams[]? | select((.height // 0) >= 720 and (.height // 0) <= 1080)] | sort_by(.height,.bitrate) | reverse | .[0].height // 0' /tmp/streams.json)
      if [ -n "$url" ]; then
        echo "Piped chose ${height}p"
        if curl -fL --retry 3 --retry-delay 1 --connect-timeout 10 --max-time 300 "$url" -o "pack/video/${label}_src.bin"; then
          if ffprobe -v error -select_streams v:0 -show_entries stream=width,height -of json "pack/video/${label}_src.bin" > "pack/meta/${label}_probe.json"; then
            realh=$(jq -r '.streams[0].height // 0' "pack/meta/${label}_probe.json")
            if [ "$realh" -ge 720 ]; then
              ffmpeg -y -loglevel error -i "pack/video/${label}_src.bin" -an -vf "scale='min(1920,iw)':-2,fps=30" -c:v libx264 -preset fast -crf 18 -pix_fmt yuv420p "pack/video/${label}.mp4"
              rm -f "pack/video/${label}_src.bin"
              echo "OK $label from Piped ${realh}p"
              return 0
            fi
          fi
        fi
      fi
    fi
  done

  # Invidious fallback: still the original YouTube adaptive stream, not a re-upload.
  for base in "${INVIDIOUS[@]}"; do
    api="$base/api/v1/videos/$id"
    echo "INVIDIOUS $api"
    if curl -fsSL --connect-timeout 8 --max-time 35 "$api" -o /tmp/video.json; then
      url=$(jq -r '[.adaptiveFormats[]? | select((.height // 0) >= 720 and (.height // 0) <= 1080 and ((.type // "") | startswith("video/")))] | sort_by(.height,.bitrate) | reverse | .[0].url // empty' /tmp/video.json)
      height=$(jq -r '[.adaptiveFormats[]? | select((.height // 0) >= 720 and (.height // 0) <= 1080 and ((.type // "") | startswith("video/")))] | sort_by(.height,.bitrate) | reverse | .[0].height // 0' /tmp/video.json)
      if [ -n "$url" ]; then
        echo "Invidious chose ${height}p"
        if curl -fL --retry 3 --retry-delay 1 --connect-timeout 10 --max-time 300 "$url" -o "pack/video/${label}_src.bin"; then
          if ffprobe -v error -select_streams v:0 -show_entries stream=width,height -of json "pack/video/${label}_src.bin" > "pack/meta/${label}_probe.json"; then
            realh=$(jq -r '.streams[0].height // 0' "pack/meta/${label}_probe.json")
            if [ "$realh" -ge 720 ]; then
              ffmpeg -y -loglevel error -i "pack/video/${label}_src.bin" -an -vf "scale='min(1920,iw)':-2,fps=30" -c:v libx264 -preset fast -crf 18 -pix_fmt yuv420p "pack/video/${label}.mp4"
              rm -f "pack/video/${label}_src.bin"
              echo "OK $label from Invidious ${realh}p"
              return 0
            fi
          fi
        fi
      fi
    fi
  done
  rm -f "pack/video/${label}_src.bin"
  echo "FAILED $label"
  return 1
}

# Exact real gameplay YouTube IDs, not fan-made replacement art.
proxy_fetch hoarfrost_a 'QmHaTKNbVZ4' || true
proxy_fetch hoarfrost_b 'Ul7WYPGScjc' || true
proxy_fetch hoarfrost_c 'HMXSuYYXUXE' || true

proxy_fetch mimic_a 'f6VB0oxVmXA' || true
proxy_fetch mimic_b '1NPbxONMdxM' || true
proxy_fetch mimic_c '0qKN2J-uoJI' || true

# Prefer non-age-restricted real gameplay mirrors of LMSH/Malenia.
proxy_fetch lmsh_a '1cE-2nFhKpo' || true
proxy_fetch lmsh_b 'QKUlaYOaAAM' || true
proxy_fetch lmsh_c 'r8doNBHE7PQ' || true

proxy_fetch wall_a 'i-bAE7axvVE' || true
proxy_fetch wall_b '4t52LiFq85I' || true
proxy_fetch wall_c '1kyHFATAS3I' || true

# Official high-quality Elden Ring footage only for opening transitions.
curl -fL --retry 4 'https://video.fastly.steamstatic.com/store_trailers/1245620/377844/2912096cfadf6d63b7a35b7e7bc4e488c91cb31e/1750649918/microtrailer.mp4' -o pack/video/official_a.mp4
curl -fL --retry 4 'https://video.fastly.steamstatic.com/store_trailers/1245620/442816/aa7a26b8b7da66bf324ce24555fe0848d4650711/1750650397/microtrailer.mp4' -o pack/video/official_b.mp4

# Quality guardrail: don't make the video unless each topic has real 720p+ footage.
for p in hoarfrost mimic lmsh wall; do
  n=$(find pack/video -maxdepth 1 -name "${p}_*.mp4" | wc -l)
  echo "$p count=$n"
  test "$n" -ge 1
 done

# Visual audit sheet.
for f in pack/video/*.mp4; do
  b=$(basename "$f" .mp4)
  d=$(ffprobe -v error -show_entries format=duration -of csv=p=0 "$f")
  for frac in .12 .33 .55 .77; do
    t=$(python3 -c 'import sys; print(max(.1,float(sys.argv[1])*float(sys.argv[2])))' "$d" "$frac")
    ffmpeg -y -loglevel error -ss "$t" -i "$f" -frames:v 1 -vf 'scale=320:-2' "pack/audit/frames/${b}_${frac}.jpg" || true
  done
done
ffmpeg -y -loglevel error -pattern_type glob -i 'pack/audit/frames/*.jpg' -vf 'scale=320:-2,tile=4x20:padding=4:margin=4' -frames:v 1 pack/audit/contact_sheet.jpg

# Actual VOICEVOX engine, Shikoku Metan Normal = speaker 2.
docker rm -f voicevox >/dev/null 2>&1 || true
docker pull voicevox/voicevox_engine:cpu-latest
docker run -d --name voicevox -p 127.0.0.1:50021:50021 voicevox/voicevox_engine:cpu-latest
for i in $(seq 1 120); do curl -fsS http://127.0.0.1:50021/version >/dev/null && break || sleep 2; done
curl -fsS http://127.0.0.1:50021/speakers > pack/meta/voicevox_speakers.json
jq '.[] | select(.name=="四国めたん")' pack/meta/voicevox_speakers.json

python3 - <<'PY'
import json, urllib.parse, urllib.request
lines=[
('intro','エルデンリング、発売初期の狂気がヤバい。2022年、世界中で大ヒットしたこのゲームですが、初期環境は本当にめちゃくちゃでした。'),
('hoarfrost','まず猛威を振るったのが戦技、霜踏み。地面を踏むだけで広範囲に大ダメージ。強敵までみるみる溶けて、発売直後は足をバタバタ踏む褪せ人が大量発生しました。'),
('mimic','さらに写し身の雫。自分とほぼ同じ装備の分身を呼べるため、本人が後ろで見ている間に、分身だけでボスを倒してしまう光景まで普通に発生。'),
('lmsh','そしてマレニア前に現れた伝説が、レット・ミー・ソロ・ハー。壺をかぶったほぼ裸の姿で、他人の世界のマレニアを何度も一人で撃破。世界的な英雄になり、後にはバンダイナムコから記念品として実物の剣まで贈られました。'),
('wall','極めつけは、火山館で見つかった異常に硬い隠し壁。普通の壁なら一撃なのに、これは何十回も殴ると消える。嘘メッセージを疑っていた褪せ人たちに、本当に壁を殴り続ける理由が生まれてしまいました。ちなみにこれはアップデートで追加された壁ではなく、発売初期から存在し、後のパッチで修正されています。')]
for key,text in lines:
    q='http://127.0.0.1:50021/audio_query?'+urllib.parse.urlencode({'text':text,'speaker':2})
    obj=json.load(urllib.request.urlopen(urllib.request.Request(q,method='POST')))
    obj['speedScale']=1.30; obj['intonationScale']=1.04; obj['volumeScale']=1.0
    req=urllib.request.Request('http://127.0.0.1:50021/synthesis?speaker=2',data=json.dumps(obj,ensure_ascii=False).encode(),headers={'Content-Type':'application/json'},method='POST')
    open(f'pack/audio/{key}.wav','wb').write(urllib.request.urlopen(req).read())
PY

python3 scripts/render_elden_hq.py
ffprobe -v error -show_entries format=duration,size -show_entries stream=codec_name,width,height -of json pack/ELDEN_RING_launch_chaos_HQ_Metan.mp4
