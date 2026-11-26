// Essai : parcours récursif d'un dossier de la carte SD par la Command Interface (cible DOS $01).
// Commandes : CHANGE_DIR $11, OPEN_DIR $13, READ_DIR $14 (un paquet par entrée : attribut + nom ?).
// Affiche l'arbre (attribut en hexa), compte dossiers et .sid, mesure le temps en jiffies.
        .encoding "petscii_mixed"
        .const CHROUT = $FFD2
        .const STROUT = $AB1E
        .const LINPRT = $BDCD
        .const UCI_CTRL = $DF1C
        .const UCI_CMD  = $DF1D
        .const UCI_RESP = $DF1E
        .const UCI_STAT = $DF1F
        .const ptr = $FB
        .const hp  = $FD
        .const HEAP = $4000

        #importonce
        .const ROOT  = cmdLineVars.get("ROOT")
        .const QUIET = cmdLineVars.get("QUIET").asNumber()
        BasicUpstart2(start)

        .macro print(s) {
        lda #<s
        ldy #>s
        jsr STROUT
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
!:      lda #0
        sta nsid
        sta nsid + 1
        sta ndirs
        sta ndirs + 1
        sta depth
        ldx #0
!:      lda root,x
        beq !+
        sta path,x
        inx
        bne !-
!:      stx plen
        lda #<HEAP
        sta heap
        lda #>HEAP
        sta heap + 1
        :print(t_titre)
        sei
        lda #0
        sta $A0
        sta $A1
        sta $A2
        cli
        jsr cd_path
        bcs !+
        jmp fatal
!:      jsr walk
        sei
        lda $A2
        sta tj
        lda $A1
        sta tj + 1
        cli
        :print(t_dirs)
        lda ndirs + 1
        ldx ndirs
        jsr LINPRT
        :print(t_sid)
        lda nsid + 1
        ldx nsid
        jsr LINPRT
        :print(t_jif)
        lda tj + 1
        ldx tj
        jsr LINPRT
        lda #13
        jmp CHROUT

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
!:      lda stat + 1            // 01 DIRECTORY EMPTY : pas de READ_DIR (sinon 87,INTERNAL ERROR)
        cmp #$31
        beq vide
        lda #<store
        sta onpkt
        lda #>store
        sta onpkt + 1
        lda #$14                // READ_DIR
        sta cmd + 1
        lda #2
        sta cmdn
        jsr exec
        bcs !+
        jmp fatal
vide:
!:      ldy #0                  // fin de liste
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
        jsr indent
        ldy #1
        lda (ptr),y
        jsr hex
        lda #32
        jsr out
        ldy #1
        lda (ptr),y
        and #$10
        beq file
        jsr pname
        lda #'/'
        jsr out
        lda #13
        jsr out
        lda ptr
        pha
        lda ptr + 1
        pha
        lda elen
        pha
        lda plen
        pha
        jsr addname
        jsr cd_path
        bcs !+
        jmp fatal
!:      inc depth
        jsr walk
        dec depth
        pla
        sta plen
        pla
        sta elen
        pla
        sta ptr + 1
        pla
        sta ptr
        jmp adv
file:   jsr pname
        jsr issid
        bcc !++
        inc nsid
        bne !+
        inc nsid + 1
!:      lda #' '
        jsr out
        lda #'*'
        jsr out
!:      lda #13
        jsr out
adv:    sec                     // ptr += elen + 1
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
        rts
}

// paquet de READ_DIR -> tas : [longueur][paquet]
store: {
        lda heap
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

// nom de l'entrée : (ptr),2 .. (ptr),elen, arrêt sur 0
pname: {
        ldy #2
!:      cpy elen
        beq !+
        bcs x
!:      lda (ptr),y
        beq x
        jsr a2p
        jsr out
        iny
        bne !--
x:      rts
}

// C = 1 si le nom finit par .sid (sans tenir compte de la casse)
issid: {
        ldy #2
!:      cpy elen
        beq !+
        bcs fin
!:      lda (ptr),y
        beq fin
        iny
        bne !--
fin:    dey                     // y = dernier caractère
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

// path += "/" + nom
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
        iny
        bne !--
x:      stx plen
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
        lda #<nop
        sta onpkt
        lda #>nop
        sta onpkt + 1
        jmp exec
}

// commande DOS sans argument (A = code), paquets ignorés
simple: {
        sta cmd + 1
        lda #2
        sta cmdn
        lda #<nop
        sta onpkt
        lda #>nop
        sta onpkt + 1
        jmp exec
}
nop:    rts

indent: {
        ldx depth
        beq x
!:      lda #32
        jsr out
        jsr out
        dex
        bne !-
x:      rts
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
        jmp out
}

// sortie écran, coupée en mode silencieux (QUIET=1)
out:    .if (QUIET == 0) {
        jmp     CHROUT
        } else {
        rts
        }

// ------------------------------------------------------------ Command Interface
// envoie cmd[0..cmdn-1] (cmd[0] = cible DOS $01), appelle onpkt pour chaque paquet de données.
// C = 1 si le statut commence par « 00 ». Délai dépassé : abandon et sortie.
exec: {
        lda #$01
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
        lda stat
        cmp #$30
        bne ko
        lda stat + 1
        cmp #$32                // 00 OK, 01 DIRECTORY EMPTY
        bcs ko
        sec
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

// délai : 3 s en jiffies
tstart: lda $A2
        sta t0
        rts
tover:  lda $A2
        sec
        sbc t0
        cmp #180
        rts

timeout:
        lda #$04
        sta UCI_CTRL
        :print(t_timeout)
        jmp quit

fatal:  :print(t_err)
        ldx #0
!:      lda stat,x
        beq !+
        jsr a2p
        jsr CHROUT
        inx
        bne !-
!:      lda #13
        jsr CHROUT
        :print(t_path)
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
root:   .text ROOT
        .byte 0
        .encoding "petscii_mixed"
t_nouci:   .text "pas de command interface"
           .byte 13,0
t_titre:   .text "parcours"
           .byte 13,0
t_dirs:    .byte 13
           .text "dossiers: "
           .byte 0
t_sid:     .byte 13
           .text "fichiers sid: "
           .byte 0
t_jif:     .byte 13
           .text "jiffies: "
           .byte 0
t_errcmd:  .text "erreur uci a l'envoi"
           .byte 13,0
t_timeout: .text "delai depasse (uci)"
           .byte 13,0
t_err:     .text "erreur: "
           .byte 0
t_path:    .text "chemin: "
           .byte 0

savesp: .byte 0
nsid:   .word 0
ndirs:  .word 0
depth:  .byte 0
heap:   .word 0
plen:   .byte 0
elen:   .byte 0
cmdn:   .byte 0
pktn:   .byte 0
stn:    .byte 0
us:     .byte 0
t0:     .byte 0
tj:     .word 0
onpkt:  .word 0
stat:   .fill 32, 0
cmd:    .fill 160, 0
path:   .fill 160, 0
pkt:    .fill 256, 0
