#!/usr/bin/env python3
import csv, html, json, os, re, subprocess, time, urllib.parse, urllib.request
from pathlib import Path
API='https://commons.wikimedia.org/w/api.php'; UA='ControllerHistoryVideoShard/1.0'
SHARD=int(os.environ.get('SHARD','0')); SHARDS=4; TARGET=250; MAX_SOURCE=60*1024*1024
OUT=Path(f'video_shard_{SHARD}'); TMP=Path(f'tmp_shard_{SHARD}'); OUT.mkdir(exist_ok=True); TMP.mkdir(exist_ok=True)
CATS=['Video game trailers','Videos by Capcom France','Videos by Xbox México','Videos of video game gameplay','Videos related to video games','Videos of video game development','Videos of video game designers']
EXTS=('.webm','.ogv','.ogg','.mp4','.mpeg','.mpg','.mov')
KEY=('nintendo','nes','snes','famicom','game boy','gamecube','wii','switch','sega','genesis','mega drive','dreamcast','saturn','playstation','dualshock','dualsense','xbox','microsoft','controller','gamepad','console','gameplay','trailer')
def clean(s):
 s=re.sub(r'<[^>]+>',' ',str(s or '')); return html.unescape(re.sub(r'\s+',' ',s)).strip()
def api(p,post=False,tries=8):
 p=dict(p); p.update({'format':'json','formatversion':'2','maxlag':'5'}); data=urllib.parse.urlencode(p).encode()
 for n in range(tries):
  try:
   req=urllib.request.Request(API,data=data if post else None,headers={'User-Agent':UA}) if post else urllib.request.Request(API+'?'+data.decode(),headers={'User-Agent':UA})
   with urllib.request.urlopen(req,timeout=45) as r:return json.load(r)
  except Exception as e: time.sleep(min(30,3*(n+1)))
 return {}
def catfiles(cat):
 out=[]; cont=None
 while True:
  p={'action':'query','list':'categorymembers','cmtitle':'Category:'+cat,'cmtype':'file','cmlimit':'500'}
  if cont:p['cmcontinue']=cont
  d=api(p)
  out += [x['title'] for x in d.get('query',{}).get('categorymembers',[]) if x.get('title','').lower().endswith(EXTS)]
  cont=d.get('continue',{}).get('cmcontinue')
  if not cont:break
  time.sleep(.6)
 return out
def candidates():
 origin={}; all=[]
 for c in CATS:
  fs=catfiles(c); print('CAT',c,len(fs),flush=True)
  for t in fs:
   if t not in origin:origin[t]=c;all.append(t)
  time.sleep(1)
 def score(t):
  lo=t.lower(); return sum(5 for k in KEY if k in lo)+(10 if 'controller' in lo or 'gamepad' in lo else 0)
 all.sort(key=lambda t:(-score(t),t.lower()))
 shard=all[SHARD::SHARDS]
 print('ALL',len(all),'SHARD',SHARD,'CANDIDATES',len(shard),flush=True)
 return shard,origin
def chunks(a,n=25):
 for i in range(0,len(a),n):yield a[i:i+n]
def best(vi):
 o=[]
 for d in vi.get('derivatives') or []:
  u=d.get('src') or d.get('url'); k=(d.get('transcodekey') or '').lower(); typ=(d.get('type') or '').lower(); w=int(d.get('width') or 0)
  if not u or ('video' not in typ and '.webm' not in u.lower()):continue
  rank=0 if '360p' in k else 1 if '480p' in k else 2 if '240p' in k else 4
  o.append((rank,abs(w-640) if w else 9999,u,k))
 if o:o.sort();return o[0][2],o[0][3]
 if int(vi.get('size') or 0)<=MAX_SOURCE:return vi.get('url'),'original'
 return None,''
def getinfos(ts,origin):
 out=[]
 for b in chunks(ts):
  d=api({'action':'query','prop':'videoinfo','titles':'|'.join(b),'viprop':'url|size|mime|dimensions|derivatives|extmetadata','viextmetadatafilter':'LicenseShortName|UsageTerms|Artist|Credit|AttributionRequired'},True)
  for p in d.get('query',{}).get('pages',[]):
   a=p.get('videoinfo') or []
   if not a:continue
   vi=a[0];u,k=best(vi)
   if not u:continue
   em=vi.get('extmetadata') or {};v=lambda z:clean((em.get(z) or {}).get('value',''));t=p.get('title','')
   out.append({'title':t,'category':origin.get(t,''),'url':u,'transcode':k,'page':'https://commons.wikimedia.org/wiki/'+urllib.parse.quote(t.replace(' ','_')),'license':v('LicenseShortName'),'usage':v('UsageTerms'),'artist':v('Artist'),'credit':v('Credit'),'attrib':v('AttributionRequired')})
  time.sleep(1)
 print('INFOS',len(out),flush=True);return out
def dl(u,p):
 for n in range(6):
  try:
   req=urllib.request.Request(u,headers={'User-Agent':UA})
   with urllib.request.urlopen(req,timeout=90) as r,open(p,'wb') as f:
    total=0
    while True:
     b=r.read(1024*1024)
     if not b:break
     total+=len(b)
     if total>MAX_SOURCE:raise RuntimeError('cap')
     f.write(b)
   return total
  except Exception as e:
   p.unlink(missing_ok=True);time.sleep(min(30,4*(n+1)))
 raise RuntimeError('download')
def dur(p):
 r=subprocess.run(['ffprobe','-v','error','-show_entries','format=duration','-of','default=nw=1:nk=1',str(p)],capture_output=True,text=True)
 try:return float(r.stdout.strip())
 except:return 0
def cut(src,st,out):
 r=subprocess.run(['ffmpeg','-hide_banner','-loglevel','error','-y','-ss',str(st),'-i',str(src),'-t','4','-vf','scale=512:-2:force_original_aspect_ratio=decrease,pad=512:288:(ow-iw)/2:(oh-ih)/2,fps=24','-an','-c:v','libx264','-preset','veryfast','-crf','30','-pix_fmt','yuv420p',str(out)],timeout=60)
 return r.returncode==0 and out.exists() and out.stat().st_size>8000
def main():
 ts,origin=candidates(); inf=getinfos(ts,origin); rows=[];ok=fail=0
 for i,x in enumerate(inf,1):
  if len(rows)>=TARGET:break
  src=TMP/f's{i}.media'
  try:
   nb=dl(x['url'],src);d=dur(src)
   if d<4.3:raise RuntimeError('short')
   starts=[max(0,(d-4)*.18),max(0,(d-4)*.70)] if d>=12 else [max(0,(d-4)*.45)]
   made=0
   for st in starts:
    if len(rows)>=TARGET:break
    cid=len(rows)+1;o=OUT/f'clip_s{SHARD}_{cid:03d}.mp4'
    if cut(src,round(st,3),o):
     made+=1;rows.append({'shard':SHARD,'clip_id':cid,'local_file':str(o),'source_title':x['title'],'source_page':x['page'],'source_url':x['url'],'category':x['category'],'start':round(st,3),'duration':4,'source_duration':round(d,3),'bytes':nb,'license':x['license'],'usage_terms':x['usage'],'artist':x['artist'],'credit':x['credit'],'attribution_required':x['attrib'],'transcode':x['transcode']})
   ok+=bool(made);fail+=not bool(made)
  except Exception as e:fail+=1;print('FAIL',i,x['title'],repr(e),flush=True)
  finally:src.unlink(missing_ok=True)
  time.sleep(.5)
  if i%10==0:print('PROGRESS',SHARD,i,len(rows),flush=True)
 fields=['shard','clip_id','local_file','source_title','source_page','source_url','category','start','duration','source_duration','bytes','license','usage_terms','artist','credit','attribution_required','transcode']
 with open(f'manifest_shard_{SHARD}.csv','w',newline='',encoding='utf8') as f:w=csv.DictWriter(f,fieldnames=fields);w.writeheader();w.writerows(rows)
 Path(f'summary_shard_{SHARD}.json').write_text(json.dumps({'shard':SHARD,'target':TARGET,'clips':len(rows),'candidates':len(ts),'infos':len(inf),'source_ok':ok,'source_fail':fail},indent=2),encoding='utf8')
 print('FINAL',SHARD,len(rows),flush=True)
 if len(rows)<TARGET:raise SystemExit(f'only {len(rows)}')
if __name__=='__main__':main()
