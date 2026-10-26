;
; This file is part of Nameplate.
; Copyright (C) 2024 BunnyBox Productions
;
; Nameplate is free software: you can redistribute it and/or modify it under the terms of the GNU General Public License as
; published by the Free Software Foundation, either version 3 of the License, or (at your option) any later version.
;
; Nameplate is distributed in the hope that it will be useful, but WITHOUT ANY WARRANTY; without even the implied warranty
; of MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the GNU General Public License for more details.
;
; You should have received a copy of the GNU General Public License along with Nameplate.
; If not, see <https://www.gnu.org/licenses/>.
;

BITS 32

;-0x37 (not patched: the point the popup is drawn at, in [esp+0x14..0x1c])
; 8b 08 89 4c 24 14 8b 50 04 89 54 24 18 8b 40 08 8d 4c 24 10 89 44 24 1c

; 0x10040D24
LEA  ECX, [ESP + 0x20]                                ; W THEN H (d9 5c 24 20             fstp   DWORD PTR [esp+0x20])
LEA  EDX, [ESP + 0x08]                                ; param 3  (d8 4c 24 08             fmul   DWORD PTR [esp+0x8])
MOV  EAX, 0x12345678                                  ; patch with C func addr, offset 0x09
CALL EAX                                              ; fastcall
MOV  ECX, [0x12345678]                                ; patch with 0x3E, ECX must preserve this value, offset 0x11
MOV  EDX, ECX                                         ; EDX is safe to be trashed
MOV  ESI, ECX                                         ; ESI final result must be preserved
AND  EDX, 0xFFFFFF
CMP  EDX, 0x808080
JNZ  .POPUP
MOV  EAX, [EDI + 0x194]                               ; EAX is safe to be trashed
AND  ESI, 0xFF000000
OR   ESI, EAX

.POPUP:                                               ; offset 0x35: "JMP .DONE" (eb 41) here when not hooked
PUSH ECX                                              ; the colour the client sets, kept
LEA  EAX, [ESP + 0x0C]                                ; the size factor, [esp+0x08] before the push
PUSH EAX
LEA  EAX, [ESP + 0x28]                                ; W then H, [esp+0x20]
PUSH EAX
LEA  EAX, [ESP + 0x20]                                ; the point, [esp+0x14]
PUSH EAX
MOV  ECX, EDI                                         ; the popup's object
MOV  EDX, ESI                                         ; its colour
MOV  EAX, 0x12345678                                  ; patch with OnDamagePopup, offset 0x4A
CALL EAX                                              ; fastcall, pops its three stack arguments
POP  ECX
TEST AL, AL
JZ   0xAE - 0x78 + .DONE                              ; claimed: to the function's end (5f 5e 83 c4 40 c3), offset 0x53
JMP  .DONE

; pad
times (0x10040D9C-0x10040D24) - ($-$$) db 0x90

.DONE:
; 0x10040D9C
