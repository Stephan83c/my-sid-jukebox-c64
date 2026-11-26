# Appels de play par seconde : relit le compteur « frames » du lecteur (adresses de essais/build/joue.sym, à mettre à jour) par l API, à N s d écart.
import urllib.request, time, sys
def rd(a,n):
    return urllib.request.urlopen(f"http://192.168.1.27/v1/machine:readmem?address={a:04X}&length={n}").read()
def fr(): return int.from_bytes(rd(0xC14F,2),'little')
v=rd(0xC13B,1)[0], rd(0xC14A,1)[0], rd(0xC14C,1)[0], rd(0xC14D,1)[0]
print("pal=%d cia=%d tpal=%d corr=%d"%v)
t0=time.time(); f0=fr(); time.sleep(float(sys.argv[1]) if len(sys.argv)>1 else 10); f1=fr(); t1=time.time()
print("appels/s = %.2f"%(((f1-f0)%65536)/(t1-t0)))
