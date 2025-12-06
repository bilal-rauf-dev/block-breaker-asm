[org 0x0100]

; ===== VIDEO INITIALIZATION =====

mov ax, 0x0100             ; Hide cursor
mov cx, 0x2000
int 0x10

mov ax, 0x0600             ; Clear screen code
mov bh, 00011000b
xor cx, cx
mov dx, 0x184F             ; Bottom-right (row 24, col 79)
int 0x10

; ===== CONSTANTS =====

SCREEN_ROWS equ 24
SCREEN_COLS equ 79

; Menu constants
MENU_ATTR           equ 00000111b
MENU_SELECTED_ATTR  equ 00011111b
MENU_TITLE_ATTR     equ 00001110b
MENU_OPTION_1       equ 0
MENU_OPTION_2       equ 1
MENU_OPTION_3       equ 2

ATTR            equ 00000111b
BALL_ATTR       equ 00001111b
BALL_CHAR       equ 'O'
LEFT_X          equ 2
RIGHT_X         equ 77
TOP_PLAY        equ 1
MID_X           equ 40
MID_Y           equ 12

; Paddle constants
PADDLE_ATTR         equ 00001001b
PADDLE_Y            equ 23
PADDLE_HALF_WIDTH   equ 7           ; Half-width of paddle (7 = 15 chars wide)
PADDLE_MIN_X        equ 0 + PADDLE_HALF_WIDTH
PADDLE_MAX_X        equ 79 - PADDLE_HALF_WIDTH
PADDLE_CHAR         equ 219         ; Solid block character (█)
PADDLE_STEP         equ 4

; Bricks
BRICK_ROWS          equ 2
BRICK_COLS          equ 8
BRICK_MAX_COUNT     equ 32
BRICK_WIDTH         equ 8
BRICK_START_X       equ 4
BRICK_START_Y       equ 1
BRICK_HSPACE        equ 1
BRICK_VSPACE        equ 1
BRICK_BLOCK         equ BRICK_WIDTH + BRICK_HSPACE  ; Total space per brick (9)
BRICK_CHAR          equ 219         ; Solid block character (█)
BRICK_ATTR          equ 01000011b

TICKS_PER_FRAME     equ 1           ; Frame delay (~55ms per tick)

; Score/Lives/Level display
SCORE_X             equ 2
SCORE_Y             equ 24
SCORE_ATTR          equ 00001111b
LIVES_X             equ 70
LIVES_Y             equ 24
LIVES_ATTR          equ 00001111b
INITIAL_LIVES       equ 3
LEVEL_X             equ 35
LEVEL_Y             equ 24
LEVEL_ATTR          equ 00001111b


; ===== PROGRAM START =====
start:

call show_menu

; Initialize game state
mov byte [ball_x],  MID_X
mov byte [ball_y],  MID_Y
mov byte [ball_dx], 1
mov byte [ball_dy], 1
mov byte [ball_speed], 1
mov byte [paddle_x], MID_X
mov word [brick_target], BRICK_ROWS * BRICK_COLS
mov word [brick_row_count], BRICK_ROWS
mov word [score], 0
mov byte [lives], INITIAL_LIVES


; ===== MAIN GAME LOOP =====
main_loop:
    call clear_frame

    call draw_bricks
    
    mov bh, PADDLE_ATTR
    mov dl, [paddle_x]
    mov dh, PADDLE_Y
    mov al, dl
    sub al, PADDLE_HALF_WIDTH       ; Start X = center - half width
    mov dl, al
    mov al, PADDLE_CHAR
    mov cx, 2*PADDLE_HALF_WIDTH + 1
.paddle_draw_loop:
    call plot
    inc dl
    loop .paddle_draw_loop

    ; Draw ball
    mov bh, BALL_ATTR
    mov al, BALL_CHAR
    mov dl, [ball_x]
    mov dh, [ball_y]
    call plot

    ; Draw UI
    call draw_score
    call draw_lives
    call draw_level

    ; ===== INPUT HANDLING =====
    mov ah, 0x01                    ; Check if key available
    int 0x16
    jz .no_key                      ; No key pressed
    xor ah, ah                      ; Read key
    int 0x16
    cmp al, 27                      ; ESC key
    je near reboot
    cmp al, 'p'                     ; DEBUG: Skip to next level
    je near .game_win
    cmp al, 'a'                     ; Move left
    je .p_left
    cmp al, 'A'
    je .p_left
    cmp al, 'd'                     ; Move right
    je .p_right
    cmp al, 'D'
    je .p_right
    cmp ah, 0x4B                    ; Left arrow scancode
    je .p_left
    cmp ah, 0x4D                    ; Right arrow scancode
    je .p_right
    jmp .no_key

.p_left:
    mov al, [paddle_x]
    mov bl, PADDLE_STEP
    sub al, bl
    cmp al, PADDLE_MIN_X            ; Stop to left boundary
    jb .set_min_left
    mov [paddle_x], al
    jmp .no_key
.set_min_left:
    mov al, PADDLE_MIN_X
    mov [paddle_x], al
    jmp .no_key

.p_right:
    mov al, [paddle_x]
    mov bl, PADDLE_STEP
    add al, bl
    cmp al, PADDLE_MAX_X            ; Stop to right boundary
    ja .set_max_right
    mov [paddle_x], al
    jmp .no_key
.set_max_right:
    mov al, PADDLE_MAX_X
    mov [paddle_x], al
    jmp .no_key

.no_key:
    ; ===== BALL PHYSICS =====
    mov al, [ball_dx]
    mov bl, [ball_speed]
    mul bl
    mov bl, [ball_x]
    add bl, al                      ; ball_x += ball_dx
    mov [ball_x], bl

    mov al, [ball_dy]
    mov bl, [ball_speed]
    mul bl
    mov bl, [ball_y]
    add bl, al                      ; ball_y += ball_dy
    mov [ball_y], bl

    ; ===== COLLISION DETECTION =====
    call check_brick_collision
    
    ; Check win condition (all bricks broken)
    mov ax, [bricks_broken]
    cmp ax, [brick_target]
    jae near .game_win

    ; Wall bounces (left/right/top)
    mov al, [ball_x]
    cmp al, 1
    jb .bounce_dx                   ; Hit left wall
    cmp al, 78
    ja .bounce_dx                   ; Hit right wall
    jmp .check_top

.bounce_dx:
    mov al, [ball_dx]
    neg al                          ; Reverse horizontal direction
    mov [ball_dx], al
    jmp .check_top

.check_top:
    mov al, [ball_y]
    cmp al, TOP_PLAY
    jb .bounce_dy                   ; Hit top wall
    jmp .walls_done

.bounce_dy:
    mov al, [ball_dy]
    neg al                          ; Reverse vertical direction
    mov [ball_dy], al

.walls_done:
    ; Paddle collision detection
    mov al, [ball_y]
    mov bl, PADDLE_Y
    dec bl                          ; Check if ball is 1 row above paddle
    cmp al, bl
    jne .after_pads
    mov al, [ball_dy]
    cmp al, 0
    jle .after_pads                 ; Only collide if moving down
    
    ; Check if ball X is within paddle width
    mov al, [ball_x]
    mov bl, [paddle_x]
    mov bh, bl
    sub bh, PADDLE_HALF_WIDTH       ; Left edge
    cmp al, bh
    jb .after_pads
    mov bh, bl
    add bh, PADDLE_HALF_WIDTH       ; Right edge
    cmp al, bh
    ja .after_pads
    
    ; Hit!
    mov al, [ball_dy]
    neg al
    mov [ball_dy], al
    call sound_paddle_hit

.after_pads:
    ; Check if ball missed paddle (out of bounds)
    mov al, [ball_y]
    cmp al, PADDLE_Y
    jb near .frame_delay
    
    ; Lost a life
    dec byte [lives]
    call sound_life_lost
    mov al, [lives]
    cmp al, 0
    je near .game_end               ; No lives left -> game over
    jmp .reset_ball                 ; Still have lives -> reset ball

.reset_ball:
    call reset_ball
    jmp .frame_delay

.game_win:
    ; Level complete! Reset and advance
    call reset_ball
    mov word [bricks_broken], 0
    inc word [brick_row_count]
    ;inc word [ball_speed]
    cmp word[brick_row_count], 5
    jge .game_end
    
    ; Calculate new brick target
    mov ax, word [brick_row_count]
    mov bx, BRICK_COLS
    mul bx                          ; AX = rows × cols
    mov word [brick_target], ax
    call reset_bricks
    jmp .frame_delay

.game_end:
    call reset_bricks
    ; Clear screen
    mov ax, 0x0600
    mov bh, 0x07
    xor cx, cx
    mov dh, SCREEN_ROWS
    mov dl, SCREEN_COLS
    int 0x10
    
    ; GAME OVER!
    mov bh, MENU_TITLE_ATTR
    mov dl, 25
    mov dh, 10
    mov si, str_end
.draw_win:
    mov al, [si]                    ; Load character manually
    cmp al, 0
    je .show_final_score
    call plot
    inc si                          ; Move to next character
    inc dl
    jmp .draw_win

.show_final_score:
    ; Display final score
    mov bh, MENU_ATTR
    mov dl, 30
    mov dh, 12
    mov si, str_final_score
.draw_final_label:
    mov al, [si]                    ; Load character manually
    cmp al, 0
    je .draw_final_number
    call plot
    inc si                          ; Move to next character
    inc dl
    jmp .draw_final_label

.draw_final_number:
    mov ax, [score]
    call display_number
    cmp cx, 0
    je .wait_key_setup

.wait_key_setup:
    inc dh
    inc dh
    mov dl, 25
    mov si, str_press_key
.draw_press_key:
    mov al, [si]                    ; Load character manually
    cmp al, 0
    je .wait_win_key
    call plot
    inc si                          ; Move to next character
    inc dl
    jmp .draw_press_key

.wait_win_key:
    xor ah, ah
    int 0x16                        ; Wait for any key
    jmp start                       ; Return to menu

; Frame timing: wait TICKS_PER_FRAME BIOS ticks (~55ms each)
.frame_delay:
    mov cl, TICKS_PER_FRAME
.wait_loop:
    call wait_tick
    dec cl
    jnz .wait_loop

    jmp main_loop


; ===== SUBROUTINES =====

; Reset ball to center 
reset_ball:
    push ax
    mov byte [ball_x], MID_X
    mov byte [ball_y], MID_Y
    mov al, [ball_dx]
    neg al
    mov [ball_dx], al
    mov byte [ball_dy], -1
    pop ax
    ret

; Draw score at bottom left
draw_score:
    push ax
    push bx
    push cx
    push dx
    push si

    mov bh, SCORE_ATTR
    mov dl, SCORE_X
    mov dh, SCORE_Y
    mov si, str_score
.draw_label:
    mov al, [si]                    ; Load character manually
    cmp al, 0
    je .draw_number
    call plot
    inc si                          ; Move to next character
    inc dl
    jmp .draw_label

.draw_number:
    mov ax, [score]
    call display_number

.done:
    pop si
    pop dx
    pop cx
    pop bx
    pop ax
    ret

; Draw lives at bottom right
draw_lives:
    push ax
    push bx
    push dx
    push si

    mov bh, LIVES_ATTR
    mov dl, LIVES_X
    mov dh, LIVES_Y
    mov si, str_lives
.draw_label:
    mov al, [si]                    ; Load character manually
    cmp al, 0
    je .draw_number
    call plot
    inc si                          ; Move to next character
    inc dl
    jmp .draw_label

.draw_number:
    mov al, [lives]
    add al, '0'
    mov bh, LIVES_ATTR
    call plot

    pop si
    pop dx
    pop bx
    pop ax
    ret

; Draw level at bottom middle
draw_level:
    push ax
    push bx
    push dx
    push si

    mov bh, LEVEL_ATTR
    mov dl, LEVEL_X
    mov dh, LEVEL_Y
    mov si, str_level
.draw_label:
    mov al, [si]                    ; Load character manually
    cmp al, 0
    je .draw_number
    call plot
    inc si                          ; Move to next character
    inc dl
    jmp .draw_label

.draw_number:
    ; Calculate level number: (current_rows - starting_rows) + 1
    mov ax, [brick_row_count]
    sub ax, BRICK_ROWS
    inc ax
    add al, '0'
    mov bh, LEVEL_ATTR
    call plot

    pop si
    pop dx
    pop bx
    pop ax
    ret

; Show menu and handle selection
show_menu:
    push ax
    push bx
    push cx
    push dx
    
    mov byte [menu_selection], 0    ; Start at option 1

.menu_loop:
    ; Clear screen
    mov ax, 0x0600
    mov bh, 0x07
    xor cx, cx
    mov dh, SCREEN_ROWS
    mov dl, SCREEN_COLS
    int 0x10
    
    ; Draw title
    mov bh, MENU_TITLE_ATTR
    mov dl, 28
    mov dh, 5
    mov si, str_title
.draw_title:
    mov al, [si]                    ; Load character manually
    cmp al, 0
    je .draw_options
    call plot
    inc si                          ; Move to next character
    inc dl
    jmp .draw_title

.draw_options:
    ; Option 1: Play game
    mov dl, 32
    mov dh, 10
    mov al, [menu_selection]
    cmp al, MENU_OPTION_1
    jne .opt1_normal
    mov bh, MENU_SELECTED_ATTR
    jmp .opt1_draw
.opt1_normal:
    mov bh, MENU_ATTR
.opt1_draw:
    mov si, str_play
.draw_opt1:
    mov al, [si]                    ; Load character manually
    cmp al, 0
    je .draw_opt2_setup
    call plot
    inc si                          ; Move to next character
    inc dl
    jmp .draw_opt1

.draw_opt2_setup:
    ; Option 2: How to play
    mov dl, 32
    mov dh, 12
    mov al, [menu_selection]
    cmp al, MENU_OPTION_2
    jne .opt2_normal
    mov bh, MENU_SELECTED_ATTR
    jmp .opt2_draw
.opt2_normal:
    mov bh, MENU_ATTR
.opt2_draw:
    mov si, str_howto
.draw_opt2:
    mov al, [si]                    ; Load character manually
    cmp al, 0
    je .draw_opt3_setup
    call plot
    inc si                          ; Move to next character
    inc dl
    jmp .draw_opt2

.draw_opt3_setup:
    ; Option 3: Exit
    mov dl, 32
    mov dh, 14
    mov al, [menu_selection]
    cmp al, MENU_OPTION_3
    jne .opt3_normal
    mov bh, MENU_SELECTED_ATTR
    jmp .opt3_draw
.opt3_normal:
    mov bh, MENU_ATTR
.opt3_draw:
    mov si, str_exit
.draw_opt3:
    mov al, [si]                    ; Load character manually
    cmp al, 0
    je .menu_input
    call plot
    inc si                          ; Move to next character
    inc dl
    jmp .draw_opt3

.menu_input:
    ; Wait for keypress
    xor ah, ah
    int 0x16
    
    cmp ah, 0x48                    ; Up arrow
    je .menu_up
    cmp ah, 0x50                    ; Down arrow
    je .menu_down
    cmp al, 13                      ; Enter
    je .menu_select
    cmp al, 27                      ; ESC
    je .menu_exit
    jmp .menu_loop

.menu_up:
    mov al, [menu_selection]
    cmp al, 0
    je .menu_loop
    dec byte [menu_selection]
    jmp .menu_loop

.menu_down:
    mov al, [menu_selection]
    cmp al, 2
    je .menu_loop
    inc byte [menu_selection]
    jmp .menu_loop

.menu_select:
    mov al, [menu_selection]
    cmp al, MENU_OPTION_1
    je .start_game
    cmp al, MENU_OPTION_2
    je .show_howto
    cmp al, MENU_OPTION_3
    je .menu_exit
    jmp .menu_loop

.show_howto:
    call show_instructions
    jmp .menu_loop

.start_game:
    mov ax, 0x0600
    mov bh, 0x07
    xor cx, cx
    mov dh, SCREEN_ROWS
    mov dl, SCREEN_COLS
    int 0x10
    mov word [score], 0
    mov byte [lives], INITIAL_LIVES
    mov word [bricks_broken], 0
    pop dx
    pop cx
    pop bx
    pop ax
    ret

.menu_exit:
    call clear_frame
    mov ax, 0x4c00
    int 0x21

; Show instructions screen
show_instructions:
    push ax
    push bx
    push dx
    
    mov ax, 0x0600
    mov bh, 0x07
    xor cx, cx
    mov dh, SCREEN_ROWS
    mov dl, SCREEN_COLS
    int 0x10
    
    mov bh, MENU_TITLE_ATTR
    mov dl, 30
    mov dh, 3
    mov si, str_howto_title
.draw_htitle:
    mov al, [si]                    ; Load character manually
    cmp al, 0
    je .draw_instructions
    call plot
    inc si                          ; Move to next character
    inc dl
    jmp .draw_htitle

.draw_instructions:
    mov bh, MENU_ATTR
    mov dl, 20
    mov dh, 6
    mov si, str_inst1
.draw_i1:
    mov al, [si]                    ; Load character manually
    cmp al, 0
    je .draw_i2_setup
    call plot
    inc si                          ; Move to next character
    inc dl
    jmp .draw_i1

.draw_i2_setup:
    mov dl, 20
    mov dh, 8
    mov si, str_inst2
.draw_i2:
    mov al, [si]                    ; Load character manually
    cmp al, 0
    je .draw_i3_setup
    call plot
    inc si                          ; Move to next character
    inc dl
    jmp .draw_i2

.draw_i3_setup:
    mov dl, 20
    mov dh, 10
    mov si, str_inst3
.draw_i3:
    mov al, [si]                    ; Load character manually
    cmp al, 0
    je .draw_i4_setup
    call plot
    inc si                          ; Move to next character
    inc dl
    jmp .draw_i3

.draw_i4_setup:
    mov dl, 20
    mov dh, 14
    mov si, str_inst4
.draw_i4:
    mov al, [si]                    ; Load character manually
    cmp al, 0
    je .wait_keypress
    call plot
    inc si                          ; Move to next character
    inc dl
    jmp .draw_i4

.wait_keypress:
    xor ah, ah
    int 0x16                        ; Wait for any key
    
    pop dx
    pop bx
    pop ax
    ret

; Draw all active bricks (only draws rows <= brick_row_count)
draw_bricks:
    push ax
    push bx
    push cx
    push dx
    push si
    push di

    xor si, si                      ; Brick index = 0
    xor di, di                      ; Row counter = 0
    mov bh, BRICK_ATTR

.row_loop:
    xor bl, bl                      ; Column counter = 0
    
.brick_loop:
    mov al, [bricks + si]
    cmp al, 0
    je .skip_brick                  ; Brick already destroyed
    
    ; Calculate Y position: START_Y + row * (1 + VSPACE)
    mov dh, BRICK_START_Y
    mov ax, di
    mov cl, 1 + BRICK_VSPACE
    mul cl
    add dh, al
    
    ; Calculate X position: START_X + col * BRICK_BLOCK
    mov ax, bx
    and ax, 0xFF                    ; Zero-extend BL to AX
    mov cl, BRICK_BLOCK
    mul cl
    mov dl, BRICK_START_X
    add dl, al
    
    push bx
    mov cx, BRICK_WIDTH
.draw_width:
    mov al, BRICK_CHAR
    call plot
    inc dl
    loop .draw_width
    pop bx

.skip_brick:
    inc si
    inc bl
    cmp bl, BRICK_COLS
    jb .brick_loop
    
    add bh, 1b                       ; Change color for next row
    inc di
    cmp di, word [brick_row_count]
    jb .row_loop

    pop di
    pop si
    pop dx
    pop cx
    pop bx
    pop ax
    ret

; Check if ball collides with any brick
check_brick_collision:
    push ax
    push bx
    push cx
    push dx
    push si

    ; Calculate which row: (ball_y - START_Y) / (1 + VSPACE)
    mov al, [ball_y]
    sub al, BRICK_START_Y
    jb near .no_hit                 ; Ball above brick area
    xor ah, ah
    mov bl, 1 + BRICK_VSPACE
    div bl                          ; AL = row, AH = position within spacing
    
    cmp al, byte [brick_row_count]
    jae .no_hit                     ; Row out of range
    
    cmp ah, 1                       ; Check if in gap (remainder > 0)
    ja .no_hit
    
    mov cl, al                      ; Save row in CL

    ; Calculate which column: (ball_x - START_X) / BRICK_BLOCK
    mov al, [ball_x]
    sub al, BRICK_START_X
    jb .no_hit                      ; Ball left of brick area
    xor ah, ah
    mov bl, BRICK_BLOCK
    div bl                          ; AL = col, AH = position within block
    
    cmp al, BRICK_COLS
    jae .no_hit                     ; Column out of range
    
    cmp ah, BRICK_WIDTH             ; Check if in horizontal gap
    jae .no_hit

    ; Calculate brick index: row * BRICK_COLS + col
    mov bl, al
    mov al, cl
    xor ah, ah
    mov cl, BRICK_COLS
    mul cl
    add al, bl
    
    mov si, ax
    and si, 0xFF
    mov al, [bricks + si]
    cmp al, 0
    je .no_hit                      ; Brick already destroyed

    ; Brick hit! 
    mov byte [bricks + si], 0
    inc word [score]
    inc word [bricks_broken]        ; Track bricks broken this level
    call sound_brick_hit
    
    ; Reverse vertical direction
    mov al, [ball_dy]
    neg al
    mov [ball_dy], al

    ; Erase brick from screen (draw spaces)
    mov ax, si
    xor dx, dx
    mov bl, BRICK_COLS
    div bl                          ; AL = row, AH = col
    
    ; Recalculate screen position
    mov dh, BRICK_START_Y
    mov bl, al
    mov al, bl
    mov cl, 1 + BRICK_VSPACE
    mul cl
    add dh, al
    
    mov al, ah
    xor ah, ah
    mov cl, BRICK_BLOCK
    mul cl
    mov dl, BRICK_START_X
    add dl, al
    
    ; Draw spaces over brick
    mov bh, 0x07
    push cx
    mov cx, BRICK_WIDTH
.erase_loop:
    mov al, ' '
    call plot
    inc dl
    loop .erase_loop
    pop cx

.no_hit:
    pop si
    pop dx
    pop cx
    pop bx
    pop ax
    ret

clear_frame:
    push ax
    push bx
    push cx
    push dx
    mov ax, 0x0600
    mov bh, 0x07
    xor cx, cx
    mov dh, SCREEN_ROWS
    mov dl, SCREEN_COLS
    int 0x10
    pop dx
    pop cx
    pop bx
    pop ax
    ret

; Reset all bricks to alive (1) for new level
reset_bricks:
    push bx
    xor bx, bx
.reset_loop:
    cmp bx, BRICK_MAX_COUNT         ; Safety check
    jae .reset_done
    mov byte [bricks + bx], 1
    inc bx
    cmp bx, word [brick_target]
    jb .reset_loop
.reset_done:
    pop bx
    ret

; Plot character using BIOS services
; IN: AL=char, BH=attribute, DL=x (0-79), DH=y (0-24)
plot:
    push ax
    push bx
    push cx
    push dx
    
    ; Set cursor position
    push ax                         ; Save character
    push bx                         ; Save attribute
    mov ah, 0x02                    ; BIOS: Set cursor position
    xor bh, bh                      ; Page 0
    int 0x10
    
    ; Write character with attribute
    pop bx                          ; Restore attribute to BX
    pop ax                          ; Restore character to AL
    mov bl, bh                      ; BL = attribute (move from BH to BL)
    mov bh, 0                       ; Page 0
    mov cx, 1                       ; Write 1 character
    mov ah, 0x09                    ; BIOS: Write char with attribute
    int 0x10
    
    pop dx
    pop cx
    pop bx
    pop ax
    ret

; Display multi-digit number in AX at position DL,DH
; Uses divide-and-push method to reverse digit order
display_number:
    push ax
    push bx
    push cx
    xor cx, cx                      ; Digit counter
    cmp ax, 0
    jne .dn_push
    push ax                         ; Special case: display '0'
    inc cx
    jmp .dn_pop
.dn_push:
    cmp al, 0
    je .dn_pop                      ; Done dividing
    xor ah, ah
    mov bl, 10
    div bl                          ; AL = quotient, AH = remainder (digit)
    push ax                         ; Push remainder
    xor ah, ah                      ; Clear AH for next iteration
    inc cx
    jmp .dn_push
.dn_pop:
    cmp cx, 0
    je .dn_done
    pop ax
    mov al, ah                      ; Get digit from AH
    add al, '0'                     ; Convert to ASCII
    call plot
    inc dl                          ; Move to next column
    dec cx
    jmp .dn_pop
.dn_done:
    pop cx
    pop bx
    pop ax
    ret

; Wait for one BIOS timer tick (~55ms)
wait_tick:
    push ax
    push bx
    push cx
    push dx
    mov ah, 0                       ; Get current tick count
    int 1Ah                         ; DX = low word of tick count
    mov bx, dx
.wt_loop:
    mov ah, 0
    int 1Ah
    cmp dx, bx                      ; Wait until tick changes
    je .wt_loop
    pop dx
    pop cx
    pop bx
    pop ax
    ret

; Return to main menu
reboot:
    call clear_frame
    call reset_bricks
    jmp start


; ===== SOUND EFFECTS (PC Speaker) =====

; High-pitch beep when brick is hit
sound_brick_hit:
    push ax
    push bx
    push cx
    mov al, 0xB6                    ; Timer mode: square wave
    out 0x43, al
    mov ax, 800                     ; Frequency divisor (high pitch)
    out 0x42, al                    ; Low byte
    mov al, ah
    out 0x42, al                    ; High byte
    in al, 0x61                     ; Read speaker port
    or al, 0x03                     ; Enable speaker
    out 0x61, al
    mov cx, 0x1000                  ; Short delay
.brick_delay:
    loop .brick_delay
    in al, 0x61
    and al, 0xFC                    ; Disable speaker
    out 0x61, al
    pop cx
    pop bx
    pop ax
    ret

; Medium-pitch beep when paddle is hit
sound_paddle_hit:
    push ax
    push bx
    push cx
    mov al, 0xB6
    out 0x43, al
    mov ax, 1200                    ; Medium pitch
    out 0x42, al
    mov al, ah
    out 0x42, al
    in al, 0x61
    or al, 0x03
    out 0x61, al
    mov cx, 0x1800                  ; Medium delay
.paddle_delay:
    loop .paddle_delay
    in al, 0x61
    and al, 0xFC
    out 0x61, al
    pop cx
    pop bx
    pop ax
    ret

; Low-pitch beep when life is lost
sound_life_lost:
    push ax
    push bx
    push cx
    mov al, 0xB6
    out 0x43, al
    mov ax, 2000                    ; Low pitch
    out 0x42, al
    mov al, ah
    out 0x42, al
    in al, 0x61
    or al, 0x03
    out 0x61, al
    mov cx, 0x4000                  ; Long delay
.lost_delay:
    loop .lost_delay
    in al, 0x61
    and al, 0xFC
    out 0x61, al
    pop cx
    pop bx
    pop ax
    ret


; ===== DATA SECTION =====

ball_x  db 0
ball_y  db 0
ball_dx db 0                        ; Horizontal velocity (-1 or +1)
ball_dy db 0                        ; Vertical velocity (-1 or +1)
ball_speed db 1                      ; Speed multiplier (not used)

bricks times BRICK_MAX_COUNT db 1   ; Brick states (1=alive, 0=destroyed)
brick_row_count dw BRICK_ROWS       ; Current level's row count
brick_target dw 0                    ; Bricks needed to complete level

paddle_x db 0                        ; Paddle center X position
score dw 0                           ; Total score
lives db 0                           ; Remaining lives
bricks_broken dw 0                   ; Bricks broken in current level

menu_selection db 0                  ; Current menu option (0-2)

; Menu strings
str_title       db 'ATARI BREAKOUT', 0
str_play        db '1. Play Game', 0
str_howto       db '2. How to Play', 0
str_exit        db '3. Exit', 0
str_howto_title db 'HOW TO PLAY', 0
str_inst1       db 'Use A/<- and D/-> keys to move the paddle', 0
str_inst2       db 'Break all bricks to win!', 0
str_inst3       db 'Press ESC to exit during game', 0
str_inst4       db 'Press any key to return to menu...', 0

; Game strings
str_score       db 'Score:', 0
str_lives       db 'Lives:', 0
str_level       db 'Level:', 0
str_end         db 'GAME OVER!', 0
str_final_score db 'Final Score: ', 0
str_press_key   db 'Press any key to continue...', 0