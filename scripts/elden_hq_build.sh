#!/usr/bin/env bash
set -euo pipefail
mkdir -p pack/video pack/audio pack/audit/frames pack/meta render

# Current public Piped API instances from TeamPiped's maintained instance list.
PIPED=(
  'https://pipedapi.kavin.rocks'
  'https://pipedapi.leptons.xyz'
  'https://pipedapi.nosebs.ru'
  'https://pipedapi-libre.kavin.rocks'
  'https://pipedapi.adminforge.de'
  'https://api.piped.yt'
  'https://pipedapi.drgns.space'
  'https://piped-api.codespace.cz'
  'https://api.piped.private.coffee'
)

fetch_clip() {
  label="$1"; id="$2"; start="$3"; length="$4"
  echo "===== $label $id ====="
  for api in "${PIPED[@]}"; do
    echo "TRY $api"
    if curl -fsSL --connect-timeout 4 --max-time 9 "$api/streams/$id" -o "/tmp/${label}.json"; then
      url=$(jq -r '[.videoStreams[]? | select((.height // 0) >= 720 and (.height // 0) <= 1080)] | sort_by(.height,.bitrate) | reverse | .[0].url // empty' "/tmp/${label}.json")
      if [ -n "$url" ]; then
        # Read only the useful source interval; do not download/transcode the full source video.
        if ffmpeg -y -loglevel error -ss "$start" -i "$url" -t "$length" -an -vf "scale='min(1280,iw)':-2,fps=30" -c:v libx264 -preset veryfast -crf 18 -pix_fmt yuv420p "pack/video/${label}.mp4"; then
          ffprobe -v error -select_streams v:0 -show_entries stream=width,height -of json "pack/video/${label}.mp4" > "pack/meta/${label}_probe.json"
          h=$(jq -r '.streams[0].height // 0' "pack/meta/${label}_probe.json")
          if [ "$h" -ge 720 ]; then echo "OK $label ${h}p via $api"; return 0; fi
        fi
      fi
    fi
  done
  rm -f "pack/video/${label}.mp4"
  echo "FAILED $label"
  return 1
}

# One high-quality, topic-specific real gameplay source per section.
# These are YouTube source streams obtained through Piped, not re-uploads to Dailymotion.
fetch_clip hoarfrost 'gXoEiA36bvM' 4 42 & p1=$!
fetch_clip mimic     'naANQ9xjFfk' 4 42 & p2=$!
fetch_clip lmsh      'HoSRJJ4Popk' 4 42 & p3=$!
fetch_clip wall      'k-ffeG4S4as' 2 42 & p4=$!

fail=0
wait "$p1" || fail=1
wait "$p2" || fail=1
wait "$p3" || fail=1
wait "$p4" || fail=1
test "$fail" -eq 0

# Opening only: official Steam-hosted Elden Ring footage.
curl -fsSL --retry 3 'https://video.fastly.steamstatic.com/store_trailers/1245620/377844/2912096cfadf6d63b7a35b7e7bc4e488c91cb31e/1750649918/microtrailer.mp4' -o pack/video/official_a.mp4
curl -fsSL --retry 3 'https://video.fastly.steamstatic.com/store_trailers/1245620/442816/aa7a26b8b7da66bf324ce24555fe0848d4650711/1750650397/microtrailer.mp4' -o pack/video/official_b.mp4

# Audit: four frames from every accepted gameplay clip.
for f in pack/video/*.mp4; do
  b=$(basename "$f" .mp4)
  d=$(ffprobe -v error -show_entries format=duration -of csv=p=0 "$f")
  for frac in .15 .35 .60 .82; do
    t=$(python3 -c 'import sys; print(max(.1,float(sys.argv[1])*float(sys.argv[2])))' "$d" "$frac")
    ffmpeg -y -loglevel error -ss "$t" -i "$f" -frames:v 1 -vf 'scale=320:-2' "pack/audit/frames/${b}_${frac}.jpg"
  done
done
ffmpeg -y -loglevel error -pattern_type glob -i 'pack/audit/frames/*.jpg' -vf 'scale=320:-2,tile=4x8:padding=4:margin=4' -frames:v 1 pack/audit/contact_sheet.jpg

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
