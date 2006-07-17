;ÿ
;   FreeDOS DISPLAY:  SelectD.ASM
;
;   ===================================================================
;
;   Hardware dependant codepage selection routines for DISPLAY
;   WWW:    http://www.freedos.org/
;
;   ===================================================================
;

; =====================================================================
;
;   Generic hardware-related DISPLAY variables and routines
;

dGraftablBuf    DD      0               ; Graftabl table Buffer

; Fn:   GetGraftablInfo
; Does: Recovers the graftabl info to the pointer stored in its buffer
; In:   Nothing
; Out:  Info retrieved, no other info returned
;       AX, DS: destroyed

GetGraftablInfo:
                mov     ax,0b000h       ; first see if GRAFTABL is active
                int     02fh
                cmp     al,0ffh
                jne     NoGraftabl

                push    bx              ; preserve BX!
                mov     ax,0b001h       ; GRAFTABL present, import the
                push    cs              ; table to DS:BX
                pop     ds
                mov     bx,dGraftablBuf
                int     02fh
                pop     bx
                
NoGraftabl:
                ret


; =====================================================================
;
;   Specific resident routines
;

;   HARDWARE:  EGA/VGA          (Ilya V. Vasilyev)

%include        "EGAr.asm"

;   HARDWARE:  CGA              (Aitor Santamar¡a Merino)

%include        "CGAr.asm"


