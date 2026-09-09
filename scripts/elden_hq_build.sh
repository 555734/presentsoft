#!/usr/bin/env bash
set -euo pipefail
mkdir -p pack/video pack/audio pack/audit/frames pack/meta pack/stills render

# High-resolution real-game imagery. No Dailymotion and no generated gameplay.
declare -A URLS
URLS[hoarfrost_01]='https://prod.assets.earlygamecdn.com/images/Elden-Ring-Guide-How-To-Get-The-Hoarfrost-Stomp-Ash-Of-War.jpg?mtime=1664787315'
URLS[hoarfrost_02]='https://d.ibtimes.com/en/full/3439034/hoarfrost-stomp-great-both-pve-pvp-elden-ring.png'
URLS[mimic_01]='https://cdn.mos.cms.futurecdn.net/ktbpFCzLzStTrJJE893oXn.jpg'
URLS[mimic_02]='https://assetsio.gnwcdn.com/elden-ring-malenia-2_Dv92W9u.png?auto=webp&fit=bounds&format=jpg&height=2048&quality=85&width=2048'
URLS[lmsh_01]='https://cdn.mos.cms.futurecdn.net/XNKFQ78byaq9QEv9JfqJGk.jpg'
URLS[lmsh_02]='https://static1-br.millenium.gg/articles/7/10/72/7/%40/127793-let-me-solo-her-ganhou-uma-espada-de-presente-da-bandai-namco-por-derrotar-malenia-1000-vezes-full-1.jpg'
URLS[wall_01]='https://cdn.mos.cms.futurecdn.net/T2CXCULShtN7Y5hKYpyQxH.jpg'
URLS[wall_02]='https://static1.millenium.org/articles/8/38/83/78/%40/1576452-passage-secret-article_cover_bd-1.jpg'

for key in "${!URLS[@]}"; do
  echo "DOWNLOAD $key"
  curl -fL --retry 4 --retry-delay 1 --connect-timeout 10 --max-time 60 -A 'Mozilla/5.0' "${URLS[$key]}" -o "pack/stills/$key.img"
  ffprobe -v error -show_entries stream=width,height -of json "pack/stills/$key.img" > "pack/meta/${key}_probe.json" || true
  ffmpeg -y -loglevel error -loop 1 -i "pack/stills/$key.img" -t 24 -r 30 \
    -vf "scale=1280:720:force_original_aspect_ratio=increase,crop=1280:720,eq=contrast=1.04:saturation=1.08" \
    -an -c:v libx264 -preset veryfast -crf 16 -pix_fmt yuv420p "pack/video/$key.mp4"
done

# Official Steam-hosted Elden Ring footage for the opening.
curl -fL --retry 4 'https://video.fastly.steamstatic.com/store_trailers/1245620/377844/2912096cfadf6d63b7a35b7e7bc4e488c91cb31e/1750649918/microtrailer.mp4' -o pack/video/official_a.mp4
curl -fL --retry 4 'https://video.fastly.steamstatic.com/store_trailers/1245620/442816/aa7a26b8b7da66bf324ce24555fe0848d4650711/1750650397/microtrailer.mp4' -o pack/video/official_b.mp4

# Visual audit sheet.
for f in pack/video/*.mp4; do
  b=$(basename "$f" .mp4)
  d=$(ffprobe -v error -show_entries format=duration -of csv=p=0 "$f")
  for frac in .18 .42 .68 .86; do
    t=$(python3 -c 'import sys; print(max(.1,float(sys.argv[1])*float(sys.argv[2])))' "$d" "$frac")
    ffmpeg -y -loglevel error -ss "$t" -i "$f" -frames:v 1 -vf 'scale=320:-2' "pack/audit/frames/${b}_${frac}.jpg"
  done
done
ffmpeg -y -loglevel error -pattern_type glob -i 'pack/audit/frames/*.jpg' -vf 'scale=320:-2,tile=4x10:padding=4:margin=4' -frames:v 1 pack/audit/contact_sheet.jpg || true

# Actual VOICEVOX Engine. 四国めたん ノーマル = speaker 2.
docker rm -f voicevox >/dev/null 2>&1 || true
docker pull voicevox/voicevox_engine:cpu-latest
docker run -d --name voicevox -p 127.0.0.1:50021:50021 voicevox/voicevox_engine:cpu-latest
for i in $(seq 1 90); do curl -fsS http://127.0.0.1:50021/version >/dev/null && break || sleep 2; done
curl -fsS http://127.0.0.1:50021/speakers > pack/meta/voicevox_speakers.json
jq -e '.[] | select(.name=="四国めたん") | .styles[] | select(.id==2)' pack/meta/voicevox_speakers.json >/dev/null

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
