#!/usr/bin/env bash
set -euo pipefail
mkdir -p pack/video pack/audio pack/audit/frames pack/meta render

python3 -m pip install --break-system-packages -U yt-dlp bgutil-ytdlp-pot-provider

docker rm -f bgutil-provider >/dev/null 2>&1 || true
docker run --name bgutil-provider -d --init -p 127.0.0.1:4416:4416 brainicism/bgutil-ytdlp-pot-provider:latest
sleep 5
docker logs --tail 30 bgutil-provider || true

ytdlp_fetch() {
  label="$1"; url="$2"
  echo "===== $label ====="
  rm -f "pack/video/${label}."* "pack/video/${label}_src."* 2>/dev/null || true
  yt-dlp -v --no-playlist \
    --extractor-args 'youtube:player_client=mweb' \
    -f 'bv*[height<=1080][height>=720]+ba/b[height<=1080][height>=720]/bv*[height<=1080]+ba/b[height<=1080]' \
    --merge-output-format mp4 \
    -o "pack/video/${label}_src.%(ext)s" "$url" || return 1
  src=$(find pack/video -maxdepth 1 -type f -name "${label}_src.*" | head -1)
  [ -n "$src" ] || return 1
  ffprobe -v error -select_streams v:0 -show_entries stream=width,height -of json "$src" > "pack/meta/${label}_probe.json" || return 1
  ffmpeg -y -loglevel error -i "$src" -an -vf "scale='min(1920,iw)':-2,fps=30" -c:v libx264 -preset fast -crf 18 -pix_fmt yuv420p "pack/video/${label}.mp4"
  rm -f "$src"
}

ytdlp_fetch hoarfrost_a 'https://www.youtube.com/watch?v=QmHaTKNbVZ4' || true
ytdlp_fetch hoarfrost_b 'https://www.youtube.com/watch?v=Ul7WYPGScjc' || true
ytdlp_fetch hoarfrost_c 'https://www.youtube.com/watch?v=HMXSuYYXUXE' || true

ytdlp_fetch mimic_a 'https://www.youtube.com/watch?v=f6VB0oxVmXA' || true
ytdlp_fetch mimic_b 'https://www.youtube.com/watch?v=1NPbxONMdxM' || true
ytdlp_fetch mimic_c 'https://www.youtube.com/watch?v=0qKN2J-uoJI' || true

ytdlp_fetch lmsh_a 'https://www.youtube.com/watch?v=1cE-2nFhKpo' || true
ytdlp_fetch lmsh_b 'https://www.youtube.com/watch?v=QKUlaYOaAAM' || true
ytdlp_fetch lmsh_c 'https://www.youtube.com/watch?v=IqN2phpMWno' || true

ytdlp_fetch wall_a 'https://www.youtube.com/watch?v=i-bAE7axvVE' || true
ytdlp_fetch wall_b 'https://www.youtube.com/watch?v=4t52LiFq85I' || true
ytdlp_fetch wall_c 'https://www.youtube.com/watch?v=1kyHFATAS3I' || true

curl -fL --retry 4 'https://video.fastly.steamstatic.com/store_trailers/1245620/377844/2912096cfadf6d63b7a35b7e7bc4e488c91cb31e/1750649918/microtrailer.mp4' -o pack/video/official_a.mp4
curl -fL --retry 4 'https://video.fastly.steamstatic.com/store_trailers/1245620/442816/aa7a26b8b7da66bf324ce24555fe0848d4650711/1750650397/microtrailer.mp4' -o pack/video/official_b.mp4

for p in hoarfrost mimic lmsh wall; do
  n=$(find pack/video -maxdepth 1 -name "${p}_*.mp4" | wc -l)
  echo "$p count=$n"
  test "$n" -ge 2
 done

for f in pack/video/*.mp4; do
  b=$(basename "$f" .mp4)
  d=$(ffprobe -v error -show_entries format=duration -of csv=p=0 "$f")
  for frac in .12 .33 .55 .77; do
    t=$(python3 -c 'import sys; print(max(.1,float(sys.argv[1])*float(sys.argv[2])))' "$d" "$frac")
    ffmpeg -y -loglevel error -ss "$t" -i "$f" -frames:v 1 -vf 'scale=320:-2' "pack/audit/frames/${b}_${frac}.jpg" || true
  done
done
ffmpeg -y -loglevel error -pattern_type glob -i 'pack/audit/frames/*.jpg' -vf 'scale=320:-2,tile=4x20:padding=4:margin=4' -frames:v 1 pack/audit/contact_sheet.jpg

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
