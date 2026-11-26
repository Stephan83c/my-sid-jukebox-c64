# SID Jukebox local : spécification (brouillon du 2026-11-25)

Un jukebox pour C64 Ultimate **sans réseau** : il trouve tout seul les fichiers `.sid` de l'utilisateur sur la carte SD
et la clé USB, et les joue au hasard. C'est la collection personnelle de chacun : **pas de HVSC, pas d'outil sur PC**,
tout se fait sur le C64. Cousin hors ligne du SID Jukebox en ligne (`~/Projet_C64/SidJukebox_C64/jukebox`, v2.0).

## 1. Décisions prises

| N° | Décision | Date |
|----|----------|------|
| L1 | Cible : C64 Ultimate (Command Interface « DOS » obligatoire). | 2026-11-25 |
| L2 | Les SID sont cherchés sur **tout** le support : `/SD` et `/USB1` (et `/USB0` s'il existe), récursivement. | 2026-11-25 |
| L3 | Ni HVSC, ni index préparé sur PC : la liste est construite par le C64. | 2026-11-25 |
| L4 | Pas de scroller. Écran nouveau (§5), pas celui du jukebox en ligne. | 2026-11-25 |
| L5 | Vu-mètres ou autre effet visuel : un plus, pas une obligation de la première version. | 2026-11-25 |
| L7 | La liste est **gardée** dans `/Temp` (survit au reset, pas à la coupure de courant) ; l'utilisateur la refait avec **R**. `jukelist.cnt` (nombre de SID, 2 octets) vaut 0 pendant une recherche : une recherche interrompue est refaite au démarrage. Vérifié sur le C64U : redémarrage en 3,6 s au lieu de 79 s. | 2026-11-25 |
| L8 | Sans liste complète (pas de `jukelist.cnt`, ou 0) et avec **R** : écran de **choix des lecteurs**. Lecteurs lus à la racine `/` de l'Ultimate (`Flash` et `Temp` écartés), tous cochés au départ, 1-9 cocher/décocher, RETURN chercher, Q annuler (R : garde l'ancienne liste). Testé sur le C64U : USB seul 304 SID, SD + USB 626. | 2026-11-25 |
| L6 | Langage : Kick Assembler, comme le client v2.0 (réutilisation du lecteur et des routines UCI). | 2026-11-25 |

## 2. Ce qui est déjà vérifié (essai `essais/dirtest.asm`)

- Parcours récursif par la Command Interface DOS (`CHANGE_DIR` $11, `OPEN_DIR` $13, `READ_DIR` $14) : un paquet par
  entrée, attribut `$10` dossier / `$20` fichier. Dossier vide : statut `01`, ne pas lire ensuite (sinon `87`).
- Clé USB de test : 239 dossiers, 304 SID trouvés en ~18 s (environ 75 ms par dossier). Détails : `BaseC64/ultimate.md`.

## 2 bis. Résultats de l'essai `essais/liste.asm` (2026-11-25)

- SD + clé USB de test : 549 dossiers, ~11 000 fichiers, **626 SID** en ~79 s ; liste `/Temp/jukelist.bin` (128 o par
  entrée : dossier, 0, nom, 0) écrite sur la cible DOS `$02` pendant que `$01` parcourt. Tirage + en-tête : ~1 s.
- Pièges (détails dans `BaseC64/ultimate.md` et `bugs.md`) : délai de garde de 20 s (une commande peut prendre ~7,7 s),
  dossier de 8 323 fichiers sur la SD (filtrer pendant READ_DIR), OPEN_FILE `$0A` pour écraser, abandon d'une commande
  restée en cours au démarrage.
- Le parcours est le point lent : 79 s, presque tout dans un seul dossier énorme sans SID. Décision L7 : liste gardée, refaite sur demande (R).

## 2 ter. Lecteur (essai `essais/joue.asm`, 2026-11-25)

- Programme recopié en `$A000-$BFFF` (ROM BASIC coupée), appels du morceau et IRQ en `$C000`, variables `$C100` ; morceaux
  en `$0800-$9FFF`. Page zéro et pages 2-3 sauvées avant init, rendues à l'arrêt ; clavier lu par la matrice.
- **PAL/NTSC (exigence de l'utilisateur)** : norme du morceau lue dans l'en-tête (clock : PAL, NTSC, les deux = machine,
  inconnue = PAL). Même norme : raster (VBI) ou timer du morceau. Normes différentes : VBI joué par le timer du CIA 1 à
  la cadence d'origine (50,12 / 59,83 Hz), timer du morceau mesuré puis corrigé (x 1,038 / x 0,963). **Hauteur non corrigée**
  (il faudrait les relais d'écriture SID, comme en v2.0). **Vérifié en NTSC le 2026-11-25** (C64U passé en NTSC puis remis
  en PAL) : morceau à timer 100,23 appels/s (100,15 en PAL), morceau VBI 50,11/s (attendu 50,12).
- Vérifié sur le C64U (PAL) : 8 morceaux joués (VBI et timer), ESPACE, + / − (bornés), Q (retour au BASIC). Non vérifié :
  passage automatique à 3:00, R pendant la lecture.
- Refusés pour l'instant : RSID (**94 sur 626** dans la collection de test, 15 %), PSID hors `$0800-$9FFF` (ex. *Edge of
  Disgrace*, `$083E-$E381`), play = 0 (aucun dans la collection).

## 2 quater. RSID, étape A (`essais/joue.asm`, 2026-11-26)

- Collection de test : 94 RSID = **50 morceaux différents** (doublons SD/USB). Émulation de l'init sur PC
  (`outils/rsid_ftp.py` pour les copier, essai `rsidscan` hors projet) : ~30 init reviennent, ~20 bouclent ; presque tous
  prennent `$FFFE` et `$FFFA` ; 8 écrivent dans `$A000-$CFFF` (zone du lecteur, non détectable avant).
- Lancement : `$01 = $37`, IRQ du KERNAL, `cli`, puis `jsr init` (depuis `$C000`). Au retour : ROM BASIC coupée si visible,
  `$01` laissé au morceau sinon. Temps = **TOD du CIA 2** (secondes, `bit $DD08` après lecture) : le morceau garde ses timers.
  Garde-fou = **alarme TOD à 3 s → NMI** (`$0318` et `$FFFA` en RAM) ; coupée au retour, NMI rendue à un simple RTI si le
  morceau ne l'a pas prise. Boucle de lecture sous `sei` (fenêtre `cli ; nop ; sei`) : les IRQ de RSID ne sauvent pas A/X/Y.
- Vérifié sur le C64U : *Old Friend*, *Seal of Focalor Intro* et *Greed*, *Oro Incenso*, *E2IRA*, *2400 AD* jouent, temps
  qui avance, ESPACE → arrêt propre et morceau suivant. *Arkanoid*, *Nightmare* (init qui boucle) : garde-fou → refus, tirage suivant.
- **Échec** : *Barber's Adagio 64* (digis) ne revient jamais de sa 1re IRQ → plus de clavier ni de temps (C64 à relancer).
  Même sort attendu pour les init qui bouclent ET prennent `$FFFA` (~16 sur 50) : l'alarme part dans la NMI du morceau.
- Non corrigés pour les RSID : tempo/hauteur PAL/NTSC (le morceau tient ses timers).

## 3. Fonctionnement prévu

1. **Démarrage** : parcours de `/SD` et `/USB1` avec un compteur à l'écran (« 123 SID TROUVES »). Les dossiers système
   (`System Volume Information`, dossiers commençant par `.`) sont sautés.
2. **Liste** : chaque SID trouvé est noté (chemin du dossier + nom). Elle ne tient pas forcément en RAM (300 SID ≈ 8 Ko
   de noms, plus les chemins) : piste principale, l'écrire dans un fichier de `/Temp` (disque en RAM de l'Ultimate, on
   n'écrit jamais sur le support de l'utilisateur). À vérifier : écriture de fichier par la Command Interface (D1).
3. **Tirage** : numéro au hasard, lecture de l'entrée correspondante, chargement du `.sid` par `OPEN_FILE`/`READ_DATA`.
4. **Contrôle avant lecture** (le serveur le faisait pour le jukebox en ligne) : en-tête PSID/RSID lu sur le C64 ;
   refus si la zone du morceau chevauche le lecteur, si le format n'est pas géré (RSID, D2), ou si l'en-tête est
   incohérent. Morceau refusé : on passe au suivant sans bruit, et on le note pour ne plus le tirer.
5. **Protection pendant la lecture** : un morceau qui décompresse par-dessus le lecteur ne se voit pas dans l'en-tête.
   Garde-fou à définir (D3) : somme de contrôle du lecteur, délai de garde, retour automatique au morceau suivant.
6. **Touches** : comme le jukebox en ligne (suivant, rejouer, sous-morceau, recherche dans les noms), à confirmer.

## 4. Mémoire (première idée, à mesurer)

- Lecteur + interface en haut de la mémoire (comme le client v2.0, à partir de `$AF00` environ), écran et jeu de caractères
  en banque VIC 3. Sans réseau ni scroller, le client devrait être plus petit que la v2.0 : la limite haute des morceaux
  pourra monter.
- Le morceau tourne directement sur le vrai SID : son exact sans relais (les relais du jukebox en ligne étaient posés par
  le serveur).

## 5. Écran (proposition, à valider)

```
 ┌──────────────────────────────────────┐
 │  S I D   J U K E B O X   L O C A L   │  logo en grands caractères
 │                                      │
 │  COMMANDO                            │  titre (en-tête du SID)
 │  ROB HUBBARD                         │  auteur
 │  1985 ELITE                          │  copyright
 │  /USB1/MUSIC/SPEED/COMMANDO.SID      │  chemin (tronqué à gauche)
 │                                      │
 │  TUNE 1/3      01:42      PAL 6581   │
 │  ▂▃▅▇█▇▅▃▂   ▁▂▃▅▃▂▁   ▃▅▇▅▃         │  effet visuel (§6)
 │                                      │
 │  304 SID   SPACE NEXT  R REPLAY ...  │
 └──────────────────────────────────────┘
```

## 6. Effet visuel « fun » (pistes, L5)

Le morceau écrit directement dans le SID, dont les registres ne se relisent pas (sauf la voix 3 : `$D41B` oscillateur,
`$D41C` enveloppe). Pistes, de la plus simple à la plus lourde :
1. **Barre de temps machine** façon démo : bande de couleur dans la bordure pendant que la routine du morceau tourne
   (sa hauteur = le temps CPU du morceau à chaque image). Vraie donnée, coût presque nul.
2. **Voix 3 en direct** : oscilloscope ou barre animée depuis `$D41B`/`$D41C` (seulement la voix 3).
3. **Vu-mètres des 3 voix** : il faudrait poser des relais d'écriture SID sur le C64 (ce que faisait le serveur) :
   gros travail, pour plus tard.

## 7. Points ouverts

- **D1 réglé le 2026-11-25** : oui, `/Temp` accepte écriture, relecture et `FILE_SEEK` par la Command Interface
  (`essais/filetest.asm` : 8 Ko écrits en ~0,4 s, relus en ~0,8 s, sans erreur, contrôlés par FTP). La liste ira dans
  `/Temp`, avec des entrées de taille fixe pour atteindre la n-ième par un seul seek.
- **D2 réglé le 2026-11-26** : RSID **exclus** (décision de l'utilisateur : trop compliqué, son pas propre), refus silencieux
  sans attente (compté dans les refus d'affilée). Essai de l'étape A gardé dans `essais/joue-rsid-etapeA.asm` (§2 quater).
- **D3** : garde-fou contre les morceaux qui écrasent le lecteur.
- **D4** : nombre maximal de SID gérés (1 000 ? 10 000 ?) et temps de parcours acceptable.
- **D5 réglé le 2026-11-26** : le programme s'appelle **My SID Jukebox** (choix de l'utilisateur).
- **D6** : réglé, voir L7.

## 8. Étapes

0. Essai du parcours (fait, `essais/dirtest.asm`).
1. Essai D1 : écrire et relire un fichier dans `/Temp` (fait, `essais/filetest.asm`).
2. Liste : parcours de SD + USB, écriture de la liste, compteur à l'écran (fait, `essais/liste.asm`, 2026-11-25).
3. Tirage, chargement, contrôle et lecture (fait, `essais/joue.asm`) ; lecture avec le lecteur du jukebox v2.0 adapté.
4. Écran et touches.
5. Effet visuel.
6. Publication (à décider).

## 9. Reprise (fin de session du 2026-11-25)

- Fait : étapes 0 à 3 (`essais/dirtest.asm`, `filetest.asm`, `liste.asm`, `joue.asm`) ; tempo PAL/NTSC vérifié.
- Le C64U fait tourner `build/joue.prg` (PAL). Restes de test : `/SD/JUKETEST` (5 SID, un dossier vide) et
  `/Temp/juketest.bin` (fichier d'essai, inutile).
- Outils PC dans `outils/` : `key.sh` (touche par la matrice), `rate.py` (appels de play par seconde), `big.py` (taille
  des dossiers par FTP).
- (2026-11-26 : étape A faite, voir §2 quater.) Ancienne proposition : RSID, étape A = RSID dont init revient et qui
  laissent libre `$A000-$CFFF` ; le lecteur ne fait plus que clavier + temps ; garde-fou NMI du CIA 2 (2 s) si init ne
  revient pas. Avant : compter par FTP combien des 94 RSID de la collection entrent dans la zone. Étape B (plus tard) :
  RSID à boucle principale ou à digis NMI (reprise par RESTORE, ou redémarrage qui retrouve la liste dans `/Temp`).
- Autres suites : relais d'écriture SID posés sur le C64 (hauteur PAL/NTSC exacte + vu-mètres), écran définitif,
  passage automatique à 3:00 et R pendant la lecture à vérifier, nom du projet (D5).

## 10. Reprise (2026-11-26)

- **Décision finale : RSID exclus** (D2). `essais/joue.asm` = version d'avant l'étape A + refus silencieux des RSID ;
  le C64U fait tourner `build/joue.prg`. Ce qui suit est gardé pour mémoire.

- RSID étape A faite (§2 quater), sauvegarde avant changements : `essais/joue-avant-rsid.asm`.
- Reste : RSID qui gardent le CPU (IRQ sans retour, init qui boucle avec `$FFFA` pris). Pistes : NMI à nous (alarme TOD
  réarmée tous les 1/10 s, enchaînée sur la NMI du morceau) pour lire clavier et temps hors boucle ; écritures `sta $FFFA`
  du morceau détournées avant lancement ; ou refus après un blocage (marqueur « en cours » dans /Temp).

## 11. Écran définitif (2026-11-26, `src/mysidjukebox.asm`)

- Choix de l'utilisateur : textes en **anglais**, **logo géant** « MY SID JUKEBOX » (28 colonnes x 3 lignes, `outils/mkbig.py`
  → `src/big.inc`), effet **voix 3**. Programme définitif dans `src/` (les essais restent dans `essais/`).
- Banque VIC 3 : écran `$CC00`, police `$E000` (RAM sous le KERNAL) = police du C64 minuscules + logo (codes 128+) + 8 barres.
  `$0288 = $CC` (le KERNAL écrit dans le bon écran), `$0291 = $80` (pas de changement de jeu par SHIFT + C=). Retour au BASIC
  (Q) : banque 0, `$D018 = $17`, `$0288 = $04`.
- Écran de lecture : logo centré (lignes 0-2), sous-titre centré (4), tout le reste aligné en colonne 1, titre / auteur / date (8, 10, 12), chemin (11-12, début coupé « ... »),
  sous-morceau + temps + norme (14), avertissement de norme (15), effet (16-20), ligne d'état des refus (22), touches (23),
  numéro du tirage (24). Écrans de choix des lecteurs et de recherche avec le même logo.
- Effet : l'oscilloscope de `$D41B` ne montrait que des blocs (voix 3 souvent en onde carrée) : remplacé par l'**enveloppe de la
  voix 3 (`$D41C`) qui défile**, échelle logarithmique. Limite : voix 3 muette = effet vide, son tenu = effet plat.
- Outil : `outils/ecran_png.py sortie.png` reconstitue l'écran en PNG par l'API (la capture HDMI ne donnait que du noir le 2026-11-26).
- Vérifié sur le C64U : lecture, ESPACE, R (choix des lecteurs, RETURN), recherche complète puis lecture.
- **Retouches du 2026-11-26 (demandes de l'utilisateur)** : effet voix 3 **retiré** (« je n'aime pas les vu-mètres » : ne
  pas en reproposer) ; version en haut à droite (`.const VERSION`, « v1.0 ») ; étiquettes **Title: / Artist: / Released:**
  (valeurs à une espace du « : », coupées au bord) ; touche **L = Loop** comme le jukebox en ligne (le morceau recommence à la fin de
  sa durée, même sous-morceau ; « Loop » en vert quand actif ; reste actif au morceau suivant). Ligne des touches (40 col.) :
  sur deux lignes centrées (21-22) : `SPACE Next  +/- Tune  L Loop` puis `R Scan  Q Quit`. Durée réglable pour les essais : `:DUREE=10`. Bouclage vérifié sur le C64U.
- **Barre de progression** (2026-11-26) : ligne 19, 38 caractères de 8 points (glyphes `bar_chars` en code 128 + BIG_N :
  partie écoulée épaisse, reste en trait fin), mise à jour chaque seconde ; Title / Artist / Released une ligne sur deux (8, 10, 12).
  Durée totale affichée calculée depuis `DUREE`.
- **Couleurs** (2026-11-26) : palette des bleus du logo, un seul accent jaune. Fond et bordure noirs ; sous-titre et
  étiquettes bleu clair (14) ; valeurs blanc (titre) et gris clair (15) ; chemin et numéro du tirage gris (12) ; ligne Tune / norme
  cyan (3), temps blanc ; barre cyan (écoulé) / bleu (reste) ; touches : lettres blanches, mots bleu clair, « Loop » jaune (7) si
  actif ; avertissement de norme jaune ; refus rouge clair (10).
