
;   FreeDOS DISPLAY:  HWInit.ASM
;
;   ===================================================================
;
;   Hardware dependant initialisation routines for DISPLAY, and
;   table with the supported hardware
;
;   WWW:    http://www.freedos.org/
;
;   ===================================================================
;

; =====================================================================
;
; Tables
;
;               .       .       .       .       .       line that rules

HardwareTables:
                DB      "EGA",0,0,0,0,0
                DB      "EGA     "
                DW      EGAInit
                DW      0

                DB      "EGA 8",0,0,0
                DB      "EGA     "
                DW      EGAInit
                DW      1

                DB      "LCD",0,0,0,0,0
                DB      "EGA     "
                DW      EGAInit
                DW      1

                DB      "EGA 14",0,0
                DB      "EGA     "
                DW      EGAInit
                DW      2

                DB      "VGA",0,0,0,0,0
                DB      "EGA     "
                DW      EGAInit
                DW      3

                DB      "CGA",0,0,0,0,0
                DB      "EGA     "
                DW      CGAInit
                DW      0

                DB      0               ; end of table

; =====================================================================
;
; Initialisation routines for EGA/VGA
;
;               .       .       .       .       .       line that rules

tblDCC           DB     NO,MDA,CGA,NO,EGA,EGA,NO,VGA,VGA,NO,MCGA,MCGA,MCGA

; Fn:   InitGraftablBuffer
; In:   None
; Out:  None
; Author:  Aitor Santamar¡a Merino
; Does: Initialises the GRAFTABL buffer to be used by GetGraftablInfo

InitGraftablBuffer:
                mov     WORD [cs:dGraftablBuf],bFont8x8+8*128
                mov     [cs:dGraftablBuf+2],cs
                ret


; Fn:   TestAdapter
; In:   (none)
; Out:  AL Video adapter type
; Note: No VESA check yet.
; Author: Ilya V. Vasilyev

TestAdapter:
                 mov    ax,1a00H        ; Call DCC
                 int    10H
                 cmp    al,1aH
                 jnz    taNoDCC

; Now we know, that have PS/2 Video BIOS.
; Active adapter code is now in BL register

                 cmp    bl,0cH
                 ja     taNoDCC
                 sub    bh,bh
                 mov    al,[tblDCC+bx]
                 cmp    al,bh
                 jnz    taKnowAdapter
taNoDCC:
                 mov    bl,10H          ; Get Configuration Information
                 mov    ah,12H          ; Alternate Select
                 int    10H
                 mov    al,EGA
                 cmp    bl,10H
                 jnz    taKnowAdapter   ; if bh<>0, EGA_MONO

                 int    11H             ; EquipList
                 and    al,30H
                 cmp    al,30H
                 mov    al,MDA
                 jz     taKnowAdapter
                 mov    al,CGA
taKnowAdapter:
                 mov    [bAdapter],al
                 ret



; Fn:   EGAInit
; In:   AX: parameter from table
;           0: "EGA" (use adapter type to determine)
;           1: "EGA 8", "LCD"  (8x8 only)
;           2: "EGA 14" (8x8,814 only)
;           3: "VGA" (8x8,8x14,8x16)
;           NO OTHERS ARE SUPPORTED
; Out:  AL Video adapter type
;       FCarry: set on error (not found, or initialisation error)
;         DX:  offset to an error string
; NOTE: bMaxHWcpNumber:  should detect the maximum number of HW CPs, if I
;          knew of a way to get this info from ARABIC/HEBREW
;       wHardCPs: no default codepages specified
;

EGAInit:        mov     [cs:wMinFontSize],ax

                ;****** Test the adapter: exit if CGA

                call    TestAdapter
                mov     [cs:bAdapter], al
                cmp     al,CGA
                ja      ComputeSubfont

                mov     dx,errAcient	; driver requires EGA or better
                stc
                ret

                ;****** Compute the minimum subfont number (AL=bAdapter)

ComputeSubfont:
                mov     cx,[cs:wMinFontSize]
                test    cx,0ffffh       ; if parameter non-null, it is
                jnz     EGAInitEnd      ; the minimum subfont number

                mov     cx,1
                cmp     al,EGA          ; remember: AL=adapter
                jb      MinimumComputed
                inc     cx
                cmp     al,VGA
                jb      MinimumComputed
                inc     cx

MinimumComputed:
                mov     [cs:wMinFontSize],cx
                
                ;****** Exit successfuly: update the resident procs and exit

EGAInitEnd:
                call    InitGraftablBuffer
                
                mov     WORD [cs:pRefreshHWcp], EGAHSelect
                mov     WORD [cs:pRefreshSWcp], EGASSelect
                clc
                ret

; Fn:   CGAInit
; In:   AX: parameter from table (IGNORED)
; Out:  AL Video adapter type
;       FCarry: set on error (not found, or initialisation error)
;         DX:  offset to an error string
;


CGAInit:
                ;****** Test the adapter: exit if not CGA
                call    TestAdapter
                cmp     al,CGA
                je      CGAOk

                mov     dx,errNoCGA	; driver requires CGA
                stc
                ret

                ;****** CGA was found, set variables and interrupt vectors
CGAOk:
                xor     ax,ax           ; set variables
                mov     [cs:wHardCPs],ax

                inc     ax
                mov     [cs:wMinFontSize],al
                mov     [cs:bMaxHWcpNumber],al

                mov     al,CGA
                mov     [cs:bAdapter],al

                push    es
                mov     ax,351Fh        ; read hardware vector
                int     21h
                mov     [cs:dOld1F],bx
                mov     [cs:dOld1F+2],es
                pop     es

                call    InitGraftablBuffer
                
                                        ; CGA procedures
                mov     WORD [cs:pRefreshHWcp], CGAHSelect
                mov     WORD [cs:pRefreshSWcp], CGASSelect
                clc
                ret

