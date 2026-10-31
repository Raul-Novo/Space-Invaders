; Space Invaders mini - NASM x86-64 / UEFI PE32+
; One source file. No C, no libc, no ELF, no OS, no external resources.
;
; Build (Windows 11, PowerShell):
;   nasm -f win64 space_invaders_uefi.asm -o game.obj
;   lld-link /subsystem:efi_application /entry:efi_main /machine:x64 /nodefaultlib /out:BOOTX64.EFI game.obj
;  Run (QEMU)
;   qemu-system-x86_64 `
;       -machine q35 `
;       -m 512M `
;       -vga std `
;       -drive "if=pflash,format=raw,unit=0,readonly=on,file=$code" `
;       -drive "if=pflash,format=raw,unit=1,file=$vars" `
;       -drive "if=ide,format=raw,file=fat:rw:$esp" `
;       -net none
;
; UEFI's x64 calling convention is Microsoft x64 (32-byte shadow space).
; This code is intended for QEMU + OVMF, with a 640x480+ 32-bit GOP mode.

bits 64
default rel

global efi_main

%define C_BG       0x0009101E
%define C_FRAME    0x00304A6A
%define C_DIM      0x00677B99
%define C_WHITE    0x00D7E8FF
%define C_BLUE     0x003B81F6
%define C_CYAN     0x009BD1FF
%define C_PINK     0x00FD79B8
%define C_GREEN    0x0073EDB0
%define C_RED      0x00F26976
%define C_DARK     0x00142135

%macro RECT 5
    mov r10d, %1              ; X
    mov r11d, %2              ; Y
    mov r8d,  %3              ; width
    mov r9d,  %4              ; height
    mov eax,  %5              ; RGB = 0x00RRGGBB
    call draw_rect
%endmacro

%macro TEXT 4
    lea rsi, [rel %1]         ; ASCII NUL-terminated
    mov r13d, %2              ; X
    mov r12d, %3              ; Y
    mov r15d, %4              ; RGB
    call draw_text
%endmacro

section .text

efi_main:
    ; EFI calls us with RCX = ImageHandle, RDX = SystemTable.
    ; Save nonvolatile Windows x64 registers; reserve shadow space.
    push rbx
    push rsi
    push rdi
    push r12
    push r13
    push r14
    push r15
    sub rsp, 32               ; RSP 16-byte aligned before calls

    mov rax, [rdx + 48]       ; EFI_SYSTEM_TABLE.ConIn
    mov [conin], rax
    mov rax, [rdx + 64]       ; EFI_SYSTEM_TABLE.ConOut
    mov [conout], rax
    mov rax, [rdx + 96]       ; EFI_SYSTEM_TABLE.BootServices
    mov [boot_services], rax

    ; BootServices->LocateProtocol(&GOP_GUID, NULL, &gop)
    lea rcx, [rel gop_guid]
    xor edx, edx
    lea r8, [rel gop]
    call qword [rax + 320]    ; EFI_BOOT_SERVICES.LocateProtocol
    test rax, rax
    jnz .no_gop

    mov r10, [gop]
    mov r10, [r10 + 24]       ; GOP->Mode
    mov r11, [r10 + 8]        ; GOP->Mode->Info

    mov eax, [r11 + 4]        ; HorizontalResolution
    cmp eax, 640
    jb .bad_mode
    sub eax, 640
    shr eax, 1
    mov [origin_x], eax

    mov eax, [r11 + 8]        ; VerticalResolution
    cmp eax, 480
    jb .bad_mode
    sub eax, 480
    shr eax, 1
    mov [origin_y], eax

    mov eax, [r11 + 12]       ; PixelFormat: 0 = RGBX, 1 = BGRX
    cmp eax, 1
    ja .bad_mode             ; no support for bitmasks/BltOnly here
    mov [pixel_format], eax

    mov eax, [r11 + 32]       ; PixelsPerScanLine (may be > width)
    shl rax, 2               ; byte pitch
    mov [pitch], rax
    mov rax, [r10 + 24]       ; GOP->Mode->FrameBufferBase
    mov [framebuffer], rax

    ; Clear the FULL physical visible framebuffer once.
    mov rdi, rax
    mov rcx, [r10 + 32]      ; GOP->Mode->FrameBufferSize
    shr rcx, 2
    xor eax, eax
    rep stosd

    ; Center the 640x480 logical playfield in the physical framebuffer.
    mov eax, [origin_y]
    imul rax, qword [pitch]
    add qword [framebuffer], rax
    mov eax, [origin_x]
    shl rax, 2
    add qword [framebuffer], rax

    ; Disable firmware watchdog for a long-running interactive UEFI app.
    mov rax, [boot_services]
    xor ecx, ecx
    xor edx, edx
    xor r8d, r8d
    xor r9d, r9d
    call qword [rax + 256]   ; SetWatchdogTimer(0, 0, 0, NULL)

    call reset_game

.main_loop:
    call poll_keyboard
    cmp byte [quit], 0
    jne .done
    cmp byte [game_state], 0
    jne .skip_update
    call update_game
.skip_update:
    call render_game
    mov rcx, 16666           ; 16.666ms target frame delay (~60 FPS)
    mov rax, [boot_services]
    call qword [rax + 248]   ; BootServices->Stall(usec)
    jmp .main_loop

.no_gop:
    lea rdx, [rel error_gop]
    jmp .print_error
.bad_mode:
    lea rdx, [rel error_mode]
.print_error:
    mov rcx, [conout]
    call qword [rcx + 8]     ; ConOut->OutputString(UTF16)
.done:
    xor eax, eax            ; EFI_SUCCESS
    add rsp, 32
    pop r15
    pop r14
    pop r13
    pop r12
    pop rdi
    pop rsi
    pop rbx
    ret

; draw_rect: X=r10d, Y=r11d, W=r8d, H=r9d, RGB=eax.
; Clobbers volatile registers only. Rectangle must fit in 640x480.
draw_rect:
    push rdi
    mov edx, eax
    mov eax, [pixel_format]
    test eax, eax
    mov eax, edx
    jnz .native_bgr
    bswap eax
    shr eax, 8               ; RGBX pixel mode needs 0x00BBGGRR
.native_bgr:
    mov rdi, [framebuffer]
    mov edx, eax             ; color temporarily in EDX
    mov eax, r11d
    imul rax, qword [pitch]
    add rdi, rax
    mov eax, r10d
    shl rax, 2
    add rdi, rax
    mov eax, edx             ; restore color for REP STOSD
    mov r10, rdi             ; row base
.row:
    mov rdi, r10
    mov ecx, r8d
    rep stosd
    add r10, qword [pitch]
    dec r9d
    jnz .row
    pop rdi
    ret

; Draw ASCII text using built-in 5x7 bitmaps, each pixel scaled to 2x2.
; RSI=text, R13D=x, R12D=y, R15D=RGB.
draw_text:
.next_char:
    movzx eax, byte [rsi]
    test eax, eax
    jz .end
    cmp al, '0'
    jb .blank
    cmp al, '9'
    jbe .number
    cmp al, 'A'
    jb .blank
    cmp al, 'Z'
    ja .blank
    sub eax, 'A' - 10
    jmp .have_index
.number:
    sub eax, '0'
.have_index:
    imul eax, eax, 7
    lea rdi, [rel font]
    add rdi, rax
    xor ebx, ebx             ; row = 0..6
.glyph_row:
    xor r14d, r14d           ; col = 0..4
.glyph_col:
    movzx ecx, byte [rdi + rbx]
    mov edx, 4
    sub edx, r14d
    bt ecx, edx
    jnc .no_pixel
    mov r10d, r14d
    shl r10d, 1
    add r10d, r13d
    mov r11d, ebx
    shl r11d, 1
    add r11d, r12d
    mov r8d, 2
    mov r9d, 2
    mov eax, r15d
    call draw_rect
.no_pixel:
    inc r14d
    cmp r14d, 5
    jb .glyph_col
    inc ebx
    cmp ebx, 7
    jb .glyph_row
.blank:
    add r13d, 12
    inc rsi
    jmp .next_char
.end:
    ret

reset_game:
    mov dword [player_x], 298
    mov dword [enemy_x], 88
    mov dword [enemy_y], 85
    mov dword [enemy_dir], 1
    mov dword [alive_mask], 0x3FFFF  ; 18 aliens alive
    mov dword [score], 0
    mov dword [lives], 3
    mov dword [frame_counter], 0
    mov byte [bullet_active], 0
    mov byte [eshot_active], 0
    mov byte [game_state], 0          ; 0 playing, 1 won, 2 lost
    ret

poll_keyboard:
    sub rsp, 40              ; align stack + 32-byte shadow space for EFI calls
    mov ebx, 24              ; read up to 24 events per frame
.again:
    mov rcx, [conin]
    lea rdx, [rel key_data]
    call qword [rcx + 8]     ; ReadKeyStroke(this, &key)
    test rax, rax
    jnz .end                 ; EFI_NOT_READY (or other status)
    movzx eax, word [key_data]  ; ScanCode
    cmp eax, 0x17           ; SCAN_ESC
    jne .not_escape
    mov byte [quit], 1
    jmp .end
.not_escape:
    movzx edx, word [key_data + 2] ; UnicodeChar
    cmp byte [game_state], 0
    je .playing
    cmp edx, 'r'
    je .restart
    cmp edx, 'R'
    jne .next
.restart:
    call reset_game
    jmp .next
.playing:
    cmp eax, 4              ; SCAN_LEFT
    je .left
    cmp edx, 'a'
    je .left
    cmp edx, 'A'
    je .left
    cmp eax, 3              ; SCAN_RIGHT
    je .right
    cmp edx, 'd'
    je .right
    cmp edx, 'D'
    je .right
    cmp edx, ' '
    jne .next
    cmp byte [bullet_active], 0
    jne .next
    mov eax, [player_x]
    add eax, 20
    mov [bullet_x], eax
    mov dword [bullet_y], 406
    mov byte [bullet_active], 1
    jmp .next
.left:
    mov eax, [player_x]
    sub eax, 18
    cmp eax, 8
    jge .save_player
    mov eax, 8
    jmp .save_player
.right:
    mov eax, [player_x]
    add eax, 18
    cmp eax, 588
    jle .save_player
    mov eax, 588
.save_player:
    mov [player_x], eax
.next:
    dec ebx
    jnz .again
.end:
    add rsp, 40
    ret

update_game:
    inc dword [frame_counter]

    ; Enemy formation advances horizontally every 7 frames.
    mov eax, [frame_counter]
    xor edx, edx
    mov ecx, 7
    div ecx
    test edx, edx
    jne .bullet_step
    mov eax, [enemy_dir]
    imul eax, eax, 5
    add [enemy_x], eax
    cmp dword [enemy_x], 30
    jle .bounce_right
    cmp dword [enemy_x], 242
    jge .bounce_left
    jmp .bullet_step
.bounce_right:
    mov dword [enemy_dir], 1
    jmp .drop
.bounce_left:
    mov dword [enemy_dir], -1
.drop:
    add dword [enemy_y], 15
    cmp dword [enemy_y], 284
    jl .bullet_step
    mov byte [game_state], 2
    ret

.bullet_step:
    cmp byte [bullet_active], 0
    je .enemy_projectile
    sub dword [bullet_y], 10
    cmp dword [bullet_y], 50
    jge .check_hits
    mov byte [bullet_active], 0
    jmp .enemy_projectile
.check_hits:
    xor esi, esi             ; enemy index 0..17
    mov ebx, 1               ; corresponding alive bit
.hit_loop:
    test dword [alive_mask], ebx
    jz .hit_next
    mov eax, esi
    xor edx, edx
    mov ecx, 6
    div ecx                  ; eax=row, edx=column
    mov r10d, edx
    imul r10d, r10d, 70
    add r10d, [enemy_x]
    mov r11d, eax
    imul r11d, r11d, 48
    add r11d, [enemy_y]
    ; Bullet rect [x,x+4) [y,y+12) vs alien [x,x+32) [y,y+22).
    mov eax, [bullet_x]
    lea edx, [eax + 4]
    cmp edx, r10d
    jle .hit_next
    lea edx, [r10d + 32]
    cmp eax, edx
    jge .hit_next
    mov eax, [bullet_y]
    lea edx, [eax + 12]
    cmp edx, r11d
    jle .hit_next
    lea edx, [r11d + 22]
    cmp eax, edx
    jge .hit_next
    not ebx
    and dword [alive_mask], ebx
    inc dword [score]
    mov byte [bullet_active], 0
    cmp dword [alive_mask], 0
    jne .enemy_projectile
    mov byte [game_state], 1
    ret
.hit_next:
    inc esi
    shl ebx, 1
    cmp esi, 18
    jb .hit_loop

.enemy_projectile:
    cmp byte [eshot_active], 0
    jne .move_enemy_shot
    ; Spawn one enemy projectile every 53 frames.
    mov eax, [frame_counter]
    xor edx, edx
    mov ecx, 53
    div ecx
    test edx, edx
    jnz .end
    ; Pick an alive enemy; wrap around if the chosen index is dead.
    mov eax, [frame_counter]
    xor edx, edx
    mov ecx, 18
    div ecx
    mov esi, edx
    mov ebx, 18
.find_shooter:
    mov eax, 1
    mov ecx, esi
    shl eax, cl
    test dword [alive_mask], eax
    jnz .shooter_found
    inc esi
    cmp esi, 18
    jb .no_wrap
    xor esi, esi
.no_wrap:
    dec ebx
    jnz .find_shooter
    jmp .end
.shooter_found:
    mov eax, esi
    xor edx, edx
    mov ecx, 6
    div ecx
    imul edx, edx, 70
    add edx, [enemy_x]
    add edx, 14
    mov [eshot_x], edx
    imul eax, eax, 48
    add eax, [enemy_y]
    add eax, 22
    mov [eshot_y], eax
    mov byte [eshot_active], 1
    jmp .end

.move_enemy_shot:
    add dword [eshot_y], 6
    mov eax, [eshot_y]
    cmp eax, 470
    jge .despawn
    cmp eax, 418
    jl .end
    cmp eax, 444
    jge .end
    mov eax, [eshot_x]
    lea edx, [eax + 5]
    cmp edx, [player_x]
    jle .end
    mov edx, [player_x]
    add edx, 44
    cmp eax, edx
    jge .end
    dec dword [lives]
    mov byte [eshot_active], 0
    cmp dword [lives], 0
    jne .end
    mov byte [game_state], 2
    jmp .end
.despawn:
    mov byte [eshot_active], 0
.end:
    ret

render_game:
    RECT 0, 0, 640, 480, C_BG

    ; Fixed stars.
    lea rsi, [rel stars]
    mov ebx, 24
.stars:
    movzx r10d, word [rsi]
    movzx r11d, word [rsi + 2]
    mov r8d, 2
    mov r9d, 2
    mov eax, C_DIM
    call draw_rect
    add rsi, 4
    dec ebx
    jnz .stars

    RECT 8, 8, 624, 2, C_FRAME
    RECT 8, 8, 2, 464, C_FRAME
    RECT 630, 8, 2, 464, C_FRAME
    RECT 8, 471, 624, 2, C_FRAME
    RECT 8, 51, 624, 2, C_FRAME
    RECT 8, 451, 624, 2, C_FRAME

    TEXT text_score, 20, 19, C_CYAN
    ; Score always between 0 and 18: two decimal digits.
    mov eax, [score]
    xor edx, edx
    mov ecx, 10
    div ecx
    add al, '0'
    add dl, '0'
    mov [score_digits], al
    mov [score_digits + 1], dl
    TEXT score_digits, 98, 19, C_WHITE
    TEXT text_title, 225, 19, C_BLUE
    TEXT text_lives, 491, 19, C_CYAN

    ; Little life indicators.
    xor esi, esi
.life_loop:
    cmp esi, [lives]
    jge .life_end
    mov r10d, esi
    imul r10d, r10d, 19
    add r10d, 568
    mov r11d, 22
    mov r8d, 13
    mov r9d, 11
    mov eax, C_GREEN
    call draw_rect
    inc esi
    jmp .life_loop
.life_end:

    ; Alien formation: 3 rows of 6, each painted with a different color.
    xor esi, esi
    mov ebx, 1
.enemy_loop:
    test dword [alive_mask], ebx
    jz .enemy_next
    mov eax, esi
    xor edx, edx
    mov ecx, 6
    div ecx
    mov r13d, edx
    imul r13d, r13d, 70
    add r13d, [enemy_x]
    mov r12d, eax
    imul r12d, r12d, 48
    add r12d, [enemy_y]
    mov r15d, C_CYAN
    cmp eax, 0
    jne .not_first
    mov r15d, C_PINK
.not_first:
    cmp eax, 2
    jne .enemy_body
    mov r15d, C_BLUE
.enemy_body:
    RECT r13d, r12d, 32, 18, r15d
    lea r10d, [r13d + 6]
    lea r11d, [r12d - 5]
    mov r8d, 5
    mov r9d, 6
    mov eax, r15d
    call draw_rect
    lea r10d, [r13d + 21]
    lea r11d, [r12d - 5]
    mov r8d, 5
    mov r9d, 6
    mov eax, r15d
    call draw_rect
    lea r10d, [r13d + 3]
    lea r11d, [r12d + 18]
    mov r8d, 6
    mov r9d, 4
    mov eax, r15d
    call draw_rect
    lea r10d, [r13d + 23]
    lea r11d, [r12d + 18]
    mov r8d, 6
    mov r9d, 4
    mov eax, r15d
    call draw_rect
    lea r10d, [r13d + 7]
    lea r11d, [r12d + 7]
    mov r8d, 5
    mov r9d, 5
    mov eax, C_DARK
    call draw_rect
    lea r10d, [r13d + 20]
    lea r11d, [r12d + 7]
    mov r8d, 5
    mov r9d, 5
    mov eax, C_DARK
    call draw_rect
.enemy_next:
    inc esi
    shl ebx, 1
    cmp esi, 18
    jb .enemy_loop

    ; Player ship.
    mov r13d, [player_x]
    RECT r13d, 430, 44, 12, C_BLUE
    lea r10d, [r13d + 11]
    mov r11d, 421
    mov r8d, 22
    mov r9d, 10
    mov eax, C_CYAN
    call draw_rect
    lea r10d, [r13d + 19]
    mov r11d, 413
    mov r8d, 6
    mov r9d, 10
    mov eax, C_WHITE
    call draw_rect

    cmp byte [bullet_active], 0
    je .skip_player_bullet
    RECT dword [bullet_x], dword [bullet_y], 4, 12, C_GREEN
.skip_player_bullet:
    cmp byte [eshot_active], 0
    je .skip_enemy_bullet
    RECT dword [eshot_x], dword [eshot_y], 5, 12, C_RED
.skip_enemy_bullet:

    TEXT text_controls, 104, 457, C_DIM

    cmp byte [game_state], 0
    je .end
    RECT 148, 185, 344, 112, C_DARK
    RECT 148, 185, 344, 3, C_FRAME
    RECT 148, 294, 344, 3, C_FRAME
    cmp byte [game_state], 1
    jne .lost
    TEXT text_win, 278, 209, C_GREEN
    jmp .overlay_footer
.lost:
    TEXT text_lost, 266, 209, C_RED
.overlay_footer:
    TEXT text_restart, 239, 254, C_WHITE
.end:
    ret

section .data
align 8
; EFI_GRAPHICS_OUTPUT_PROTOCOL_GUID
; {9042a9de-23dc-4a38-96fb-7aded080516a}
gop_guid:       dd 0x9042a9de
                dw 0x23dc, 0x4a38
                db 0x96,0xfb,0x7a,0xde,0xd0,0x80,0x51,0x6a

; UTF-16LE messages (UEFI Console OutputString).
error_gop:      dw __utf16__('GOP graphics protocol not found.'), 13, 10, 0
error_mode:     dw __utf16__('Need >=640x480 GOP RGBX/BGRX 32-bit mode.'), 13, 10, 0

text_score:     db 'SCORE',0
score_digits:   db '00',0
text_title:     db 'SPACE INVADERS',0
text_lives:     db 'LIVES',0
text_controls:  db 'A D MOVE SPACE FIRE ESC EXIT',0
text_win:       db 'YOU WIN',0
text_lost:      db 'GAME OVER',0
text_restart:   db 'R TO RESTART',0

; 24 stars: x,y (16-bit).
stars:
    dw 28, 78,  71, 129,  137, 70,  203, 164
    dw 264, 80,  334, 135,  405, 94,  481, 148
    dw 551, 78,  603, 194,  35, 247,  89, 359
    dw 159, 290,  219, 398,  283, 347,  357, 371
    dw 429, 302,  513, 411,  586, 334,  618, 394
    dw 59, 411,  187, 221,  388, 229,  572, 257

; 5x7 bitmap font. Glyphs: '0'..'9' then 'A'..'Z'.
; Each row uses its 5 low bits; bit 4 is leftmost pixel.
font:
; 0
    db 0x0E,0x11,0x13,0x15,0x19,0x11,0x0E
; 1
    db 0x04,0x0C,0x04,0x04,0x04,0x04,0x0E
; 2
    db 0x0E,0x11,0x01,0x02,0x04,0x08,0x1F
; 3
    db 0x1E,0x01,0x01,0x0E,0x01,0x01,0x1E
; 4
    db 0x02,0x06,0x0A,0x12,0x1F,0x02,0x02
; 5
    db 0x1F,0x10,0x10,0x1E,0x01,0x01,0x1E
; 6
    db 0x0E,0x10,0x10,0x1E,0x11,0x11,0x0E
; 7
    db 0x1F,0x01,0x02,0x04,0x08,0x08,0x08
; 8
    db 0x0E,0x11,0x11,0x0E,0x11,0x11,0x0E
; 9
    db 0x0E,0x11,0x11,0x0F,0x01,0x01,0x0E
; A
    db 0x0E,0x11,0x11,0x1F,0x11,0x11,0x11
; B
    db 0x1E,0x11,0x11,0x1E,0x11,0x11,0x1E
; C
    db 0x0F,0x10,0x10,0x10,0x10,0x10,0x0F
; D
    db 0x1E,0x11,0x11,0x11,0x11,0x11,0x1E
; E
    db 0x1F,0x10,0x10,0x1E,0x10,0x10,0x1F
; F
    db 0x1F,0x10,0x10,0x1E,0x10,0x10,0x10
; G
    db 0x0F,0x10,0x10,0x17,0x11,0x11,0x0F
; H
    db 0x11,0x11,0x11,0x1F,0x11,0x11,0x11
; I
    db 0x0E,0x04,0x04,0x04,0x04,0x04,0x0E
; J
    db 0x07,0x02,0x02,0x02,0x12,0x12,0x0C
; K
    db 0x11,0x12,0x14,0x18,0x14,0x12,0x11
; L
    db 0x10,0x10,0x10,0x10,0x10,0x10,0x1F
; M
    db 0x11,0x1B,0x15,0x15,0x11,0x11,0x11
; N
    db 0x11,0x19,0x15,0x13,0x11,0x11,0x11
; O
    db 0x0E,0x11,0x11,0x11,0x11,0x11,0x0E
; P
    db 0x1E,0x11,0x11,0x1E,0x10,0x10,0x10
; Q
    db 0x0E,0x11,0x11,0x11,0x15,0x12,0x0D
; R
    db 0x1E,0x11,0x11,0x1E,0x14,0x12,0x11
; S
    db 0x0F,0x10,0x10,0x0E,0x01,0x01,0x1E
; T
    db 0x1F,0x04,0x04,0x04,0x04,0x04,0x04
; U
    db 0x11,0x11,0x11,0x11,0x11,0x11,0x0E
; V
    db 0x11,0x11,0x11,0x11,0x11,0x0A,0x04
; W
    db 0x11,0x11,0x11,0x15,0x15,0x15,0x0A
; X
    db 0x11,0x11,0x0A,0x04,0x0A,0x11,0x11
; Y
    db 0x11,0x11,0x0A,0x04,0x04,0x04,0x04
; Z
    db 0x1F,0x01,0x02,0x04,0x08,0x10,0x1F

section .bss
align 8
conin:         resq 1
conout:        resq 1
boot_services: resq 1
gop:           resq 1
framebuffer:   resq 1
pitch:         resq 1
origin_x:      resd 1
origin_y:      resd 1
pixel_format:  resd 1
key_data:      resd 1
player_x:      resd 1
enemy_x:       resd 1
enemy_y:       resd 1
enemy_dir:     resd 1
alive_mask:    resd 1
score:         resd 1
lives:         resd 1
frame_counter: resd 1
bullet_x:      resd 1
bullet_y:      resd 1
eshot_x:       resd 1
eshot_y:       resd 1
bullet_active: resb 1
eshot_active:  resb 1
game_state:    resb 1
quit:          resb 1
