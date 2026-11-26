// Étape 2-3 (essai) : liste de tous les .sid de /SD, /USB0, /USB1 écrite dans /Temp/jukelist.bin, puis tirage au hasard
// et affichage de l'en-tête du morceau. ESPACE = autre tirage, Q = quitter.
// Cible DOS $01 : parcours et lecture des SID. Cible DOS $02 : fichier de liste (ouvert pendant le parcours).
// Entrée de liste : 128 octets = chemin du dossier (ASCII), 0, nom du fichier, 0, zéros.
        .encoding "petscii_mixed"
        .const CHROUT = $FFD2
        .const STROUT = $AB1E
        .const LINPRT = $BDCD
        .const GETIN  = $FFE4
        .const PLOT   = $FFF0
        .const UCI_CTRL = $DF1C
        .const UCI_CMD  = $DF1D
        .const UCI_RESP = $DF1E
        .const UCI_STAT = $DF1F
        .const ptr = $FB
        .const hp  = $FD
        .const HEAP = $4000
        .const HEAPEND = $A000          // RAM sous la ROM BASIC non relisible : pas au-delà
        .const ENT = 128
        .const l_temp = 5
        .const l_nom = 12
        .const LT = cmdLineVars.containsKey("LT") ? cmdLineVars.get("LT").asNumber() : 2   // cible DOS du fichier de liste
        .const DIAG = cmdLineVars.containsKey("DIAG") ? 1 : 0   // diagnostic : fichier refermé avant le parcours
        .const nvars = 10                // nsid, ndirs, nlong

        BasicUpstart2(start)

        .macro print(s) {
        lda #<s
        ldy #>s
        jsr STROUT
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

start:  tsx
        stx savesp
        lda #$0E
        jsr CHROUT
        lda #$93
        jsr CHROUT
        lda UCI_CMD
        cmp #$C9
        beq !+
        :print(t_nouci)
        rts
!:      lda UCI_CTRL            // commande en cours laissée par un programme précédent : abandon
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
        rts
!:      lda $DC04               // graine du hasard
        eor $A2
        sta rnd
        lda $D012
        ora #1
        sta rnd + 1
        :setpkt(nop)
        lda #0
        ldx #nvars - 1
!:      sta vars,x
        dex
        bpl !-
        jsr readcnt             // liste complète gardée dans /Temp ?
        bcc !+
        jmp pick
!:      jsr choose              // pas de liste : choix des lecteurs
        bcs !+
        rts                     // Q : abandon
!:      jsr scan
        jmp go

// ------------------------------------------------------------ choix des lecteurs
// Liste la racine « / » de l'Ultimate (SD, Flash, Temp, USB0, USB1...) ; Flash et Temp écartés. Tous cochés au départ.
// 1-9 : cocher/décocher, RETURN : valider (au moins un coché), Q : abandon. C = 1 si validé ; roots = « /NOM/ » 0 ... 0.
        .const NDRV = 8
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
        beq aff                 // racine vide
        :setpkt(drvstore)
        lda #$14
        sta cmd + 1
        lda #2
        sta cmdn
        jsr exec
        bcs aff
        jmp fatal
aff:    lda #$93
        jsr CHROUT
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
        .byte $2C               // saute le lda suivant
!:      lda #' '
        jsr CHROUT
        lda #']'
        jsr CHROUT
        lda #' '
        jsr CHROUT
        lda idrv                // nom : drvtab + 16 * i
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
valide: ldx #0                  // roots = « /NOM/ » 0 pour chaque lecteur coché, puis 0
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
        jmp key                 // rien de coché
!:      sec
        rts
}

// paquet de READ_DIR de la racine : garde les dossiers sauf Flash et Temp (16 octets par nom, 15 car. au plus)
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

// C = 1 si le nom du paquet (pkt+1..) est égal à la chaîne ASCII terminée par 0 en A/X
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
fin:    cpx pktn                // fin du modèle : le nom doit finir aussi
        bcs oui
        lda pkt,x
        beq oui
non:    clc
        rts
oui:    sec
        rts
}

// ------------------------------------------------------------ recherche (liste refaite)
scan:   lda #$93
        jsr CHROUT
        :print(t_titre)
        lda #0
        ldx #nvars - 1
!:      sta vars,x
        dex
        bpl !-
        lda #<HEAP
        sta heap
        lda #>HEAP
        sta heap + 1
        lda #0                  // compteur à 0 pendant la recherche : une recherche interrompue sera refaite
        tax
        jsr writecnt

        // ---- fichier de liste sur la cible 2
        lda #LT
        sta target
        jsr cd_temp
        :step(s_cdtemp)
        lda #$0A                // écriture + création en écrasant ($0E = « FILE EXISTS » si le fichier existe)
        jsr openf
        :step(s_openw)
        .if (DIAG == 1) {
        jsr closef
        :step(s_close)
        }

        jsr jzero
        ldx #0                  // racines
rootl:  stx iroot
        lda roots,x
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
        bcc !+                  // support absent
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
        :print(t_dirs)
        lda ndirs + 1
        ldx ndirs
        jsr LINPRT
        :print(t_long)
        lda nlong + 1
        ldx nlong
        jsr LINPRT
        :print(t_plein)
        lda nplein + 1
        ldx nplein
        jsr LINPRT
        :print(t_tmax)
        lda tmax + 1
        ldx tmax
        jsr LINPRT
        :print(t_temps)
        lda tj + 1
        ldx tj
        jsr LINPRT
        :print(t_jif)
        lda nsid
        ldx nsid + 1
        jsr writecnt
        lda #120                // 2 s pour lire le bilan
        jmp waitj

go:     lda nsid
        ora nsid + 1
        beq !+
        jmp pick
!:      :print(t_aucun)
        rts

// attend A jiffies
waitj: {
        clc
        adc $A2
!:      cmp $A2
        bne !-
        rts
}

// lit /Temp/jukelist.cnt (nombre de SID, 2 octets) ; C = 1 et nsid si la liste est complète
readcnt: {
        lda #LT
        sta target
        jsr cd_temp
        jsr exec
        bcc non
        lda #$01
        jsr openc
        jsr exec
        bcc non                 // pas de fichier : première mise en route
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
        beq non                 // 0 : recherche interrompue
        lda cntv
        sta nsid
        lda cntv + 1
        sta nsid + 1
        sec
        rts
non:    clc
        rts
}

// écrit A (bas) / X (haut) dans /Temp/jukelist.cnt
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

// ------------------------------------------------------------ tirage
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
        // entrée k : position k * 128
        lda #LT
        sta target
        jsr cd_temp             // la cible a pu changer de dossier (parcours, SID précédent)
        :step(s_cdtemp)
        lda #$01
        jsr openf
        :step(s_openr)
        lda #$06
        sta cmd + 1
        lda #0
        sta cmd + 2
        lda k
        lsr
        ror cmd + 2             // (k * 128) octet 0 = bit 0 de k en bit 7
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
        // ent = dossier 0 nom 0
        lda #1
        sta target
        ldx #0
!:      lda ent,x
        beq !+
        sta path,x
        inx
        bne !-
!:      stx plen
        inx
        stx inom
        jsr cd_path
        :step(s_cdsid)
        lda #$02
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
        :step(s_opensid)
        lda #<hdr
        ldx #>hdr
        jsr bufset
        lda #0
        sta fsize
        sta fsize + 1
        sta fsize + 2
        :setpkt(tobuf)
rdl:    lda #$04
        jsr readn
        jsr exec
        bcc rdend               // fin de fichier signalée par une erreur
        lda lastn
        cmp #128
        beq rdl
rdend:  jsr closef
        jsr exec
        jsr show
wkey:   jsr GETIN
        beq wkey
        cmp #' '
        bne !+
        jmp pick
!:      cmp #'r'                // refaire la liste (choix des lecteurs d'abord)
        bne !++
        jsr choose
        bcs !+
        jmp pick                // Q : on garde l'ancienne liste
!:      jsr scan
        jmp go
!:      cmp #'q'
        bne wkey
        rts

// ------------------------------------------------------------ affichage de l'en-tête
show: {
        lda #$93
        jsr CHROUT
        :print(t_tir)
        lda k + 1
        ldx k
        jsr inc16print
        :print(t_sur)
        lda nsid + 1
        ldx nsid
        jsr LINPRT
        lda #13
        jsr CHROUT
        lda #13
        jsr CHROUT
        ldx #0                  // chemin complet
!:      cpx plen
        beq !+
        lda path,x
        jsr a2p
        jsr CHROUT
        inx
        bne !-
!:      lda #'/'
        jsr CHROUT
        ldx inom
!:      lda ent,x
        beq !+
        jsr a2p
        jsr CHROUT
        inx
        bne !-
!:      lda #13
        jsr CHROUT
        lda #13
        jsr CHROUT
        lda hdr                 // PSID / RSID
        cmp #$50
        beq ok
        cmp #$52
        beq ok
        :print(t_pasid)
        rts
ok:     ldx #$16
        jsr pstr
        ldx #$36
        jsr pstr
        ldx #$56
        jsr pstr
        lda #13
        jsr CHROUT
        ldx #0
!:      lda hdr,x
        jsr a2p
        jsr CHROUT
        inx
        cpx #4
        bne !-
        lda #' '
        jsr CHROUT
        lda #'v'
        jsr CHROUT
        lda hdr + 5
        ora #$30
        jsr CHROUT
        :print(t_songs)
        lda hdr + $0E
        ldx hdr + $0F
        jsr LINPRT
        :print(t_start)
        lda hdr + $10
        ldx hdr + $11
        jsr LINPRT
        // adresse de chargement (0 = deux premiers octets des données)
        lda hdr + 8
        ora hdr + 9
        bne !+
        ldx hdr + 7             // dataOffset (octet bas, < 128 en pratique)
        lda hdr,x
        sta load
        lda hdr + 1,x
        sta load + 1
        lda #2
        sta dsub
        jmp !++
!:      lda hdr + 9
        sta load
        lda hdr + 8
        sta load + 1
        lda #0
        sta dsub
!:      // taille des données = fsize - dataOffset - dsub ; fin = load + taille - 1
        sec
        lda fsize
        sbc hdr + 7
        sta dsize
        lda fsize + 1
        sbc hdr + 6
        sta dsize + 1
        lda fsize + 2
        sbc #0
        sta dsize + 2
        sec
        lda dsize
        sbc dsub
        sta dsize
        lda dsize + 1
        sbc #0
        sta dsize + 1
        lda dsize + 2
        sbc #0
        sta dsize + 2
        clc
        lda load
        adc dsize
        sta fin
        lda load + 1
        adc dsize + 1
        sta fin + 1
        lda #0
        adc dsize + 2
        sta fin + 2
        lda fin
        bne !+
        lda fin + 1
        bne !+
        dec fin + 2
!:      lda fin
        bne !+
        dec fin + 1
!:      dec fin
        :print(t_load)
        lda load + 1
        ldx load
        jsr hexw
        lda #'-'
        jsr CHROUT
        lda fin + 2
        beq !+
        lda #'!'                // dépasse $FFFF
        jsr CHROUT
!:      lda fin + 1
        ldx fin
        jsr hexw
        :print(t_init)
        lda hdr + $0A
        ldx hdr + $0B
        jsr hexw
        :print(t_play)
        lda hdr + $0C
        ldx hdr + $0D
        jsr hexw
        :print(t_taille)
        lda fsize + 1
        ldx fsize
        jsr LINPRT
        :print(t_touches)
        rts
}

// chaîne de l'en-tête (32 car. au plus) en X, puis retour à la ligne
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

inc16print:                     // affiche A:X + 1
        inx
        bne !+
        clc
        adc #1
!:      jmp LINPRT

// ------------------------------------------------------------ parcours
walk: {
        inc ndirs
        bne !+
        inc ndirs + 1
!:      lda heap
        pha
        lda heap + 1
        pha
        lda #$13                // OPEN_DIR
        jsr simple
        bcs !+
        jmp fatal
!:      lda stat + 1            // 01 : dossier vide, pas de READ_DIR
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
        jsr skipdir
        bcs adv
        lda ptr
        pha
        lda ptr + 1
        pha
        lda elen
        pha
        lda plen
        pha
        jsr addname
        bcc !+                  // chemin trop long
        jsr cd_path
        bcc !+                  // dossier illisible : sauté
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
file:   jsr issid
        bcc adv
        jsr addentry
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

// paquet de READ_DIR -> tas : [longueur][paquet], seulement les sous-dossiers (hors dossiers système) et les .sid.
// Un dossier peut compter des milliers de fichiers (8 323 dans une collection de ROM) : tout garder déborde.
// Tas plein (HEAPEND) : entrée ignorée et comptée dans nplein.
store: {
        lda #<(pkt - 1)         // (ptr),1 = attribut, (ptr),2.. = nom, comme dans le tas
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
garde:  clc                     // place : heap + pktn + 2 (fin de liste) < HEAPEND
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

// C = 1 si le dossier doit être sauté : nom commençant par « . » ou « $ », ou « System Volume Information »
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
        lda d_svi,x             // fin du paquet : il faut être à la fin du modèle
        beq oui
non:    clc
        rts
oui:    sec
        rts
}

// C = 1 si le nom finit par .sid
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

// path += "/" + nom ; C = 0 si trop long (> 120)
addname: {
        ldx plen
        lda #$2F
        cmp path - 1,x          // pas de double « / » (racines « /SD/ »)
        beq !+
        sta path,x
        inx
!:
        ldy #2
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

// écrit l'entrée « chemin 0 nom 0 » sur la cible 2
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
        .if (DIAG == 0) {
        :step(s_write)
        }
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

// compteur en ligne 2
counter: {
        sec
        jsr PLOT
        stx svx
        sty svy
        ldx #2
        ldy #0
        clc
        jsr PLOT
        lda nsid + 1
        ldx nsid
        jsr LINPRT
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

// OPEN_FILE jukelist.bin, attribut A (cible courante) ; exec à faire par l'appelant
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

// OPEN_FILE jukelist.cnt, attribut A ; exec à faire par l'appelant
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

closef: lda #$03                // CLOSE_FILE ; exec à faire par l'appelant
        sta cmd + 1
        lda #2
        sta cmdn
        :setpkt(nop)
        rts

// READ_DATA de 128 octets (A = $04) ; exec à faire par l'appelant ; lastn = octets reçus
readn: {
        sta cmd + 1
        lda #128
        sta cmd + 2
        lda #0
        sta cmd + 3
        sta lastn
        lda #4
        sta cmdn
        rts
}

simple: {
        sta cmd + 1
        lda #2
        sta cmdn
        :setpkt(nop)
        jmp exec
}
nop:    rts

// tampon de réception : 128 octets au plus à partir de A/X ; compte la taille du fichier
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
        bmi !+                  // tampon plein (128)
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
        clc
        lda fsize
        adc pktn
        sta fsize
        bcc !+
        inc fsize + 1
        bne !+
        inc fsize + 2
!:      rts
}

// hasard : LFSR 16 bits (16 pas), mélangé au timer du CIA 1
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

// prod (32 bits) = m1 * m2 (16 bits)
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

// ASCII -> PETSCII minuscules
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

hexw:   pha                     // A = octet haut, X = octet bas
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

// délai de garde : 20 s (1 200 jiffies), sur 16 bits ($A1/$A2) ; le plus long temps vu est gardé dans tmax
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
        lda cmd                 // cible et commande en cause
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
        jsr STROUT
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
        rts

        .encoding "ascii"
d_temp: .text "/Temp"
d_nom:  .text "jukelist.bin"
d_cnt:  .text "jukelist.cnt"            // même longueur que d_nom (l_nom)
d_svi:  .text "System Volume Information"
        .byte 0
d_flash: .text "Flash"
        .byte 0
d_tmp:  .text "Temp"
        .byte 0
d_root: .text "/"
        .encoding "petscii_mixed"
t_choix:   .text "jukebox local : lecteurs a explorer"
           .byte 13,13,0
t_choixt:  .byte 13
           .text "1-9: cocher   return: chercher"
           .byte 13
           .text "q: annuler"
           .byte 13,0
t_nodrv:   .text "aucun lecteur (sd, usb) trouve"
           .byte 13,0
t_abort:   .text "uci occupee, abandon impossible"
           .byte 13,0
t_nouci:   .text "pas de command interface"
           .byte 13,0
t_titre:   .text "jukebox local : recherche des sid..."
           .byte 13,0
t_trouves: .text " sid trouves   "
           .byte 0
t_dirs:    .byte 13
           .text "dossiers: "
           .byte 0
t_long:    .text "  trop longs: "
           .byte 0
t_plein:   .text "  tas plein: "
           .byte 0
t_tmax:    .byte 13
           .text "  attente max: "
           .byte 0
t_temps:   .byte 13
           .text "temps: "
           .byte 0
t_jif:     .text " jiffies"
           .byte 13,0
t_aucun:   .text "aucun sid trouve"
           .byte 13,0
t_tir:     .text "tirage: "
           .byte 0
t_sur:     .text " / "
           .byte 0
t_pasid:   .text "pas un fichier psid/rsid"
           .byte 13,0
t_songs:   .text "  morceaux:"
           .byte 0
t_start:   .text "  depart:"
           .byte 0
t_load:    .byte 13
           .text "zone "
           .byte 0
t_init:    .byte 13
           .text "init "
           .byte 0
t_play:    .text "  play "
           .byte 0
t_taille:  .byte 13
           .text "fichier: "
           .byte 0
t_touches: .byte 13,13
           .text "espace: autre tirage  r: refaire la liste"
           .byte 13
           .text "q: quitter"
           .byte 13,0
t_errcmd:  .text "erreur uci a l'envoi"
           .byte 13,0
t_timeout: .byte 13
           .text "delai depasse (uci), cible/commande: "
           .byte 0
t_err:     .byte 13
           .text "erreur a l'etape "
           .byte 0
t_chemin:  .text "chemin: "
           .byte 0
s_cdtemp:  .text "cd /Temp"
           .byte 0
s_openw:   .text "creation de la liste"
           .byte 0
s_write:   .text "ecriture de la liste"
           .byte 0
s_close:   .text "fermeture"
           .byte 0
s_openr:   .text "ouverture de la liste"
           .byte 0
s_opencnt: .text "ouverture du compteur"
           .byte 0
s_seek:    .text "seek"
           .byte 0
s_read:    .text "lecture de la liste"
           .byte 0
s_cdsid:   .text "cd dossier du sid"
           .byte 0
s_opensid: .text "ouverture du sid"
           .byte 0

// variables remises à zéro au démarrage
vars:
nsid:   .word 0
ndirs:  .word 0
nlong:  .word 0
tmax:   .word 0
nplein: .word 0
savesp: .byte 0
etape:  .word 0
target: .byte 0
iroot:  .byte 0
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
cntv:   .word 0
ndrv:   .byte 0
idrv:   .byte 0
tmp:    .byte 0
drvsel: .fill NDRV, 0
drvtab: .fill NDRV * 16, 0
roots:  .fill NDRV * 19 + 1, 0
k:      .word 0
bufp:   .word 0
bufn:   .byte 0
fsize:  .fill 3, 0
dsize:  .fill 3, 0
fin:    .fill 3, 0
load:   .word 0
dsub:   .byte 0
stat:   .fill 32, 0
cmd:    .fill 160, 0
path:   .fill 160, 0
ent:    .fill 128, 0
hdr:    .fill 128, 0
pkt:    .fill 256, 0
