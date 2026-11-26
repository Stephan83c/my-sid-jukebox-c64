# My SID Jukebox (dossier SidJukeboxLocal_C64)

Jukebox SID **hors ligne** pour C64 Ultimate : il trouve les `.sid` personnels de l'utilisateur sur la SD et la clé USB
et les joue au hasard. Pas de HVSC, pas d'outil PC, pas de réseau, pas de scroller. Tout est décrit dans `SPEC.md`
(décisions L1-L6, points ouverts D1-D5, étapes).

- Base de connaissances commune : `~/Projet_C64/BaseC64/` (lire `ultimate.md` § Command Interface « DOS » avant de
  toucher aux fichiers).
- Code à reprendre (lecteur, routines UCI) : `~/Projet_C64/SidJukebox_C64/jukebox/c64/src/` (client v2.0, Kick Assembler).
  Le copier ici, ne pas modifier le jukebox en ligne depuis ce projet.
- Assembler : `java -jar ~/KickAssembler/KickAss.jar fichier.asm`.
- Essais : `essais/dirtest.asm` (parcours récursif) :
  `java -jar ~/KickAssembler/KickAss.jar essais/dirtest.asm -o build/x.prg :ROOT=/USB1 :QUIET=1`.
- Lancer sur le C64U : `curl -sS -X POST --data-binary @build/x.prg http://192.168.1.27/v1/runners:run_prg`,
  après avoir vérifié que l'UCI est au repos (`python3 ~/Projet_C64/BaseC64/code-reutilisable/outils-pc/ultimate.py uci`
  = `00 c9`) et qu'aucun programme réseau n'a de socket ouvert.
- Dossier de test sur la carte SD : `/SD/JUKETEST` (créé par FTP le 2026-11-25, 5 SID, un dossier vide).

- **Programme définitif** : `src/mysidjukebox.asm` (logo : `outils/mkbig.py` → `src/big.inc`). Assembler :
  `java -jar ~/KickAssembler/KickAss.jar src/mysidjukebox.asm -o build/mysidjukebox.prg` (essai court : `:DUREE=10`).
  Écran reconstitué par l'API : `python3 outils/ecran_png.py x.png`.
- Dépôt git local (branche `main`, créé le 2026-11-26), pas de dépôt distant. `build/` et `*.sym` ne sont pas suivis.
- Licence : **GPL-3.0-or-later** (fichier `LICENSE`, décision de l'utilisateur le 2026-11-26), auteur affiché : « Stephan ».
