#!/usr/bin/env python3
import os, struct, sys
from pathlib import Path
from PIL import Image, ImageDraw, ImageFont

# The game's own folder, the one holding FTABLE.DAT and the ROM folders; FFXI_DIR to read another
ROOT = Path(os.environ.get('FFXI_DIR') or Path.home() / 'Games/PhoenixXI/SquareEnix/FINAL FANTASY XI')
IMAGE_AT = 0x41

def load_tables(root=ROOT):
    pairs=[('/FTABLE.DAT','/VTABLE.DAT')]+[(f'/ROM{i}/FTABLE{i}.DAT',f'/ROM{i}/VTABLE{i}.DAT') for i in range(2,10)]
    ft=vt=None
    for fp,vp in pairs:
        fpath=root / fp.lstrip('/')
        vpath=root / vp.lstrip('/')
        if not fpath.exists() or not vpath.exists():
            continue
        fb=fpath.read_bytes(); vb=vpath.read_bytes()
        f=list(struct.unpack('<'+'H'*(len(fb)//2), fb)); v=list(vb)
        if ft is None:
            ft, vt = f, v
        else:
            for i,x in enumerate(f):
                if x>0 and i<len(ft): ft[i]=x
            for i,x in enumerate(v):
                if x>0 and i<len(vt): vt[i]=x
    return ft,vt

FT,VT=load_tables()

def dat_path(fileid):
    if fileid<0 or fileid>=len(VT) or VT[fileid]==0:
        return None
    r=VT[fileid]
    folder='ROM' if r==1 else f'ROM{r}'
    val=FT[fileid]
    return ROOT / folder / str(val>>7) / f'{val & 0x7f}.DAT'

def read_color(data, off, bit):
    if bit == 8:
        g=data[off]; return (g,g,g,255),1
    if bit == 16:
        rgb=struct.unpack_from('<H',data,off)[0]
        r=((rgb>>11)&0x1f)*255//31; g=((rgb>>5)&0x3f)*255//63; b=(rgb&0x1f)*255//31
        return (r,g,b,255),2
    if bit == 24:
        b,g,r=data[off:off+3]; return (r,g,b,255),3
    if bit == 32:
        b,g,r,a=data[off:off+4]; return (r,g,b,255 if a else 0),4
    return (255,0,255,255),0

def decode(fileid):
    p=dat_path(fileid)
    if not p or not p.exists(): return None
    data=p.read_bytes()
    if len(data) < IMAGE_AT+48: return None
    size,w,h,planes,bits,comp,imgsz,rx,ry,used,important,typ=struct.unpack_from('<IiiHHIIIIIII',data,IMAGE_AT)
    if size != 40 or planes != 1 or typ != 10 or w<=0 or h<=0 or w>2048 or h>2048:
        return None
    off=IMAGE_AT+48
    palette=None
    if bits == 8:
        palette=[]
        for i in range(256):
            c,n=read_color(data,off,32); palette.append(c); off+=4
    im=Image.new('RGBA',(w,h),(0,0,0,0))
    pix=im.load()
    for idx in range(w*h):
        if off>=len(data): break
        if bits==8:
            c=palette[data[off]]; off+=1
        else:
            c,n=read_color(data,off,bits); off+=n
        x=idx%w; y=idx//w
        pix[x,h-1-y]=c
    return im,p

if __name__ == '__main__':
    out=Path(sys.argv[1]) if len(sys.argv)>1 else Path('tmp_maps')
    out.mkdir(exist_ok=True)
    ids=list(range(int(sys.argv[2]), int(sys.argv[3])+1)) if len(sys.argv)>3 else [int(sys.argv[2])]
    thumbs=[]
    for fid in ids:
        r=decode(fid)
        if not r: continue
        im,p=r
        im.save(out/f'{fid}.png')
        th=im.convert('RGB').resize((128,128))
        thumbs.append((fid,th))
    if len(thumbs)>1:
        W=8*160; H=((len(thumbs)+7)//8)*154
        sheet=Image.new('RGB',(W,H),'white'); d=ImageDraw.Draw(sheet)
        for n,(fid,th) in enumerate(thumbs):
            x=(n%8)*160; y=(n//8)*154
            sheet.paste(th,(x,y+18)); d.text((x,y),str(fid),fill=(0,0,0))
        sheet.save(out/'sheet.png')
        print(out/'sheet.png')
