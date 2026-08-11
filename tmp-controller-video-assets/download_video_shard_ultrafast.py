#!/usr/bin/env python3
import importlib.util, subprocess
from pathlib import Path
base=Path(__file__).with_name('download_video_shard.py')
spec=importlib.util.spec_from_file_location('base_shard',base)
m=importlib.util.module_from_spec(spec);spec.loader.exec_module(m)
slow_cut=m.cut

def quick_dl(url,path):
    path.unlink(missing_ok=True)
    r=subprocess.run([
      'curl','-L','--fail','--silent','--show-error','--connect-timeout','5','--max-time','20',
      '--retry','1','--retry-delay','1','--max-filesize',str(60*1024*1024),
      '-A','ControllerHistoryVideoUltraFast/1.0',url,'-o',str(path)
    ],timeout=28)
    if r.returncode!=0 or not path.exists() or path.stat().st_size<10000:
        path.unlink(missing_ok=True); raise RuntimeError('quick download failed')
    return path.stat().st_size

def quick_cut(src,st,out):
    try:
        r=subprocess.run(['ffmpeg','-hide_banner','-loglevel','error','-y','-ss',str(st),'-i',str(src),'-t','4','-map','0:v:0','-an','-c:v','copy',str(out)],timeout=20)
        if r.returncode==0 and out.exists() and out.stat().st_size>8000:return True
    except Exception:pass
    out.unlink(missing_ok=True)
    try:return slow_cut(src,st,out)
    except Exception:return False

m.dl=quick_dl
m.cut=quick_cut
m.time.sleep=lambda x: None if x<=1.1 else __import__('time').sleep(min(x,2))
m.main()
