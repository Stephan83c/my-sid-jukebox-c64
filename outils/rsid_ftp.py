# Copie par FTP tous les RSID de l Ultimate dans un dossier local : python3 rsid_ftp.py DEST /SD /USB1
import ftplib, sys, os, io
f=ftplib.FTP('192.168.1.27',timeout=60,encoding='latin-1'); f.login()
dest=sys.argv[1]; n=[0,0]
def walk(p):
    L=[]; f.retrlines('LIST '+p, L.append)
    for l in L:
        nm=l.split(None,8)[8]
        if l.startswith('d'): walk(p+'/'+nm); continue
        if not nm.lower().endswith('.sid'): continue
        n[0]+=1
        b=io.BytesIO(); f.retrbinary('RETR '+p+'/'+nm, b.write); d=b.getvalue()
        if d[:4]==b'RSID':
            n[1]+=1
            out=os.path.join(dest,(p+'/'+nm).strip('/').replace('/','__'))
            open(out,'wb').write(d)
for r in sys.argv[2:]: walk(r)
print('sid',n[0],'rsid',n[1])
