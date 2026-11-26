// Essai D1 : écrire puis relire un fichier dans /Temp par la Command Interface DOS (cible $01).
// Commandes : CHANGE_DIR $11, OPEN_FILE $02 (attribut + nom), CLOSE_FILE $03, READ_DATA $04 (longueur 16 bits),
// WRITE_DATA $05 ($00 $00 + données), FILE_SEEK $06 (position 32 bits).
// Fichier de 8 Ko (64 blocs de 128 octets), octet i du bloc c = i + 5*c. Relu en entier et comparé, puis
// relecture de 16 octets à la position 1000 après FILE_SEEK. Temps affichés en jiffies.
        .encoding "petscii_mixed"
        .const CHROUT = $FFD2
        .const STROUT = $AB1E
        .const LINPRT = $BDCD
        .const UCI_CTRL = $DF1C
        .const UCI_CMD  = $DF1D
        .const UCI_RESP = $DF1E
        .const UCI_STAT = $DF1F
        .const NBLOCS = 64
        .const d_temp_n = 5             // longueur de "/Temp"
        .const d_nom_n = 12             // longueur de "juketest.bin"

        BasicUpstart2(start)

        .macro print(s) {
        lda #<s
        ldy #>s
        jsr STROUT
        }
        // cmd[1..] = octets, puis exec ; arrêt avec le nom de l'étape si le statut n'est pas 00/01
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
!:      :print(t_titre)
        lda #<nop
        sta onpkt
        lda #>nop
        sta onpkt + 1

        // ---- CHANGE_DIR /Temp
        lda #$11
        sta cmd + 1
        ldx #0
!:      lda d_temp,x
        sta cmd + 2,x
        inx
        cpx #d_temp_n
        bne !-
        inx
        inx
        stx cmdn
        :step(s_cd)

        // ---- OPEN_FILE création (écrase)
        lda #$0E
        jsr openf
        :step(s_openw)

        // ---- WRITE_DATA x 64
        jsr jzero
        lda #0
        sta bloc
        sta c5
wloop:  lda #$05
        sta cmd + 1
        lda #0
        sta cmd + 2
        sta cmd + 3
        ldx #0
        lda c5
!:      sta cmd + 4,x
        clc
        adc #1
        inx
        cpx #128
        bne !-
        lda #132
        sta cmdn
        :step(s_write)
        clc
        lda c5
        adc #5
        sta c5
        inc bloc
        lda bloc
        cmp #NBLOCS
        bne wloop
        lda #$03                // CLOSE_FILE
        sta cmd + 1
        lda #2
        sta cmdn
        :step(s_close)
        :print(t_ecrit)
        jsr jprint

        // ---- relecture complète
        lda #$01
        jsr openf
        :step(s_openr)
        jsr jzero
        lda #0
        sta vpos
        sta vpos + 1
        sta errs
        sta errs + 1
        lda #<verify
        sta onpkt
        lda #>verify
        sta onpkt + 1
        lda #0
        sta bloc
rloop:  lda #$04
        sta cmd + 1
        lda #128
        sta cmd + 2
        lda #0
        sta cmd + 3
        lda #4
        sta cmdn
        :step(s_read)
        inc bloc
        lda bloc
        cmp #NBLOCS
        bne rloop
        :print(t_relu)
        jsr jprint
        :print(t_octets)
        lda vpos + 1
        ldx vpos
        jsr LINPRT
        :print(t_errs)
        lda errs + 1
        ldx errs
        jsr LINPRT

        // ---- FILE_SEEK 1000 puis 16 octets
        lda #$06
        sta cmd + 1
        lda #<1000
        sta cmd + 2
        lda #>1000
        sta cmd + 3
        lda #0
        sta cmd + 4
        sta cmd + 5
        lda #6
        sta cmdn
        :step(s_seek)
        lda #<1000
        sta vpos
        lda #>1000
        sta vpos + 1
        lda #0
        sta errs
        sta errs + 1
        lda #$04
        sta cmd + 1
        lda #16
        sta cmd + 2
        lda #0
        sta cmd + 3
        lda #4
        sta cmdn
        :step(s_read)
        :print(t_seek)
        lda vpos + 1
        ldx vpos
        jsr LINPRT
        :print(t_errs)
        lda errs + 1
        ldx errs
        jsr LINPRT
        lda #<nop
        sta onpkt
        lda #>nop
        sta onpkt + 1
        lda #$03
        sta cmd + 1
        lda #2
        sta cmdn
        :step(s_close)
        :print(t_fin)
        rts

// OPEN_FILE, attribut dans A, nom d_nom
openf: {
        sta cmd + 2
        lda #$02
        sta cmd + 1
        ldx #0
!:      lda d_nom,x
        sta cmd + 3,x
        inx
        cpx #d_nom_n
        bne !-
        inx
        inx
        inx
        stx cmdn
        rts
}

// compare chaque octet reçu à la valeur attendue en vpos : (vpos & $7F) + 5 * (vpos >> 7)
verify: {
        ldx #0
l:      lda vpos
        asl
        lda vpos + 1
        rol                     // A = vpos >> 7 (bloc)
        sta tmp
        asl
        asl
        clc
        adc tmp                 // 5 * bloc
        sta tmp
        lda vpos
        and #$7F
        clc
        adc tmp
        cmp pkt,x
        beq ok
        inc errs
        bne ok
        inc errs + 1
ok:     inc vpos
        bne !+
        inc vpos + 1
!:      inx
        cpx pktn
        bne l
        rts
}
nop:    rts

jzero:  sei
        lda #0
        sta $A1
        sta $A2
        cli
        rts
jprint: sei
        lda $A2
        tax
        lda $A1
        cli
        jsr LINPRT
        :print(t_jif)
        rts

// ------------------------------------------------------------ Command Interface (copie de dirtest.asm)
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
        sta stat
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
        lda stn                 // pas de statut : accepté
        beq ok
        lda stat
        cmp #$30
        bne ko
        lda stat + 1
        cmp #$32                // 00 OK, 01
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

a2p: {
        cmp #$41
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
quit:   ldx savesp
        txs
        rts

        .encoding "ascii"
d_temp: .text "/Temp"
d_nom:  .text "juketest.bin"
        .encoding "petscii_mixed"
t_nouci:   .text "pas de command interface"
           .byte 13,0
t_titre:   .text "essai d1 : fichier dans /Temp"
           .byte 13,13,0
t_ecrit:   .text "ecrit 8192 octets en "
           .byte 0
t_relu:    .text "relu en "
           .byte 0
t_jif:     .text " jiffies"
           .byte 13,0
t_octets:  .text "octets lus: "
           .byte 0
t_errs:    .text "  erreurs: "
           .byte 0
t_seek:    .byte 13
           .text "seek 1000, position finale: "
           .byte 0
t_fin:     .byte 13,13
           .text "fin de l'essai"
           .byte 13,0
t_errcmd:  .text "erreur uci a l'envoi"
           .byte 13,0
t_timeout: .text "delai depasse (uci)"
           .byte 13,0
t_err:     .text "erreur a l'etape "
           .byte 0
s_cd:      .text "cd"
           .byte 0
s_openw:   .text "open ecriture"
           .byte 0
s_write:   .text "write"
           .byte 0
s_close:   .text "close"
           .byte 0
s_openr:   .text "open lecture"
           .byte 0
s_read:    .text "read"
           .byte 0
s_seek:    .text "seek"
           .byte 0

savesp: .byte 0
etape:  .word 0
bloc:   .byte 0
c5:     .byte 0
vpos:   .word 0
errs:   .word 0
tmp:    .byte 0
cmdn:   .byte 0
pktn:   .byte 0
stn:    .byte 0
us:     .byte 0
t0:     .byte 0
onpkt:  .word 0
stat:   .fill 32, 0
cmd:    .fill 160, 0
pkt:    .fill 256, 0
