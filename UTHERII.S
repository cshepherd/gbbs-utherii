*-------------------------------
* GBBS Pro Uthernet II driver
* 8/13/2024 ballmerpeak
*-------------------------------

utherii     ent

            org   $e00

*-------------------------------
* jump table

cardslot    dfb   1 ; card slot
            dfb   0 ; init modem at
            dfb   0 ; speed of call

bytcnt      dfb   0,0,0

            jmp   reset     ; reset card (TODO auto-detect?)
            jmp   init      ; init for ring
            jmp   ring      ; check for ring
            jmp   answer    ; answer if ring
            jmp   hangup    ; hangup connection
            jmp   inp       ; input a byte
            jmp   out       ; output a byte
            jmp   chkdcd    ; check carrier
            jmp   setspd    ; set speed
            jmp   raisedtr  ; raise dtr
            jmp   flush     ; flush buffer
            jmp   shutdown  ; quit

*-------------------------------
* Uthernet II configuration
my_gw       db    192,168,64,1
my_mask     db    255,255,255,0
mac_addr    db    $08,00,$20,$C0,$10,$20
my_ip       db    192,168,64,254

port_num    ddb   6502
*-------------------------------
* internal variables
active      db    0
rx_rd       db    00,00
rx_rd_orig  db    00,00
rx_rcvd     db    00,00
tx_wr       db    00,00
tx_ptr      db    00,00
tx_free     db    00,00

; set addr
; a = reg no hi
; x = reg no lo
setaddr
]cn1        sta   $c000       ; ]cn1+1 = card_base + 1
; set addr lo only
; x = reg no lo
setaddrlo
]cn2        stx   $c000       ; ]cn2+1 = card_base + 2
            rts

; set global reg
; a = value
setglobalreg
]cn3        sta   $c000       ; ]cn3+1 = card_base + 0
            rts

; read global reg
; a = value
readglobalreg
]cn6        lda   $c000       ; ]cn6+1 = card_base + 0
            rts

; send data
; a = value
setdata
]cn4        sta   $c000       ; ]cn4+1 = card_base + 3
            rts

; read data
; a = value
getdata
]cn5        lda   $c000       ; ]cn5+1 = card_base + 3
            rts

; Just reset the Uthernet II
; all regs preserved
reset       pha
            phx
            phy
            lda   cardslot
            asl
            asl
            asl
            asl
            clc
            adc   #$84
            sta   ]cn3+1
            sta   ]cn6+1
            inc
            sta   ]cn1+1
            inc
            sta   ]cn2+1
            inc
            sta   ]cn4+1
            sta   ]cn5+1

            lda   #$80                ; $80 = reset
            jsr   setglobalreg

            jsr   readglobalreg
            bne   initfail

            lda   $c034
            and   #$F0
            sta   $c034 ; black border = initialized

            clc
            ply
            plx
            pla
            rts

initfail    sec
            brk  $00                  ; YOU LOSE
            ply
            plx
            pla
            rts

; "init modem for ring"
; set up uthernet II MAC and IP params
; then issue TCP LISTEN command to Wiznet
; all regs preserved
init        pha
            phx
            phy
            jsr   reset
            lda   #$03                ; Indirect Bus IF mode, Address Auto-Increment
            jsr   setglobalreg

            lda   #00
            ldx   #01
            jsr   setaddr             ; 0001 - Gateway Address

            ldx   #00                 ; set gw(4)+mask(4)+mac(6)+ip(4)
]gw         lda   my_gw,x
            jsr   setdata
            inx
            cpx   #18+1
            bne   ]gw

            lda   #00
            ldx   #$1a
            jsr   setaddr             ; 001A - rx mem

            lda   #$55                ; 00 = 4x 2KB socket buffers
            jsr   setdata             ; rx mem: 2K for up to 4 socks
            jsr   setdata             ; tx mem (via auto inc): 2K for up to 4 sockets

            lda   #$04
            ldx   #$04
            jsr   setaddr             ; 0404 = S0 source port
            lda   port_num
            jsr   setdata
            lda   port_num+1
            jsr   setdata

            lda   #$04
            ldx   #$00
            jsr   setaddr             ; $0400 = S0 mode port
            lda   #$01
            jsr   setdata             ; $01 = TCP

            lda   #$04
            ldx   #$01
            jsr   setaddr             ; $0401 = S0 command port
            lda   #$01
            jsr   setdata             ; send OPEN command

]slp        lda   #$04
            ldx   #$03
            jsr   setaddr             ; $0403 = S0 status register
            jsr   getdata
            beq   sockfail
            cmp   #$13
            beq   initpass
            bra   ]slp                ; loop until status of SOCK_INIT is reached
initpass    lda   #$04
            ldx   #$01
            jsr   setaddr             ; $0401 = socket command register
            lda   #02
            jsr   setdata             ; $02 = LISTEN

            lda   $c034
            and   #$F0
            clc
            adc   #$0F
            sta   $c034 ; white border = listening

            ply
            plx
            pla
            rts
sockfail    brk   $01                 ; YOU LOSE (SOCK_CLOSED)

; 'answer' function (answer if ringing)
; wiznet does this automatically, so do nothing
answer      rts

; 'ring' function (check for ring)
; all regs preserved
ring        pha
            phx
            phy
            lda   #$04
            ldx   #$03
            jsr   setaddr             ; $0403 = socket status register
            jsr   getdata
            beq   closed
            cmp   #$17                ; established?
            bne   closed

            lda   #01                 ; answer
            sta   active

            lda   $c034
            and   #$F0
            clc
            adc   #$06
            sta   $c034 ; blue border = connected

            ply
            plx
            pla
            sec                       ; SEC = connected
            rts
closed      lda   #00
            sta   active
            ply
            plx
            pla
            clc                       ; CLC = not connected
            rts

; 'hangup' function (close tcp socket)
; all regs preserved
hangup      pha
            phx
            phy
            lda   #$04
            ldx   #$01
            jsr   setaddr             ; S0 command register
            lda   #$08                ; DISCON
            jsr   setdata
            ply
            plx
            pla
            clc
            rts

; chkdcd function
chkdcd      rts

; 'flush' function
; flush wiznet buffer
; all regs preserved
flush       pha
            phx
            phy
            ldy   #1
            lda   #$04
            ldx   #$28                ; add rx_rcvd to rx_rd_orig and store back in $0428
            jsr   setaddr
            lda   rx_rd_orig+1
            jsr   setdata
            lda   rx_rd_orig
            jsr   setdata

            ldy   #2
            ldx   #$01
            jsr   setaddrlo           ; S0 command register
            lda   #$40
            jsr   setdata             ; RECV command to signal we processed the last chunk

            ply
            plx
            pha
            rts

; setspd function
; set modem speed
setspd      rts

; raisedtr function
; raise dtr to send AT commands
raisedtr    rts

; shutdown function
; don't drop connection, just get ready to quit
; (disable SSC interrupts if we were a modem)
shutdown    rts

; inp function
; get one byte frm wiznet buffer
; if carry set, byte in A
; if carry clear, no byte
; xy preserved
inp         phx
            phy
            lda   #$04
            ldx   #$28
            jsr   setaddr             ; S0_RX_RD (un-translated rx base)
            jsr   getdata
            sta   rx_rd+1             ; +1 to reverse endianness
            sta   rx_rd_orig+1
            jsr   getdata
            sta   rx_rd
            sta   rx_rd_orig

            clc
            xce
            rep   $30                 ; longa longm
            lda   rx_rd
            and   #$7FF               ; 2KB
            clc
            adc   #$6000              ; RX base
            sta   rx_rd               ; NOTE storing it little-endian here
            sec
            xce
            sep   $30                 ; shorta shortm

            lda   #$04
            ldx   #$26
            jsr   setaddr             ; rx size = $0426
            jsr   getdata
            sta   rx_rcvd+1
            jsr   getdata
            sta   rx_rcvd             ; rx_rcvd now has bytes rcvd
            bne   have_byte
            lda   rx_rcvd+1
            bne   have_byte

            ply
            plx
            clc
            rts                       ; no byte. clc/rts

have_byte   lda   rx_rd+1             ; at least 1 byte available
            ldx   rx_rd
            jsr   setaddr             ; start at this base address
            jsr   getdata             ; read the byte from the buffer
            pha

            clc                       ; inc wiznet read buffer
            xce
            rep   $30                 ; longa longx
            lda   rx_rd_orig
            inc
            sta   rx_rd_orig          ; this is what we'll write back to rx_rd
            lda   rx_rcvd
            dec 
            sta   rx_rcvd             ; also subtract 1 from rx_rcvd
            sec
            xce
            sep   $30                 ; shorta shortx

            ldy   #1
            lda   #$04
            ldx   #$28                ; add rx_rcvd to rx_rd_orig and store back in $0428
            lda   rx_rd_orig+1
            jsr   setdata
            lda   rx_rd_orig
            jsr   setdata

            lda   rx_rcvd
            bne   have_byte2
            lda   rx_rcvd+1
            bne   have_byte2

            ldx   #$01
            jsr   setaddrlo           ; S0 command register
            lda   #$40
            jsr   setdata             ; RECV command

have_byte2  pla                       ; restore the byte
            ply                       ; restore saved regs
            plx
            sec
            rts

; out function
; add one byte to wiznet buffer
; a = byte, xy preserved
out         phx
            phy
            pha                       ; save data byte
            lda   #$04
            ldx   #$24
            jsr   setaddr             ; S0_TX_WR
            jsr   getdata
            sta   tx_wr+1             ; +1 to reverse endianness
            sta   tx_ptr+1
            jsr   getdata
            sta   tx_wr               ; tx_wr is the translated 5100 address we write to
            sta   tx_ptr              ; tx_ptr will be the exact original value
                                      ; + 4KB, 8KB etc without translation

            clc
            xce
            rep   $30                 ; 16 bit math because i can
            lda   tx_wr
            and   #$07FF              ; 2KB
            clc
            adc   #$4000              ; TX base
            sta   tx_wr               ; NOTE storing it little-endian here
            sec
            xce
            sep   $30

]txwt       ldy   #1
            lda   #$04
            ldx   #$20
            jsr   setaddr             ; tx free space = $0420 blaze it
            jsr   getdata
            sta   tx_free+1
            jsr   getdata
            sta   tx_free             ; store little-endian

            lda   tx_free+1
            bne   havebyte3
            lda   tx_free
            bne   havebyte3
            bra   ]txwt               ; wait if no tx buffer byte free
                                      ; (i srsly doubt this ever happens)

havebyte3   lda   tx_wr+1
            ldx   tx_wr
            jsr   setaddr             ; start at this base address

            pla
            ldy   #3
            jsr   setdata

            clc
            xce
            rep   $30
            lda   tx_ptr
            inc
            sta   tx_ptr
            sec
            xce
            sep   $30

            lda   #$04
            ldx   #$24
            jsr   setaddr
            lda   tx_ptr+1
            jsr   setdata
            lda   tx_ptr
            jsr   setdata             ; inc S0_TX_WR to add the byte

            lda   #$04
            ldx   #$01
            jsr   setaddr             ; S0 command register
            lda   #$20
            jsr   setdata             ; SEND command

]wt         nop
            jsr   getdata
            bne   ]wt          ; wait for send completion

            ply
            plx
            rts
