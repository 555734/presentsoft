import os, subprocess, glob
font='/usr/share/fonts/opentype/noto/NotoSansCJK-Bold.ttc'
sections=[
('intro','エルデンリング発売初期の狂気','2022年 初期環境がヤバすぎた','official'),
('hoarfrost','戦技「霜踏み」が猛威','踏むだけでボスが溶ける','hoarfrost'),
('mimic','写し身の雫が強すぎる','本人より分身が働く','mimic'),
('lmsh','伝説「Let Me Solo Her」','壺頭ほぼ全裸でマレニアを撃破','lmsh'),
('wall','何十回も殴ると消える壁','発売初期から存在 → 後に修正','wall')]
os.makedirs('render',exist_ok=True)
def dur(p): return float(subprocess.check_output(['ffprobe','-v','error','-show_entries','format=duration','-of','csv=p=0',p],text=True).strip())
def esc(s): return s.replace('\\','\\\\').replace(':','\\:').replace("'","\\'")
finals=[]
for key,top,bottom,prefix in sections:
    ad=dur(f'pack/audio/{key}.wav')
    clips=sorted(glob.glob(f'pack/video/{prefix}_*.mp4')) if prefix!='official' else sorted(glob.glob('pack/video/official_*.mp4'))
    if not clips: raise SystemExit(f'No visual for {key}')
    chunk=1.35; t=0.; i=0; parts=[]
    while t < ad-.01:
        ln=min(chunk,ad-t); clip=clips[i%len(clips)]; cd=dur(clip)
        usable=max(cd-ln-.3,.1); off=min(max(.05,((i*4.3)%usable)),max(.05,cd-ln-.02))
        out=f'render/{key}_{i:02d}.mp4'
        subprocess.run(['ffmpeg','-y','-loglevel','error','-ss',str(off),'-i',clip,'-t',str(ln),'-vf','scale=1080:1110:force_original_aspect_ratio=increase,crop=1080:1110,eq=contrast=1.03:saturation=1.08','-an','-r','30','-c:v','libx264','-preset','ultrafast','-crf','18','-pix_fmt','yuv420p',out],check=True)
        parts.append(out); t+=ln; i+=1
    lst=f'render/{key}.txt'
    with open(lst,'w') as f:
        for p in parts: f.write("file '"+os.path.abspath(p)+"'\n")
    center=f'render/{key}_center.mp4'
    subprocess.run(['ffmpeg','-y','-loglevel','error','-f','concat','-safe','0','-i',lst,'-t',str(ad),'-c','copy',center],check=True)
    out=f'render/{key}_final.mp4'
    fc=(f"[0:v][1:v]overlay=0:405:shortest=1[v];[v]drawtext=fontfile={font}:text='{esc(top)}':fontcolor=black:borderw=2:bordercolor=white:fontsize=82:x=(w-text_w)/2:y=82,drawtext=fontfile={font}:text='{esc(bottom)}':fontcolor=black:borderw=2:bordercolor=white:fontsize=70:x=(w-text_w)/2:y=1620[outv]")
    subprocess.run(['ffmpeg','-y','-loglevel','error','-f','lavfi','-i',f'color=c=white:s=1080x1920:r=30:d={ad}','-i',center,'-i',f'pack/audio/{key}.wav','-filter_complex',fc,'-map','[outv]','-map','2:a','-t',str(ad),'-c:v','libx264','-preset','ultrafast','-crf','18','-pix_fmt','yuv420p','-c:a','aac','-b:a','192k',out],check=True)
    finals.append(out)
with open('render/final.txt','w') as f:
    for p in finals: f.write("file '"+os.path.abspath(p)+"'\n")
subprocess.run(['ffmpeg','-y','-loglevel','error','-f','concat','-safe','0','-i','render/final.txt','-c','copy','render/pre_final.mp4'],check=True)
d=dur('render/pre_final.mp4'); ratio=d/59.0
if abs(d-59.0)>.15:
    subprocess.run(['ffmpeg','-y','-loglevel','error','-i','render/pre_final.mp4','-filter_complex',f'[0:v]setpts=PTS/{ratio}[v];[0:a]atempo={ratio}[a]','-map','[v]','-map','[a]','-t','59','-c:v','libx264','-preset','ultrafast','-crf','18','-pix_fmt','yuv420p','-c:a','aac','-b:a','192k','pack/ELDEN_RING_launch_chaos_HQ_Metan.mp4'],check=True)
else: subprocess.run(['cp','render/pre_final.mp4','pack/ELDEN_RING_launch_chaos_HQ_Metan.mp4'],check=True)
