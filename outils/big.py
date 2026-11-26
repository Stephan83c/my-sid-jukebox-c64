# Parcourt un dossier de l Ultimate par FTP et montre les plus gros dossiers : python3 big.py /SD
import ftplib, sys
f=ftplib.FTP('192.168.1.27',timeout=30,encoding='latin-1'); f.login()
res=[]; tot=[0,0,0]
def walk(p):
    L=[]; f.retrlines('LIST '+p, L.append)
    b=sum(len(l.split(None,8)[8])+2 for l in L); res.append((b,len(L),p)); tot[0]+=1
    for l in L:
        n=l.split(None,8)[8]
        if l.startswith('d'): walk(p+'/'+n)
        else:
            tot[1]+=1
            if n.lower().endswith('.sid'): tot[2]+=1
walk(sys.argv[1])
print('dossiers',tot[0],'fichiers',tot[1],'sid',tot[2])
for r in sorted(res)[-5:]: print(r)
