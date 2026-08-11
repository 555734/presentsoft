#!/usr/bin/env python3
import csv, html, json, re, subprocess, time, urllib.parse, urllib.request
from pathlib import Path

API='https://commons.wikimedia.org/w/api.php'
UA='ControllerHistoryVideoLibrary/2.0 (documentary research; reusable Commons media)'
TARGET=1000
CLIPS_PER_SOURCE=4
MAX_SOURCE=60*1024*1024
OUT=Path('video_assets'); TMP=Path('video_tmp')
OUT.mkdir(exist_ok=True); TMP.mkdir(exist_ok=True)
for i in range(1,5): (OUT/f'part{i:02d}').mkdir(exist_ok=True)

CATEGORIES=[
 'Video game trailers',
 'Videos by Capcom France',
 'Videos by Xbox México',
 'Videos of video game gameplay',
 'Videos of gamepads',
 'Videos related to video games',
 'Videos of video game development',
 'Videos of video game designers',
]
KEYWORDS=(
 'nintendo','famicom','nes','snes','super nintendo','game boy','gamecube','wii','switch','joy-con',
 'sega','genesis','mega drive','dreamcast','saturn','game gear',
 'playstation','dualshock','dualsense','ps1','ps2','ps3','ps4','ps5','sony',
 'xbox','microsoft','controller','gamepad','joystick','console','arcade','gameplay','trailer'
)
VIDEO_EXTS=('.webm','.ogv','.ogg','.mp4','.mpeg','.mpg','.mov')

def clean(s):
    if not s: return ''
    s=re.sub(r'<[^>]+>',' ',str(s))
    return html.unescape(re.sub(r'\s+',' ',s)).strip()

def request_json(params, post=False, tries=10):
    p=dict(params); p.update({'format':'json','formatversion':'2','maxlag':'5'})
    data=urllib.parse.urlencode(p).encode()
    for n in range(tries):
        try:
            req=urllib.request.Request(API, data=data if post else None,
                headers={'User-Agent':UA,'Accept':'application/json'}) if post else \
                urllib.request.Request(API+'?'+data.decode(),headers={'User-Agent':UA,'Accept':'application/json'})
            with urllib.request.urlopen(req,timeout=45) as r:
                return json.load(r)
        except Exception as e:
            delay=min(45,3*(n+1))
            print('API_RETRY',n+1,repr(e),'sleep',delay,flush=True)
            time.sleep(delay)
    return {}

def category_files(cat):
    files=[]; cont=None
    while True:
        q={'action':'query','list':'categorymembers','cmtitle':'Category:'+cat,'cmtype':'file','cmlimit':'500'}
        if cont: q['cmcontinue']=cont
        d=request_json(q)
        for x in d.get('query',{}).get('categorymembers',[]):
            t=x.get('title','')
            if t.lower().endswith(VIDEO_EXTS): files.append(t)
        cont=d.get('continue',{}).get('cmcontinue')
        if not cont: break
        time.sleep(1.0)
    return files

def collect():
    seen={}; ordered=[]
    for cat in CATEGORIES:
        fs=category_files(cat)
        print('CATEGORY',cat,'VIDEOS',len(fs),flush=True)
        for t in fs:
            if t not in seen:
                seen[t]=cat; ordered.append(t)
        time.sleep(1.5)
    def score(t):
        lo=t.lower(); s=sum(5 for k in KEYWORDS if k in lo)
        if 'controller' in lo or 'gamepad' in lo: s+=12
        if 'xbox' in lo or 'playstation' in lo or 'nintendo' in lo or 'sega' in lo: s+=8
        return s
    ordered.sort(key=lambda t:(-score(t),t.lower()))
    print('UNIQUE_VIDEO_CANDIDATES',len(ordered),flush=True)
    return ordered,seen

def chunks(xs,n=25):
    for i in range(0,len(xs),n): yield xs[i:i+n]

def best_derivative(vi):
    opts=[]
    for d in vi.get('derivatives') or []:
        u=d.get('src') or d.get('url')
        if not u: continue
        typ=(d.get('type') or '').lower(); key=(d.get('transcodekey') or '').lower()
        if 'video' not in typ and '.webm' not in u.lower(): continue
        w=int(d.get('width') or 0)
        rank=9
        if '360p' in key: rank=0
        elif '480p' in key: rank=1
        elif '240p' in key: rank=2
        elif 300<=w<=900: rank=3
        opts.append((rank,abs(w-640) if w else 9999,u,key))
    if opts:
        opts.sort(); _,_,u,key=opts[0]; return u,key
    if int(vi.get('size') or 0)<=MAX_SOURCE: return vi.get('url'),'original'
    return None,''

def infos(titles,origin):
    result=[]
    for batch in chunks(titles,25):
        d=request_json({'action':'query','prop':'videoinfo','titles':'|'.join(batch),
          'viprop':'url|size|mime|dimensions|derivatives|extmetadata',
          'viextmetadatafilter':'LicenseShortName|UsageTerms|Artist|Credit|AttributionRequired'},post=True)
        for p in d.get('query',{}).get('pages',[]):
            title=p.get('title',''); arr=p.get('videoinfo') or []
            if not arr: continue
            vi=arr[0]; url,key=best_derivative(vi)
            if not url: continue
            em=vi.get('extmetadata') or {}
            val=lambda k: clean((em.get(k) or {}).get('value',''))
            result.append({'title':title,'category':origin.get(title,''),'url':url,'transcode':key,
              'source_page':'https://commons.wikimedia.org/wiki/'+urllib.parse.quote(title.replace(' ','_')),
              'license':val('LicenseShortName'),'usage_terms':val('UsageTerms'),'artist':val('Artist'),
              'credit':val('Credit'),'attribution_required':val('AttributionRequired')})
        print('VIDEOINFO',len(result),flush=True); time.sleep(1.5)
    return result

def download(url,path,tries=7):
    for n in range(tries):
        try:
            req=urllib.request.Request(url,headers={'User-Agent':UA})
            with urllib.request.urlopen(req,timeout=90) as r, open(path,'wb') as f:
                cl=r.headers.get('Content-Length')
                if cl and int(cl)>MAX_SOURCE: raise RuntimeError('too large')
                total=0
                while True:
                    b=r.read(1024*1024)
                    if not b: break
                    total+=len(b)
                    if total>MAX_SOURCE: raise RuntimeError('over cap')
                    f.write(b)
            return total
        except Exception as e:
            try: path.unlink(missing_ok=True)
            except: pass
            delay=min(40,4*(n+1)); print('DOWNLOAD_RETRY',n+1,repr(e),'sleep',delay,flush=True); time.sleep(delay)
    raise RuntimeError('download failed')

def probe(path):
    p=subprocess.run(['ffprobe','-v','error','-show_entries','format=duration','-of','default=nw=1:nk=1',str(path)],capture_output=True,text=True)
    try: return float(p.stdout.strip())
    except: return 0

def positions(d):
    if d<4.3:return []
    n=1 if d<12 else 2 if d<22 else 3 if d<40 else 4
    usable=max(.1,d-4.1)
    if n==1:return [usable*.45]
    return [usable*(.08+.84*i/(n-1)) for i in range(n)]

def cut(src,start,out):
    cmd=['ffmpeg','-hide_banner','-loglevel','error','-y','-ss',f'{start:.3f}','-i',str(src),'-t','4.0',
      '-vf','scale=512:-2:force_original_aspect_ratio=decrease,pad=512:288:(ow-iw)/2:(oh-ih)/2,fps=24',
      '-an','-c:v','libx264','-preset','veryfast','-crf','30','-pix_fmt','yuv420p',str(out)]
    p=subprocess.run(cmd,stdout=subprocess.DEVNULL,stderr=subprocess.PIPE,text=True,timeout=70)
    return p.returncode==0 and out.exists() and out.stat().st_size>8000

def main():
    titles,origin=collect(); data=infos(titles,origin)
    rows=[]; source_ok=source_fail=0
    for i,info in enumerate(data,1):
        if len(rows)>=TARGET: break
        src=TMP/f'source_{i:04d}.media'
        try:
            nbytes=download(info['url'],src); d=probe(src); pos=positions(d)
            if not pos: raise RuntimeError('short or invalid')
            made=0
            for st in pos:
                if len(rows)>=TARGET: break
                cid=len(rows)+1; part=(cid-1)//250+1; out=OUT/f'part{part:02d}'/f'clip_{cid:04d}.mp4'
                if cut(src,st,out):
                    made+=1; rows.append({'clip_id':cid,'local_file':str(out),'source_title':info['title'],
                      'source_page':info['source_page'],'source_video_url':info['url'],'source_category':info['category'],
                      'clip_start_seconds':round(st,3),'clip_duration_seconds':4.0,'source_duration_seconds':round(d,3),
                      'source_download_bytes':nbytes,'license':info['license'],'usage_terms':info['usage_terms'],
                      'artist':info['artist'],'credit':info['credit'],'attribution_required':info['attribution_required'],
                      'transcode':info['transcode']})
            if made: source_ok+=1
            else: source_fail+=1
        except Exception as e:
            source_fail+=1; print('SOURCE_FAIL',i,info['title'],repr(e),flush=True)
        finally:
            src.unlink(missing_ok=True)
        time.sleep(.8)
        if i%10==0 or len(rows)>=TARGET: print('PROGRESS sources',i,'clips',len(rows),'ok',source_ok,'fail',source_fail,flush=True)
    fields=['clip_id','local_file','source_title','source_page','source_video_url','source_category','clip_start_seconds','clip_duration_seconds','source_duration_seconds','source_download_bytes','license','usage_terms','artist','credit','attribution_required','transcode']
    with open('video_manifest.csv','w',newline='',encoding='utf-8') as f:
        w=csv.DictWriter(f,fieldnames=fields); w.writeheader(); w.writerows(rows)
    Path('video_manifest.json').write_text(json.dumps(rows,ensure_ascii=False,indent=2),encoding='utf-8')
    summary={'target_clips':TARGET,'downloaded_clips':len(rows),'candidate_videos':len(titles),'video_infos':len(data),'usable_source_videos':source_ok,'failed_sources':source_fail,'strategy':'direct Commons video categories + low-res derivatives + 4-second B-roll clips'}
    Path('video_summary.json').write_text(json.dumps(summary,ensure_ascii=False,indent=2),encoding='utf-8')
    Path('README_VIDEO_ASSETS.txt').write_text('Derived from Wikimedia Commons video files. See video_manifest.csv for source page, license, creator, attribution and transcode metadata. Verify attribution requirements before publication.\n',encoding='utf-8')
    print('FINAL',json.dumps(summary),flush=True)
    if len(rows)<TARGET: raise SystemExit(f'Only {len(rows)} clips')
if __name__=='__main__': main()
