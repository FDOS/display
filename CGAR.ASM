; =====================================================================
;
;   CGA  codepage selection routines
;
;   Copyright (C) 9 Aug 2000 Ilya V. Vasilyev aka AtH//UgF@hMoscow
;      ( adapted from Ilya's GRAFTABL )
;   e-mail: hscool@netclub.ru
;      ( minimum touches by Aitor )
;
;               .       .       .       .       .       line that rules
;

dOld1F          dd      0


; Fn:   CGASSelect
; Does: Set a proper localized font for a given video mode in CGA
; In:   AL Screen mode (-1 if unknown) (UNUSED)
; Mod:  (none)
;

CGASSelect:
                push    dx

                call    GetGraftablInfo ; obtain the graftabl info to 8x8

                push    cs
                pop     ds
                mov     dx,bFont8x8+8*128
                mov     ax,251fh
                int     21H

                pop     dx
                clc
endCGASSelect:
                ret

; Fn:   CGAHSelect
; Does: Restore the original hardware font in CGA
; In:   CX: Number of codepage to be restored (IGNORED)

CGAHSelect:
                push    dx

                lds     dx,[cs:dOld1F]
                mov     ax,251Fh
                int     21H

                pop     dx
                clc
                ret


