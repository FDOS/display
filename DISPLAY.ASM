
;   FreeDOS DISPLAY.SYS           v0.12
;   FreeDOS PRINTER.SYS
;
;   ===================================================================
;
;   FreeDOS driver to add support of codepage management for the
;   default CON driver (for screen) or default PRN driver (for printer)
;
;   Copyright (C) 2002-05 Aitor Santamar¡a_Merino
;   email:  aitorsm@inicia.es
;
;   (contributed code from DISPLAY 0.5b package, and patches by
;    Ilya V. Vasilyev aka AtH//UgF@hMoscow (hscool@netclub.ru)
;    in  VIDEOINT.ASM, SELECTD.ASM and DISPHW.ASM)
;
;   WWW:    http://www.freedos.org/
;
;   ===================================================================
;
;   This program is free software; you can redistribute it and/or modify
;   it under the terms of the GNU General Public License as published by
;   the Free Software Foundation; either version 2 of the License, or
;   (at your option) any later version.
;
;   This program is distributed in the hope that it will be useful,
;   but WITHOUT ANY WARRANTY; without even the implied warranty of
;   MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
;   GNU General Public License for more details.
;
;   You should have received a copy of the GNU General Public License
;   along with this program; if not, write to the Free Software
;   Foundation, Inc., 675 Mass Ave, Cambridge, MA 02139, USA.
;

CPU     8086

;
;   Driver you want to compile (uncomment ONLY one!)
;

%define DISPLAY
;%define PRINTER

;       .       .       .       .       .       .       line that rules
;
;===================================================================
; VERSION CONSTANT
;===================================================================
;
; NOTE: To change it, please also modify the output string at the
;       bottom of the file

Version                 EQU     000CH   ; Version of the driver (0.12)


;===================================================================
; DRIVER ERROR CONSTANTS
;===================================================================
;
; Explained the functions where errors are admissible

ERR_UnknownFunction     EQU     1       ; (all)
ERR_CPNotPrepared       EQU     26      ; Select (SW)
ERR_CPNotSelected       EQU     26      ; Query
ERR_KEYBFailed          EQU     27      ; Select (HW/SW)
ERR_QueryDeviceError    EQU     27      ; Query
ERR_DevCPNotFound       EQU     27      ; In prepare
ERR_SelPrepDeviceError  EQU     29      ; Select (HW/SW), In prepare
                                        ; NEW: also reflects problems with XMS
                                        ;      in select
ERR_FileDamaged         EQU     31      ; In prepare
                                        ; NEW: also reflects problems with XMS
                                        ;      in prepare
ERR_NoPrepareStart      EQU     31      ; End prepare

;===================================================================
; OTHER CONSTANTS
;===================================================================
;

CommandLine_Offset      EQU     080h    ; where in PSP is commandline

%ifdef          DISPLAY
DriverSignature         EQU     1
%endif
%ifdef          PRINTER
DriverSignature         EQU     2
%endif

;===================================================================
; PROGRAM HEADER
;===================================================================
;
;               .       .       .       .       .       line that rules


                ORG     100H

                jmp     NEAR Install    ; simply go to Install

DevName         DB      "        "      ; Device name

;===================================================================
; INTERRUPT SERVICES  (DISPLAY only)
;===================================================================
;
;       .       .       .       .       .       .       line that rules

%ifdef          DISPLAY

%include        "videoint.asm"
%include        "muxint.asm"

%endif

;===================================================================
; SELECT RESIDENT SUBROUTINES
;===================================================================
;
;       .       .       .       .       .       .       line that rules


; Fn:   FindCodepage
; Does: Finds a codepage in the prepared array
; In:   BX=new codepage
; Out:  CL=position in table (starts on 0=first hardware codepage, ...)
;          (0ffh if not found)
;       CH=00h


FindCodepage:   xor     cx,cx           ; CL: total table size
                mov     cl,[cs:wNumSoftCPs]
                add     cl,[cs:wNumHardCPs]
                push    bx
                mov     ax,bx
                mov     bl,cl           ; copy of table size on BL
                inc     cl              ; to control the loop better

                mov     di,wHardCPs     ; DS:SI: begining of table
                push    es
                push    cs
                pop     es
                cld

        repne   scasw

                test    cl,0ffh
                jnz     CodepageFound
                mov     cl,0ffh
                jmp     FindCodepageEnd


CodepageFound:
                xchg    bl,cl
                sub     cl,bl           ; tablesize-loop = position


FindCodepageEnd:
                pop     es
                pop     bx
                ret

; Fn:   GetMemoryLocation
; Does: From the number of buffer to be used, obtains the
;       Handle, Segment and Offset to be used in the memory transfer
; In:   CX: number of buffer to be used (untouched)
; Out:  AX: Handle
;       DX: Segment // upperWord of offset
;       SI: Offset

GetMemoryLocation:
                push    cx
                shl     cx,1
                mov     si,wBufferPtrs
                add     si,cx
                mov     dx,[cs:si]              ; DX: stored value
                pop     cx

                mov     al,1
                shl     al,cl
                test    al,[cs:fBuffersInXMS]
                jz      RealMemoryData

XMSMemoryData:
                mov     ax,dx
                xor     dx,dx
                xor     si,si
                ret

RealMemoryData:
                xor      ax,ax
                mov      si,dx
                push     cs
                pop      dx
                ret



; Fn:   MoveBufferToSelect
; Does: Moves info from a prepare buffer to the select buffer (bFont8x8)
; In:   CL: Number of buffer that is to be used for the transfer
; Out:  CFlag set on error

MoveBufferToSelect:

                ; Stablish the source
                call    GetMemoryLocation
                
                mov     [cs:XMSMoveSrcH],ax
                mov     [cs:XMSMoveSrcO+2],dx
                mov     word [cs:XMSMoveSrcO],si

                ; Stablish the target

                mov     word [cs:XMSMoveTrgH],0
                mov     [cs:XMSMoveTrgO+2],cs
                mov     word [cs:XMSMoveTrgO],bFont8x8

                ; Stablish the length

                mov     cx,[cs:wTableSize]

                ; Do the move

                shl     cx,1
                mov     word [cs:XMSMoveLen],cx

                push    cs
                pop     ds
                mov     si,XMSMoveLen

                ; Stablish the function number and call XMS
                
                mov     ah,0Bh

                call    far [cs:lpXMSdriver]
                cmp     ax,1
                je      ReturnSuccess
                stc
                ret
ReturnSuccess:
                clc
                ret


; Fn:   SelectCodepage
; Does: Selects a codepage from the pool
; In:   BX=new codepage
; Error:   CF set
;          AX=0 if not found, and in this case
;          DX= error code
; Success: AX=1
;          CF clear
;          DX untouched


SelectCodepage:
               ;************ PUSH globally DI, SI, DX

                push    di
                push    si
                push    dx

                ;************ check if KEYB/PRINT are ready for the change

                push    bx              ; save cp number, just in case
;jmp KeybOK ; Fast and dirty way to bypass Keyb support
%ifdef          DISPLAY
                mov     ax,0ad80h       ; first see if it is installed
                int     02fh
                cmp     al,0ffh
                jne     KeybOK          ; if not found, continue
                mov     ax,0ad81h
                pop     bx
                clc
                push    bx
                int     02fh
                jnc     KeybOK
                jmp     KeybFailed
%endif

%ifdef          PRINTER
                push    ds
                mov     ax,0104h        ; Freeze status to read config
                int     02fh
                jc      PrintFailed
                mov     dl,[ds:si]      ; get first byte of the first
                pop     ds              ; file in the print queue
                mov     ax,0105h        ; Restore status (hope to succeed!)
                int     02fh
                test    dl,0ffh         ; now test if there are files to
                jz      KeybOK          ; print, if there is any -> fail
                jmp     KeybFailed      ; (DS already pop-ed)

PrintFailed:    pop     ds
%endif

KeybFailed:
                pop     bx              ; KEYB or PRINT are not ready
                mov     dx, ERR_KEYBFailed
                jmp     SelectCodepageError

                ;************ If =current, then REFRESH

KeybOK:
                pop     bx              ; recover codepage number

                cmp     bx, [cs:wCPselected]
                jne     CheckBuffer

                push    cx
                test    BYTE [cs:bActive], 0ffh
                jz      RefreshHW

PreRefreshSW:
                push    es
                push    ds
                
                jmp     RefreshSW

                ;************ see if it is the one in the buffer

CheckBuffer:
                cmp     bx,[cs:wCPbuffer]
                jne     NotRefresh

                push    cx
                jmp     PreRefreshSW

                ;************ see if it is in the table
                
NotRefresh:
                push    cx
                call    FindCodepage    ; see if we find it

                cmp     cl, 0ffh
                jne     CPFound
                mov     dx, ERR_CPNotPrepared
                pop     cx
                jmp     SelectCodepageError

CPFound:
                ;************ READY TO SELECT

                cmp     cx,[cs:wNumHardCPs]
                jae     SetSWCodepage
                mov     [cs:whtCPselected], cx

                ;************ set the hardware codepage

RefreshHW:      mov     cx,[cs:whtCPselected]
                call    [cs:pRefreshHWcp]
                pop     cx

                jc      SelectCodepageError

                mov     BYTE [cs:bActive],0

                jmp     SelectCodepageSuccess

                ;************ set the software codepage

SetSWCodepage:
                push    es
                push    ds

                sub     cx,[cs:wNumHardCPs]  ; CX=0,1,2...

                call    MoveBufferToSelect
                mov     dx,ERR_SelPrepDeviceError
                jc      SelectCodepageError

RefreshSW:
                mov     al,-1           ; unknown vide mode!
                call    [cs:pRefreshSWcp]

                pop     ds
                pop     es
                pop     cx

                mov     dx,ERR_SelPrepDeviceError
                jc      SelectCodepageError

                mov     [cs:wCPbuffer],bx
                                        ; the buffer we copied

                mov     dx, ERR_SelPrepDeviceError
                                        ; in case of success, DX will be
                                        ; POP-ed

                jc      SelectCodepageError
                
                mov     BYTE [cs:bActive],1

                ;************ exit routines: we have BX=CP

SelectCodepageSuccess:

                mov     [cs:wCPselected],bx
                mov     ax, 0001h
                clc

                jmp     SelectCodepageEnd2

SelectCodepageError:
                mov     si,sp
                mov     word [ss:si],dx
                xor     ax,ax
                stc
                jmp     SelectCodepageEnd2

SelectCodepageEnd:
                pop     cx
SelectCodepageEnd2:
                pop     dx
                pop     si
                pop     di
                ret
                

;===================================================================
; PREPARE RESIDENT SUBROUTINES
;===================================================================
;
;       .       .       .       .       .       .       line that rules

; Fn:   MoveDataToBuffer
; Does: Moves font data from certain buffer to the SELECT buffer
;       SIZE and OFFSET of the data to be moved should be given
; In:   DL: Number of buffer that is to be used for the transfer (0,1,...)
;       CX: size (in bytes) to be moved
;       DS:SI-> Pointer to memory where source data resides
;       DI: offset on the table to be transferred
; Out:  Carry set on error, clear on success
;       DL must be preserved
;       SI gets updated to the new position

MoveDataToBuffer:
                push    dx
                push    bx              ; get the table entry

                shl     dx,1
                mov     bx,wBufferPtrs
                add     bx,dx
                mov     ax,[cs:bx]

                pop     bx

                push    cx              ; determine wether XMS or TPA
                mov     cx,dx
                shr     cx,1            ; undo the SHL above
                mov     dx,1
                shl     dl,cl
                test    [cs:fBuffersInXMS],dl
                pop     cx
                pop     dx
                jz      MoveDataToBufferTPA

                ;****** Move procedures:
                ; AX: table entry
                ; CX: size (bytes)
                ; DS:SI-> source data
                ; DI: offset

MoveDataToBufferXMS:

                mov     [cs:XMSMoveLen],cx

                mov     word [cs:XMSMoveSrcH],0
                mov     [cs:XMSMoveSrcO],si
                mov     [cs:XMSMoveSrcO+2],ds

                mov     [cs:XMSMoveTrgH],ax
                mov     [cs:XMSMoveTrgO],di
                mov     word [cs:XMSMoveTrgO+2],0

                add     si,cx
                push    si
                push    ds

                mov     ah,0Bh
                push    cs
                pop     ds
                mov     si,XMSMoveLen

                call    far [cs:lpXMSdriver]

                pop     ds
                pop     si

                cmp     ax,1
                je      MoveDataToBufferSuccess
                stc
                ret

MoveDataToBufferTPA:
                push    cs
                pop     es

                add     di,ax

                shr     cx,1            ; WORD granularity!
                cld
           rep  movsw

MoveDataToBufferSuccess:
                clc
                ret


; Fn:   ReadSubfont
; Does: Reads a subfont from the appropriate section of the CPI file
; In:   DS:SI->  position in the CPI file where the subfont starts
;       DL:      number of buffer to be transferred (0,1,...)
; Out:  CF set on error, clear otherwise
;       If success: SI point to the byte immediately after the whole block
;       AX,CX: trashed
;
; FORMAT OF THE SUBFONT  (offsets respect to DI)
; ---------------------
; 0  DB  Size:     values 16, 14 or 8
; 1  DB  witdth:   MUST be 8
; 2  DW  (ignored)
; 4  DW  n.chars:  MUST be 255
; 6  <data>
;

ReadSubfont:

                ;**************  check DB 8 annd DW 255
                mov     al,[ds:si+1]
                cmp     al,8
                jne     ReadSubfontError
                mov     ax,[si+4]
                cmp     ax,256
                jne     ReadSubfontError

                ;************** check the number of subfonts
                mov     al,[si]         ; get the subfont size to ax
                mov     cx,[cs:wNumSubFonts]

                cmp     al,8
                je      ComputeSizeToMove
                cmp     cx,2
                jb      ReadSubfontError

                cmp     al,14
                je      ComputeSizeToMove
                cmp     cx,3
                jb      ReadSubfontError

                cmp     al,16
                jne     ReadSubfontError
                
                ;************** add the appropriate offset

ComputeSizeToMove:
                add     si,6            ; now points to the data

                xor     di,di           ; relative offset=0
                mov     cx,2048         ; initialize to 2048 bytes (8x256)
                
                cmp     al,8
                je      ReadSubfontMoveData

                add     di,cx           ; destination now skips 8x8
                mov     cx,3584         ; set to 3584 bytes (14x256)
                cmp     al,14
                je      ReadSubfontMoveData

                cmp     al,16
                jne     ReadSubfontError
                add     di,cx           ; destination now skips 8x14
                mov     cx,4096         ; set to 4096 bytes (16x256)

                ;************** Move the data
                ; CX: number of bytes to move
                ; DI: relative offset in the file
                
ReadSubfontMoveData:
                call    MoveDataToBuffer
                ret                     ; returns with carry as appropriate

ReadSubfontError:

                stc
                ret

; Fn:   ReadCodepage
; Does: Reads a codepage from the appropriate section of the CPI file
; In:   DS:SI->  position in the CPI file where the codepage starts
;       DX:      number of buffer where to read font  (0,1,...)
; Out:  CF=1:    There was an error in file, PREPARE must fail;
;                DX: error code
;       CF=0:    Info was or was not updated, but loop has to continue
;                SI points to the byte immediately after the whole block

; FORMAT OF THE CODEPAGE (FONT) (offsets respect to DI)
; ----------------------
;  0  DW      FontHeaderSize (usually 28)
;  2  DD      Far Pointer to Next Codepage (FONT)
;  6  DW   *  Driver type signature (1=DISPLAY, 2=PRINTER)
;  8  8DB  *  Hardware type string (e.g. "EGA     ")
; 16  DW   +  CP-ID (e.g. 850)
; 18  6DB     Reserved (empty)
; 24  DD      Pointer to next FontHeader
; --- the  limit of the font header (28)
; 28  DW   *  Signature (1) (FONT)
; 30  DW   *  Number of subfonts (usually 3)
; 32  DW   *  Size of the whole subfonts block (usually 9746 bytes)
;
; (*)  to be tested

ReadCodepage:

                ;**************  check all signatures and everything
                mov     ax,[si+6]      ; it is for us
                cmp     ax,DriverSignature
                jne     ReadCodepageNext

                mov     ax,[si+28]      ; it is a FONT
                cmp     ax,1
                jne     ReadCodepageError

                push    si
                add     si,8            ; DS:SI->String in CPI file

                push    cs
                pop     es
                mov     di,sHWFontName  ; ES:DI->Our font name

                mov     cx,8
          repe  cmpsb
                pop     si
                jne     ReadCodepageNext

                mov     ax,[si+30]      ; we force it to have 3 subfonts
                cmp     ax,3
                jne     ReadCodepageError

                mov     ax,[si+32]      ; we force it to be 9746
                cmp     ax,9746
                jne     ReadCodepageError

                mov     bx,[si+16]      ; store CP number to bx

                ;**************  read the data
                add     si,34           ; 34-16=18

                call    ReadSubfont
                jc      ReadCodepageError

                call    ReadSubfont
                jc      ReadCodepageError

                call    ReadSubfont
                jc      ReadCodepageError

                mov     di, [cs:wNumHardCPs]
                add     di, dx
                shl     di, 1
                add     di, wHardCPs            ; everything ok: store cp
                mov     [cs:di], bx             ; and success

                ;**************  exit points

ReadCodepageNext:
                clc
                jmp     ReadCodepageEnd
                
ReadCodepageError:
                mov     dx,ERR_FileDamaged

ReadCodepageGotoend:
                stc

ReadCodepageEnd:
                ret

; Fn:   PrepareThisCodepage
; Does: For the codepage pointed by DS:SI, fill in all buffers that apply
; In:   DS:SI->  Where the codepage starts (see description in ReadCodepage)
; Out:  CF=0:    Everything is ok, loop on (CPs on file) must continue
;       CF=1:    There was an error in the CPI file (DX contains errorcode)

PrepareThisCodepage:

                xor     dx,dx
LoopPrepareList:
                ; see if it is on our prepare list
                mov     bx,dx
                shl     bx,1
                mov     bx,[cs:bx+wToPrepareBuf]

                cmp     bx,[ds:si+16]
                jne     LoopPrepareListBreak

                ; found! prepare it
                push    dx
                push    si
                
                call    ReadCodepage
                
                pop     si
                pop     dx
                
                jc      PrepareThisCodepageEnd

                mov     bx,dx
                shl     bx,1
                mov     word [cs:bx+wToPrepareBuf],0

LoopPrepareListBreak:
                inc     dx

                cmp     dx,[cs:wToPrepareSize]
                jb      LoopPrepareList

PrepareThisCodepageCont:
                clc
PrepareThisCodepageEnd:
                ret


; Fn:   PrepareCodepage
; Does: Prepares the codepage in the appropiate position
; In:   CX:      Size of the whole CPI file
;       DS:SI->  RAW CPI structure
; Out:  DX:      Error code, 0 if not error
;
; FORMAT OF THE CODEPAGE (FONT)
; ----------------------
;  0  DB      0ffh, "FONT   "
;  8  DB 15   (ignore)
; 23  DW      Number of CPs in file
; 25  --- (Font 1 starts here)

PrepareCodepage:
                push    ax
                push    cx
                push    bx
                push    es
                push    si
                push    di

                ;*** header of the CPI file

                push    cs              ; ES segment = CS
                pop     es

                mov     bx,cx           ; BX to hold the CPI structure size

                mov     di, sCPIsignature
                mov     cx, 8
           repe cmpsb
                jne     ErrorInSubfonts

                mov     cx, [ds:si+15]  ; 15=23-8; number of CPs in files
                add     si,17           ; si-> first font

loopFindCP:
                cmp     bx, 9780
                jb      ErrorInSubfonts

                push    bx
                push    cx
                call    PrepareThisCodepage
                pop     cx
                pop     bx

                jc      prepareEnd

                ;       next
                add     si,9780         ; 9780=distance between fonts
                sub     bx,9780

                loop    loopFindCP

                ;       check if all the requested have been prepared
                xor     dx,dx
                mov     cx,[cs:wToPrepareSize]

loop3:          mov     bx,cx
                dec     bx
                shl     bx,1
                or      dx,[cs:bx+wToPrepareBuf]
                loop    loop3

                test    dx,0FFFFh
                jz      prepareEnd

                mov     dx, ERR_DevCPNotFound
                jmp     prepareEnd

ErrorInSubfonts:
                mov     dx,ERR_FileDamaged

prepareEnd:
                pop     di
                pop     si
                pop     es
                pop     bx
                pop     cx
                pop     ax
                ret


; Fn:   GenericIOCTL
; Does: Implements the Generic IOCTL call
; In:   CL:      subfunction number
;       DS:BX->  specific parameter table
; Out:  cf  set on error. In that case:
;         AX:      error code
;
; FUNCTIONS 45h/65h: set/get iteration count  (UNSUPPORTED)
; ------------------------------------------
; 00h  DW   Iteration count
;
; FUNCTION 4Ah/6Ah: select/query codepage
; ---------------------------------------
; 00h  DW   Length of data (ignored)
; 02h  DW   codepage ID
;
; FUNCTION 4Ch: start codepage prepare
; ------------------------------------
; 00h  DW   Flags (must be 0 for DISPLAY,
;                  bit0: prepare catridge selection in PRINTER.SYS)
;                 (we shall IGNORE these flags)
; 02h  DW   Length of the rest in BYTES ( 2 + 2N ) (will be ignored)
; 04h  DW   Number N of codepages
; 06h  DW times N  Codepages to prepare
;
; FUNCTION 4Dh: end codepage prepare  (IGNORE PACKET)
; ----------------------------------
;
; FUNCTION 6Bh: query prepared codepages list
; -------------------------------------------
; 00h  DW   total length of data
; 02h  DW   number of hardware CPs (N)
; 04h  DW times N  hardware CPs
; xxh  DW   number of prepared CPs (M)
; xxh  DW times M  prepared CPs
;
; FUNCTIONS 5Fh/7Fh: set/get Display Information Packet
; -----------------------------------------------------
; 00h  DB   Video parameters packet
; 01h  DB   Reserved (=0)
; 02h  DW   Packet length (=14)
; 04h  DW   Flags (0: intense; 1: blink)
; 06h  DB   Mode  (1: text, 2: graphics)
; 07h  DB   Reserved (=0)
; 08h  DW   Colours  (0 if mono)
; 0Ah  DW   Width (APA width in pixels)
; 0Ch  DW   Length (APA length in pixels)
; 0Eh  DW   Width in characters (columns)
; 10h  DW   Lehgth in characters (rows)
;

GenericIoctl:

                ;****** Select codepage
                cmp     cl, 04Ah
                jne     GI_no04Ah

                push    bx
                mov     bx, [ds:bx+2]
                call    SelectCodepage
                pop     bx
                test    ax, 0ffffh
                jnz     GI_success
                mov     ax, dx
                jmp     GI_error

GI_no04Ah:
                ;****** Query codepage
                cmp     cl, 06Ah
                jne     GI_no06Ah

                mov     ax,[cs:wCPselected]
                mov     [ds:bx+2],ax
                cmp     ax,-1
                jne     GI_success

                mov     ax, ERR_CPNotSelected
                jmp     GI_error

GI_no06Ah:
                ;****** Start codepage prepare
                cmp     cl, 04Ch
                jne     GI_no04Ch

                mov     cx, [ds:bx+2]
                mov     si, bx
                add     si, 4

                push    cs
                pop     es
                mov     di, wToPrepareSize

                cld
           rep  movsb

                mov     byte [cs:fInPrepare], 1
                jmp     GI_success

GI_no04Ch:
                ;****** End codepage prepare
                cmp     cl, 04Dh
                jne     GI_no04Dh

                test    byte [cs:fInPrepare],0FFh
                jnz     endprepOk

                mov     ax,ERR_NoPrepareStart
                jmp     GI_error
endprepOk:
                mov     byte [cs:fInPrepare], 0

GI_success:
                xor     ax, ax
                clc
                ret

GI_no04Dh:
                ;****** Query codepage list
                cmp     cl, 06Bh
                jne     GI_no06Bh

                mov     ax, [cs:wNumHardCPs]    ; length of data
                add     ax, [cs:wNumSoftCPs]
                shl     ax, 1                   ; was in words
                add     ax, 4
                mov     [ds:bx], ax

                mov     cx, [cs:wNumHardCPs]    ; number of HW CPs
                mov     [ds:bx+2], cx

                mov     di, bx                  ; hardware CPs
                add     di, 4
                push    ds
                pop     es
                push    cs
                pop     ds
                mov     si, wHardCPs
                cld
           rep  movsw

                mov     ax, [cs:wNumSoftCPs]    ; number of SW CPs
                mov     [es:di], ax
                add     di, 2

                mov     si, wHardCPs            ; software CPs
                add     si, [cs:wNumHardCPs]
                add     si, [cs:wNumHardCPs]
                mov     cx, [cs:wNumSoftCPs]
           rep  movsw

                cmp     word [cs:wCPselected],-1
                jne     GI_success

                mov     ax, ERR_CPNotSelected
                jmp     GI_error

GI_no06Bh:
                ;****** Unknown function

                test    cl, 80h
                jnz     GI_success
                
                mov     ax, ERR_UnknownFunction

GI_error:
                stc
                ret


;===================================================================
; HARDWARE DEPENDANT SELECT ROUTINES
;===================================================================
;
;       .       .       .       .       .       .       line that rules

%ifdef          DISPLAY
%include        "selectd.asm"
%endif

%ifdef          PRINTER
%include        "selectp.asm"
%endif




;===================================================================
; DISPLAY DATA SEGMENT
;===================================================================
;
;               .       .       .       .       .       line that rules

bActive         DB      0               ; SW codepage selected?
wCPselected     DW      -1              ; Selected codepage
wCPbuffer       DW      0               ; CP in buffer bFont8x8
whtCPselected   DW      0               ; position in the hardware table of
                                        ; current hardware codepage
wTableSize	DW	0		; Total RAW table size in WORDS

pRefreshHWcp    DW      0               ; Hardware codepage select procedure
pRefreshSWcp    DW      0               ; Software codepage select procedure

fInPrepare      DB      0               ; Preparation in course?
wToPrepareSize  DW      0               ; Number of cps to be prepared
wToPrepareBuf   times   12 DW  0        ; codepages to be prepared

sCPIsignature   DB      0ffh,"FONT   "  ; signature of a CPI file
sHWFontName     DB      "        "      ; space for the hardware name to be
                                        ; searched in the CPI file

fIsXMS          DB      0               ; is there an XMS driver installed?
lpXMSdriver     DD      0               ; entry point to current XMS driver
                                        ; (0 if none installed)

                                        ; XMS Move structure
XMSMoveLen      DD      0               ; * length in bytes
XMSMoveSrcH     DW      0               ; * source handle (0 for real pointer)
XMSMoveSrcO     DD      0               ; * source offset (or real pointer)
XMSMoveTrgH     DW      0               ; * target handle (0 for real pointer)
XMSMoveTrgO     DD      0               ; * target offset (or real pointer)

wNumSoftCPs     DW      0               ; number of software codepages
wNumSubFonts    DW      0               ; number of subfonts (m)
wNumHardCPs     DW      1               ; number of hardware codepages
wHardCPs        DW      0,0,0,0,0,0,0   ; hardware CP list, followed by
                                        ; the software codepages

fBuffersInXMS   DB      0               ; flags: bit i = buffer i in XMS
wBufferPtrs     DW      0,0,0,0,0,0,0,0 ; buffer pointers:
                                        ;   if in XMS: handle to EMB
                                        ;   if not in XMS: offset (wrt CS)

bFont8x8        times   2048 DB 0       ; space for the 8x8 font
bFont8x14       times   3584 DB 0       ; space for the 8x14 font
bFont8x16       times   4096 DB 0       ; space for the 8x16 font


;===================================================================
; DISPLAY DATA BUFFERS
;===================================================================
;               .       .       .       .       .       line that rules
;
; Prepared Codepage Tables (array of these structures)
; (maximum= 5 of the (8,14,16) size
;

                times 9728 db 0
                times 9728 db 0
                times 9728 db 0
                times 9728 db 0
                times 9728 db 0



;===================================================================
; NON-RESIDENT VARIABLES
;===================================================================
;

;               MEMORY and HEAP management

pMemTop:        DW      bLastByte       ; top of memory
pHeapBase:      DW      bFont8x8        ; base of the heap, starts on 8x8

;               OTHERS

wMinFontSize:   DW      0               ; minimum font size
                                        ; 1=8x8  2=8x8,14  3=8x8,14,16
bMaxHWcpNumber: DB      0               ; maximum number of hardware CPs
                                        ; admissible, 0 if unknown


;===================================================================
; NON-RESIDENT HARDWARE DEPENDANT ROUTINES AND TABLE
;===================================================================
;

%ifdef          DISPLAY
%include        "HWInitD.asm"
%endif

%ifdef          PRINTER
%include        "HWInitP.asm"
%endif



;===================================================================
; MAIN FOR THE .COM VERSION
;===================================================================
;
;               .       .       .       .       .       line that rules


start:
Install:
                push    cs
                call    DoInstall       ; call DoInstall
                jc      Done            ; Carry? then we should exit
                mov     dx,[cs:pHeapBase]
                int     27H             ; TSR  for .COM files
Done:           int     20H             ; Exit for .COM files



;===================================================================
; INSTALLATION RUNTIME FUNCTIONS
;===================================================================
;
;               .       .       .       .       .       line that rules

; Fn:   IsBlank
; In:   AL: character
; Out:  CarryFlag set if blank, clear if not

IsBlank:
                cmp     al,32
                jne     IsBlank_a
IsBlankExit1:   stc
                ret
IsBlank_a:
                cmp     al,10
                je      IsBlankExit1
                cmp     al,9
                je      IsBlankExit1
                clc
                ret

; Fn:   OutStrDX
; In:   DX: near pointer to string to be displayed
; Out:  -

OutStrDX:       mov     ah,9
                int     21H
		stc			; Error
                ret			; From DoInstall



; Fn:   DoInstall
; In:   -
; Out:  CF on error (do not stay resident)


DoInstall:
                ;****** show copyright and version

                mov     dx,copyVer
                call    OutStrDX

                ;****** check if already loaded
%ifdef DISPLAY
                mov     ax,0ad00H
                int     2fH
                cmp     al,-1
                jne     TestDRK

                mov     dx,errAlready
                jmp     OutStrDX

                ;****** Some versions of DR-KEYB are a no-no
TestDRK:
                mov     ax,0ad80h
                xor     bx,bx
                mov     cx,bx
                int     02fh
                cmp     ah,0ffh         ; KEYB installed?
                jne     ScanCommandline
                test    bx,0ffffh       ; MS-KEYB?
                jnz     ScanCommandline
                test    cx,0ffffh       ; FD-KEYB?
                jz      ScanCommandline
                cmp     ch,7
                jae     ScanCommandline ; check DR-KEYB version
                mov     dx,errNoDRDOS
                jmp     OutStrDX
%endif

                ;****** SCAN COMMANDLINE, in STAGES
ScanCommandline:
                cld 
                cli

                push    cs
                pop     es
                push    cs
                pop     ds


                ; 1.- Find the string and capitalize it

                mov     cx, [cs:CommandLine_Offset]
                mov     si, CommandLine_Offset+1
loop0:          mov     al, [cs:si]
                cmp     al, 13
                je      endUpper
                cmp     al, 'a'
                jb      cont0
                cmp     al, 'z'
                ja      cont0
                sub     al, 'a'-'A'
                mov     [cs:si], al
cont0:          inc     si
                loop    loop0
endUpper:

                ; 2.- Remove starting spaces
    
;                mov     cx, [cs:CommandLine_Offset]
;                        (AITOR) we trust that the commandline will end in #13
                mov     si, CommandLine_Offset+1
loop1:          lodsb
                cmp     al, 13
                jne     skp1
                mov     dx, SES_ParamRequired
                jmp     SyntaxError
skp1:           call    IsBlank
                jc      loop1

                ; 3.- Save device name
                ;     Also block illegal chars (ASCII compatibility
                ;     assumed)

                mov     di, DevName
                mov     cx, 8
loop2:          mov     al, [es:si]
                cmp     al, '='
                je      EndDevName
                cmp     al, ':'
                je      EndDevName
                cmp     al, 13
                jne     skp2
                mov     dx, SES_UnexpectedEOL
                jmp     SyntaxError
skp2:           cmp     al, '/'
                je      illegalChar
                cmp     al, '\'         ; character '\
                je      illegalChar
                cmp     al, 34          ; illegal char: double quote
                je      illegalChar
                cmp     al, '*'
                je      illegalChar
                cmp     al, '|'
                je      illegalChar
                cmp     al, '<'         ; illegal chars: '<'..'?'
                jb      cont1
                cmp     al, '?'
                ja      cont1
                cmp     al, '='         ; and =
                je      cont1              
                jmp     illegalChar
cont1:          movsb
                loop    loop2
                mov     dx, SES_NameTooLong
                jmp     SyntaxError

illegalChar:    mov     dx, SES_IllegalChar
                jmp     SyntaxError

EndDevName:
                cmp     al, ':'
                jne     cont2
                inc     si

cont2:          inc     si              ; it was pointing to =
                mov     al, '('
                mov     di, si
                scasb
                je      skp3
                mov     dx, SES_OpenBrExpected
                jmp     SyntaxError
       

                ; 4.- Get hardware name and initialize it

skp3:           inc     si
                mov     di, HardwareTables

loop3b:
                push    si              ; si->begining of the name
                mov     cx, 8           ; length
           repe cmpsb
                je      HwTypeFound8c   ; if =, CX=0 => found (check ,)
                mov     al, [ds:si-1]
                mov     dl, [es:di-1]

                add     di,cx           ; di->CP-HardwareName
                
                cmp     al, ','
                jne     skp3b           ; if commandline<>, error

                test    dl, 0ffh
                jz      HwTypeFound     ; if sourcename<>0 error

skp3b:
                add     di,12           ; skip the table
                mov     al, [es:di]
                pop     si              ; recover si->beginig of the name
                test    al, 0ffh        ; 0=end of the table
                jnz     loop3b

                mov     dx, SES_WrongHwName
                jmp     SyntaxError     ; hardware NOT supported

HwTypeFound8c:  mov     al, [ds:si]     ; if name is 8 char long, we still
                cmp     al, ','         ; need to check the comma
                jne     needC
                inc     si
                
HwTypeFound:
                push    si              ; save SI (pos in string)
                mov     si,di           ; DI points to the begining of
                                        ; the hardware name

                mov     di,sHWFontName
                mov     cx,8
           rep  movsb
                                        ; initialize it!
                mov     ax,[cs:si+2]
                call    [cs:si]
                pop     si              ; recover si
                jnc     HWInitOk        ; print error string and exit
                call    SyntaxError2

HWInitOk:
                pop     di              ; discard 1 element from stack
                                        ; (was: begining of HwName in params)
                jmp     GetHWCodepages  ; goto next stage

needC:          ; error if comma not found
                mov     dx, SES_CommaExpected
                jmp     SyntaxError

                ; 5.- HWCodepage

GetHWCodepages:
                cmp     byte [cs:si],'('
                jne     HW1codepage
                inc     si
                mov     di,wHardCPs
                mov     ch,5
                call    ReadSW
                xor     ch,ch
                mov     [cs:wNumHardCPs],cx
                jmp     CommaBeforeFonts
HW1codepage:
                call    ReadNumber
                mov     [cs:wHardCPs], ax

CommaBeforeFonts:
                mov     di, si
                mov     al,','
                scasb
                jne     needC           ; , expected
                inc     si

                ; check that it does not exceed the maximum number of hw fonts
                test     BYTE [cs:bMaxHWcpNumber],0ffh
                jz       ArraySize
                mov      cx,[cs:wNumHardCPs]
                cmp      cx,[cs:bMaxHWcpNumber]
                jna      ArraySize
                mov      dx, SES_TooManyHWPools
                jmp      SyntaxError

                ; 6.- ArraySize

ArraySize:
%ifdef          DISPLAY
                cmp     byte [cs:si],'('
                jne     NoSubfonts      ; (fonts,subfonts) specified
                inc     si
                mov     di,wNumSoftCPs
                mov     ch,2
                call    ReadSW
                mov     ax,[cs:wNumSoftCPs]
                jmp     CheckFontNumber
NoSubfonts:
%endif
                call    ReadNumber      ; number of fonts only

CheckFontNumber:
                cmp     ax, 8           ; maximum: 5
                jna     numberOk
                mov     dx, SES_TooManyPools
                jmp     SyntaxError

numberOk:
                test    al,0ffh         ; minimum: 1
                jnz     jmp4b
                inc     al
jmp4b:          mov     [cs:wNumSoftCPs], ax
                                        ; number of subfonts ok?
                mov     ax,[cs:wMinFontSize]
                cmp     ax,[cs:wNumSubFonts]
                jbe     ClosingBracket
                mov     [cs:wNumSubFonts],ax

                ; 7.- No more arguments

ClosingBracket:
                mov     di, si
                mov     al,')'
                scasb
                je      jmp5
                mov     dx, SES_CloseBrExpected
                jmp     SyntaxError
jmp5:           inc     si

loop4b:         lodsb
                call    IsBlank
                jc      loop4b
                cmp     al,13
                je      jmp6
                mov     dx, SES_WrongNumberPars
                jmp     SyntaxError     ; wrong # of params specified

jmp6:           sti                     ; success

                ;****** END SCAN COMMANDLINE (everything OK)

                ;****** Compute the size of the table (from subfonts)

                mov     ax,[cs:wNumSubFonts]
                cmp     ax,1
                ja      Subfonts2
                mov     WORD [wTableSize],128*8
                jmp     SetVectors
Subfonts2:      cmp     ax,2
                ja      Subfonts3
                mov     WORD [wTableSize],128*(8+14)
                jmp     SetVectors
Subfonts3:      mov     WORD [wTableSize],128*(8+14+16)

                ;****** find if there are XMS drivers

                mov     ax,4300h
                int     2Fh

                cmp     al,80h
                jne     doneXMS

                mov     BYTE [cs:fIsXMS],1

                mov     ax, 4310h       ; get the driver entry point
                int     2Fh

                mov     [cs:lpXMSdriver],bx
                mov     [cs:lpXMSdriver+2],es

doneXMS:
                ;****** Allocate the memory for the buffers

                mov     ax,[wTableSize]         ; get size in BYTES
                shl     ax,1

                call    mAlloc                  ; SELECT buffer

                mov     si,wBufferPtrs

                xor     cx,cx                   ; CX: global counter
                xor     bx,bx                   ; BH: allocated in XMS
                                                ; BL: allocated in conventional

loop5:
                call    XMSAlloc                ; loop: allocate PREP. buffers
                jc      TryLocalHeap

                inc     bh
                push    ax
                mov     al,1
                shl     al,cl
                or      [cs:fBuffersInXMS],al
                pop     ax
                jmp     loop5next

TryLocalHeap:
                call    mAlloc                  ; second try: TPA memory
                inc     bl

                test    dx,dx                   ; allocated?
                jnz     loop5next

                mov     dx, SES_NoAllocatedBufs
                jmp     SyntaxError

loop5next:
                mov     [cs:si],dx              ; save for the first buffer
                add     si,2

                inc     cx
                cmp     cx,[cs:wNumSoftCPs]
                jb      loop5                   ; end of loop

                mov     dx,sMemAllocatedBuffers
                call    OutStrDX
                xor     ah,ah
                mov     al,bl
                push    bx
                call    WriteNumber
                pop     bx
                mov     dx,sInTPA
                call    OutStrDX
                xor     ah,ah
                mov     al,bh
                call    WriteNumber
                mov     dx,sInXMS
                call    OutStrDX
                mov     dx,ReturnString
                call    OutStrDX

                ;****** set our interrupt vectors (DISPLAY ONLY)
SetVectors:

%ifdef          DISPLAY

                mov     ax,352fH        ; Get vector 2f
                int     21H
                mov     [dOld2f],bx
                mov     [dOld2f+2],es

                mov     dx,New2f
                mov     ax,252fH        ; Set vector 2f
                int     21H

                mov     ax,3510H        ; Get vector 10
                int     21H
                mov     [dOld10],bx
                mov     [dOld10+2],es

                mov     dx,New10
                mov     ax,2510H        ; Set vector 10
                int     21H
%endif

                ;****** Free environtment space

EndInstall:
                mov     ax, [cs:02ch]
                mov     es, ax
                mov     ah, 049h
                int     21h

                clc
                retf

; Fn:   WriteNumber
; In:   AX: number of at most 3 cyphers to be written
; Out:  -
; Note: SyntaxErrorStr space is reused (as it is no longer used when
;       this function is called)
;       I know this is not the most optimal code in the world...

WriteNumber:    mov     di,copyVer           ; reuse the space
                mov     bx,100
                push    cs
                pop     es
                call    DWriteCypher
div10:          mov     al,ah
                xor     ah,ah
                mov     bx,10
                call    DWriteCypher
                mov     al,ah
                call    WriteCypher
                mov     BYTE [es:di],'$'
                mov     dx, copyVer
                jmp     OutStrDX              ; write the str and exit

DWriteCypher:   div     bl

WriteCypher:    add     al,'0'
                mov     [es:di],al
                inc     di
retWC:          ret


; Fn:   SyntaxError
; In:   DX: error string to be displayed
; Out:  -

SyntaxError:    push    dx                 ; save address of string to output
                mov     dx, SyntaxErrorStr
                call    OutStrDX

                mov     ax, si
                sub     ax, CommandLine_Offset
                call    WriteNumber

                pop     dx
SyntaxError2:
                call    OutStrDX

                mov     dx, ReturnString
                call    OutStrDX

                sti
                stc
                jmp     Done

; Fn:   ReadNumber
; In:   ES:SI -> a string number of at most 5 cyphers
; Out:  AX the number read
; Note: it stops whenever it finds the first non-number character or
;       whenever 5 characters are read
;       I know this is not the most optimal code in the world...


ReadNumber:     xor     ax,ax
                xor     bx,bx
                mov     cx,5
loopA:          cmp     BYTE [es:si],'0'
                jb      EndReadNumber
                cmp     BYTE [es:si],'9'
                ja      EndReadNumber
                mov     dx, 10             ; DX annihilated by MUL!
                mul     dx
                mov     bl, [es:si]
                add     ax, bx
                sub     ax, '0'
                inc     si
                loop    loopA
EndReadNumber:  ret



; Fn:   ReadSW
; In:   ES:SI -> list of the form [number,] ... )
;       ES:DI -> array of WORD to store the list
;       CH maximum admissible length
; Out:  CL lenght of the list
; Note: it stops whenever it finds the )
;       on error condition (illegal char, list too long) it aborts
;       automatically


ReadSW:         xor     cl, cl
NextItemListSW: push    cx
                call    ReadNumber
                pop     cx
                inc     cl
                stosw
                lodsb
                cmp     al, ','
                jne     NotCommaSW
                cmp     cl, ch
                jb      NextItemListSW
                mov     dx, SES_ListTooLong
                jmp     SyntaxError
NotCommaSW:     cmp     al, ')'
                je      ReadSWEnd
                mov     dx, SES_IllegalChar
                jmp     SyntaxError
ReadSWEnd:      ret


; Fn:   mAlloc
; In:   AX: number of bytes to allocate
; Out:  DX: near ptr (wrt to CS) where memory was allocated
;           0 if it couldn't be allocated
; Does: Reserves memory from the local DISPLAY heap

mAlloc:         mov     dx,[cs:pHeapBase]
                push    dx
                add     dx,ax
                cmp     dx,[cs:pMemTop]
                jbe     mAllocOk

                pop     dx              ; failure: not enough memory
                xor     dx,dx
                ret

mAllocOk:       mov     [cs:pHeapBase],dx
                pop     dx
                ret

; Fn:   XMSAlloc
; In:   AX: number of bytes to allocate
; Out:  FCarry set on error
;       DX: handle to EMB in XMS
; Does: Tries to allocate CX bytes in an EMB in extended memory

XMSAlloc:
                test    byte [cs:fIsXMS],0FFh
                jnz     XMSAllocOk
                stc
                ret
XMSAllocOk:
                push    ax
                
                push    cx
                add     ax,1023         ; ax: size in KBs
                mov     cx,10
                shr     ax,cl
                pop     cx

                mov     dx,ax
                mov     ah,9
                push    bx
                push    cx
                call    far [cs:lpXMSdriver]
                pop     cx
                pop     bx

                xor     al,1            ; driver returns 1 on success
                rcr     ax,1

                pop     ax
                ret

;===================================================================
; STRINGS, ARRAYS and STRUCTURES
;
;               .       .       .       .       .       line that rules


; Copyright message
%ifdef           DISPLAY
copyVer          DB     "FreeDOS DISPLAY ver. 0.12", 0dH, 0aH, "$"
%endif
%ifdef           PRINTER
copyVer          DB     "FreeDOS PRINTER ver. 0.12", 0dH, 0aH, "$"
%endif
ReturnString     DB     0dH, 0aH, "$"

;               LOCALISED Strings

%include        "strings.en"

bLastByte:

                END
                
