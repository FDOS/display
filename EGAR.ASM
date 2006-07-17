; =====================================================================
;
;   EGA/VGA  codepage selection routines
;
;   Copyright (C) 9 Aug 2000 Ilya V. Vasilyev aka AtH//UgF@hMoscow
;   e-mail: hscool@netclub.ru
;   ( minimum touches by Aitor )
;
;               .       .       .       .       .       line that rules
;



; Fn:   SModeTest
; Does: Determines wether text mode or graphic mode is enabled
; In:   nothing
; Out:  Carry set if graphic mode is set
;
;               (EGA/VGA only!)


SModeTest:
                push    ax
                mov     al,6
                push    dx
                mov     dx,3ceH
                out     dx,al
                call    sfr             ; Small delay
                inc     dx
                in      al,dx           ; Graph Controller Misc Register
                pop     dx
                shr     al,1
                pop     ax
sfr:            ret




; Fn:   EGASSelect
; Does: Set a proper localized font for a given video mode
; In:   AL Screen mode (-1 if unknown)
; Mod:  (none)
;
; Summary: self-determine rows per character, then call the
;          load-character-table function, which is int10h:
;               AX=1100h (for text mode),
;               AX=1121h (for graphics mode)
;
; NOTES:
; - AX, CX, DS, ES, DI  will be used and not preserved
;

EGASSelect:
                push    cs              ; we require ES==CS
                pop     es

                push    dx
                push    bx
                push    si
                push    bp

                ;************ initialise DX to number of lines (rows)
		;             in the screen

                xor     bx,bx                   ; BL: Zero!
                mov     ds,bx
                mov     dx,[484H]
                mov     bh,dh                   ; BH: bytes per character
                inc     dx                      ; DL: number of lines

                ;************ restore int1Fh vector with pointer to 8x8 table
                ;             (this is useful just in the 8x8 mode)

                mov     WORD [7cH],bFont8x8+1024; Kinda tradition to restore
                mov     [7eH],cs                ; vector 1fH every time

                ;************ determine the table to be installed (the number
		;             of rows)

                cmp     BYTE [cs:bAdapter],VGA  ; if VGA (or better) or BH>=16,
                jb      sfNo8x16		; then 8x16
                cmp     bh,16
                jb      sfNo8x16
                mov     bh,16                   ; force bh=16 (in case it's >16)
                jmp     SHORT sfSetIt
sfNo8x16:
                cmp     bh,14                   ; check bh>=14
                jb      sfNo8x14
                mov     bh,14                   ; force bh=14 (in case it's >14)
                jmp     SHORT sfSetIt
sfNo8x14:
                cmp     bh,8                    ; check bh>=8  If below 8,
                jb      sfpr                    ; then unsupported ->RETURN
                mov     bh,8                    ; force bh=8 (in case it's >8)

                ;************ We have checked the number of rows, then set it
                ;             First, we obtain the data from their sources
sfSetIt:
                mov     bp, bFont8x8

                cmp     bh, 8
                je      sfToG

                add     bp, 2048
                cmp     bh, 14
                je      sfToG

                add     bp, 3584

                ;             Second, we determine wether text or graphics
sfToG:
                cmp     al,13H
                ja      sfTest          ; Screen modes above 13H are unknown
                cmp     al,0dH
                jae     sfGraph         ; Screen modes 0d..13H   are graphics
                cmp     al,4
                jb      sfText          ; Screen modes  0..3     are text
                cmp     al,7
                jz      sfText          ; Screen mode    7       is  text
                jb      sfGraph         ; Screen modes  4..6     are graphics

                ;************ unknown, test if text/graphics mode
sfTest:
                call    SModeTest
                jc      sfGraph

                ;************ set the font for text mode: use int10h / ax=1100h
sfText:
                mov     cx,256          ; Load 256 characters
                mov     ax,1100H        ; Load user font, reprogram controller
                cwd                     ; DX=0, BL is already zero, BH=bpc
                jmp     SHORT sfi10

                ;************ set the font for graphics mode:
		;             use int10h / ax=1121h
sfGraph:
                mov     cl,bh           ; bytes per character
                sub     ch,ch           ; BL is already zero, DL=# of lines
                mov     ax,1121H

                ;************ call the appropriate interrupt function
sfi10:
                pushf
                call    FAR [cs:dOld10]

                ;************ end of interrupt
sfpr:
                pop     bp
                pop     si
                pop     bx
                pop     dx
                clc                     ; just in case, always SUCCEED
endEGASSelect:
                ret


; Fn:   old10call
; Does: clears BX and calls the old driver
; In:   AX = some function of the old 10handler
; Out:  results of the call

old10call:      xor     bx, bx
                pushf
                call    FAR [cs:dOld10]
                ret



; Fn:   RefreshHWcp
; Does: Sets the hardware codepage, helped by the old int 10h handler
; In:   CL: index of hardware font page to select (0, 1,...)
; Out:  -

EGAHSelect:

                push    ax
                push    bx

                ;*********************** try Arabic/Hebrew first

                inc     cl
                mov     ax,0ad42h
                int     02fh

                ;*********************** now call BIOS to refresh

                mov     cx,[cs:wNumSubFonts]

                call    SModeTest
                jc      RestoreGraph

                mov     ax, 1101h       ; text mode calls
                call    old10call
                cmp     cl,2
                jb      RefreshHWcpEnd
                
                mov     ax, 1102h
                call    old10call
                cmp     cl,3
                jb      RefreshHWcpEnd

                mov     ax, 1104h
                call    old10call
                jmp     RefreshHWcpEnd

RestoreGraph:                           ; graphics mode calls
                mov     ax, 1122h
                call    old10call
                cmp     cl,2
                jb      RefreshHWcpEnd

                mov     ax, 1123h
                call    old10call
                cmp     cl,3
                jb      RefreshHWcpEnd

                mov     ax, 1124h
                call    old10call

RefreshHWcpEnd:
                clc
                pop     bx
                pop     ax

                ret
