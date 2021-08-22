;==============================================================================
; Contents of this file are copyright Phillip Stevens
;
; You have permission to use this for NON COMMERCIAL USE ONLY
; If you wish to use it elsewhere, please include an acknowledgement to myself.
;
; https://github.com/feilipu/
;
; https://feilipu.me/
;

INCLUDE     "rc2014.inc"

SECTION     vector_rst
ORG         $0000

SECTION     vector_table_prototype
ORG         VECTOR_PROTO

SECTION     vector_null_ret
ORG         VECTOR_PROTO+VECTOR_SIZE

SECTION     serial_interrupt
ORG         $0080

SECTION     acia_rxa
ORG         $00B0

SECTION     serial_tx
ORG         $0130

SECTION     serial_print
ORG         $01A0

SECTION     init
ORG         $01B8

SECTION     init_strings
ORG         $0240

;==============================================================================
