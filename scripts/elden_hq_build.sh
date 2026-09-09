#!/usr/bin/env bash
set -euo pipefail
rm -rf pack render
mkdir -p pack/video pack/audio pack/audit/frames pack/meta pack/stills render

python3 -m pip install --break-system-packages -q -U yt-dlp pillow

# Never use Dailymotion. Keep gameplay at native 720p+; do not pre-shrink it.
dl_video(){
  local name="$1" url="$2" section="$3"
  echo "=== DOWNLOAD $name ==="
  yt-dlp --no-playlist --download-sections "$section" --force-keyframes-at-cuts \
    -f 'bv*[height>=720][height<=1080]+ba/b[height>=720][height<=1080]/bv*[height<=1080]+ba/b[height<=1080]' \
    --merge-output-format mp4 -o "pack/video/${name}.%(ext)s" "$url"
  local f
  f=$(find pack/video -maxdepth 1 -type f -name "${name}.*" | head -1)
  [ -n "$f" ] && [ -s "$f" ]
  [ "$f" = "pack/video/${name}.mp4" ] || mv "$f" "pack/video/${name}.mp4"
  ffprobe -v error -show_entries stream=codec_name,width,height,r_frame_rate -show_entries format=duration,size -of json "pack/video/${name}.mp4" > "pack/meta/${name}_probe.json"
}

# Opening: official Steam-hosted full trailers, using the max MP4 URLs from Steam's API.
steam_json=$(curl -fsSL -A 'Mozilla/5.0' 'https://store.steampowered.com/api/appdetails?appids=1245620&l=english')
mapfile -t MOVIES < <(printf '%s' "$steam_json" | jq -r '."1245620".data.movies[]?.mp4.max // empty' | head -3)
idx=0
for u in "${MOVIES[@]}"; do
  idx=$((idx+1))
  curl -fL --retry 4 --connect-timeout 10 --max-time 240 -A 'Mozilla/5.0' "$u" -o "pack/video/official_${idx}.mp4"
  ffprobe -v error -show_entries stream=codec_name,width,height,r_frame_rate -show_entries format=duration,size -of json "pack/video/official_${idx}.mp4" > "pack/meta/official_${idx}_probe.json"
done
[ "$idx" -ge 1 ]

# Topic-matched real gameplay. These are 720p source clips; no Dailymotion, no generated gameplay.
dl_video hoarfrost_01 'https://streamable.com/3yq05h' '*0-95'
dl_video mimic_01 'https://rutube.ru/video/f6f4c594abf9716058e985629f0f7719/' '*125-300'
dl_video lmsh_01 'https://rutube.ru/video/7d5b11cff06ac780a050659390188fa8/' '*40-210'

# High-resolution verified screenshots for extra cuts and the real-world sword gift.
get_still(){
  local name="$1" url="$2"
  curl -fL --retry 4 --connect-timeout 10 --max-time 90 -A 'Mozilla/5.0' "$url" -o "pack/stills/${name}.img"
  ffprobe -v error -show_entries stream=width,height -of json "pack/stills/${name}.img" > "pack/meta/${name}_still_probe.json" || true
  # Animate the still rather than holding one frame. 1280x720 master, slow push-in.
  ffmpeg -y -loglevel error -loop 1 -i "pack/stills/${name}.img" -t 18 -r 30 \
    -vf "scale=1400:800:force_original_aspect_ratio=increase,crop=1400:800,zoompan=z='min(zoom+0.0008,1.10)':x='iw/2-(iw/zoom/2)':y='ih/2-(ih/zoom/2)':d=540:s=1280x720:fps=30,eq=contrast=1.04:saturation=1.06" \
    -an -c:v libx264 -preset fast -crf 15 -pix_fmt yuv420p "pack/video/${name}.mp4"
}
get_still hoarfrost_02 'https://d.ibtimes.com/en/full/3439034/hoarfrost-stomp-great-both-pve-pvp-elden-ring.png'
get_still mimic_02 'https://cdn.mos.cms.futurecdn.net/ktbpFCzLzStTrJJE893oXn.jpg'
get_still lmsh_02 'https://cdn-cf-east.streamable.com/image/anshdc.jpg?Expires=1772355879686&Key-Pair-Id=APKAIEYUVEN4EVB2OKEQ&Signature=gqbZ--B9kVnVnpC9eJIUXOUcEeQ7T4ka2hKNO-~hCl1bfFGvVXgZlzUW~kqIgdD80QGk~Nc9DWVOBbpDie93EbiZmZzr6lJQySk4kc1mLfkfNeuJWA3BviEMwlJkNaGLM~k8uodRAiupOCBsPMbzzCZvDu8~EQaPmHgjjdVT~7tUwBDL5juD-lBb2F~cvM9lAMdkyIr9D5kWj4wpl5QTK82Q3Aqtm04GiBueAq3o3GPMjBCpILuq2Cd6FnO2aVJY0TMT~MMih4R7UqCdOy9IkNWuvjJ0eD8EWWXN3Y67WMvOpvkXjjHBeNLw5bjjBVovSm5y4TNJLEf1I9y2MxAcrA__'
get_still lmsh_03 'https://static1-br.millenium.gg/articles/7/10/72/7/%40/127793-let-me-solo-her-ganhou-uma-espada-de-presente-da-bandai-namco-por-derrotar-malenia-1000-vezes-full-1.jpg'
get_still wall_01 'https://i.imgur.com/fWjkRga.jpeg'
get_still wall_02 'https://cdn.mos.cms.futurecdn.net/T2CXCULShtN7Y5hKYpyQxH.jpg'

# Reject obviously broken gameplay masters. Still-derived masters are 1280x720 by construction.
for f in pack/video/*.mp4; do
  b=$(basename "$f" .mp4)
  ffprobe -v error -show_entries stream=codec_name,width,height,r_frame_rate -show_entries format=duration,size -of json "$f" > "pack/meta/${b}_final_probe.json"
  w=$(ffprobe -v error -select_streams v:0 -show_entries stream=width -of csv=p=0 "$f" | head -1)
  h=$(ffprobe -v error -select_streams v:0 -show_entries stream=height -of csv=p=0 "$f" | head -1)
  echo "$b ${w}x${h}"
  [ "${w:-0}" -ge 960 ] || { echo "LOW RES $b"; exit 1; }
done

# Genuine VOICEVOX Engine / 四国めたん ノーマル.
docker rm -f voicevox >/dev/null 2>&1 || true
docker pull voicevox/voicevox_engine:cpu-ubuntu20.04-latest
docker run -d --name voicevox -p 127.0.0.1:50021:50021 voicevox/voicevox_engine:cpu-ubuntu20.04-latest
for i in $(seq 1 120); do
  if curl -fsS http://127.0.0.1:50021/version >/dev/null; then break; fi
  sleep 1
done
curl -fsS http://127.0.0.1:50021/speakers > pack/meta/voicevox_speakers.json
SPK=$(jq -r '[.[]|select(.name=="四国めたん")|.styles[]|select(.name=="ノーマル")][0].id' pack/meta/voicevox_speakers.json)
[ "$SPK" != "null" ] && [ -n "$SPK" ]
export SPK

python3 - <<'PY'
import json, os, urllib.parse, urllib.request
speaker=int(os.environ['SPK'])
lines=[
('intro','エルデンリング、発売初期の環境が狂いすぎていた。2022年の発売直後、何もかもがカオスでした。'),
('hoarfrost','まず猛威を振るったのが戦技、霜踏み。足を踏むだけで高火力と凍傷をばらまき、強敵までみるみる溶ける。世界中で謎の足踏みラッシュが発生しました。'),
('mimic','さらに写し身の雫。自分とほぼ同じ分身を呼べるため、本人が後ろで見ているだけで、分身がボスを殴り倒す光景まで続出。'),
('lmsh','そしてマレニア前には、壺をかぶった裸同然の男、レット・ミー・ソロ・ハーが出現。他人の世界でマレニアをほぼノーダメージで倒し続け、ついにはバンダイナムコから記念品と実物の剣まで贈られました。'),
('wall','さらに火山館では、普通の壁なのに何十回も殴ると消える謎の壁まで発見。これはアップデートで追加されたのではなく、発売初期から存在した不具合らしき壁で、後のアップデートで修正されました。')]
for key,text in lines:
    qurl='http://127.0.0.1:50021/audio_query?'+urllib.parse.urlencode({'text':text,'speaker':speaker})
    req=urllib.request.Request(qurl,method='POST')
    obj=json.load(urllib.request.urlopen(req,timeout=30))
    obj['speedScale']=1.34
    obj['intonationScale']=1.05
    obj['volumeScale']=1.0
    data=json.dumps(obj,ensure_ascii=False).encode('utf-8')
    req=urllib.request.Request(f'http://127.0.0.1:50021/synthesis?speaker={speaker}',data=data,headers={'Content-Type':'application/json'},method='POST')
    with open(f'pack/audio/{key}.wav','wb') as f: f.write(urllib.request.urlopen(req,timeout=120).read())
PY

python3 scripts/render_elden_hq.py

# Audit the actual final output and make a contact sheet from it.
ffprobe -v error -show_entries format=duration,size,bit_rate -show_entries stream=codec_name,width,height,r_frame_rate -of json pack/ELDEN_RING_launch_chaos_HQ_Metan.mp4 | tee pack/meta/final_probe.json
for t in 1 5 10 15 20 25 30 35 40 45 50 55 58; do
  ffmpeg -y -loglevel error -ss "$t" -i pack/ELDEN_RING_launch_chaos_HQ_Metan.mp4 -frames:v 1 -vf 'scale=270:-2' "pack/audit/frames/final_${t}.jpg"
done
ffmpeg -y -loglevel error -pattern_type glob -i 'pack/audit/frames/final_*.jpg' -vf 'scale=270:-2,tile=4x4:padding=4:margin=4' -frames:v 1 pack/audit/contact_sheet.jpg
