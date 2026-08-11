#!/usr/bin/env python3
import importlib.util, subprocess, sys
from pathlib import Path
base=Path(__file__).with_name('download_video_shard.py')
spec=importlib.util.spec_from_file_location('base_shard',base)
m=importlib.util.module_from_spec(spec);spec.loader.exec_module(m)
slow=m.cut

def fast_cut(src,st,out):
    try:
        r=subprocess.run(['ffmpeg','-hide_banner','-loglevel','error','-y','-ss',str(st),'-i',str(src),'-t','4','-map','0:v:0','-an','-c:v','copy',str(out)],timeout=30)
        if r.returncode==0 and out.exists() and out.stat().st_size>8000:
            return True
    except Exception:
        pass
    try: out.unlink(missing_ok=True)
    except Exception: pass
    return slow(src,st,out)

m.cut=fast_cut
m.main()
