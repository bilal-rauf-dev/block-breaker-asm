# Atari Breakout - x86 Assembly Game

A classic Atari Breakout clone written in pure x86 16-bit assembly for DOS, using only BIOS interrupts for maximum compatibility and portability.

![Game Screenshot](https://img.shields.io/badge/Platform-DOS-blue) ![Assembly](https://img.shields.io/badge/Language-x86%20Assembly-orange) ![BIOS](https://img.shields.io/badge/Graphics-BIOS%20Only-green)

<img width="1235" height="813" alt="image" src="https://github.com/user-attachments/assets/73ba3eb0-ad5b-4076-a4c5-d33bd6dd2afd" />

## 🎮 Features

- **Progressive Difficulty**: Start with 2 rows of bricks, advance through 5 levels with increasing brick counts
- **Lives System**: 3 lives per game - don't let the ball fall!
- **Score Tracking**: Accumulates across all levels
- **Sound Effects**: PC speaker sounds for brick hits, paddle bounces, and life loss
- **Interactive Menu**: Navigate with arrow keys, includes instructions screen
- **Smooth Controls**: Responsive paddle movement with arrow keys or A/D
- **Pure BIOS Implementation**: No direct video memory access - uses INT 0x10 for all graphics

## 🕹️ Controls

| Key | Action |
|-----|--------|
| `←` / `A` | Move paddle left |
| `→` / `D` | Move paddle right |
| `ESC` | Return to menu / Exit game |
| `↑` / `↓` | Navigate menu options |
| `Enter` | Select menu option |

## 🚀 How to Build & Run

### Prerequisites
- **NASM** (Netwide Assembler)
- **DOSBox** or real DOS environment

### Build
```bash
nasm -f bin project.asm -o GAME.COM
```

### Run
```bash
dosbox GAME.COM
```

Or on real DOS/FreeDOS:
```
GAME.COM
```

## 📁 Project Structure

```
project.asm          - Main game source code (~1500 lines)
GAME.COM            - Compiled executable (DOS .COM format)
README.md           - This file
```

## 🎯 Gameplay

1. **Start Game**: Launch from the main menu
2. **Break Bricks**: Use the paddle to bounce the ball and destroy all bricks
3. **Level Up**: Complete each level to advance (rows increase: 2→3→4→5)
4. **Win Condition**: Beat all 5 levels
5. **Lose Condition**: Run out of lives (ball falls past paddle)

### Scoring
- Each brick destroyed = **+1 point**
- Score persists across levels
- Final score displayed on game over screen

## 🔧 Technical Details

### Architecture
- **Format**: DOS .COM executable (org 0x0100)
- **Mode**: x86 16-bit real mode
- **Size**: ~3KB executable
- **Memory**: Single segment (code + data)

### BIOS Services Used
| Service | Function | Purpose |
|---------|----------|---------|
| `INT 0x10` | Video Services | All graphics output |
| `INT 0x16` | Keyboard Services | Input handling |
| `INT 0x1A` | Time Services | Frame timing (~18 FPS) |
| `INT 0x21` | DOS Services | Program termination |

### Graphics Implementation
- **Video Mode**: Text mode 80×25
- **Rendering**: Character-based using BIOS teletype
- **Colors**: 4-bit attribute bytes (background + foreground)
- **Frame Rate**: ~18 FPS (synchronized with BIOS timer)

### Sound Implementation
- **Hardware**: PC speaker via Programmable Interval Timer (PIT)
- **Ports**: 0x43 (command), 0x42 (frequency), 0x61 (speaker gate)
- **Frequencies**:
  - Brick hit: ~1491 Hz (high pitch)
  - Paddle bounce: ~994 Hz (medium pitch)
  - Life lost: ~596 Hz (low pitch)

## 📚 Code Structure

### Constants (Lines 16-80)
Defines all game parameters: screen size, colors, paddle/ball/brick dimensions, speeds, and positions.

### Main Loop (Lines 118-450)
- Frame rendering (paddle, ball, bricks, UI)
- Non-blocking keyboard input
- Ball physics and collision detection
- Game state management

### Subroutines (Lines 460-1400)
- `reset_ball`: Initialize ball position
- `draw_bricks`: Render brick grid with color gradients
- `check_brick_collision`: Detect and handle brick destruction
- `plot`: BIOS character output
- `display_number`: Integer to ASCII conversion
- `wait_tick`: Frame timing control
- `sound_*`: PC speaker sound effects

### Data Section (Lines 1510+)
All game state variables and string constants.

## 🎓 Educational Value

This project demonstrates:
- **Low-level programming**: Direct hardware interaction
- **BIOS interrupt usage**: Portable graphics without OS dependencies
- **Game loop architecture**: Input → Update → Render cycle
- **Collision detection**: Grid-based and bounding box algorithms
- **Assembly optimization**: Register usage, minimal memory footprint
- **Retro gaming**: Classic 1970s arcade game mechanics

Perfect for learning:
- x86 assembly language
- DOS programming
- BIOS services
- Game development fundamentals
- Hardware-level sound generation

## 🐛 Known Limitations

- Text-mode graphics only (no pixel graphics)
- Fixed 18 FPS (BIOS timer limitation)
- PC speaker sound (no sound card support)
- DOS/DOSBox only (not Windows/Linux native)

## 📝 License

This project is provided as-is for educational purposes. Feel free to modify, learn from, and share!

## 🙏 Acknowledgments

- Original Atari Breakout (1976) by Steve Wozniak
- Inspired by classic DOS game programming techniques
- Built with NASM assembler

## 📧 Contributing

Feel free to submit issues or pull requests for:
- Bug fixes
- Code optimizations
- Documentation improvements
- New features (power-ups, difficulty modes, etc.)

---

**Made with ❤️ and x86 assembly**

*For the love of retro gaming and low-level programming!*
