[org 0x0100]               ; .COM file: code starts at offset 0x0100 in memory

; ===== VIDEO INITIALIZATION =====
; Setup video mode and clear the screen before game starts

; Hide the blinking cursor so it doesn't interfere with graphics
mov ax, 0x0100             ; AH=01h (Set Cursor Shape), AL=00h
mov cx, 0x2000             ; CH=20h (cursor start line - invalid/hidden), CL=00h
int 0x10                   ; Call BIOS video services

; Clear the entire screen to prepare for game display
mov ax, 0x0600             ; AH=06h (Scroll Up), AL=00h (clear entire window)
mov bh, 00011000b          ; Attribute: dark gray on black (background color)
xor cx, cx                 ; CH=0, CL=0 (top-left corner at row 0, col 0)
mov dx, 0x184F             ; DH=24 (row 24), DL=79 (col 79) - bottom-right corner
int 0x10                   ; Call BIOS to clear screen

; ===== CONSTANTS =====
; All game configuration values defined here for easy tweaking

; Screen dimensions (standard 80x25 text mode, 0-indexed)
SCREEN_ROWS equ 24         ; Last usable row (0-24 = 25 rows total)
SCREEN_COLS equ 79         ; Last usable column (0-79 = 80 cols total)

; Menu screen color attributes (format: background[3bits] + foreground[4bits])
MENU_ATTR           equ 00000111b   ; Normal: white text on black (0x07)
MENU_SELECTED_ATTR  equ 00011111b   ; Highlighted: white on blue (0x1F)
MENU_TITLE_ATTR     equ 00001110b   ; Title: yellow text on black (0x0E)

; Menu option indices (used for tracking cursor position)
MENU_OPTION_1       equ 0          ; Play Game
MENU_OPTION_2       equ 1          ; How to Play
MENU_OPTION_3       equ 2          ; Exit

; General game attributes
ATTR            equ 00000111b      ; Default attribute: white on black

; Ball appearance and boundaries
BALL_ATTR       equ 00001111b      ; Ball color: bright white (0x0F)
BALL_CHAR       equ 'O'            ; Ball character (capital O)
LEFT_X          equ 2              ; Left wall X position (playable area starts at 2)
RIGHT_X         equ 77             ; Right wall X position (playable area ends at 77)
TOP_PLAY        equ 1              ; Top boundary of play area (row 1, row 0 for bricks)

; Screen center positions (used for ball/paddle spawn)
MID_X           equ 40             ; Horizontal center of screen (80/2)
MID_Y           equ 12             ; Vertical center of screen (25/2)

; Paddle constants (bottom paddle controlled by player)
PADDLE_ATTR         equ 00001001b  ; Paddle color: blue on black (0x09)
PADDLE_Y            equ 23         ; Paddle row (near bottom, row 24 for UI)
PADDLE_HALF_WIDTH   equ 7          ; Half-width: 7 chars on each side = 15 total width
PADDLE_MIN_X        equ 0 + PADDLE_HALF_WIDTH  ; Leftmost center position (prevents off-screen)
PADDLE_MAX_X        equ 79 - PADDLE_HALF_WIDTH ; Rightmost center position
PADDLE_CHAR         equ 219        ; Solid block character (█ / ASCII 219)
PADDLE_STEP         equ 4          ; Columns moved per keypress (higher = faster)

; Brick layout and appearance
BRICK_ROWS          equ 2          ; Starting number of brick rows (increases per level)
BRICK_COLS          equ 8          ; Number of brick columns (fixed)
BRICK_MAX_COUNT     equ 32         ; Maximum bricks in array (4 rows × 8 cols, supports up to level 4)
BRICK_WIDTH         equ 8          ; Width of each brick in characters
BRICK_START_X       equ 4          ; Left margin before first brick column
BRICK_START_Y       equ 1          ; Top margin (row 1, leaves row 0 for top border)
BRICK_HSPACE        equ 1          ; Horizontal gap between bricks (columns)
BRICK_VSPACE        equ 1          ; Vertical gap between brick rows
BRICK_BLOCK         equ BRICK_WIDTH + BRICK_HSPACE  ; Total horizontal space per brick (8+1=9)
BRICK_CHAR          equ 219        ; Solid block character (█ / ASCII 219)
BRICK_ATTR          equ 01000011b  ; Brick color: cyan on black (0x43)

; Game timing (BIOS timer ticks at ~18.2 Hz, each tick ≈ 55ms)
TICKS_PER_FRAME     equ 1          ; Wait 1 tick between frames (~18 FPS)
                                   ; Increase this value to slow down the game

; UI Display positions and attributes (bottom row HUD)
; Score display (bottom-left)
SCORE_X             equ 2          ; Column position for "Score:" label
SCORE_Y             equ 24         ; Row 24 (bottom row)
SCORE_ATTR          equ 00001111b  ; Bright white text (0x0F)

; Lives display (bottom-right)
LIVES_X             equ 70         ; Column position for "Lives:" label
LIVES_Y             equ 24         ; Row 24 (bottom row)
LIVES_ATTR          equ 00001111b  ; Bright white text (0x0F)
INITIAL_LIVES       equ 3          ; Starting number of lives (3 chances)

; Level display (bottom-center)
LEVEL_X             equ 35         ; Column position for "Level:" label
LEVEL_Y             equ 24         ; Row 24 (bottom row)
LEVEL_ATTR          equ 00001111b  ; Bright white text (0x0F)


; ===== PROGRAM START =====
; Entry point after DOS loads the .COM file
start:

; Display the main menu (user selects Play/Instructions/Exit)
call show_menu

; Initialize game state variables to starting values
; Ball starts at screen center, moving down-right
mov byte [ball_x],  MID_X      ; Ball X position = center (40)
mov byte [ball_y],  MID_Y      ; Ball Y position = center (12)
mov byte [ball_dx], 1          ; Ball X velocity = 1 (moving right)
mov byte [ball_dy], 1          ; Ball Y velocity = 1 (moving down)
mov byte [ball_speed], 1       ; Ball speed multiplier (currently unused)

; Paddle starts at horizontal center
mov byte [paddle_x], MID_X     ; Paddle center X = 40

; Level progression tracking
mov word [brick_target], BRICK_ROWS * BRICK_COLS  ; Target bricks = 2×8 = 16
mov word [brick_row_count], BRICK_ROWS             ; Current level rows = 2

; Player stats
mov word [score], 0            ; Score starts at 0
mov byte [lives], INITIAL_LIVES ; Lives starts at 3


; ===== MAIN GAME LOOP =====
; This loop runs continuously at ~18 FPS until game ends
main_loop:
    ; Clear the play area (removes previous frame's graphics)
    call clear_frame

    ; Draw all active bricks (only draws rows up to current level)
    call draw_bricks
    
    ; ===== DRAW PADDLE =====
    ; Paddle is drawn as a horizontal line of solid blocks at the bottom
    mov bh, PADDLE_ATTR            ; Set paddle color attribute
    mov dl, [paddle_x]             ; Get paddle center X position
    mov dh, PADDLE_Y               ; Paddle is always at row 23
    mov al, dl                     ; Copy center X to AL
    sub al, PADDLE_HALF_WIDTH      ; Calculate left edge: center - 7 = leftmost char
    mov dl, al                     ; DL now points to left edge
    mov al, PADDLE_CHAR            ; Load the solid block character
    mov cx, 2*PADDLE_HALF_WIDTH + 1 ; Total width = 2*7+1 = 15 characters
.paddle_draw_loop:
    call plot                      ; Draw one paddle character at (DL, DH)
    inc dl                         ; Move one column to the right
    loop .paddle_draw_loop         ; Repeat CX times (15 iterations)

    ; ===== DRAW BALL =====
    ; Ball is a single 'O' character that moves around
    mov bh, BALL_ATTR              ; Set ball color (bright white)
    mov al, BALL_CHAR              ; Load 'O' character
    mov dl, [ball_x]               ; Get ball X position
    mov dh, [ball_y]               ; Get ball Y position
    call plot                      ; Draw ball at current position

    ; ===== DRAW UI =====
    ; Display score, lives, and level at bottom of screen
    call draw_score                ; Shows "Score: XX" at bottom-left
    call draw_lives                ; Shows "Lives: X" at bottom-right
    call draw_level                ; Shows "Level: X" at bottom-center

    ; ===== INPUT HANDLING =====
    ; Non-blocking keyboard check (game continues even if no key pressed)
    mov ah, 0x01                   ; BIOS function: Check keyboard status
    int 0x16                       ; ZF=1 if no key pressed, ZF=0 if key waiting
    jz .no_key                     ; Jump if no key pressed (skip input processing)
    
    ; Key is available, read it now
    xor ah, ah                     ; BIOS function: Read keystroke (blocking)
    int 0x16                       ; AL=ASCII char, AH=scan code
    
    ; Check ESC key (exit to menu)
    cmp al, 27                     ; ASCII 27 = ESC
    je near reboot                 ; Return to main menu
    
    ; DEBUG: Check 'p' key (skip to next level)
    cmp al, 'p'                    ; Lowercase 'p'
    je near .game_win              ; Jump to level complete code
    
    ; Check left movement keys (A or left arrow)
    cmp al, 'a'                    ; Lowercase 'a'
    je .p_left
    cmp al, 'A'                    ; Uppercase 'A'
    je .p_left
    
    ; Check right movement keys (D or right arrow)
    cmp al, 'd'                    ; Lowercase 'd'
    je .p_right
    cmp al, 'D'                    ; Uppercase 'D'
    je .p_right
    
    ; Check arrow key scancodes (AH contains scan code from BIOS)
    cmp ah, 0x4B                   ; Scan code for left arrow
    je .p_left
    cmp ah, 0x4D                   ; Scan code for right arrow
    je .p_right
    
    jmp .no_key                    ; Unknown key, ignore it

.p_left:
    ; Move paddle left by PADDLE_STEP columns (4 columns per press)
    mov al, [paddle_x]             ; Get current paddle center X
    mov bl, PADDLE_STEP            ; Load movement speed (4)
    sub al, bl                     ; New X = current X - 4
    cmp al, PADDLE_MIN_X           ; Check if new position goes past left edge
    jb .set_min_left               ; If below minimum, clamp to minimum
    mov [paddle_x], al             ; Valid position, update paddle X
    jmp .no_key                    ; Done processing input
.set_min_left:
    ; Paddle hit left boundary, clamp to minimum allowed position
    mov al, PADDLE_MIN_X           ; Set to leftmost allowed position
    mov [paddle_x], al             ; Update paddle X
    jmp .no_key                    ; Done processing input

.p_right:
    ; Move paddle right by PADDLE_STEP columns (4 columns per press)
    mov al, [paddle_x]             ; Get current paddle center X
    mov bl, PADDLE_STEP            ; Load movement speed (4)
    add al, bl                     ; New X = current X + 4
    cmp al, PADDLE_MAX_X           ; Check if new position goes past right edge
    ja .set_max_right              ; If above maximum, clamp to maximum
    mov [paddle_x], al             ; Valid position, update paddle X
    jmp .no_key                    ; Done processing input
.set_max_right:
    ; Paddle hit right boundary, clamp to maximum allowed position
    mov al, PADDLE_MAX_X           ; Set to rightmost allowed position
    mov [paddle_x], al             ; Update paddle X
    jmp .no_key                    ; Done processing input

.no_key:
    ; ===== BALL PHYSICS =====
    ; Update ball position based on velocity and speed multiplier
    ; Formula: new_position = old_position + (velocity * speed)
    
    ; Update X position (horizontal movement)
    mov al, [ball_dx]              ; Load X velocity (-1 or +1)
    mov bl, [ball_speed]           ; Load speed multiplier (currently always 1)
    mul bl                         ; AL = dx * speed
    mov bl, [ball_x]               ; Load current X position
    add bl, al                     ; New X = old X + (dx * speed)
    mov [ball_x], bl               ; Store new X position

    ; Update Y position (vertical movement)
    mov al, [ball_dy]              ; Load Y velocity (-1 or +1)
    mov bl, [ball_speed]           ; Load speed multiplier
    mul bl                         ; AL = dy * speed
    mov bl, [ball_y]               ; Load current Y position
    add bl, al                     ; New Y = old Y + (dy * speed)
    mov [ball_y], bl               ; Store new Y position

    ; ===== COLLISION DETECTION =====
    
    ; Check if ball hit any bricks (and destroy them)
    call check_brick_collision
    
    ; Check win condition: all bricks in current level destroyed?
    mov ax, [bricks_broken]        ; Number of bricks broken this level
    cmp ax, [brick_target]         ; Target bricks for this level (16, 24, 32...)
    jae near .game_win             ; If >= target, level complete!

    ; ===== WALL COLLISION (BOUNCE) =====
    ; Left and right walls: reverse horizontal velocity
    mov al, [ball_x]               ; Get current ball X
    cmp al, 1                      ; Check left wall (X=1)
    jb .bounce_dx                  ; Ball hit or passed left wall
    cmp al, 78                     ; Check right wall (X=78)
    ja .bounce_dx                  ; Ball hit or passed right wall
    jmp .check_top                 ; No horizontal wall hit, check vertical

.bounce_dx:
    ; Ball hit left or right wall, reverse horizontal direction
    mov al, [ball_dx]              ; Get current X velocity
    neg al                         ; Flip sign: 1 becomes -1, -1 becomes 1
    mov [ball_dx], al              ; Store reversed velocity
    jmp .check_top                 ; Continue to check vertical walls

.check_top:
    ; Top wall: reverse vertical velocity (no bottom wall, that's a miss)
    mov al, [ball_y]               ; Get current ball Y
    cmp al, TOP_PLAY               ; Check top boundary (Y=1)
    jb .bounce_dy                  ; Ball hit or passed top wall
    jmp .walls_done                ; No vertical wall hit, done with walls

.bounce_dy:
    ; Ball hit top wall, reverse vertical direction
    mov al, [ball_dy]              ; Get current Y velocity
    neg al                         ; Flip sign: 1 becomes -1, -1 becomes 1
    mov [ball_dy], al              ; Store reversed velocity

.walls_done:
    ; ===== PADDLE COLLISION =====
    ; Check if ball is in the row just above the paddle
    mov al, [ball_y]               ; Get ball Y position
    mov bl, PADDLE_Y               ; Get paddle Y (row 23)
    dec bl                         ; BL = 22 (one row above paddle)
    cmp al, bl                     ; Is ball at row 22?
    jne .after_pads                ; No, skip paddle collision
    
    ; Ball is at correct Y, check if moving downward
    mov al, [ball_dy]              ; Get Y velocity
    cmp al, 0                      ; Is it negative (moving up)?
    jle .after_pads                ; Yes, ball moving up - no collision
    
    ; Ball is moving down at paddle height, check X overlap
    ; Paddle collision zone: [paddle_x - 7] to [paddle_x + 7]
    mov al, [ball_x]               ; Get ball X position
    mov bl, [paddle_x]             ; Get paddle center X
    mov bh, bl                     ; Copy to BH for calculation
    sub bh, PADDLE_HALF_WIDTH      ; BH = left edge (center - 7)
    cmp al, bh                     ; Is ball X < left edge?
    jb .after_pads                 ; Yes, ball missed paddle (too far left)
    mov bh, bl                     ; Restore paddle center
    add bh, PADDLE_HALF_WIDTH      ; BH = right edge (center + 7)
    cmp al, bh                     ; Is ball X > right edge?
    ja .after_pads                 ; Yes, ball missed paddle (too far right)
    
    ; Hit! Ball is within paddle bounds, bounce it back up
    mov al, [ball_dy]              ; Get current Y velocity
    neg al                         ; Reverse it (1 becomes -1)
    mov [ball_dy], al              ; Store reversed velocity (ball bounces up)
    call sound_paddle_hit          ; Play bounce sound effect

.after_pads:
    ; ===== MISS DETECTION =====
    ; Check if ball fell below the paddle (player missed)
    mov al, [ball_y]               ; Get ball Y position
    cmp al, PADDLE_Y               ; Compare to paddle row (23)
    jb near .frame_delay           ; Ball is above paddle, still in play
    
    ; Ball fell off screen! Player loses a life
    dec byte [lives]               ; Decrement life counter
    call sound_life_lost           ; Play sad sound effect
    
    ; Check if game over (no lives remaining)
    mov al, [lives]                ; Get remaining lives
    cmp al, 0                      ; Any lives left?
    je near .game_end              ; No lives -> game over screen
    jmp .reset_ball                ; Still alive -> reset ball position

.reset_ball:
    ; Reset ball to starting position (center screen, above paddle)
    call reset_ball                ; Subroutine: X=40, Y=20, dx=1, dy=-1
    jmp .frame_delay               ; Continue game loop

.game_win:
    ; ===== LEVEL COMPLETE =====
    ; Player broke all bricks in current level, advance to next!
    
    call reset_ball                ; Reset ball position
    mov word [bricks_broken], 0    ; Reset brick counter for new level
    inc word [brick_row_count]     ; Add one more row of bricks
    
    ; Speed increase commented out for balance
    ;inc word [ball_speed]         ; Optionally increase ball speed
    
    ; Check maximum level (5 rows = hardest level)
    cmp word [brick_row_count], 5  ; At maximum difficulty?
    jge .game_end                  ; Yes -> victory screen!
    
    ; Calculate new target: (rows × columns)
    ; Example: Level 3 = 3 rows × 8 cols = 24 bricks
    mov ax, word [brick_row_count] ; Get number of rows for this level
    mov bx, BRICK_COLS             ; Get columns (8)
    mul bx                         ; AX = rows × cols
    mov word [brick_target], ax    ; Set new target brick count
    
    call reset_bricks              ; Regenerate brick grid
    jmp .frame_delay               ; Continue to next level

.game_end:
    ; ===== GAME OVER / VICTORY SCREEN =====
    ; Player either won (beat all levels) or lost (ran out of lives)
    
    call reset_bricks              ; Clean up brick array
    
    ; Clear the entire screen using BIOS scroll function
    mov ax, 0x0600                 ; AH=0x06 scroll up, AL=0x00 full screen
    mov bh, 0x07                   ; Attribute: white on black
    xor cx, cx                     ; Top-left corner (row 0, col 0)
    mov dh, SCREEN_ROWS            ; Bottom row (24)
    mov dl, SCREEN_COLS            ; Right column (79)
    int 0x10                       ; Execute BIOS video service
    
    ; Display game over message ("GAME OVER!" or "YOU WIN!")
    mov bh, MENU_TITLE_ATTR        ; Bright yellow attribute (0x0E)
    mov dl, 25                     ; Start at column 25 (centered-ish)
    mov dh, 10                     ; Row 10 (upper-middle of screen)
    mov si, str_end                ; Pointer to end message string
.draw_win:
    ; Character-by-character drawing loop
    mov al, [si]                   ; Load character from string
    cmp al, 0                      ; Is it null terminator?
    je .show_final_score           ; Yes, move to score display
    call plot                      ; Draw character at (DL, DH) with attr BH
    inc si                         ; Advance string pointer
    inc dl                         ; Move cursor right
    jmp .draw_win                  ; Continue loop

.show_final_score:
    ; Display "Final Score: " label
    mov bh, MENU_ATTR              ; Normal menu attribute (0x0F)
    mov dl, 30                     ; Column 30 (centered)
    mov dh, 12                     ; Row 12 (below game over text)
    mov si, str_final_score        ; Pointer to "Final Score: " string
.draw_final_label:
    mov al, [si]                   ; Load character
    cmp al, 0                      ; Null terminator?
    je .draw_final_number          ; Yes, draw the number
    call plot                      ; Draw character
    inc si                         ; Next character
    inc dl                         ; Next column
    jmp .draw_final_label          ; Loop

.draw_final_number:
    ; Display the numeric score value
    mov ax, [score]                ; Load final score
    call display_number            ; Convert and display at (DL, DH)
    cmp cx, 0                      ; Check if conversion succeeded
    je .wait_key_setup             ; Continue to "press any key" prompt

.wait_key_setup:
    ; Display "Press any key" prompt below score
    inc dh                         ; Move down 1 row
    inc dh                         ; Move down another row (2 rows below score)
    mov dl, 25                     ; Center horizontally
    mov si, str_press_key          ; Pointer to prompt string
.draw_press_key:
    mov al, [si]                   ; Load character
    cmp al, 0                      ; Null terminator?
    je .wait_win_key               ; Yes, wait for input
    call plot                      ; Draw character
    inc si                         ; Next character
    inc dl                         ; Next column
    jmp .draw_press_key            ; Loop

.wait_win_key:
    ; Blocking keyboard input: wait for player to press any key
    xor ah, ah                     ; AH=0x00: blocking read keystroke
    int 0x16                       ; BIOS keyboard service (blocks until key)
    jmp start                      ; Return to main menu

; ===== FRAME TIMING =====
; Maintain consistent frame rate by waiting for BIOS timer ticks
; Each tick is approximately 55ms (18.2 ticks per second)
; TICKS_PER_FRAME = 1, so game runs at ~18 FPS
.frame_delay:
    mov cl, TICKS_PER_FRAME        ; Number of ticks to wait (1)
.wait_loop:
    call wait_tick                 ; Wait for one BIOS timer tick
    dec cl                         ; Decrement tick counter
    jnz .wait_loop                 ; Loop until all ticks elapsed

    jmp main_loop                  ; Start next frame


; =========================================================================
; ===== SUBROUTINES =====
; =========================================================================

; -------------------------------------------------------------------------
; reset_ball: Reset ball to starting position
; -------------------------------------------------------------------------
; Resets ball to center of screen with upward-left velocity
; Called after life loss or level advancement
;
; Modifies: ball_x, ball_y, ball_dx, ball_dy
; Preserves: All registers (AX saved/restored)
;
reset_ball:
    push ax                        ; Save AX register
    mov byte [ball_x], MID_X       ; X = 40 (horizontal center)
    mov byte [ball_y], MID_Y       ; Y = 20 (above paddle)
    mov al, [ball_dx]              ; Load current X velocity
    neg al                         ; Reverse it (alternate direction each reset)
    mov [ball_dx], al              ; Store new X velocity
    mov byte [ball_dy], -1         ; Y velocity = -1 (always moves up)
    pop ax                         ; Restore AX
    ret                            ; Return to caller

; -------------------------------------------------------------------------
; draw_score: Display "Score: ###" at bottom left
; -------------------------------------------------------------------------
; Draws score label and numeric value at fixed position (1, 24)
;
; Uses: plot (character output), display_number (integer to string)
; Preserves: All registers
;
draw_score:
    push ax                        ; Save all modified registers
    push bx
    push cx
    push dx
    push si

    mov bh, SCORE_ATTR             ; Attribute: bright white (0x0F)
    mov dl, SCORE_X                ; X position: column 1
    mov dh, SCORE_Y                ; Y position: row 24 (bottom)
    mov si, str_score              ; Pointer to "Score: " string
.draw_label:
    ; Draw "Score: " text character by character
    mov al, [si]                   ; Load character from string
    cmp al, 0                      ; Null terminator?
    je .draw_number                ; Yes, switch to number display
    call plot                      ; Draw character at cursor position
    inc si                         ; Advance string pointer
    inc dl                         ; Move cursor right
    jmp .draw_label                ; Continue loop

.draw_number:
    ; Convert and display numeric score value
    mov ax, [score]                ; Load score value
    call display_number            ; Convert to string and draw at (DL, DH)

.done:
    pop si                         ; Restore all registers
    pop dx
    pop cx
    pop bx
    pop ax
    ret                            ; Return to caller

; -------------------------------------------------------------------------
; draw_lives: Display "Lives: #" at bottom right
; -------------------------------------------------------------------------
; Draws lives label and count at fixed position (70, 24)
;
; Uses: plot (character output)
; Preserves: All registers
;
draw_lives:
    push ax                        ; Save modified registers
    push bx
    push dx
    push si

    mov bh, LIVES_ATTR             ; Attribute: cyan (0x0B)
    mov dl, LIVES_X                ; X position: column 70
    mov dh, LIVES_Y                ; Y position: row 24 (bottom)
    mov si, str_lives              ; Pointer to "Lives: " string
.draw_label:
    ; Draw "Lives: " text character by character
    mov al, [si]                   ; Load character from string
    cmp al, 0                      ; Null terminator?
    je .draw_number                ; Yes, switch to number display
    call plot                      ; Draw character at cursor position
    inc si                         ; Advance string pointer
    inc dl                         ; Move cursor right
    jmp .draw_label                ; Continue loop

.draw_number:
    ; Display single-digit lives count (1-3)
    mov al, [lives]                ; Load lives value (1, 2, or 3)
    add al, '0'                    ; Convert to ASCII ('1', '2', or '3')
    mov bh, LIVES_ATTR             ; Restore attribute (may be modified by plot)
    call plot                      ; Draw digit at current cursor position

    pop si                         ; Restore all registers
    pop dx
    pop bx
    pop ax
    ret                            ; Return to caller

; -------------------------------------------------------------------------
; draw_level: Display "Level: #" at bottom center
; -------------------------------------------------------------------------
; Draws level label and current level number at fixed position (35, 24)
; Level number is calculated from brick_row_count
;
; Uses: plot (character output)
; Preserves: All registers
;
draw_level:
    push ax                        ; Save modified registers
    push bx
    push dx
    push si

    mov bh, LEVEL_ATTR             ; Attribute: bright green (0x0A)
    mov dl, LEVEL_X                ; X position: column 35
    mov dh, LEVEL_Y                ; Y position: row 24 (bottom)
    mov si, str_level              ; Pointer to "Level: " string
.draw_label:
    ; Draw "Level: " text character by character
    mov al, [si]                   ; Load character from string
    cmp al, 0                      ; Null terminator?
    je .draw_number                ; Yes, switch to number display
    call plot                      ; Draw character at cursor position
    inc si                         ; Advance string pointer
    inc dl                         ; Move cursor right
    jmp .draw_label                ; Continue loop

.draw_number:
    ; Calculate and display level number
    ; Formula: level = (current_rows - starting_rows) + 1
    ; Example: current=3, starting=2 -> level = (3-2)+1 = 2
    mov ax, [brick_row_count]      ; Load current row count (2, 3, 4...)
    sub ax, BRICK_ROWS             ; Subtract starting rows (2)
    inc ax                         ; Add 1 (level 1 = 2 rows)
    add al, '0'                    ; Convert to ASCII ('1', '2', '3', '4')
    mov bh, LEVEL_ATTR             ; Restore attribute
    call plot                      ; Draw digit

    pop si                         ; Restore all registers
    pop dx
    pop bx
    pop ax
    ret                            ; Return to caller

; -------------------------------------------------------------------------
; show_menu: Display main menu and handle user selection
; -------------------------------------------------------------------------
; Displays title, menu options (1=Play, 2=Instructions, 3=Exit)
; Allows cursor navigation with arrow keys, Enter to select
; Returns to appropriate screen based on selection
;
; Menu Selection Values:
;   0 = Play Game
;   1 = View Instructions
;   2 = Exit to DOS
;
; Modifies: menu_selection, various display registers
; Uses: plot, BIOS keyboard services
;
show_menu:
    push ax                        ; Save modified registers
    push bx
    push cx
    push dx
    
    mov byte [menu_selection], 0   ; Default selection: option 1 (Play)

.menu_loop:
    ; ===== MENU RENDERING =====
    ; Redraw entire menu screen (called on every selection change)
    
    ; Clear the entire screen using BIOS scroll function
    mov ax, 0x0600                 ; AH=0x06 scroll up, AL=0x00 full clear
    mov bh, 0x07                   ; Attribute: white on black
    xor cx, cx                     ; Top-left corner (row 0, col 0)
    mov dh, SCREEN_ROWS            ; Bottom row (24)
    mov dl, SCREEN_COLS            ; Right column (79)
    int 0x10                       ; Execute BIOS video service
    
    ; Draw game title "ATARI BREAKOUT" in bright yellow
    mov bh, MENU_TITLE_ATTR        ; Attribute: bright yellow (0x0E)
    mov dl, 28                     ; Start column (centered)
    mov dh, 5                      ; Row 5 (near top)
    mov si, str_title              ; Pointer to title string
.draw_title:
    mov al, [si]                   ; Load character
    cmp al, 0                      ; Null terminator?
    je .draw_options               ; Yes, move to menu options
    call plot                      ; Draw character
    inc si                         ; Next character
    inc dl                         ; Next column
    jmp .draw_title                ; Continue loop

.draw_options:
    ; ===== DRAW MENU OPTION 1: "1. Play Game" =====
    mov dl, 32                     ; Start column (centered)
    mov dh, 10                     ; Row 10 (middle of screen)
    
    ; Check if this option is currently selected
    mov al, [menu_selection]       ; Load current selection (0=Play, 1=How, 2=Exit)
    cmp al, MENU_OPTION_1          ; Is option 1 selected? (value = 0)
    jne .opt1_normal               ; No, use normal attribute
    mov bh, MENU_SELECTED_ATTR     ; Yes, use highlight attribute (black on white)
    jmp .opt1_draw                 ; Draw the text
.opt1_normal:
    mov bh, MENU_ATTR              ; Use normal attribute (white on black)
.opt1_draw:
    mov si, str_play               ; Pointer to "1. Play Game" string
.draw_opt1:
    mov al, [si]                   ; Load character
    cmp al, 0                      ; Null terminator?
    je .draw_opt2_setup            ; Yes, move to next option
    call plot                      ; Draw character
    inc si                         ; Next character
    inc dl                         ; Next column
    jmp .draw_opt1                 ; Continue loop

.draw_opt2_setup:
    ; ===== DRAW MENU OPTION 2: "2. How to Play" =====
    mov dl, 32                     ; Start column (centered)
    mov dh, 12                     ; Row 12 (2 rows below option 1)
    
    ; Check if this option is currently selected
    mov al, [menu_selection]       ; Load current selection
    cmp al, MENU_OPTION_2          ; Is option 2 selected? (value = 1)
    jne .opt2_normal               ; No, use normal attribute
    mov bh, MENU_SELECTED_ATTR     ; Yes, use highlight attribute
    jmp .opt2_draw
.opt2_normal:
    mov bh, MENU_ATTR              ; Use normal attribute
.opt2_draw:
    mov si, str_howto              ; Pointer to "2. How to Play" string
.draw_opt2:
    mov al, [si]                   ; Load character
    cmp al, 0                      ; Null terminator?
    je .draw_opt3_setup            ; Yes, move to next option
    call plot                      ; Draw character
    inc si                         ; Next character
    inc dl                         ; Next column
    jmp .draw_opt2                 ; Continue loop

.draw_opt3_setup:
    ; ===== DRAW MENU OPTION 3: "3. Exit" =====
    mov dl, 32                     ; Start column (centered)
    mov dh, 14                     ; Row 14 (2 rows below option 2)
    
    ; Check if this option is currently selected
    mov al, [menu_selection]       ; Load current selection
    cmp al, MENU_OPTION_3          ; Is option 3 selected? (value = 2)
    jne .opt3_normal               ; No, use normal attribute
    mov bh, MENU_SELECTED_ATTR     ; Yes, use highlight attribute
    jmp .opt3_draw
.opt3_normal:
    mov bh, MENU_ATTR              ; Use normal attribute
.opt3_draw:
    mov si, str_exit               ; Pointer to "3. Exit" string
.draw_opt3:
    mov al, [si]                   ; Load character
    cmp al, 0                      ; Null terminator?
    je .menu_input                 ; Yes, wait for user input
    call plot                      ; Draw character
    inc si                         ; Next character
    inc dl                         ; Next column
    jmp .draw_opt3                 ; Continue loop

.menu_input:
    ; ===== MENU INPUT HANDLING =====
    ; Wait for user to press a key (blocking)
    xor ah, ah                     ; AH=0x00: blocking read keystroke
    int 0x16                       ; BIOS keyboard service (waits for key)
    ; After INT 0x16: AL = ASCII code, AH = scan code
    
    ; Check which key was pressed
    cmp ah, 0x48                   ; Scan code 0x48 = Up Arrow
    je .menu_up                    ; Move selection up
    cmp ah, 0x50                   ; Scan code 0x50 = Down Arrow
    je .menu_down                  ; Move selection down
    cmp al, 13                     ; ASCII 13 = Enter key
    je .menu_select                ; Activate selected option
    cmp al, 27                     ; ASCII 27 = ESC key
    je .menu_exit                  ; Exit to DOS
    jmp .menu_loop                 ; Unknown key, ignore and redraw

.menu_up:
    ; Move cursor up (decrease selection value)
    mov al, [menu_selection]       ; Load current selection
    cmp al, 0                      ; Already at top option?
    je .menu_loop                  ; Yes, can't go higher - ignore
    dec byte [menu_selection]      ; Decrement selection (2→1, 1→0)
    jmp .menu_loop                 ; Redraw menu with new selection

.menu_down:
    ; Move cursor down (increase selection value)
    mov al, [menu_selection]       ; Load current selection
    cmp al, 2                      ; Already at bottom option (3rd option)?
    je .menu_loop                  ; Yes, can't go lower - ignore
    inc byte [menu_selection]      ; Increment selection (0→1, 1→2)
    jmp .menu_loop                 ; Redraw menu with new selection

.menu_select:
    ; User pressed Enter - activate the selected option
    mov al, [menu_selection]       ; Load current selection
    cmp al, MENU_OPTION_1          ; Option 1 (Play Game)?
    je .start_game                 ; Yes, start the game
    cmp al, MENU_OPTION_2          ; Option 2 (How to Play)?
    je .show_howto                 ; Yes, show instructions screen
    cmp al, MENU_OPTION_3          ; Option 3 (Exit)?
    je .menu_exit                  ; Yes, exit to DOS
    jmp .menu_loop                 ; Unknown option, redraw menu

.show_howto:
    ; Display instructions screen, then return to menu
    call show_instructions         ; Show full instructions page
    jmp .menu_loop                 ; Return to menu after user presses key

.start_game:
    ; Initialize new game session
    ; Clear the entire screen
    mov ax, 0x0600                 ; AH=0x06 scroll up, AL=0x00 full clear
    mov bh, 0x07                   ; Attribute: white on black
    xor cx, cx                     ; Top-left corner (0, 0)
    mov dh, SCREEN_ROWS            ; Bottom row
    mov dl, SCREEN_COLS            ; Right column            ; Right column
    int 0x10                       ; Execute BIOS video service
    
    ; Reset game state variables for new game
    mov word [score], 0            ; Reset score to 0
    mov byte [lives], INITIAL_LIVES ; Reset lives to 3
    mov word [bricks_broken], 0    ; Reset brick counter
    
    pop dx                         ; Restore registers
    pop cx
    pop bx
    pop ax
    ret                            ; Return to main program (start game loop)

.menu_exit:
    ; Exit to DOS gracefully
    call clear_frame               ; Clean up screen
    mov ax, 0x4c00                 ; AH=0x4C terminate program, AL=0x00 return code
    int 0x21                       ; DOS service (program terminates here)

; -------------------------------------------------------------------------
; show_instructions: Display "How to Play" instructions screen
; -------------------------------------------------------------------------
; Shows game controls and objective, waits for key press
;
; Instructions Displayed:
;   - Use arrow keys to move paddle
;   - Press ESC to pause/return to menu
;   - Break all bricks to advance levels
;   - Don't let the ball fall past the paddle
;
; Modifies: Display registers
; Preserves: AX, BX, DX (saved/restored)
;
show_instructions:
    push ax                        ; Save modified registers
    push bx
    push dx
    
    ; Clear screen
    mov ax, 0x0600                 ; AH=0x06 scroll up, AL=0x00 full clear
    mov bh, 0x07                   ; Attribute: white on black
    xor cx, cx                     ; Top-left corner
    mov dh, SCREEN_ROWS            ; Bottom row
    mov dl, SCREEN_COLS            ; Right column
    int 0x10                       ; Execute BIOS video service
    
    ; Draw title "HOW TO PLAY" in bright yellow
    mov bh, MENU_TITLE_ATTR        ; Attribute: bright yellow (0x0E)
    mov dl, 30                     ; Start column (centered)
    mov dh, 3                      ; Row 3 (near top)
    mov si, str_howto_title        ; Pointer to title string
.draw_htitle:
    mov al, [si]                   ; Load character
    cmp al, 0                      ; Null terminator?
    je .draw_instructions          ; Yes, move to instruction lines
    call plot                      ; Draw character
    inc si                         ; Next character
    inc dl                         ; Next column
    jmp .draw_htitle               ; Continue loop

.draw_instructions:
    ; Draw instruction line 1
    mov bh, MENU_ATTR              ; Attribute: normal white (0x0F)
    mov dl, 20                     ; Start column (left-aligned)
    mov dh, 6                      ; Row 6
    mov si, str_inst1              ; Pointer to first instruction
.draw_i1:
    mov al, [si]                   ; Load character
    cmp al, 0                      ; Null terminator?
    je .draw_i2_setup              ; Yes, move to next line
    call plot                      ; Draw character
    inc si                         ; Next character
    inc dl                         ; Next column
    jmp .draw_i1                   ; Continue loop

.draw_i2_setup:
    ; Draw instruction line 2
    mov dl, 20                     ; Reset to left column
    mov dh, 8                      ; Row 8 (2 rows below line 1)
    mov si, str_inst2              ; Pointer to second instruction
.draw_i2:
    mov al, [si]                   ; Load character
    cmp al, 0                      ; Null terminator?
    je .draw_i3_setup              ; Yes, move to next line
    call plot                      ; Draw character
    inc si                         ; Next character
    inc dl                         ; Next column
    jmp .draw_i2                   ; Continue loop

.draw_i3_setup:
    ; Draw instruction line 3
    mov dl, 20                     ; Reset to left column
    mov dh, 10                     ; Row 10 (2 rows below line 2)
    mov si, str_inst3              ; Pointer to third instruction
.draw_i3:
    mov al, [si]                   ; Load character
    cmp al, 0                      ; Null terminator?
    je .draw_i4_setup              ; Yes, move to next line
    call plot                      ; Draw character
    inc si                         ; Next character
    inc dl                         ; Next column
    jmp .draw_i3                   ; Continue loop

.draw_i4_setup:
    ; Draw instruction line 4
    mov dl, 20                     ; Reset to left column
    mov dh, 14                     ; Row 14 (4 rows below line 3)
    mov si, str_inst4              ; Pointer to fourth instruction
.draw_i4:
    mov al, [si]                   ; Load character
    cmp al, 0                      ; Null terminator?
    je .wait_keypress              ; Yes, wait for user to exit
    call plot                      ; Draw character
    inc si                         ; Next character
    inc dl                         ; Next column
    jmp .draw_i4                   ; Continue loop

.wait_keypress:
    ; Wait for user to press any key to return to menu
    xor ah, ah                     ; AH=0x00: blocking read keystroke
    int 0x16                       ; BIOS keyboard service (blocks until key)
    
    pop dx                         ; Restore registers
    pop bx
    pop ax
    ret                            ; Return to menu

; -------------------------------------------------------------------------
; draw_bricks: Render all active bricks on screen
; -------------------------------------------------------------------------
; Iterates through brick array and draws only non-destroyed bricks
; Only draws rows up to brick_row_count (progressive difficulty)
;
; Brick Grid Layout:
;   - 8 columns (BRICK_COLS)
;   - Variable rows (brick_row_count: 2-5)
;   - Each brick is BRICK_WIDTH (9) characters wide
;   - Horizontal spacing: BRICK_BLOCK (10 chars, includes 1 space)
;   - Vertical spacing: VSPACE (1 row between rows)
;
; Brick Array: 32 bytes (8 cols × 4 rows max visible)
;   - 0 = destroyed, 1 = active
;
; Modifies: Display registers
; Preserves: AX, BX, CX, DX, SI, DI
;
draw_bricks:
    push ax                        ; Save all modified registers
    push bx
    push cx
    push dx
    push si
    push di

    xor si, si                     ; SI = brick array index (0-31)
    xor di, di                     ; DI = row counter (0, 1, 2...)
    mov bh, BRICK_ATTR             ; BH = brick attribute (bright magenta 0x0D)

.row_loop:
    ; Process one row of bricks
    xor bl, bl                     ; BL = column counter (0-7)
    
.brick_loop:
    ; Check if current brick is destroyed
    mov al, [bricks + si]          ; Load brick state from array    bricks: 1 1 1 1 0 1 1 1 1 1 1 1
    cmp al, 0                      ; Is it destroyed (0)?
    je .skip_brick                 ; Yes, skip rendering
    
    ; Calculate brick Y position: START_Y + row × (HEIGHT + VSPACE)
    ; HEIGHT = 1, VSPACE = 1, so formula: START_Y + row × 2
    mov dh, BRICK_START_Y          ; DH = starting Y (row 3)
    mov ax, di                     ; AX = current row number
    mov cl, 1 + BRICK_VSPACE       ; CL = row height + spacing = 2
    mul cl                         ; AX = row × 2
    add dh, al                     ; DH = Y position (3, 5, 7, 9...)
    ; ROWS
    
    ; Calculate brick X position: START_X + col × BRICK_BLOCK
    ; BRICK_BLOCK = 10 (9 chars width + 1 space)
    mov ax, bx                     ; AX = current column (BL)
    and ax, 0xFF                   ; Zero-extend BL to 16-bit AX
    mov cl, BRICK_BLOCK            ; CL = block width (10)
    mul cl                         ; AX = col × 10
    mov dl, BRICK_START_X          ; DL = starting X (column 1)
    add dl, al                     ; DL = X position (1, 11, 21, 31...)
    ; COLUMNS
    
    ; Draw brick as a horizontal line of characters
    push bx                        ; Save column counter
    mov cx, BRICK_WIDTH            ; CX = brick width (9 characters)
.draw_width:
    mov al, BRICK_CHAR             ; AL = brick character (solid block 0xDB)
    call plot                      ; Draw one character at (DL, DH)
    inc dl                         ; Move cursor right
    loop .draw_width               ; Repeat CX times (9 chars)
    pop bx                         ; Restore column counter

.skip_brick:
    ; Move to next brick in array
    inc si                         ; Increment brick array index
    inc bl                         ; Increment column counter
    cmp bl, BRICK_COLS             ; Processed all 8 columns?
    jb .brick_loop                 ; No, continue with next column
    
    ; End of row reached, prepare for next row
    add bh, 1b                     ; Change color attribute for visual variety
    inc di                         ; Increment row counter
    cmp di, word [brick_row_count] ; Processed all active rows?
    jb .row_loop                   ; No, continue with next row

    ; All bricks drawn, restore registers and return
    pop di                         ; Restore all registers
    pop si
    pop dx
    pop cx
    pop bx
    pop ax
    ret                            ; Return to caller

; -------------------------------------------------------------------------
; check_brick_collision: Detect and handle ball-brick collision
; -------------------------------------------------------------------------
; Checks if ball is currently overlapping any active brick
; If collision detected:
;   - Marks brick as destroyed (bricks[index] = 0)
;   - Reverses ball vertical velocity (bounce)
;   - Increments score and brick counter
;   - Plays brick hit sound
;
; Collision Detection Algorithm:
;   1. Convert ball Y to brick row: (ball_y - START_Y) ÷ 2
;   2. Convert ball X to brick column: (ball_x - START_X) ÷ 10
;   3. Check if position is within active brick bounds
;   4. Calculate array index: row × 8 + col
;   5. Check if brick exists at that index
;
; Modifies: bricks array, ball_dy, score, bricks_broken
; Preserves: AX, BX, CX, DX, SI
;
check_brick_collision:
    push ax                        ; Save all modified registers
    push bx
    push cx
    push dx
    push si

    ; ===== STEP 1: Calculate which brick ROW the ball is in =====
    ; Formula: row = (ball_y - START_Y) ÷ (1 + VSPACE)
    ; VSPACE = 1, so: row = (ball_y - 3) ÷ 2
    mov al, [ball_y]               ; AL = ball Y position
    sub al, BRICK_START_Y          ; AL = ball_y - 3 (relative to brick grid)
    jb near .no_hit                ; If negative, ball is above brick area
    xor ah, ah                     ; Zero-extend AL to 16-bit AX
    mov bl, 1 + BRICK_VSPACE       ; BL = row height + gap = 2
    div bl                         ; AL = row number, AH = remainder (position within row)
    
    ; Check if row is within active brick range
    cmp al, byte [brick_row_count] ; Is row >= active row count?
    jae .no_hit                    ; Yes, ball below brick area
    
    ; Check if ball is in vertical gap between rows
    cmp ah, 1                      ; Is remainder > 1? (in gap)
    ja .no_hit                     ; Yes, ball between rows
    
    mov cl, al                     ; Save row number in CL

    ; ===== STEP 2: Calculate which brick COLUMN the ball is in =====
    ; Formula: col = (ball_x - START_X) ÷ BRICK_BLOCK
    ; BRICK_BLOCK = 10 (9 chars width + 1 space)
    mov al, [ball_x]               ; AL = ball X position
    sub al, BRICK_START_X          ; AL = ball_x - 1 (relative to brick grid)
    jb .no_hit                     ; If negative, ball left of brick area
    xor ah, ah                     ; Zero-extend AL to 16-bit AX
    mov bl, BRICK_BLOCK            ; BL = brick block width = 10
    div bl                         ; AL = column number, AH = remainder (position within block)
    
    ; Check if column is within brick grid bounds
    cmp al, BRICK_COLS             ;                                                                                                                                                                                                                                                                                        
    jae .no_hit                    ; Yes, ball right of brick area
    
    ; Check if ball is in horizontal gap between bricks
    cmp ah, BRICK_WIDTH            ; Is remainder >= 9? (in gap)
    jae .no_hit                    ; Yes, ball between bricks

    ; ===== STEP 3: Calculate brick array index =====
    ; Formula: index = row × BRICK_COLS + col
    ; Example: row=1, col=3 -> index = 1×8 + 3 = 11
    mov bl, al                     ; BL = column number (save it)
    mov al, cl                     ; AL = row number (from CL)
    xor ah, ah                     ; Zero-extend AL to 16-bit AX
    mov cl, BRICK_COLS             ; CL = 8 (columns per row)
    mul cl                         ; AX = row × 8
    add al, bl                     ; AL = row×8 + col (brick index)
    
    ; ===== STEP 4: Check if brick exists at this position =====
    mov si, ax                     ; SI = brick index
    and si, 0xFF                   ; Ensure SI is 8-bit value (0-31)
    mov al, [bricks + si]          ; Load brick state from array
    cmp al, 0                      ; Is brick already destroyed?
    je .no_hit                     ; Yes, no collision

    ; ===== COLLISION CONFIRMED! =====
    ; Ball hit an active brick, now handle the collision
    mov byte [bricks + si], 0      ; Mark brick as destroyed (0)
    inc word [score]               ; Increment player score
    inc word [bricks_broken]       ; Increment level brick counter
    call sound_brick_hit           ; Play brick hit sound effect
    
    ; Reverse ball vertical direction (bounce off brick)
    mov al, [ball_dy]              ; Load current Y velocity
    neg al                         ; Reverse it (1 becomes -1, -1 becomes 1)
    mov [ball_dy], al              ; Store new Y velocity

    ; ===== Erase brick from screen (draw spaces over it) =====
    ; Convert array index back to row/col for screen position
    mov ax, si                     ; AX = brick index
    xor dx, dx                     ; Clear DX for division
    mov bl, BRICK_COLS             ; BL = 8 (divisor)
    div bl                         ; AL = row, AH = col
    
    ; Recalculate brick screen Y position
    mov dh, BRICK_START_Y          ; DH = starting Y (row 3)
    mov bl, al                     ; BL = row number
    mov al, bl                     ; AL = row number (copy)
    mov cl, 1 + BRICK_VSPACE       ; CL = row spacing (2)
    mul cl                         ; AX = row × 2
    add dh, al                     ; DH = Y position
    
    ; Recalculate brick screen X position
    mov al, ah                     ; AL = column number (from remainder)
    xor ah, ah                     ; Zero-extend AL to 16-bit AX
    mov cl, BRICK_BLOCK            ; CL = block width (10)
    mul cl                         ; AX = col × 10
    mov dl, BRICK_START_X          ; DL = starting X (column 1)
    add dl, al                     ; DL = X position
    
    ; Draw spaces over the destroyed brick (erase it)
    mov bh, 0x07                   ; Attribute: white on black
    push cx                        ; Save CX (contains row spacing)
    mov cx, BRICK_WIDTH            ; CX = brick width (9 characters)
.erase_loop:
    mov al, ' '                    ; AL = space character
    call plot                      ; Draw space at (DL, DH)
    inc dl                         ; Move cursor right
    loop .erase_loop               ; Repeat CX times (9 spaces)
    pop cx                         ; Restore CX

.no_hit:
    ; No collision detected, restore registers and return
    pop si                         ; Restore all registers
    pop dx
    pop cx
    pop bx
    pop ax
    ret                            ; Return to caller

; -------------------------------------------------------------------------
; clear_frame: Clear entire screen using BIOS
; -------------------------------------------------------------------------
; Utility function to clear screen with white-on-black attribute
;
; Uses: BIOS INT 0x10 AH=0x06 (scroll window)
; Preserves: All registers
;
clear_frame:
    push ax                        ; Save all modified registers
    push bx
    push cx
    push dx
    
    mov ax, 0x0600                 ; AH=0x06 scroll up, AL=0x00 full clear
    mov bh, 0x07                   ; Attribute: white on black
    xor cx, cx                     ; Top-left corner (row 0, col 0)
    mov dh, SCREEN_ROWS            ; Bottom row (24)
    mov dl, SCREEN_COLS            ; Right column (79)
    int 0x10                       ; Execute BIOS video service
    
    pop dx                         ; Restore all registers
    pop cx
    pop bx
    pop ax
    ret                            ; Return to caller

; -------------------------------------------------------------------------
; reset_bricks: Initialize brick array for new level
; -------------------------------------------------------------------------
; Resets first N bricks to active (1), where N = brick_target
; Used when starting new level after clearing previous one
;
; Algorithm: Set bricks[0..brick_target-1] = 1 (active)
; Remaining bricks stay 0 (destroyed/unused)
;
; Modifies: bricks array
; Preserves: BX (saved/restored)
;
reset_bricks:
    push bx                        ; Save BX register
    xor bx, bx                     ; BX = brick index (start at 0)
.reset_loop:
    ; Safety check: don't exceed brick array bounds
    cmp bx, BRICK_MAX_COUNT        ; Is index >= 32 (max bricks)?
    jae .reset_done                ; Yes, stop (safety limit)
    
    mov byte [bricks + bx], 1      ; Set brick to active (1)
    inc bx                         ; Increment brick index
    
    ; Check if we've reset enough bricks for this level
    cmp bx, word [brick_target]    ; Have we reset brick_target bricks?
    jb .reset_loop                 ; No, continue loop
.reset_done:
    pop bx                         ; Restore BX
    ret                            ; Return to caller

; -------------------------------------------------------------------------
; plot: Draw single character at screen position using BIOS
; -------------------------------------------------------------------------
; Draws character with specified attribute at cursor position
;
; Parameters:
;   AL = character to draw (ASCII)
;   BH = attribute byte (bgnd[3bits] + fgnd[4bits])
;   DL = column (X position, 0-79)
;   DH = row (Y position, 0-24)
;
; Uses: BIOS INT 0x10
;   - AH=0x02: Set cursor position
;   - AH=0x09: Write character with attribute
;
; Preserves: All registers
;
plot:
    push ax                        ; Save all registers
    push bx
    push cx
    push dx
    
    ; ===== Set cursor position to (DL, DH) =====
    push ax                        ; Save character (AL) and attribute (BH)
    push bx
    mov ah, 0x02                   ; BIOS function: Set cursor position
    xor bh, bh                     ; BH = page number (0 = active page)
    int 0x10                       ; Execute BIOS video service
    ; Cursor now at (DL, DH)
    
    ; ===== Write character at cursor with attribute =====
    pop bx                         ; Restore BX (contains attribute in BH)
    pop ax                         ; Restore AX (contains character in AL)
    mov bl, bh                     ; BL = attribute (move from BH to BL)
    mov bh, 0                      ; BH = page number (0)
    mov cx, 1                      ; CX = repetition count (1 = single char)
    mov ah, 0x09                   ; BIOS function: Write char with attribute
    int 0x10                       ; Execute BIOS video service
    ; Character now visible at (DL, DH) with color BL
    
    pop dx                         ; Restore all registers
    pop cx
    pop bx
    pop ax
    ret                            ; Return to caller

; -------------------------------------------------------------------------
; display_number: Convert 16-bit number to decimal and display
; -------------------------------------------------------------------------
; Converts unsigned integer in AX to ASCII decimal digits
; Displays each digit at current cursor position (DL, DH)
; Cursor advances right with each digit
;
; Algorithm: Repeated division by 10
;   1. Divide AX by 10: quotient in AL, remainder in AH
;   2. Push remainder (digit) onto stack
;   3. Repeat until quotient is 0
;   4. Pop digits and display in correct order
;
; Parameters:
;   AX = number to display (0-65535)
;   DL = starting column
;   DH = row
;   BH = attribute (from caller context)
;
; Returns:
;   CX = number of digits displayed
;   DL = final column (starting + digit count)
;
; Preserves: AX, BX (saved/restored)
;
display_number:
    push ax                        ; Save modified registers
    push bx
    push cx
    
    xor cx, cx                     ; CX = digit counter (0)
    cmp ax, 0                      ; Special case: is number 0?
    jne .dn_push                   ; No, use normal algorithm
    
    ; Handle zero: push single 0 digit
    push ax                        ; Push 0 onto stack
    inc cx                         ; Digit count = 1
    jmp .dn_pop                    ; Skip to display
    
.dn_push:
    ; Decompose number into digits using repeated division
    cmp al, 0                      ; Is quotient 0? (all digits extracted)
    je .dn_pop                     ; Yes, start displaying
    
    xor ah, ah                     ; Zero-extend AL to 16-bit AX
    mov bl, 10                     ; Divisor = 10
    div bl                         ; AL = AX ÷ 10 (quotient), AH = AX mod 10 (digit)
    push ax                        ; Save quotient (AL) and digit (AH)
    xor ah, ah                     ; Clear AH for next iteration
    inc cx                         ; Increment digit count
    jmp .dn_push                   ; Continue with quotient
    
.dn_pop:
    ; Display digits in correct order (most significant first)
    cmp cx, 0                      ; Any digits left to display?
    je .dn_done                    ; No, finished
    
    pop ax                         ; Restore digit (in AH) and quotient (in AL)
    mov al, ah                     ; AL = digit value (0-9)
    add al, '0'                    ; Convert to ASCII ('0'-'9')
    call plot                      ; Draw digit at (DL, DH)
    inc dl                         ; Move cursor right
    dec cx                         ; Decrement digit counter
    jmp .dn_pop                    ; Continue with next digit
    
.dn_done:
    pop cx                         ; Restore registers
    pop bx
    pop ax
    ret                            ; Return to caller

; -------------------------------------------------------------------------
; wait_tick: Wait for one BIOS timer tick (~55ms)
; -------------------------------------------------------------------------
; Polls BIOS timer until it advances by one tick
; Used for frame rate control (18.2 ticks per second = 18 FPS)
;
; Uses: BIOS INT 0x1A (time of day)
;   - AH=0x00: Get system timer count
;   - Returns: CX:DX = tick count (DX = low word)
;
; Preserves: All registers
;
wait_tick:
    push ax                        ; Save modified registers
    push bx
    push cx
    push dx
    
    mov ah, 0                      ; AH=0x00: Get system timer count
    int 1Ah                        ; BIOS time service
    ; Returns: DX = low word of tick count
    mov bx, dx                     ; BX = starting tick count
    
.wt_loop:
    ; Poll timer until it changes
    mov ah, 0                      ; AH=0x00: Get system timer count
    int 1Ah                        ; BIOS time service
    cmp dx, bx                     ; Has tick count changed?
    je .wt_loop                    ; No, keep waiting
    ; Yes, one tick has elapsed (~55ms passed)
    
    pop dx                         ; Restore all registers
    pop cx
    pop bx
    pop ax
    ret                            ; Return to caller

; -------------------------------------------------------------------------
; reboot: Return to main menu (game restart)
; -------------------------------------------------------------------------
; Clears screen, resets brick array, and returns to menu
; Called when user wants to restart or return to menu
;
; Modifies: Screen, bricks array
;
reboot:
    call clear_frame               ; Clear entire screen
    call reset_bricks              ; Reset brick array to initial state
    jmp start                      ; Jump back to main menu


; =========================================================================
; ===== SOUND EFFECTS (PC Speaker) =====
; =========================================================================
; All sound functions use PC speaker via Programmable Interval Timer (PIT)
;
; PC Speaker Control:
;   Port 0x43: PIT command register
;   Port 0x42: PIT channel 2 data (frequency divisor)
;   Port 0x61: PC speaker gate (bit 0 = timer gate, bit 1 = speaker enable)
;
; Frequency calculation: freq_hz = 1193180 / divisor
;   Example: divisor = 800 -> freq = 1491 Hz (high pitch)
;            divisor = 1500 -> freq = 795 Hz (low pitch)
;

; -------------------------------------------------------------------------
; sound_brick_hit: Play high-pitched beep (brick destroyed)
; -------------------------------------------------------------------------
; Short, high-frequency tone to indicate successful brick hit
;
; Frequency: ~1491 Hz (divisor 800)
; Duration: ~10ms (hardware delay loop)
;
; Preserves: All registers
;
sound_brick_hit:
    push ax                        ; Save modified registers
    push bx
    push cx
    
    ; Configure PIT channel 2 for square wave output
    mov al, 0xB6                   ; Command: channel 2, square wave, binary mode
    out 0x43, al                   ; Send to PIT command register
    
    ; Set frequency divisor (high pitch)
    mov ax, 800                    ; Divisor = 800 (freq ~ 1491 Hz)
    out 0x42, al                   ; Send low byte to channel 2
    mov al, ah                     ; AL = high byte of divisor
    out 0x42, al                   ; Send high byte to channel 2
    
    ; Enable PC speaker
    in al, 0x61                    ; Read current speaker port state
    or al, 0x03                    ; Set bits 0-1 (enable timer gate + speaker)
    out 0x61, al                   ; Activate speaker
    
    ; Sound duration delay (~10ms)
    mov cx, 0x1000                 ; Delay counter (4096 iterations)
.brick_delay:
    loop .brick_delay              ; Busy-wait loop
    
    ; Disable PC speaker
    in al, 0x61                    ; Read speaker port state
    and al, 0xFC                   ; Clear bits 0-1 (disable speaker)
    out 0x61, al                   ; Silence speaker
    
    pop cx                         ; Restore registers
    pop bx
    pop ax
    ret                            ; Return to caller

; -------------------------------------------------------------------------
; sound_paddle_hit: Play medium-pitched beep (ball bounces off paddle)
; -------------------------------------------------------------------------
; Medium-frequency tone to indicate paddle collision
;
; Frequency: ~994 Hz (divisor 1200)
; Duration: ~15ms (hardware delay loop)
;
; Preserves: All registers
;
sound_paddle_hit:
    push ax                        ; Save modified registers
    push bx
    push cx
    
    ; Configure PIT channel 2
    mov al, 0xB6                   ; Command: channel 2, square wave
    out 0x43, al                   ; Send to PIT command register
    
    ; Set frequency divisor (medium pitch)
    mov ax, 1200                   ; Divisor = 1200 (freq ~ 994 Hz)
    out 0x42, al                   ; Send low byte
    mov al, ah                     ; AL = high byte
    out 0x42, al                   ; Send high byte
    
    ; Enable PC speaker
    in al, 0x61                    ; Read speaker port
    or al, 0x03                    ; Enable timer gate + speaker
    out 0x61, al                   ; Activate speaker
    
    ; Sound duration delay (~15ms)
    mov cx, 0x1800                 ; Delay counter (6144 iterations)
.paddle_delay:
    loop .paddle_delay             ; Busy-wait loop
    
    ; Disable PC speaker
    in al, 0x61                    ; Read speaker port
    and al, 0xFC                   ; Disable speaker
    out 0x61, al                   ; Silence speaker
    
    pop cx                         ; Restore registers
    pop bx
    pop ax
    ret                            ; Return to caller

; -------------------------------------------------------------------------
; sound_life_lost: Play low-pitched beep (player loses a life)
; -------------------------------------------------------------------------
; Low-frequency tone to indicate negative event (life lost)
;
; Frequency: ~596 Hz (divisor 2000)
; Duration: ~20ms (hardware delay loop)
;
; Preserves: All registers
;
sound_life_lost:
    push ax                        ; Save modified registers
    push bx
    push cx
    
    ; Configure PIT channel 2
    mov al, 0xB6                   ; Command: channel 2, square wave
    out 0x43, al                   ; Send to PIT command register
    
    ; Set frequency divisor (low pitch)
    mov ax, 2000                   ; Divisor = 2000 (freq ~ 596 Hz)
    out 0x42, al                   ; Send low byte
    mov al, ah                     ; AL = high byte
    out 0x42, al                   ; Send high byte
    
    ; Enable PC speaker
    in al, 0x61                    ; Read speaker port
    or al, 0x03                    ; Enable timer gate + speaker
    out 0x61, al                   ; Activate speaker
    
    ; Sound duration delay (~40ms - longest/saddest sound)
    mov cx, 0x4000                 ; Delay counter (16384 iterations)
.lost_delay:
    loop .lost_delay               ; Busy-wait loop
    
    ; Disable PC speaker
    in al, 0x61                    ; Read speaker port
    and al, 0xFC                   ; Disable speaker
    out 0x61, al                   ; Silence speaker
    
    pop cx                         ; Restore registers
    pop bx
    pop ax
    ret                            ; Return to caller


; =========================================================================
; ===== DATA SECTION =====
; =========================================================================
; All game state variables and strings
;

; ----- Ball State Variables -----
ball_x  db 0                       ; Ball X position (0-79 columns)
ball_y  db 0                       ; Ball Y position (0-24 rows)
ball_dx db 0                       ; Horizontal velocity (-1=left, +1=right)
ball_dy db 0                       ; Vertical velocity (-1=up, +1=down)
ball_speed db 1                    ; Speed multiplier (currently unused, kept for future)

; ----- Brick State Variables -----
bricks times BRICK_MAX_COUNT db 1  ; Brick array: 32 bytes (1=active, 0=destroyed)
brick_row_count dw BRICK_ROWS      ; Current level's brick row count (2, 3, 4, or 5)
brick_target dw 0                  ; Total bricks needed to complete current level

; ----- Game State Variables -----
paddle_x db 0                      ; Paddle center X position (7-72, safe zone)7-72, safe zone)
score dw 0                         ; Total score (accumulated across all levels)
lives db 0                         ; Remaining lives (0-3, starts at 3)
bricks_broken dw 0                 ; Bricks destroyed in current level only

; ----- Menu State Variables -----
menu_selection db 0                ; Current menu option (0=Play, 1=Instructions, 2=Exit)

; ----- String Constants -----
; Menu screen strings
str_title       db 'ATARI BREAKOUT', 0
str_play        db '1. Play Game', 0
str_howto       db '2. How to Play', 0
str_exit        db '3. Exit', 0

; Instructions screen strings
str_howto_title db 'HOW TO PLAY', 0
str_inst1       db 'Use A/<- and D/-> keys to move the paddle', 0
str_inst2       db 'Break all bricks to win!', 0
str_inst3       db 'Press ESC to exit during game', 0
str_inst4       db 'Press any key to return to menu...', 0

; In-game UI strings
str_score       db 'Score:', 0     ; Bottom-left status
str_lives       db 'Lives:', 0     ; Bottom-right status
str_level       db 'Level:', 0     ; Bottom-center status

; Game over screen strings
str_end         db 'GAME OVER!', 0 ; Used for both win and lose
str_final_score db 'Final Score: ', 0
str_press_key   db 'Press any key to continue...', 0
