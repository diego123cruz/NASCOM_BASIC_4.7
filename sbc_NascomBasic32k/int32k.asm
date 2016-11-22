;==================================================================================
; Contents of this file are copyright Grant Searle
;
; You have permission to use this for NON COMMERCIAL USE ONLY
; If you wish to use it elsewhere, please include an acknowledgement to myself.
;
; http://searle.hostei.com/grant/index.html
;
; eMail: home.micros01@btinternet.com
;
; If the above don't work, please perform an Internet search to see if I have
; updated the web page hosting service.
;
;==================================================================================
;
; ACIA 6850 interrupt driven serial I/O to run modified NASCOM Basic 4.7.
; Full input and output buffering with incoming data hardware handshaking.
; Handshake shows full before the buffer is totally filled to
; allow run-on from the sender.
; Transmit and receive are interrupt driven.
;
; https://github.com/feilipu/
; https://feilipu.me/
;
;==================================================================================

SER_CTRL_ADDR   .EQU   $80    ; Address of Control Register (write only)
SER_STATUS_ADDR .EQU   $80    ; Address of Status Register (read only)
SER_DATA_ADDR   .EQU   $81    ; Address of Data Register

SER_CLK_DIV_01  .EQU   $00    ; Divide the Clock by 1
SER_CLK_DIV_16  .EQU   $01    ; Divide the Clock by 16
SER_CLK_DIV_64  .EQU   $02    ; Divide the Clock by 64 (default value)
SER_RESET       .EQU   $03    ; Master Reset (issue before any other Control word)

SER_7E2         .EQU   $00    ; 7 Bits Even Parity 2 Stop Bits
SER_7O2         .EQU   $04    ; 7 Bits  Odd Parity 2 Stop Bits
SER_7E1         .EQU   $08    ; 7 Bits Even Parity 1 Stop Bit
SER_7O1         .EQU   $0C    ; 7 Bits  Odd Parity 1 Stop Bit
SER_8N2         .EQU   $10    ; 8 Bits   No Parity 2 Stop Bits
SER_8N1         .EQU   $14    ; 8 Bits   No Parity 1 Stop Bit
SER_8E1         .EQU   $18    ; 8 Bits Even Parity 1 Stop Bit
SER_8O1         .EQU   $1C    ; 8 Bits  Odd Parity 1 Stop Bit

SER_TDI_RTS0    .EQU   $00    ; _RTS low,  Transmitting Interrupt Disabled
SER_TEI_RTS0    .EQU   $20    ; _RTS low,  Transmitting Interrupt Enabled
SER_TDI_RTS1    .EQU   $40    ; _RTS high, Transmitting Interrupt Disabled
SER_TDI_BRK     .EQU   $60    ; _RTS low,  Transmitting Interrupt Disabled, BRK on Tx

SER_TEI_MASK    .EQU   $60    ; Mask for the Tx Interrupt & RTS bits   

SER_REI         .EQU   $80    ; Receive Interrupt Enabled

SER_RDRF        .EQU   $01	  ; Receive Data Register Full
SER_TDRE        .EQU   $02	  ; Transmit Data Register Empty
SER_DCD         .EQU   $04	  ; Data Carrier Detect
SER_CTS         .EQU   $08    ; Clear To Send
SER_FE          .EQU   $10    ; Framing Error (Received Byte)
SER_OVRN        .EQU   $20    ; Overrun (Received Byte
SER_PE          .EQU   $40    ; Parity Error (Received Byte)
SER_IRQ         .EQU   $80    ; IRQ (Either Transmitted or Received Byte)
   
   
  
SER_RX_BUFSIZE  .EQU     60H  ; Size of the Rx Buffer, 96 Bytes
SER_RX_FULLSIZE .EQU     SER_RX_BUFSIZE - 4
                              ; Size of the Rx Buffer, when not_RTS is signalled

SER_TX_BUFSIZE  .EQU     60H  ; Size of the Tx Buffer, 96 Bytes

serControl      .EQU     $8000
serRxBuf        .EQU     serControl+1
serRxInPtr      .EQU     serRxBuf+SER_RX_BUFSIZE
serRxOutPtr     .EQU     serRxInPtr+2
serRxBufUsed    .EQU     serRxOutPtr+2
serTxBuf        .EQU     serRxBufUsed+1
serTxInPtr      .EQU     serTxBuf+SER_TX_BUFSIZE
serTxOutPtr     .EQU     serTxInPtr+2
serTxBufUsed    .EQU     serTxOutPtr+2
basicStarted    .EQU     serTxBufUsed+1

                             ; end of ACIA stuff is $80CB
                             ; set BASIC Work space WRKSPC $80D0

TEMPSTACK       .EQU     $817B ; Top of BASIC line input buffer (CURPOS WRKSPC+0ABH)
                               ; so it is "free ram" when BASIC resets

CR              .EQU     0DH
LF              .EQU     0AH
CS              .EQU     0CH             ; Clear screen

                .ORG $0000
;------------------------------------------------------------------------------
; Reset

RST00:          DI                       ;Disable interrupts
                JP       INIT            ;Initialize Hardware and go

;------------------------------------------------------------------------------
; TX a character over RS232 

                .ORG     0008H
RST08:           JP      TXA

;------------------------------------------------------------------------------
; RX a character over RS232 Channel A [Console], hold here until char ready.

                .ORG 0010H
RST10:           JP      RXA

;------------------------------------------------------------------------------
; Check serial status

                .ORG 0018H
RST18:           JP      CKINCHAR

;------------------------------------------------------------------------------
; RST 38 - INTERRUPT VECTOR [ for IM 1 ]

                .ORG     0038H
RST38:                 
serialInt:
        push af
        push hl

; start doing the Rx stuff

        in a, (SER_STATUS_ADDR)     ; get the status of the ACIA
        and SER_RDRF                ; check whether a byte has been received
        jr z, tx_check              ; if not, go check for bytes to transmit 

        in a, (SER_DATA_ADDR)       ; Get the received byte from the ACIA 
        push af

        ld a, (serRxBufUsed)        ; Get the number of bytes in the Rx buffer
        cp SER_RX_BUFSIZE              ; check whether there is space in the buffer
        jr c, poke_rx               ; not full, so go poke Rx byte
        pop af                      ; buffer full so drop the Rx byte
        jr tx_check                 ; check if we can send something

poke_rx:

        ld hl, (serRxInPtr)         ; get the pointer to where we poke
        pop af                      ; get Rx byte
        ld (hl), a                  ; write the Rx byte to the serRxIn

        inc hl                      ; move the Rx pointer along
        ld a, l	                    ; move low byte of the Rx pointer
        cp (serRxBuf + SER_RX_BUFSIZE) & $FF
        jr nz, no_rx_wrap
        ld hl, serRxBuf             ; we wrapped, so go back to start of buffer
    	
no_rx_wrap:

        ld (serRxInPtr), hl         ; write where the next byte should be poked

        ld hl, serRxBufUsed
        inc (hl)                    ; atomically increment Rx count

; now start doing the Tx stuff

tx_check:

        ld a, (serTxBufUsed)        ; get the number of bytes in the Tx buffer
        or a                        ; check whether it is zero
        jr z, tei_clear             ; if the count is zero, then disable the Tx Interrupt

        in a, (SER_STATUS_ADDR)     ; get the status of the ACIA
        and SER_TDRE                ; check whether a byte can be transmitted
        jr z, rts_check             ; if not, go check for the receive RTS selection

        ld hl, (serTxOutPtr)        ; get the pointer to place where we pop the Tx byte
        ld a, (hl)                  ; get the Tx byte
        out (SER_DATA_ADDR), a      ; output the Tx byte to the ACIA

        inc hl                      ; move the Tx pointer along
        ld a, l                     ; get the low byte of the Tx pointer
        cp (serTxBuf + SER_TX_BUFSIZE) & $FF
        jr nz, no_tx_wrap
        ld hl, serTxBuf             ; we wrapped, so go back to start of buffer

no_tx_wrap:

        ld (serTxOutPtr), hl        ; write where the next byte should be popped

        ld hl, serTxBufUsed
        dec (hl)                    ; atomically decrement current Tx count
        jr nz, tx_end               ; if we've more Tx bytes to send, we're done for now
        
tei_clear:

        ld a, (serControl)          ; get the ACIA control echo byte
        and ~SER_TEI_MASK           ; mask out the Tx interrupt bits
        or SER_TDI_RTS0             ; mask out (disable) the Tx Interrupt, keep RTS low
        ld (serControl), a          ; write the ACIA control byte back
        out (SER_CTRL_ADDR), a      ; Set the ACIA CTRL register

rts_check:

        ld a, (serRxBufUsed)        ; get the current Rx count    	
        cp SER_RX_FULLSIZE          ; compare the count with the preferred full size
        jr c, tx_end                ; leave the RTS low, and end

        ld a, (serControl)          ; get the ACIA control echo byte
        and ~SER_TEI_MASK           ; mask out the Tx interrupt bits
        or SER_TDI_RTS1             ; Set RTS high, and disable Tx Interrupt
        ld (serControl), a          ; write the ACIA control echo byte back
        out (SER_CTRL_ADDR), a	    ; Set the ACIA CTRL register

tx_end:

        pop hl
        pop af
        
        ei
        reti

;------------------------------------------------------------------------------
RXA:
waitForRxChar:

        ld a, (serRxBufUsed)        ; get the number of bytes in the Rx buffer

        or a                        ; see if there are zero bytes available
        jr z, waitForRxChar         ; wait, if there are no bytes available
        
        push hl                     ; Store HL so we don't clobber it

        ld hl, (serRxOutPtr)        ; get the pointer to place where we pop the Rx byte
        ld a, (hl)                  ; get the Rx byte
        push af                     ; save the Rx byte on stack

        inc hl                      ; move the Rx pointer along
        ld a, l                     ; get the low byte of the Rx pointer
        cp (serRxBuf + SER_RX_BUFSIZE) & $FF
        jr nz, get_no_rx_wrap
        ld hl, serRxBuf             ; we wrapped, so go back to start of buffer

get_no_rx_wrap:

        ld (serRxOutPtr), hl        ; write where the next byte should be popped

        ld hl,serRxBufUsed
        dec (hl)                    ; atomically decrement Rx count
        ld a,(hl)                   ; get the newly decremented Rx count

        cp SER_RX_FULLSIZE          ; compare the count with the preferred full size
        jr nc, get_clean_up_rx      ; if the buffer is full, don't change the RTS

        di                          ; critical section begin
        
        ld a, (serControl)          ; get the ACIA control echo byte
        and ~SER_TEI_MASK           ; mask out the Tx interrupt bits
        or SER_TDI_RTS0             ; set RTS low.
        ld (serControl), a	        ; write the ACIA control echo byte back
        out (SER_CTRL_ADDR), a      ; set the ACIA CTRL register
        
        ei                          ; critical section end

get_clean_up_rx:

        pop af                      ; get the Rx byte from stack
        pop hl                      ; recover HL

        ret                         ; char ready in A

;------------------------------------------------------------------------------
TXA:
        push hl                     ; Store HL so we don't clobber it        
        push af                     ; Store character

waitForTxChar:        
        ld a, (serTxBufUsed)        ; Get the number of bytes in the Tx buffer
        cp SER_TX_BUFSIZE           ; check whether there is space in the buffer
        jr nc, waitForTxChar        ; buffer full, so wait till space available
        
        pop af                      ; Retrieve character
        
put_poke_tx:

        ld hl, (serTxInPtr)         ; get the pointer to where we poke
        ld (hl), a                  ; write the Tx byte to the serTxInPtr   
        inc hl                      ; move the Tx pointer along

        ld a, l                     ; move low byte of the Tx pointer
        cp (serTxBuf + SER_TX_BUFSIZE) & $FF
        jr nz, put_no_tx_wrap
        ld hl, serTxBuf             ; we wrapped, so go back to start of buffer

put_no_tx_wrap:

        ld (serTxInPtr), hl         ; write where the next byte should be poked

        ld hl, serTxBufUsed
        inc (hl)                    ; atomic increment of Tx count

clean_up_tx:
        
        di                          ; critical section begin
        
        ld a, (serControl)          ; get the ACIA control echo byte
        and ~SER_TEI_MASK           ; mask out the Tx interrupt bits
        or SER_TEI_RTS0             ; set RTS low. if the TEI was not set, it will work again
        ld (serControl), a          ; write the ACIA control echo byte back
        out (SER_CTRL_ADDR), a      ; set the ACIA CTRL register
        
        ei                          ; critical section end
        
        pop hl                      ; recover HL

        ret

;------------------------------------------------------------------------------
CKINCHAR:       LD       A,(serRxBufUsed)
                CP       $0
                RET

PRINT:          LD       A,(HL)          ; Get character
                OR       A               ; Is it $00 ?
                RET      Z               ; Then RETurn on terminator
                RST      08H             ; Print it
                INC      HL              ; Next Character
                JR       PRINT           ; Continue until $00
                RET
;------------------------------------------------------------------------------
INIT:
               LD        HL,TEMPSTACK    ; Temp stack
               LD        SP,HL           ; Set up a temporary stack
               
               LD        HL,serRxBuf     ; Initialise Rx Buffer
               LD        (serRxInPtr),HL
               LD        (serRxOutPtr),HL

               LD        HL,serTxBuf     ; Initialise Tx Buffer
               LD        (serTxInPtr),HL
               LD        (serTxOutPtr),HL              
               
               XOR       A               ; 0 the accumulator
               LD        (serRxBufUsed),A
               LD        (serTxBufUsed),A
               
               ld        a, SER_RESET   ; Master Reset the ACIA
               out       (SER_CTRL_ADDR),a
		
               nop

               ld        a, SER_REI|SER_TDI_RTS0|SER_8N1|SER_CLK_DIV_64
                                         ; load the default ACIA configuration
                                         ; 8n1 at 115200 baud
                                         ; receive interrupt enabled
                                         ; transmit interrupt disabled
                                    
               ld        (serControl), a     ; write the ACIA control byte echo
               out       (SER_CTRL_ADDR), a  ; output to the ACIA control byte
               
               IM        1               ; interrupt mode 1
               EI
               
               LD        HL,SIGNON1      ; Sign-on message
               CALL      PRINT           ; Output string
               LD        A,(basicStarted); Check the BASIC STARTED flag
               CP        'Y'             ; to see if this is power-up
               JR        NZ,COLDSTART    ; If not BASIC started then always do cold start
               LD        HL,SIGNON2      ; Cold/warm message
               CALL      PRINT           ; Output string
CORW:
               CALL      RXA
               AND       %11011111       ; lower to uppercase
               CP        'C'
               JR        NZ, CHECKWARM
               RST       08H
               LD        A,$0D
               RST       08H
               LD        A,$0A
               RST       08H
COLDSTART:     LD        A,'Y'           ; Set the BASIC STARTED flag
               LD        (basicStarted),A
               JP        $01C0           ; <<<< Start BASIC COLD
CHECKWARM:
               CP        'W'
               JR        NZ, CORW
               RST       08H
               LD        A,$0D
               RST       08H
               LD        A,$0A
               RST       08H
               JP        $01C3           ; <<<< Start BASIC WARM
              

SIGNON1:       .BYTE     "Z80 SBC by Grant Searle",CR,LF
               .BYTE     "ACIA by feilipu",CR,LF,0
SIGNON2:       .BYTE     CR,LF
               .BYTE     "Cold or warm start (C or W)? ",0
 
               .ORG      01BFH           ; fill the space to bas32k.asm with $FF
               .BYTE     $FF
               .END