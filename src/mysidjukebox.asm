// My SID Jukebox : jukebox SID hors ligne pour C64 Ultimate (programme définitif, issu de essais/joue.asm).
// Écran : banque VIC 3, écran $CC00, caractères $E000 (police du C64 + logo géant).
// (historique de l'essai :) Choix des lecteurs, liste dans /Temp (gardée, R pour la refaire),
// tirage au hasard, chargement du .sid et lecture.
// Mémoire : programme recopié en $A000-$BFFF (ROM BASIC coupée, $01 = $36) ; routines d'appel et d'IRQ + variables en
// $C000-$CFFF ; morceaux permis en $0800-$9FFF (même zone que le tas de la recherche, jamais utilisés en même temps).
// Lecture : PSID seulement (RSID exclus, décision D2 du 2026-11-26 ; play = 0 refusé), IRQ raster (VBI) ou timer du CIA 1 selon le
// champ speed ; page zéro et pages 2-3 sauvées avant init et rendues à l'arrêt ; temps compté par le CIA 2 (1/100 s).
// Touches pendant la lecture (matrice, sans KERNAL) : ESPACE suivant, + / - sous-morceau, R refaire la liste, Q quitter.
        .encoding "petscii_mixed"
        #import "big_size.inc"
        .const CHROUT = $FFD2
        .const GETIN  = $FFE4
        .const PLOT   = $FFF0
        .const UCI_CTRL = $DF1C
        .const UCI_CMD  = $DF1D
        .const UCI_RESP = $DF1E
        .const UCI_STAT = $DF1F
        .const ptr = $FB                // parcours / chargement
        .const hp  = $FD
        .const sp  = $22                // chaînes à afficher
        .const CODE = $A000
        .const LOW  = $C000             // appels du morceau, IRQ, sortie (hors ROM)
        .const BSS  = $C100
        .const ZPS  = $C800             // sauvegarde page zéro
        .const P23S = $CA00             // sauvegarde pages 2-3
        .const HEAP = $0800             // tas de la recherche = zone des morceaux
        .const HEAPEND = $A000
        .const TUNELO = $0800
        .const TUNEHI = $A000           // première adresse interdite au morceau
        .const ENT = 128
        .const l_temp = 5
        .const l_nom = 12
        .const NDRV = 8
        .const LT = 2                   // cible DOS du fichier de liste
        .const DUREE = cmdLineVars.containsKey("DUREE") ? cmdLineVars.get("DUREE").asNumber() : 180  // secondes par morceau (essai : :DUREE=10)
        .const SCR  = $CC00             // écran (banque VIC 3)
        .const COLR = $D800
        .const CHR  = $E000             // caractères (RAM sous le KERNAL)
        .const D018V = $38              // écran $CC00, caractères $E000
        .const BORD = 0
        .const BACK = 0
        .const LOGOX = (40 - BIG_W) / 2 // logo centré
        .const VERSION = "v1.0"         // affichée en haut à droite
        .const VLEN = VERSION.size()
        .const LROW = 0                 // logo : lignes 0-2 (version à droite sur la ligne 0)
        .const IROW = 8                 // Title / Artist / Released : lignes 8, 10, 12
        .const PROW = 14                // chemin : lignes 14-15
        .const TROW = 17                // sous-morceau, temps, norme
        .const TCOL = 15
        .const BROW = 19                // barre de progression
        .const BARX = 1
        .const BARW = 38                // 38 caractères de 8 points
        .const BARK = round(BARW * 8 * 256 / DUREE)  // points = secs x BARK / 256
        .const BAR0 = 128 + BIG_N       // 9 glyphes : 0 à 8 points pleins à gauche, trait fin à droite
        .const SROW = 20                // ligne d'état (refus ; même ligne que l'avertissement de norme)
        .const KROW = 21                // touches : lignes 21-22, centrées
        .const MAXREF = 40              // refus d'affilée avant d'abandonner
        .const FORCEK = cmdLineVars.containsKey("FORCEK") ? cmdLineVars.get("FORCEK").asNumber() : -1  // essai : 1er tirage imposé

        BasicUpstart2(boot)

        .macro print(s) {
        lda #<s
        ldy #>s
        jsr prs
        }
        .macro setpkt(r) {
        lda #<r
        sta onpkt
        lda #>r
        sta onpkt + 1
        }
        .macro step(name) {
        lda #<name
        sta etape
        lda #>name
        sta etape + 1
        jsr exec
        bcs !+
        jmp fatal
!:
        }
        .macro copy(src, dst, len) {
        lda #<src
        sta $FB
        lda #>src
        sta $FC
        lda #<dst
        sta $FD
        lda #>dst
        sta $FE
        ldx #>(len + 255)
        ldy #0
!:      lda ($FB),y
        sta ($FD),y
        iny
        bne !-
        inc $FC
        inc $FE
        dex
        bne !-
        }

// ------------------------------------------------------------ démarrage (en $0801, écrasé ensuite)
boot:   sei
        lda #$36
        sta $01
        :copy(srcA, CODE, endA - CODE)
        :copy(srcL, LOW, endL - LOW)
        lda #0                  // variables à zéro (la RAM garde ce qu'a laissé le programme précédent)
        tax
!:      sta BSS,x
        sta BSS + $100,x
        sta BSS + $200,x
        sta BSS + $300,x
        sta BSS + $400,x
        sta BSS + $500,x
        inx
        bne !-
        cli
        jmp start

// ------------------------------------------------------------ bloc bas ($C000) : appels du morceau et IRQ
srcL:
        .pseudopc LOW {
// init du morceau : A = sous-morceau - 1
callinit:
        ldx #0
        ldy #0
        jsr doinit
        lda #$36                // le morceau a pu changer $01
        sta $01
        rts
doinit: jmp (initv)

// IRQ (par $0314 : le KERNAL a déjà empilé A, X, Y)
irq:    lda $DC0D               // acquitte le CIA 1 (mode timer)
        lda #$FF
        sta $D019               // acquitte le raster (mode VBI)
        jsr doplay
        lda #$36
        sta $01
        inc frames
        bne !+
        inc frames + 1
!:      jmp $EA81               // dépile Y, X, A ; RTI
doplay: jmp (playv)

// retour au BASIC
exitb:  sei
        lda #$37
        sta $01
        lda $DD00               // banque VIC 0, écran $0400, police en ROM
        ora #$03
        sta $DD00
        lda #$17
        sta $D018
        lda #$04
        sta $0288
        lda #0
        sta $0291
        lda #14
        sta $D020
        lda #6
        sta $D021
        cli
        lda #$93
        jsr CHROUT
        jmp ($A002)
endL:
        }

// ------------------------------------------------------------ programme principal ($A000)
srcA:
        .pseudopc CODE {
start:  tsx
        stx savesp
        jsr vinit
        lda #$93
        jsr CHROUT
        lda UCI_CMD
        cmp #$C9
        beq !+
        :print(t_nouci)
        jmp exitb
!:      lda UCI_CTRL            // commande laissée en cours par un programme précédent : abandon
        and #$30
        beq !+
        lda #$04
        sta UCI_CTRL
        jsr tstart
w_ab:   lda UCI_CTRL
        and #$34
        beq !+
        jsr tover
        bcc w_ab
        :print(t_abort)
        jmp exitb
!:      lda $DC04               // graine du hasard
        eor $A2
        sta rnd
        lda $D012
        ora #1
        sta rnd + 1
        lda $02A6               // 1 = PAL
        sta pal
        :setpkt(nop)
        jsr readcnt             // liste complète gardée dans /Temp ?
        bcc !+
        jmp pick
!:      jsr choose
        bcs !+
        jmp exitb
!:      jsr scan
        jmp go

// ------------------------------------------------------------ tirage, chargement, lecture
pick:   jsr random              // k = (rnd * nsid) >> 16
        lda rnd
        sta m1
        lda rnd + 1
        sta m1 + 1
        lda nsid
        sta m2
        lda nsid + 1
        sta m2 + 1
        jsr mul16
        lda prod + 2
        sta k
        lda prod + 3
        sta k + 1
        .if (FORCEK >= 0) {
        lda forced
        bne !+
        inc forced
        lda #<FORCEK
        sta k
        lda #>FORCEK
        sta k + 1
!:
        }
        lda #0
        sta song                // 0 = sous-morceau de départ de l'en-tête
loadk:  jsr getent
        jsr loadsid
        bcs !+
        jmp refus
!:      lda #0
        sta nref
        jsr show
        jsr playstart
        jmp ploop

// refus : raison en A/Y affichée 1 s, puis autre tirage
refus:  sta rais
        sty rais + 1
        cmp #<r_rsid            // RSID : exclus sans message ni attente (décision du 2026-11-26)
        bne !+
        cpy #>r_rsid
        bne !+
        jmp rcount
!:      jsr clrst
        lda #10
        sta $0286
        :print(t_refus)
        lda rais
        ldy rais + 1
        jsr prs
        lda #50
        jsr waitj
rcount: inc nref
        lda nref
        cmp #MAXREF
        bcs !+
        jmp pick
!:      jsr clrst
        :print(t_trop)
!:      jsr GETIN
        beq !-
        jmp pick

// lit l'entrée k de la liste dans ent
getent: lda #LT
        sta target
        jsr cd_temp
        :step(s_cdtemp)
        lda #$01
        jsr openf
        :step(s_openr)
        lda #$06                // FILE_SEEK k * 128
        sta cmd + 1
        lda #0
        sta cmd + 2
        lda k
        lsr
        ror cmd + 2
        lda k
        lsr
        sta cmd + 3
        lda k + 1
        and #$01
        beq !+
        lda cmd + 3
        ora #$80
        sta cmd + 3
!:      lda k + 1
        lsr
        sta cmd + 4
        lda #0
        sta cmd + 5
        lda #6
        sta cmdn
        :step(s_seek)
        lda #<ent
        ldx #>ent
        jsr bufset
        :setpkt(tobuf)
        lda #$04
        jsr readn
        :step(s_read)
        jsr closef
        :step(s_close)
        rts

// ouvre et charge le .sid de ent ; C = 1 si prêt à jouer, sinon A/Y = raison
loadsid: {
        lda #1
        sta target
        ldx #0                  // ent = dossier 0 nom 0
!:      lda ent,x
        beq !+
        sta path,x
        inx
        bne !-
!:      stx plen
        inx
        stx inom
        jsr cd_path
        bcs !+
        lda #<r_dos
        ldy #>r_dos
        clc
        rts
!:      lda #$02                // OPEN_FILE lecture
        sta cmd + 1
        lda #$01
        sta cmd + 2
        ldy #3
        ldx inom
!:      lda ent,x
        beq !+
        sta cmd,y
        inx
        iny
        bne !-
!:      sty cmdn
        :setpkt(nop)
        jsr exec
        bcs !+
        lda #<r_dos
        ldy #>r_dos
        clc
        rts
!:      lda #<hdr               // en-tête
        ldx #>hdr
        jsr bufset
        :setpkt(tobuf)
        lda #$04
        jsr readn
        jsr exec
        lda lastn
        cmp #$76
        bcs !+
        jmp k_fmt
!:      lda hdr + 1             // « PSID » ou « RSID »
        cmp #$53
        beq !+
        jmp k_fmt
!:      lda hdr
        cmp #$52
        bne !+
        jmp k_rsid
!:      cmp #$50
        beq !+
        jmp k_fmt
!:      lda hdr + $0D           // play = 0 : le morceau pose sa propre IRQ
        ora hdr + $0C
        bne !+
        jmp k_play0
!:      lda hdr + $0B
        sta initv
        lda hdr + $0A
        sta initv + 1
        lda hdr + $0D
        sta playv
        lda hdr + $0C
        sta playv + 1
        lda hdr + $0F           // sous-morceaux
        sta nsongs
        lda hdr + $0E
        beq !+
        lda #255                // plus de 255 : borné
        sta nsongs
!:      lda song
        bne !+
        lda hdr + $11           // départ de l'en-tête
        sta song
!:      lda song
        beq s1
        cmp nsongs
        beq s_ok
        bcc s_ok
s1:     lda #1
        sta song
s_ok:   lda #$06                // FILE_SEEK dataOffset
        sta cmd + 1
        lda hdr + 7
        sta cmd + 2
        lda hdr + 6
        sta cmd + 3
        lda #0
        sta cmd + 4
        sta cmd + 5
        lda #6
        sta cmdn
        :setpkt(nop)
        jsr exec
        bcs !+
        jmp k_dos
!:      lda hdr + 9             // adresse de chargement
        sta load
        lda hdr + 8
        sta load + 1
        ora load
        bne !+
        lda #<load              // 0 : les deux premiers octets des données
        ldx #>load
        jsr bufset
        :setpkt(tobuf)
        lda #$04
        sta cmd + 1
        lda #2
        sta cmd + 2
        lda #0
        sta cmd + 3
        sta lastn
        lda #4
        sta cmdn
        jsr exec
        lda lastn
        cmp #2
        beq !+
        jmp k_fmt
!:      lda load + 1            // zone basse
        cmp #>TUNELO
        bcs !+
        jmp k_zone
!:      lda load
        sta ptr
        lda load + 1
        sta ptr + 1
        lda #0
        sta over
        :setpkt(todest)
rd:     lda #$04
        jsr readn
        jsr exec
        bcc fin
        lda over
        bne fin
        lda lastn
        cmp #128
        beq rd
fin:    jsr closef
        jsr exec
        lda over
        beq !+
        jmp k_zone
!:      lda ptr                 // fin = ptr - 1
        sec
        sbc #1
        sta zfin
        lda ptr + 1
        sbc #0
        sta zfin + 1
        lda initv + 1           // init et play dans $0800-$9FFF
        cmp #>TUNELO
        bcc k_adr
        cmp #>TUNEHI
        bcs k_adr
        lda playv + 1
        cmp #>TUNELO
        bcc k_adr
        cmp #>TUNEHI
        bcs k_adr
        jsr modes
        sec
        rts
k_fmt:  lda #<r_fmt
        ldy #>r_fmt
        jmp ko
k_rsid: lda #<r_rsid
        ldy #>r_rsid
        jmp ko
k_play0: lda #<r_play0
        ldy #>r_play0
        jmp ko
k_dos:  lda #<r_dos
        ldy #>r_dos
        jmp ko
k_zone: lda #<r_zone
        ldy #>r_zone
        jmp ko
k_adr:  lda #<r_adr
        ldy #>r_adr
ko:     pha
        tya
        pha
        jsr closef              // fichier peut-être encore ouvert (erreur ignorée)
        jsr exec
        pla
        tay
        pla
        clc
        rts
}

// paquet de READ_DATA -> (ptr), sans dépasser TUNEHI
todest: {
        clc
        lda ptr
        adc pktn
        lda ptr + 1
        adc #0
        cmp #>TUNEHI
        bcc ok
        bne trop
        lda ptr                 // fin pile sur TUNEHI permise
        clc
        adc pktn
        beq ok
trop:   lda #1
        sta over
        rts
ok:     ldy #0
!:      lda pkt,y
        sta (ptr),y
        iny
        cpy pktn
        bne !-
        clc
        lda ptr
        adc pktn
        sta ptr
        bcc !+
        inc ptr + 1
!:      clc
        lda lastn
        adc pktn
        sta lastn
        rts
}

// ------------------------------------------------------------ lecture
playstart: {
        sei
        ldx #2                  // sauvegarde page zéro et pages 2-3
!:      lda $00,x
        sta ZPS,x
        inx
        bne !-
!:      lda $0200,x
        sta P23S,x
        lda $0300,x
        sta P23S + $100,x
        inx
        bne !-
        jsr clockinit
        lda #0
        sta frames
        sta frames + 1
        sta secs
        sta secs + 1
        ldx song
        dex
        txa
        jsr callinit
        sei
        lda #<irq
        sta $0314
        lda #>irq
        sta $0315
        lda #0
        sta corr
        lda cia
        bne m_cia
        lda tpal                // VBI
        cmp pal
        bne v_tim
        lda #$7F                // même norme : raster ligne 250, CIA 1 muet
        sta $DC0D
        lda $DC0D
        lda $D011
        and #$7F
        sta $D011
        lda #250
        sta $D012
        lda #$01
        sta $D01A
        lda #$FF
        sta $D019
        jmp go_
v_tim:  lda #1                  // normes différentes : timer du CIA 1 à la cadence d'origine du morceau
        sta corr
        lda #0
        sta $D01A
        lda pal
        beq !+
        lda #<(16469 - 1)       // morceau NTSC (59,83 Hz) sur C64 PAL
        ldx #>(16469 - 1)
        jmp !++
!:      lda #<(20404 - 1)       // morceau PAL (50,12 Hz) sur C64 NTSC
        ldx #>(20404 - 1)
!:      sta $DC04
        stx $DC05
        lda #$11
        sta $DC0E
        jmp c_on
m_cia:  lda #0                  // timer du CIA 1 (celui de init, ou celui du KERNAL)
        sta $D01A
        lda tpal
        cmp pal
        beq c_on
        lda #1                  // normes différentes : période mesurée puis corrigée
        sta corr
        jsr latch
        lda pal
        beq !+
        lda #<2402              // morceau NTSC sur C64 PAL : P x 0,963353 = P - P x 2402/65536
        sta m2
        lda #>2402
        sta m2 + 1
        jsr scaleP
        sec
        lda m1
        sbc prod + 2
        tax
        lda m1 + 1
        sbc prod + 3
        jmp setl
!:      lda #<2493              // morceau PAL sur C64 NTSC : P x 1,038040 = P + P x 2493/65536
        sta m2
        lda #>2493
        sta m2 + 1
        jsr scaleP
        clc
        lda m1
        adc prod + 2
        tax
        lda m1 + 1
        adc prod + 3
setl:   tay                     // latch = P' - 1
        txa
        sec
        sbc #1
        sta $DC04
        tya
        sbc #0
        sta $DC05
        lda #$11
        sta $DC0E
c_on:   lda #$81
        sta $DC0D
        lda $DC0D
go_:    lda #1
        sta playing
        cli
        rts
}

// cia = bit (song-1) du champ speed ($12-$15, bit 31 au-delà de 32) ; tpal = norme du morceau (1 = PAL)
// clock (PSID v2+, $77 bits 2-3) : 1 PAL, 2 NTSC, 3 les deux (= machine), 0 inconnu (= PAL, presque tous les vieux PSID)
modes: {
        ldx song
        dex
        cpx #32
        bcc !+
        ldx #31
!:      txa
        and #7
        tay
        txa
        lsr
        lsr
        lsr
        eor #3
        tax
        lda hdr + $12,x
!:      dey
        bmi !+
        lsr
        jmp !-
!:      and #1
        sta cia
        lda #1
        sta tpal
        lda hdr + 5
        cmp #2
        bcc x
        lda hdr + $77
        lsr
        lsr
        and #3
        cmp #2
        bne !+
        lda #0                  // NTSC
        sta tpal
        rts
!:      cmp #3
        bne x
        lda pal                 // les deux : norme de la machine
        sta tpal
x:      rts
}

// m1 = période du timer A du CIA 1 posée par init (plus grande valeur lue sur ~70 ms) + 1
latch: {
        lda $DC0E               // charge la période posée par init : sinon le compteur finit d'abord l'ancien
        ora #$10                // décompte (celui du KERNAL) et la mesure le prend pour la période
        sta $DC0E
        lda #0
        sta m1
        sta m1 + 1
        ldx #0
        ldy #10                 // 10 x 256 lectures d'environ 35 cycles : plus d'une période de 65 536 cycles
l:      lda $DC05
        sta tmp + 1
        lda $DC04
        pha
        lda $DC05
        cmp tmp + 1
        beq !+
        pla
        jmp l
!:      pla
        sta tmp
        lda tmp + 1
        cmp m1 + 1
        bcc n
        bne g
        lda tmp
        cmp m1
        bcc n
g:      lda tmp
        sta m1
        lda tmp + 1
        sta m1 + 1
n:      dex
        bne l
        dey
        bne l
        inc m1
        bne !+
        inc m1 + 1
!:      rts
}
// prod = m1 x m2 (m1 gardé)
scaleP: lda m1
        pha
        lda m1 + 1
        pha
        jsr mul16
        pla
        sta m1 + 1
        pla
        sta m1
        rts

// arrêt : SID muets, IRQ et CIA du KERNAL, page zéro et pages 2-3 rendues, VIC remis
stop: {
        lda playing
        bne !+
        rts
!:      sei
        lda #0
        sta playing
        sta $D01A
        lda #$FF
        sta $D019
        lda #$7F
        sta $DC0D
        sta $DD0D
        lda #0                  // tous les SID (y compris $D420, $D500...) muets
        tax
!:      sta $D400,x
        sta $D500,x
        inx
        bne !-
        ldx #2
!:      lda ZPS,x
        sta $00,x
        inx
        bne !-
!:      lda P23S,x
        sta $0200,x
        lda P23S + $100,x
        sta $0300,x
        inx
        bne !-
        lda #$36
        sta $01
        lda #$FF                // ports du CIA 1 pour le clavier
        sta $DC02
        lda #0
        sta $DC03
        lda pal                 // timer A du KERNAL : 1/60 s
        beq !+
        lda #$25
        ldx #$40
        jmp !++
!:      lda #$95
        ldx #$42
!:      sta $DC04
        stx $DC05
        lda #$11
        sta $DC0E
        lda #$81
        sta $DC0D
        lda $DC0D
        lda #$1B                // VIC : écran texte normal, banque 0
        sta $D011
        lda #$C8
        sta $D016
        lda #D018V
        sta $D018
        lda #0
        sta $D015
        lda $DD02
        ora #$03
        sta $DD02
        lda $DD00               // banque VIC 3
        and #$FC
        sta $DD00
        lda #BORD
        sta $D020
        lda #BACK
        sta $D021
        cli
        rts
}

// boucle de lecture : clavier (matrice), temps
ploop: {
        jsr keys
        cmp #0
        beq tps
        pha
        jsr release
        pla
        cmp #1
        bne !+
        jsr stop
        jmp pick
!:      cmp #2
        bne !+
        jsr stop
        jmp exitb
!:      cmp #3
        bne !+
        jsr stop
        jsr choose
        bcs sc
        jmp pick
sc:     jsr scan
        jmp go
!:      cmp #4                  // + : sous-morceau suivant
        bne !+
        lda song
        cmp nsongs
        bcs tps
        inc song
        jsr stop
        jmp loadk
!:      cmp #5                  // - : sous-morceau précédent
        bne k_l
        lda song
        cmp #2
        bcc tps
        dec song
        jsr stop
        jmp loadk
k_l:    cmp #6                  // L : boucle oui / non (le morceau continue)
        bne tps
        lda loop
        eor #1
        sta loop
        jsr pkeys
tps:    jsr clocksec
        bcs !+
        jmp ploop
!:
        jsr ptime
        jsr pbar
        lda secs + 1
        bne fini
        lda secs
        cmp #DUREE
        bcs fini
        jmp ploop
fini:   jsr stop
        lda loop                // boucle : même morceau, même sous-morceau, depuis le début
        beq !+
        jmp loadk
!:      jmp pick
}

// A = 0 rien, 1 ESPACE, 2 Q, 3 R, 4 +, 5 -, 6 L
keys: {
        lda #$FF                // un morceau peut avoir changé les directions
        sta $DC02
        lda #0
        sta $DC03
        lda #$7F                // colonne 7 : ESPACE ligne 4, Q ligne 6
        sta $DC00
        lda $DC01
        tax
        and #$10
        beq k1
        txa
        and #$40
        beq k2
        lda #$FB                // colonne 2 : R ligne 1
        sta $DC00
        lda $DC01
        and #$02
        beq k3
        lda #$DF                // colonne 5 : + ligne 0, - ligne 3
        sta $DC00
        lda $DC01
        tax
        and #$01
        beq k4
        txa
        and #$08
        beq k5
        txa                     // L : colonne 5, ligne 2
        and #$04
        beq k6
        lda #0
        rts
k1:     lda #1
        rts
k2:     lda #2
        rts
k3:     lda #3
        rts
k4:     lda #4
        rts
k5:     lda #5
        rts
k6:     lda #6
        rts
}
// attend que toutes les touches soient relâchées
release: {
!:      lda #0
        sta $DC00
        lda $DC01
        cmp #$FF
        bne !-
        lda #$FF
        sta $DC00
        rts
}

// temps : timer A du CIA 2 = 1/100 s, timer B compte ses débordements
clockinit: {
        lda #$7F
        sta $DD0D
        lda pal
        beq !+
        lda #<(9852 - 1)
        ldx #>(9852 - 1)
        jmp !++
!:      lda #<(10227 - 1)
        ldx #>(10227 - 1)
!:      sta $DD04
        stx $DD05
        lda #$FF
        sta $DD06
        sta $DD07
        lda #$51
        sta $DD0F
        lda #$11
        sta $DD0E
        lda $DD0D
        jsr readb
        sta lastb
        stx lastb + 1
        rts
}
readb: {
!:      ldx $DD07
        lda $DD06
        cpx $DD07
        bne !-
        rts
}
// C = 1 si une seconde de plus s'est écoulée (secs augmenté)
clocksec: {
        jsr readb
        sta tmp
        stx tmp + 1
        sec
        lda lastb
        sbc tmp
        sta tdt
        lda lastb + 1
        sbc tmp + 1
        bne oui
        lda tdt
        cmp #100
        bcs oui
        clc
        rts
oui:    sec
        lda lastb
        sbc #100
        sta lastb
        bcs !+
        dec lastb + 1
!:      inc secs
        bne !+
        inc secs + 1
!:      sec
        rts
}
// mm:ss à l'écran (codes écran, sans KERNAL)
ptime: {
        lda secs
        ldx #0
!:      cmp #60
        bcc !+
        sbc #60
        inx
        bne !-
!:      pha
        txa
        jsr dec2
        sta SCR + TROW * 40 + TCOL
        stx SCR + TROW * 40 + TCOL + 1
        pla
        jsr dec2
        sta SCR + TROW * 40 + TCOL + 3
        stx SCR + TROW * 40 + TCOL + 4
        rts
}
// A (0-99) -> A = dizaines, X = unités, en codes écran
dec2: {
        ldx #0
!:      cmp #10
        bcc !+
        sbc #10
        inx
        bne !-
!:      ora #$30
        pha
        txa
        ora #$30
        tax
        pla
        pha
        txa
        tay
        pla
        tax
        tya
        rts
}

// ------------------------------------------------------------ écran du morceau
show: {
        jsr frame
        lda #<t_ti              // Title / Artist / Released
        ldy #>t_ti
        ldx #IROW
        jsr label
        lda #1
        sta $0286
        ldx #$16
        jsr hval
        lda #<t_ar
        ldy #>t_ar
        ldx #IROW + 2
        jsr label
        lda #15
        sta $0286
        ldx #$36
        jsr hval
        lda #<t_re
        ldy #>t_re
        ldx #IROW + 4
        jsr label
        lda #15
        sta $0286
        ldx #$56
        jsr hval
        jsr ppath
        lda #13                 // sous-morceau, temps, norme
        sta $0286
        ldx #TROW
        ldy #1
        clc
        jsr PLOT
        :print(t_song)
        lda #0
        ldx song
        jsr prdec
        lda #'/'
        jsr CHROUT
        lda #0
        ldx nsongs
        jsr prdec
        ldx #TROW
        ldy #TCOL
        clc
        jsr PLOT
        lda #1
        sta $0286
        :print(t_temps)
        lda #13
        sta $0286
        ldx #TROW
        ldy #30
        clc
        jsr PLOT
        lda tpal
        jsr pnorm
        lda #' '
        jsr CHROUT
        lda cia
        bne !+
        lda tpal
        beq n60
        :print(t_50)
        jmp !++
n60:    :print(t_60)
        jmp !+
!:      :print(t_cia)
!:      lda tpal
        cmp pal
        beq !+
        lda #12
        sta $0286
        lda #<t_corr
        ldy #>t_corr
        ldx #BROW + 1
        jsr atleft
!:      jsr pkeys
        lda #0                  // barre vide (secs remis à 0 par playstart de toute façon)
        sta secs
        sta secs + 1
        ldx #BARW - 1
        lda #14
!:      sta COLR + BROW * 40 + BARX,x
        dex
        bpl !-
        jsr pbar
        lda #11                 // ligne 24 : numéro du tirage
        sta $0286
        ldx #24
        ldy #1
        clc
        jsr PLOT
        :print(t_tir)
        lda k + 1
        ldx k
        inx
        bne !+
        clc
        adc #1
!:      jsr prdec
        :print(t_sur)
        lda nsid + 1
        ldx nsid
        jsr prdec
        rts
}

// fond commun : écran effacé, logo géant (lignes 1-3), sous-titre (ligne 5)
frame: {
        lda #$93
        jsr CHROUT
        ldx #BIG_W - 1
!:      lda big_map,x
        sta SCR + LROW * 40 + LOGOX,x
        lda big_map + BIG_W,x
        sta SCR + (LROW + 1) * 40 + LOGOX,x
        lda big_map + 2 * BIG_W,x
        sta SCR + (LROW + 2) * 40 + LOGOX,x
        lda #1
        sta COLR + LROW * 40 + LOGOX,x
        lda #3
        sta COLR + (LROW + 1) * 40 + LOGOX,x
        lda #14
        sta COLR + (LROW + 2) * 40 + LOGOX,x
        dex
        bpl !-
        lda #11                 // version, en haut à droite
        sta $0286
        ldx #0
        ldy #39 - VLEN
        clc
        jsr PLOT
        :print(t_ver)
        lda #12
        sta $0286
        lda #<t_sub             // sous-titre centré
        ldy #>t_sub
        ldx #LROW + 4
        jmp center
}

// chaîne A/Y en colonne 1 de la ligne X
atleft: {
        pha
        tya
        pha
        ldy #1
        clc
        jsr PLOT
        pla
        tay
        pla
        jmp prs
}

// chaîne A/Y (sans codes de couleur) centrée sur la ligne X
center: {
        sta sp
        sty sp + 1
        ldy #0
!:      lda (sp),y
        beq !+
        iny
        bne !-
!:      tya
        eor #$FF                // (40 - longueur) / 2
        sec
        adc #40
        lsr
        tay
        clc
        jsr PLOT
        lda sp
        ldy sp + 1
        jmp prs
}

// barre de progression : secs x BARK / 256 points sur BARW caractères
pbar: {
        lda secs
        sta m1
        lda secs + 1
        sta m1 + 1
        lda #<BARK
        sta m2
        lda #>BARK
        sta m2 + 1
        jsr mul16
        lda prod + 1            // points = prod >> 8, bornés à BARW x 8
        ldx prod + 2
        cpx #>(BARW * 8)
        bcc !+
        bne pl
        cmp #<(BARW * 8)
        bcc !+
pl:     lda #<(BARW * 8)
        ldx #>(BARW * 8)
!:      sta tmp                 // tmp = points (octet bas) ; A = points / 8 = caractères pleins
        stx tmp + 1
        lsr tmp + 1
        ror
        lsr tmp + 1
        ror
        lsr tmp + 1
        ror
        sta tmp + 1
        lda tmp
        and #7
        sta tmp                 // reste (0-7)
        ldx #0
bl:     cpx tmp + 1
        bcs !+
        lda #BAR0 + 8
        bne w
!:      bne !+
        lda tmp
        clc
        adc #BAR0
        bne w
!:      lda #BAR0
w:      sta SCR + BROW * 40 + BARX,x
        inx
        cpx #BARW
        bne bl
        rts
}

// étiquette A/Y (gris) en colonne 1 de la ligne X, puis une espace ; hmax = place restante jusqu'au bord
label: {
        sta sp
        sty sp + 1
        stx svy
        ldy #1
        clc
        jsr PLOT
        lda #12
        sta $0286
        lda sp
        ldy sp + 1
        jsr prs
        lda #' '
        jsr CHROUT
        sec                     // colonne du curseur
        jsr PLOT
        tya
        eor #$FF
        sec
        adc #40
        sta hmax
        rts
}

// chaîne de l'en-tête en X : jusqu'au bord droit (hmax caractères au plus)
hval: {
        ldy hmax
!:      lda hdr,x
        beq x
        jsr a2p
        jsr CHROUT
        inx
        dey
        bne !-
x:      rts
}

// touches sur deux lignes centrées : « Loop » en vert clair quand la boucle est active
pkeys: {
        ldx #KROW
        ldy #(40 - 28) / 2      // « SPACE Next  +/- Tune  L Loop » = 28 colonnes
        clc
        jsr PLOT
        :print(t_k1)
        lda #$9B
        ldx loop
        beq !+
        lda #$99
!:      jsr CHROUT
        :print(t_loop)
        ldx #KROW + 1
        ldy #(40 - 14) / 2      // « R Scan  Q Quit » = 14 colonnes
        clc
        jsr PLOT
        :print(t_k2)
        rts
}

// chemin complet (dossier/nom), lignes 11-12, 78 caractères au plus : début remplacé par « ... »
ppath: {
        ldy #0
        ldx #0
!:      cpx plen
        beq !+
        lda path,x
        jsr a2p
        sta sbuf,y
        inx
        iny
        bne !-
!:      lda #'/'
        sta sbuf,y
        iny
        ldx inom
!:      lda ent,x
        beq !+
        jsr a2p
        sta sbuf,y
        inx
        iny
        cpy #160
        bne !-
!:      sty sbn
        lda #11
        sta $0286
        ldx #PROW
        ldy #1
        clc
        jsr PLOT
        lda #39                 // place sur la 1re ligne (colonnes 1-39)
        sta tmp
        ldx #0
        lda sbn
        cmp #79
        bcc pr
        lda #'.'
        jsr CHROUT
        jsr CHROUT
        jsr CHROUT
        lda #36
        sta tmp
        lda sbn                 // on garde les 75 derniers
        sec
        sbc #75
        tax
pr:     cpx sbn
        beq x
        lda tmp                 // 1re ligne pleine : suite en colonne 1 de la ligne suivante
        bne !+
        stx svx
        ldx #PROW + 1
        ldy #1
        clc
        jsr PLOT
        ldx svx
        dec tmp                 // tmp = $FF : plus de changement de ligne
!:      lda sbuf,x
        jsr CHROUT
        dec tmp
        inx
        bne pr
x:      rts
}

// efface la ligne d'état et y place le curseur
clrst: {
        ldx #39
        lda #' '
!:      sta SCR + SROW * 40,x
        dex
        bpl !-
        ldx #SROW
        ldy #1
        clc
        jmp PLOT
}

// écran du jukebox : police du C64 (minuscules) recopiée en $E000, logo à partir du code 128, banque VIC 3
vinit: {
        sei
        lda #$32                // ROM des caractères visible, BASIC coupé ($33 cacherait ce programme en $A000)
        sta $01
        ldx #0
!:
        .for (var i = 0; i < 8; i++) {
        lda $D800 + i * 256,x
        sta CHR + i * 256,x
        }
        inx
        bne !-
        lda #$36
        sta $01
        ldx #0
!:      lda big_chars,x
        sta CHR + 128 * 8,x
        lda big_chars + BIG_N * 4,x
        sta CHR + 128 * 8 + BIG_N * 4,x
        inx
        cpx #BIG_N * 4
        bne !-
        ldx #9 * 8 - 1
!:      lda bar_chars,x
        sta CHR + BAR0 * 8,x
        dex
        bpl !-
        lda $DD02
        ora #$03
        sta $DD02
        lda $DD00
        and #$FC
        sta $DD00
        lda #D018V
        sta $D018
        lda #>SCR
        sta $0288
        lda #$80                // SHIFT + C= ne change plus de jeu de caractères
        sta $0291
        lda #BORD
        sta $D020
        lda #BACK
        sta $D021
        cli
        rts
}
// barre : glyphe n = n points pleins à gauche (lignes 1-6), trait fin (lignes 3-4) sur toute la largeur
bar_chars:
        .for (var n = 0; n <= 8; n++) .for (var r = 0; r < 8; r++) .byte ((r >= 1 && r <= 6) ? ($FF00 >> n) & $FF : 0) | ((r == 3 || r == 4) ? $FF : 0)
        #import "big.inc"

pnorm:  beq !+
        :print(t_pal)
        rts
!:      :print(t_ntsc)
        rts

// chaîne de l'en-tête en X (32 car. au plus), puis retour à la ligne
pstr: {
        ldy #32
!:      lda hdr,x
        beq x
        jsr a2p
        jsr CHROUT
        inx
        dey
        bne !-
x:      lda #13
        jmp CHROUT
}

// ------------------------------------------------------------ recherche (liste refaite)
scan:   jsr frame
        lda #15
        sta $0286
        lda #<t_titre
        ldy #>t_titre
        ldx #IROW
        jsr atleft
        lda #0
        sta nsid
        sta nsid + 1
        sta ndirs
        sta ndirs + 1
        sta nlong
        sta nlong + 1
        sta nplein
        sta nplein + 1
        sta tmax
        sta tmax + 1
        lda #<HEAP
        sta heap
        lda #>HEAP
        sta heap + 1
        lda #0                  // compteur à 0 pendant la recherche : une recherche interrompue sera refaite
        tax
        jsr writecnt
        lda #LT
        sta target
        jsr cd_temp
        :step(s_cdtemp)
        lda #$0A                // écriture + création en écrasant
        jsr openf
        :step(s_openw)
        jsr jzero
        ldx #0
rootl:  lda roots,x
        beq rootf
        ldy #0
!:      lda roots,x
        beq !+
        sta path,y
        inx
        iny
        bne !-
!:      sty plen
        inx
        stx inext
        lda #1
        sta target
        jsr cd_path
        bcc !+
        jsr walk
!:      ldx inext
        jmp rootl
rootf:  lda #LT
        sta target
        jsr closef
        :step(s_close)
        sei
        lda $A2
        sta tj
        lda $A1
        sta tj + 1
        cli
        jsr counter
        ldx #IROW + 4
        ldy #1
        clc
        jsr PLOT
        lda #12
        sta $0286
        :print(t_dirs)
        lda ndirs + 1
        ldx ndirs
        jsr prdec
        :print(t_temps2)
        lda tj + 1
        ldx tj
        jsr prdec
        :print(t_jif)
        lda nsid
        ldx nsid + 1
        jsr writecnt
        lda #100
        jmp waitj

go:     lda nsid
        ora nsid + 1
        beq !+
        jmp pick
!:      jsr clrst
        :print(t_aucun)
!:      jsr GETIN
        beq !-
        jmp exitb

// attend A jiffies
waitj: {
        clc
        adc $A2
!:      cmp $A2
        bne !-
        rts
}

readcnt: {
        lda #LT
        sta target
        jsr cd_temp
        jsr exec
        bcc non
        lda #$01
        jsr openc
        jsr exec
        bcc non
        lda #<cntv
        ldx #>cntv
        jsr bufset
        :setpkt(tobuf)
        lda #$04
        jsr readn
        jsr exec
        jsr closef
        jsr exec
        lda lastn
        cmp #2
        bne non
        lda cntv
        ora cntv + 1
        beq non
        lda cntv
        sta nsid
        lda cntv + 1
        sta nsid + 1
        sec
        rts
non:    clc
        rts
}

writecnt: {
        sta cntv
        stx cntv + 1
        lda #LT
        sta target
        jsr cd_temp
        :step(s_cdtemp)
        lda #$0A
        jsr openc
        :step(s_opencnt)
        lda #$05
        sta cmd + 1
        lda #0
        sta cmd + 2
        sta cmd + 3
        lda cntv
        sta cmd + 4
        lda cntv + 1
        sta cmd + 5
        lda #6
        sta cmdn
        :step(s_write)
        jsr closef
        :step(s_close)
        rts
}

// ------------------------------------------------------------ choix des lecteurs
choose: {
        lda #0
        sta ndrv
        lda #1
        sta target
        lda #1
        sta plen
        lda d_root
        sta path
        jsr cd_path
        bcs !+
        jmp fatal
!:      lda #$13
        jsr simple
        bcs !+
        jmp fatal
!:      lda stat + 1
        cmp #$31
        beq aff
        :setpkt(drvstore)
        lda #$14
        sta cmd + 1
        lda #2
        sta cmdn
        jsr exec
        bcs aff
        jmp fatal
aff:    jsr frame
        ldx #IROW - 1
        ldy #0
        clc
        jsr PLOT
        lda #15
        sta $0286
        :print(t_choix)
        lda ndrv
        bne !+
        :print(t_nodrv)
        clc
        rts
!:      ldx #0
ligne:  stx idrv
        lda #' '
        jsr CHROUT
        txa
        clc
        adc #'1'
        jsr CHROUT
        lda #' '
        jsr CHROUT
        lda #'['
        jsr CHROUT
        lda drvsel,x
        beq !+
        lda #'x'
        .byte $2C
!:      lda #' '
        jsr CHROUT
        lda #']'
        jsr CHROUT
        lda #' '
        jsr CHROUT
        lda idrv
        asl
        asl
        asl
        asl
        tax
!:      lda drvtab,x
        beq !+
        jsr a2p
        jsr CHROUT
        inx
        bne !-
!:      lda #13
        jsr CHROUT
        ldx idrv
        inx
        cpx ndrv
        bne ligne
        :print(t_choixt)
key:    jsr GETIN
        beq key
        cmp #'q'
        bne !+
        clc
        rts
!:      cmp #13
        beq valide
        sec
        sbc #'1'
        cmp ndrv
        bcs key
        tax
        lda drvsel,x
        eor #1
        sta drvsel,x
        jmp aff
valide: ldx #0
        ldy #0
        sty idrv
r_l:    lda drvsel,x
        beq r_n
        lda #'/'
        sta roots,y
        iny
        txa
        asl
        asl
        asl
        asl
        sta tmp
        stx svx
        ldx tmp
!:      lda drvtab,x
        beq !+
        sta roots,y
        inx
        iny
        bne !-
!:      lda #$2F
        sta roots,y
        iny
        lda #0
        sta roots,y
        iny
        inc idrv
        ldx svx
r_n:    inx
        cpx ndrv
        bne r_l
        lda #0
        sta roots,y
        lda idrv
        bne !+
        jmp key
!:      sec
        rts
}

drvstore: {
        lda pkt
        and #$10
        beq x
        lda ndrv
        cmp #NDRV
        bcs x
        lda #<d_flash
        ldx #>d_flash
        jsr pktis
        bcs x
        lda #<d_tmp
        ldx #>d_tmp
        jsr pktis
        bcs x
        lda ndrv
        asl
        asl
        asl
        asl
        tay
        ldx #1
!:      cpx pktn
        beq !+
        lda pkt,x
        beq !+
        sta drvtab,y
        iny
        inx
        cpx #16
        bcc !-
!:      lda #0
        sta drvtab,y
        ldx ndrv
        lda #1
        sta drvsel,x
        inc ndrv
x:      rts
}

pktis: {
        sta hp
        stx hp + 1
        ldy #0
        ldx #1
!:      lda (hp),y
        beq fin
        cpx pktn
        bcs non
        cmp pkt,x
        bne non
        iny
        inx
        bne !-
fin:    cpx pktn
        bcs oui
        lda pkt,x
        beq oui
non:    clc
        rts
oui:    sec
        rts
}

// ------------------------------------------------------------ parcours
walk: {
        inc ndirs
        bne !+
        inc ndirs + 1
!:      lda heap
        pha
        lda heap + 1
        pha
        lda #$13
        jsr simple
        bcs !+
        jmp fatal
!:      lda stat + 1
        cmp #$31
        beq vide
        :setpkt(store)
        lda #$14
        sta cmd + 1
        lda #2
        sta cmdn
        jsr exec
        bcs vide
        jmp fatal
vide:   ldy #0
        lda heap
        sta hp
        lda heap + 1
        sta hp + 1
        tya
        sta (hp),y
        inc heap
        bne !+
        inc heap + 1
!:      tsx
        lda $0102,x
        sta ptr
        lda $0101,x
        sta ptr + 1
loop:   ldy #0
        lda (ptr),y
        bne !+
        jmp done
!:      sta elen
        ldy #1
        lda (ptr),y
        and #$10
        beq file
        lda ptr
        pha
        lda ptr + 1
        pha
        lda elen
        pha
        lda plen
        pha
        jsr addname
        bcc !+
        jsr cd_path
        bcc !+
        jsr walk
!:      pla
        sta plen
        pla
        sta elen
        pla
        sta ptr + 1
        pla
        sta ptr
        jmp adv
file:   jsr addentry
adv:    sec
        lda ptr
        adc elen
        sta ptr
        bcc !+
        inc ptr + 1
!:      jmp loop
done:   pla
        sta heap + 1
        pla
        sta heap
        lda #1
        sta target
        rts
}

// paquet de READ_DIR -> tas, seulement sous-dossiers (hors système) et .sid ; tas borné
store: {
        lda #<(pkt - 1)
        sta ptr
        lda #>(pkt - 1)
        sta ptr + 1
        lda pktn
        sta elen
        lda pkt
        and #$10
        beq fic
        jsr skipdir
        bcs x
        jmp garde
fic:    jsr issid
        bcc x
garde:  clc
        lda heap
        adc pktn
        tax
        lda heap + 1
        adc #0
        tay
        inx
        bne !+
        iny
!:      inx
        bne !+
        iny
!:      cpy #>HEAPEND
        bcc ok
        inc nplein
        bne x
        inc nplein + 1
x:      rts
ok:     lda heap
        sta hp
        lda heap + 1
        sta hp + 1
        ldy #0
        lda pktn
        sta (hp),y
        ldx #0
!:      lda pkt,x
        iny
        sta (hp),y
        inx
        cpx pktn
        bne !-
        sec
        lda heap
        adc pktn
        sta heap
        bcc !+
        inc heap + 1
!:      rts
}

skipdir: {
        ldy #2
        lda (ptr),y
        cmp #$2E
        beq oui
        cmp #$24
        beq oui
        ldx #0
!:      lda (ptr),y
        cmp d_svi,x
        bne non
        cmp #0
        beq oui
        inx
        iny
        cpy elen
        bcc !-
        beq !-
        lda d_svi,x
        beq oui
non:    clc
        rts
oui:    sec
        rts
}

issid: {
        ldy #2
!:      cpy elen
        beq !+
        bcs fin
!:      lda (ptr),y
        beq fin
        iny
        bne !--
fin:    dey
        cpy #5
        bcc non
        lda (ptr),y
        and #$DF
        cmp #$44
        bne non
        dey
        lda (ptr),y
        and #$DF
        cmp #$49
        bne non
        dey
        lda (ptr),y
        and #$DF
        cmp #$53
        bne non
        dey
        lda (ptr),y
        cmp #$2E
        bne non
        sec
        rts
non:    clc
        rts
}

addname: {
        ldx plen
        lda #$2F
        cmp path - 1,x
        beq !+
        sta path,x
        inx
!:      ldy #2
!:      cpy elen
        beq !+
        bcs x
!:      lda (ptr),y
        beq x
        sta path,x
        inx
        cpx #121
        bcs long
        iny
        bne !--
x:      stx plen
        sec
        rts
long:   clc
        rts
}

addentry: {
        ldx #0
!:      cpx plen
        beq !+
        lda path,x
        sta cmd + 4,x
        inx
        bne !-
!:      lda #0
        sta cmd + 4,x
        inx
        ldy #2
!:      cpy elen
        beq !+
        bcs fin
!:      lda (ptr),y
        beq fin
        cpx #ENT - 1
        bcs long
        sta cmd + 4,x
        inx
        iny
        bne !--
fin:    lda #0
!:      cpx #ENT
        beq !+
        sta cmd + 4,x
        inx
        bne !-
!:      lda #$05
        sta cmd + 1
        lda #0
        sta cmd + 2
        sta cmd + 3
        lda #ENT + 4
        sta cmdn
        lda #LT
        sta target
        :setpkt(nop)
        :step(s_write)
        lda #1
        sta target
        inc nsid
        bne !+
        inc nsid + 1
!:      jmp counter
long:   inc nlong
        bne !+
        inc nlong + 1
!:      rts
}

counter: {
        sec
        jsr PLOT
        stx svx
        sty svy
        ldx #IROW + 2
        ldy #1
        clc
        jsr PLOT
        lda #1
        sta $0286
        lda nsid + 1
        ldx nsid
        jsr prdec
        :print(t_trouves)
        ldx svx
        ldy svy
        clc
        jmp PLOT
}

// ------------------------------------------------------------ utilitaires
cd_temp: {
        lda #$11
        sta cmd + 1
        ldx #0
!:      lda d_temp,x
        sta cmd + 2,x
        inx
        cpx #l_temp
        bne !-
        inx
        inx
        stx cmdn
        :setpkt(nop)
        rts
}
cd_path: {
        lda #$11
        sta cmd + 1
        ldx #0
!:      cpx plen
        beq !+
        lda path,x
        sta cmd + 2,x
        inx
        bne !-
!:      inx
        inx
        stx cmdn
        :setpkt(nop)
        jmp exec
}
openf: {
        sta cmd + 2
        lda #$02
        sta cmd + 1
        ldx #0
!:      lda d_nom,x
        sta cmd + 3,x
        inx
        cpx #l_nom
        bne !-
        inx
        inx
        inx
        stx cmdn
        :setpkt(nop)
        rts
}
openc: {
        sta cmd + 2
        lda #$02
        sta cmd + 1
        ldx #0
!:      lda d_cnt,x
        sta cmd + 3,x
        inx
        cpx #l_nom
        bne !-
        inx
        inx
        inx
        stx cmdn
        :setpkt(nop)
        rts
}
closef: lda #$03
        sta cmd + 1
        lda #2
        sta cmdn
        :setpkt(nop)
        rts
readn:  sta cmd + 1
        lda #128
        sta cmd + 2
        lda #0
        sta cmd + 3
        sta lastn
        lda #4
        sta cmdn
        rts
simple: sta cmd + 1
        lda #2
        sta cmdn
        :setpkt(nop)
        jmp exec
nop:    rts

bufset: sta bufp
        stx bufp + 1
        lda #0
        sta bufn
        rts
tobuf: {
        lda bufp
        sta hp
        lda bufp + 1
        sta hp + 1
        ldx #0
!:      ldy bufn
        bmi !+
        lda pkt,x
        sta (hp),y
        inc bufn
!:      inx
        cpx pktn
        bne !--
        clc
        lda lastn
        adc pktn
        sta lastn
        rts
}

random: {
        ldx #16
!:      lsr rnd + 1
        ror rnd
        bcc !+
        lda rnd + 1
        eor #$B4
        sta rnd + 1
!:      dex
        bne !--
        lda rnd
        eor $DC04
        sta rnd
        bne !+
        inc rnd
!:      rts
}
mul16: {
        lda #0
        sta prod + 2
        sta prod + 3
        ldx #16
l:      lsr m2 + 1
        ror m2
        bcc !+
        clc
        lda prod + 2
        adc m1
        sta prod + 2
        lda prod + 3
        adc m1 + 1
        sta prod + 3
!:      ror prod + 3
        ror prod + 2
        ror prod + 1
        ror prod
        dex
        bne l
        rts
}

// chaîne PETSCII terminée par 0 en A/Y
prs: {
        sta sp
        sty sp + 1
        ldy #0
!:      lda (sp),y
        beq x
        jsr CHROUT
        iny
        bne !-
        inc sp + 1
        bne !-
x:      rts
}
// nombre 16 bits A (haut) / X (bas) en décimal
prdec: {
        sta nh
        stx nl
        lda #0
        sta nz
        ldy #0
d:      ldx #0
!:      lda nl
        sec
        sbc p10l,y
        pha
        lda nh
        sbc p10h,y
        bcc !+
        sta nh
        pla
        sta nl
        inx
        jmp !-
!:      pla
        txa
        bne pr
        lda nz
        bne pr
        cpy #4
        bne nx
pr:     txa
        ora #$30
        jsr CHROUT
        lda #1
        sta nz
nx:     iny
        cpy #5
        bne d
        rts
p10l:   .byte <10000, <1000, <100, <10, <1
p10h:   .byte >10000, >1000, >100, >10, >1
}

a2p: {
        cmp #$5F
        bne !+
        lda #$A4
        rts
!:      cmp #$41
        bcc x
        cmp #$5B
        bcs !+
        ora #$80
        rts
!:      cmp #$61
        bcc x
        cmp #$7B
        bcs x
        and #$DF
x:      rts
}
hexw:   pha
        lda #'$'
        jsr CHROUT
        pla
        jsr hex
        txa
hex: {
        pha
        lsr
        lsr
        lsr
        lsr
        jsr h1
        pla
        and #$0F
h1:     cmp #10
        bcc !+
        adc #6
!:      adc #$30
        jmp CHROUT
}
jzero:  sei
        lda #0
        sta $A1
        sta $A2
        cli
        rts

// ------------------------------------------------------------ Command Interface
exec: {
        lda target
        sta cmd
        jsr tstart
idle:   lda UCI_CTRL
        and #$30
        beq send
        and #$20
        beq !+
        lda #$02
        sta UCI_CTRL
!:      jsr tover
        bcc idle
        jmp timeout
send:   ldx #0
!:      lda cmd,x
        sta UCI_CMD
        inx
        cpx cmdn
        bne !-
        lda #$01
        sta UCI_CTRL
        lda UCI_CTRL
        and #$08
        beq !+
        lda #$08
        sta UCI_CTRL
        :print(t_errcmd)
        jmp quit
!:      lda #0
        sta stn
        sta stat
        sta stat + 1
next:   jsr tstart
wait:   lda UCI_CTRL
        sta us
        and #$20
        bne data
        jsr tover
        bcc wait
        jmp timeout
data:   ldx #0
!:      lda UCI_CTRL
        bpl st
        lda UCI_RESP
        sta pkt,x
        inx
        bne !-
        dex
        jmp !-
st:     stx pktn
!:      bit UCI_CTRL
        bvc !+
        lda UCI_STAT
        ldx stn
        cpx #31
        bcs !-
        sta stat,x
        inc stn
        jmp !-
!:      lda pktn
        beq !+
        jsr callpkt
!:      lda us
        and #$30
        cmp #$30
        bne fin
        jsr ack
        jmp next
fin:    ldx stn
        lda #0
        sta stat,x
        jsr ack
        lda stn
        beq ok
        lda stat
        cmp #$30
        bne ko
        lda stat + 1
        cmp #$32
        bcs ko
ok:     sec
        rts
ko:     clc
        rts
}
callpkt: jmp (onpkt)

ack: {
        lda #$02
        sta UCI_CTRL
        jsr tstart
!:      lda UCI_CTRL
        and #$02
        beq x
        jsr tover
        bcc !-
        jmp timeout
x:      rts
}

// délai de garde : 20 s (1 200 jiffies) sur 16 bits
        .const TLIM = 1200
tstart: sei
        lda $A2
        sta t0
        lda $A1
        sta t0 + 1
        cli
        rts
tover:  sei
        lda $A2
        sec
        sbc t0
        sta tdt
        lda $A1
        cli
        sbc t0 + 1
        sta tdt + 1
        cmp tmax + 1
        bcc !+
        bne nm
        lda tdt
        cmp tmax
        bcc !+
nm:     lda tdt
        sta tmax
        lda tdt + 1
        sta tmax + 1
!:      lda tdt + 1
        cmp #>TLIM
        bne !+
        lda tdt
        cmp #<TLIM
!:      rts

timeout:
        lda #$04
        sta UCI_CTRL
        :print(t_timeout)
        lda cmd
        jsr hex
        lda #' '
        jsr CHROUT
        lda cmd + 1
        jsr hex
        lda #13
        jsr CHROUT
        jmp quit

fatal:  :print(t_err)
        lda etape
        ldy etape + 1
        jsr prs
        lda #' '
        jsr CHROUT
        ldx #0
!:      lda stat,x
        beq !+
        jsr a2p
        jsr CHROUT
        inx
        bne !-
!:      lda #13
        jsr CHROUT
        :print(t_chemin)
        ldx #0
!:      cpx plen
        beq !+
        lda path,x
        jsr a2p
        jsr CHROUT
        inx
        bne !-
!:      lda #13
        jsr CHROUT
quit:   ldx savesp
        txs
!:      jsr GETIN
        beq !-
        jmp exitb

        .encoding "ascii"
d_temp: .text "/Temp"
d_nom:  .text "jukelist.bin"
d_cnt:  .text "jukelist.cnt"
d_svi:  .text "System Volume Information"
        .byte 0
d_flash: .text "Flash"
        .byte 0
d_tmp:  .text "Temp"
        .byte 0
d_root: .text "/"
        .encoding "petscii_mixed"
t_choix:   .text " Drives to search:"
           .byte 13,13,0
t_choixt:  .byte 13
           .text " 1-9 tick/untick   RETURN search"
           .byte 13
           .text " Q cancel"
           .byte 13,0
t_nodrv:   .text " No drive found (SD, USB)"
           .byte 13,0
t_abort:   .text "UCI busy, cannot abort"
           .byte 13,0
t_nouci:   .text "No Command Interface (enable it in the Ultimate menu)"
           .byte 13,0
t_sub:     .text "Your own SIDs, played at random"
           .byte 0
t_titre:   .text "Searching for SIDs..."
           .byte 0
t_trouves: .text " SIDs found   "
           .byte 0
t_dirs:    .text "Folders: "
           .byte 0
t_temps2:  .text "  time: "
           .byte 0
t_jif:     .text " jiffies"
           .byte 0
t_aucun:   .text "No SID found (press a key)"
           .byte 0
t_tir:     .text "SID "
           .byte 0
t_sur:     .text " of "
           .byte 0
t_song:    .text "Tune "
           .byte 0
t_pal:     .text "PAL"
           .byte 0
t_ntsc:    .text "NTSC"
           .byte 0
t_50:      .text "50Hz"
           .byte 0
t_60:      .text "60Hz"
           .byte 0
t_cia:     .text "TIMER"
           .byte 0
t_corr:    .text "Other video standard: tempo adjusted"
           .byte 0
           .var dmm = floor(DUREE / 60)
           .var dss = mod(DUREE, 60)
t_temps:   .text "00:00 / " + (dmm < 10 ? "0" : "") + toIntString(dmm) + ":" + (dss < 10 ? "0" : "") + toIntString(dss)
           .byte 0
t_k1:      .byte 5                     // touches (pkeys)
           .text "SPACE"
           .byte $9B
           .text " Next  "
           .byte 5
           .text "+/-"
           .byte $9B
           .text " Tune  "
           .byte 5
           .text "L"
           .byte 0
t_loop:    .text " Loop"
           .byte 0
t_k2:      .byte 5
           .text "R"
           .byte $9B
           .text " Scan  "
           .byte 5
           .text "Q"
           .byte $9B
           .text " Quit"
           .byte 0
t_ver:     .text VERSION
           .byte 0
t_ti:      .text "Title:"
           .byte 0
t_ar:      .text "Artist:"
           .byte 0
t_re:      .text "Released:"
           .byte 0
t_refus:   .text "Skipped: "
           .byte 0
t_trop:    .text "Too many skipped in a row (press a key)"
           .byte 0
r_fmt:     .text "not a PSID file"
           .byte 0
r_rsid:    .text "RSID (not supported)"
           .byte 0
r_play0:   .text "play = 0 (not supported)"
           .byte 0
r_dos:     .text "read error"
           .byte 0
r_zone:    .text "outside $0800-$9FFF"
           .byte 0
r_adr:     .text "init or play outside the tune"
           .byte 0
t_errcmd:  .text "UCI error while sending"
           .byte 13,0
t_timeout: .byte 13
           .text "UCI timeout, target/command: "
           .byte 0
t_err:     .byte 13
           .text "Error at step: "
           .byte 0
t_chemin:  .text "Path: "
           .byte 0
s_cdtemp:  .text "cd /Temp"
           .byte 0
s_openw:   .text "create list"
           .byte 0
s_write:   .text "write list"
           .byte 0
s_close:   .text "close"
           .byte 0
s_openr:   .text "open list"
           .byte 0
s_opencnt: .text "open counter"
           .byte 0
s_seek:    .text "seek"
           .byte 0
s_read:    .text "read list"
           .byte 0
endA:
        }
endBoot:

// ------------------------------------------------------------ variables ($C100, mises à zéro au démarrage)
        * = BSS "variables" virtual
nsid:   .word 0
ndirs:  .word 0
nlong:  .word 0
nplein: .word 0
tmax:   .word 0
savesp: .byte 0
etape:  .word 0
target: .byte 0
inext:  .byte 0
inom:   .byte 0
heap:   .word 0
plen:   .byte 0
elen:   .byte 0
cmdn:   .byte 0
pktn:   .byte 0
lastn:  .byte 0
stn:    .byte 0
us:     .byte 0
t0:     .word 0
tdt:    .word 0
tj:     .word 0
svx:    .byte 0
svy:    .byte 0
onpkt:  .word 0
rnd:    .word 0
m1:     .word 0
m2:     .word 0
prod:   .fill 4, 0
k:      .word 0
bufp:   .word 0
bufn:   .byte 0
cntv:   .word 0
ndrv:   .byte 0
idrv:   .byte 0
tmp:    .word 0
nh:     .byte 0
nl:     .byte 0
nz:     .byte 0
pal:    .byte 0
song:   .byte 0
nsongs: .byte 0
nref:   .byte 0
rais:   .word 0
initv:  .word 0
playv:  .word 0
load:   .word 0
zfin:   .word 0       // fin du morceau (ne pas l'appeler « fin » : étiquette locale de loadsid, d'exec...)
over:   .byte 0
cia:    .byte 0
playing: .byte 0
tpal:   .byte 0
corr:   .byte 0
forced: .byte 0
frames: .word 0
secs:   .word 0
lastb:  .word 0
loop:   .byte 0
hmax:   .byte 0
hh:     .byte 0
sbn:    .byte 0
sbuf:   .fill 168, 0
drvsel: .fill NDRV, 0
drvtab: .fill NDRV * 16, 0
roots:  .fill NDRV * 19 + 1, 0
stat:   .fill 32, 0
cmd:    .fill 160, 0
path:   .fill 160, 0
ent:    .fill 128, 0
hdr:    .fill 128, 0
pkt:    .fill 256, 0
endBss:
        .errorif endBss > ZPS, "variables trop grandes"
        .errorif endL > BSS, "bloc bas trop grand"
        .errorif endA > $C000, "programme trop grand"
