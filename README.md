
# SNK68000 The Next Space FPGA Implementation — NextSpaceMD

FPGA compatible core of SNK's The Next Space (A8004 based) arcade hardware for [**MiSTerFPGA**](https://github.com/MiSTer-devel/Main_MiSTer/wiki) written by **Erin Olafson** and verified against and authentic The Next Space (A8004-1) PCB purchased by [**atrac17**](https://github.com/atrac17). Maintenance and miscellaneous quality of life features (NextSpaceMD) added by TheJesusfish.

The intent is for this core to be a 1:1 playable implementation of The Next Space (A8004-1) arcade hardware. Currently in **beta state**, this core is in active development with assistance from [**atrac17**](https://github.com/atrac17).

<br>
<p align="center">
<img width="" height="" src="https://user-images.githubusercontent.com/32810066/227825179-40535bb2-fe8c-45e2-a56c-05523264c98c.png">
</p>

## Supported Games

| Title | PCB<br>Number | Status  | Released | MAME 0.288 sets |
|-------|---------------|---------|----------|-----------------|
| [**The Next Space**](https://snk.fandom.com/wiki/The_Next_Space) | A8004-1 (TNS)      | Implemented | **Yes** | **tnextspc, tnextspc2, tnextspcj** |
| [**Paddle Mania**](https://snk.fandom.com/wiki/Paddle_Mania)     | ALPHA68K-96-I (PM) | Implemented | **Yes** | **paddlema** |

Not supported: the Alpha 68k N board games (Super Stingray, Kyros / Kyros no Yakata, Mahjong Block Jongbou, Jongbou 2) use different graphics, sound and MCU hardware.

## External Modules

|Name| Purpose | Author |
|----|---------|--------|
| [**fx68k**](https://github.com/ijor/fx68k) @ `0602ee4`                                                         | [**Motorola 68000 CPU**](https://en.wikipedia.org/wiki/Motorola_68000) | Jorge Cwik |
| [**T80**](https://github.com/MiSTer-devel/NeoGeo_MiSTer/tree/master/rtl/cpu/T80) (NeoGeo_MiSTer `rtl/cpu/T80` @ `90a8350`) | [**Zilog Z80 CPU**](https://en.wikipedia.org/wiki/Zilog_Z80) | Daniel Wallner / MikeJ / Sorgelig |
| [**jtopl**](https://github.com/jotego/jtopl) @ `f96ff3e`                                                      | [**Yamaha OPL 2**](https://en.wikipedia.org/wiki/Yamaha_OPL#OPL2)      | Jose Tejada |
| [**Template_MiSTer sys/**](https://github.com/MiSTer-devel/Template_MiSTer) @ `e901a9f` (incl. yc_out)        | MiSTer framework                                                       | MiSTer-devel |
| [**Arcade-TaitoF2_MiSTer**](https://github.com/MiSTer-devel/Arcade-TaitoF2_MiSTer) @ `9438df9` save-state code (`rtl/savestate/`: ddram, memory_stream, savestates, savestate_ui) | Save states | Martin Donlon |
| [**Pause_MiSTer**](https://github.com/JimmyStones/Pause_MiSTer) (`rtl/pause.v`, va7deo modified)              | Pause handling                                                          | Jim Gregory |

The save-state controller (`rtl/nextspace_ss.sv`) follows the TaitoF2 design; the high-score keeper (`rtl/hiscore.sv`) follows the Arcade-RaizingMD_MiSTer / Arcade-IGSPGM_MiSTer NVRAM flow and uses MAME's `hiscore.dat`.

# Known Issues / Tasks

- Verify video timings for A8004-1 by measuring PCB [Task]  

# PCB Check List

### Clock Information

H-Sync      | V-Sync      | Source                  | PCB<br>Number  |
------------|-------------|-------------------------|----------------|
15.625kHz   | 59.185606Hz | [**ADALM2000**](FILLME) | A8004-1 (TNS)  |

### Crystal Oscillators

Location        | PCB<br>Number | Freq (MHz) | Use                 |
|---------------|---------------|------------|---------------------|
24MHz           | A8004-1 (TNS) | 24.000     | Video / Pixel Clock |
4MHz            | A8004-1 (TNS) | 4.000      | Z80 / YM3812        |
18MHz           | A8004-1 (TNS) | 18.000     | M68000              |
24MHz           | 68K-96-1 (PM) | 24.000     | All Components      |

**Pixel clock:** 6.00 MHz

**Estimated geometry:**

    383 pixels/line
  
    263 pixels/line

### Main Components

Location | PCB<br>Number | Chip | Use |
---------|---------------|------|-----|
15-L     | A8004-1 (TNS)  | [**Motorola 68000 CPU**](https://en.wikipedia.org/wiki/Motorola_68000) | Main CPU  |
Z80A     | A8004-1 (TNS)  | [**Zilog Z80 CPU**](https://en.wikipedia.org/wiki/Zilog_Z80)           | Sound CPU |
YM3812   | A8004-1 (TNS)  | [**Yamaha YM3812**](https://en.wikipedia.org/wiki/Yamaha_OPL#OPL2)     | OPL-2     |
68000-8  | 68K-96-1 (PM)  | [**Motorola 68000 CPU**](https://en.wikipedia.org/wiki/Motorola_68000) | Main CPU  |
Z80A     | 68K-96-1 (PM)  | [**Zilog Z80 CPU**](https://en.wikipedia.org/wiki/Zilog_Z80)           | Sound CPU |
20 Y3812 | 68K-96-1 (PM)  | [**Yamaha YM3812**](https://en.wikipedia.org/wiki/Yamaha_OPL#OPL2)     | OPL-2     |

### Custom Components

Location | PCB<br>Number | Chip | Use |
---------|---------------|------|-----|
SNKCLK   | A8004-1 (TNS) | [**SNK CLK**](https://github.com/va7deo/alpha68k/blob/main/doc/ALPHA-68K96V/ALPHA68K-96V_Schematics.pdf)        | Counter |
SNK I/O  | A8004-1 (TNS) | [**SNK I/O**](https://github.com/va7deo/SNK68/blob/main/doc/Custom%20Components/SNK_IO.jpg)                     | Input Handling |
INPUT 87 | 68K-96-1 (PM) | [**ALPHA-INPUT 87**](https://github.com/va7deo/alpha68k/blob/main/doc/ALPHA-68K96V/ALPHA68K-96V_Schematics.pdf) | Input Handling |

# Core Features

### Native Y/C Output

- Native Y/C ouput is possible with the [**analog I/O rev 6.1 pcb**](https://github.com/MiSTer-devel/Main_MiSTer/wiki/IO-Board). Using the following cables, [**HD-15 to BNC cable**](https://www.amazon.com/StarTech-com-Coax-RGBHV-Monitor-Cable/dp/B0033AF5Y0/) will transmit Y/C over the green and red lines. Choose an appropriate adapter to feed [**Y/C (S-Video)**](https://www.amazon.com/MEIRIYFA-Splitter-Extension-Monitors-Transmission/dp/B09N19XZJQ) to your display.

### H/V Adjustments

- There are two H/V toggles, H/V-sync positioning adjust and H/V-sync width adjust. Positioning will move the display for centering on CRT display. The sync width adjust can be used to for sync issues (rolling) without modifying the video timings.

- Every position and width value (-8 to +7) keeps exactly one sync pulse per line and per frame; negative values move the pulse earlier / make it shorter, and the V-sync pulse is at least one line long.

### Orientation

- Both games are vertical and start rotated on HDMI (Video Settings, Orientation: Vert). Orientation: Horz outputs the original horizontal raster. The analog output is always the original raster.

- The Next Space's Flip Screen DIP turns the picture by 180 degrees in the core's own raster, so it works on the analog and HDMI outputs.

### Save States

- Four save-state slots. On the controller: hold **L**, then **Down** saves, **Up** restores, **Left / Right** changes the slot. On the keyboard: **Alt+F1** saves, **F1** restores the selected slot. The OSD has Savestate Slot, Autoincrement Slot, Save state and Restore state.

- A save always goes to the slot that was selected when it started. With **Autoincrement Slot** On, the next slot is selected once the save has finished.

- Restoring a slot that holds no save (or an incomplete one) leaves the game running and shows "No save in this slot". A save cut short by a reset leaves its slot empty until the next save; the slot's file on the SD card keeps the previous save.

### High Scores

- High scores are kept with MAME's `hiscore.dat` entries. With **Autosave Hiscores** On (default) the table is saved to `config/nvram` whenever the OSD is opened; **Save Hiscores** saves it at once. The saved table is restored once the game has set up its own table.

### DIP Switches

- DIP switches follow MAME 0.288 (names shortened only where an OSD row would overflow). Changing a DIP in the OSD does not reset the game; it applies at **Reset to apply** (or any reset).

- The Next Space: switches SW2:3 and SW2:4 are one OSD entry, **Game Mode**, because SW2:4 selects what SW2:3 does. Its four settings are what the board does: **Demo Sounds Off**, **Demo Sounds On** (default), **Freeze** and **Inf Lives (Cheat)**.

### Scandoubler Options

- Additional toggle to enable the scandoubler without changing ini settings and new scanline option for 100% is available, this draws a black line every other frame. Below is an example.

<table><tr><th>Scandoubler Fx</th><th>Scanlines 25%</th><th>Scanlines 50%</th><th>Scanlines 75%</th><th>Scanlines 100%</th><tr><td><br> <p align="center"><img width="112" height="128" src="https://user-images.githubusercontent.com/32810066/228109742-163427e8-bc8e-4bb4-81da-0d1935d679b6.png"></td><td><br> <p align="center"><img width="112" height="128" src="https://user-images.githubusercontent.com/32810066/228109798-6d96e076-b57a-456a-a041-49d8e53a0662.png"></td><td><br> <p align="center"><img width="112" height="128" src="https://user-images.githubusercontent.com/32810066/228109835-7b97b5b1-dea3-477e-b889-a8e81a36a0e1.png"></td><td><br> <p align="center"><img width="112" height="128" src="https://user-images.githubusercontent.com/32810066/228109870-a2f23677-0e22-462a-8881-27f0d8c97812.png"></td><td><br> <p align="center"><img width="112" height="128" src="https://user-images.githubusercontent.com/32810066/228109912-48502df2-9e54-4ff8-a1f8-45680026ecb1.png"></td></tr></table>

# Controls

- The service menu is accessed by toggling a dipswitch for supported titles. Paddle Mania has a test switch that can be toggled with F2, it does not enter the test menu and toggling the dipswitch is required.

- Paddle Mania supports co-op two player, two player versus the CPU opponents or a third and up to four player versus. 1P Start is referenced as the "A" button, 2P Start is "B" button. These are referenced in Paddle Mania's test menu.

- Each controller drives its own player: controller 1 Start / Coin = 1P Start / Coin A, controller 2 Start / Coin = 2P Start / Coin B, and all player 2 controls come from controller 2. Paddle Mania players 3 and 4 use controllers 3 and 4 (the board has no player 3 / 4 start or coin).

- Default controller buttons (button names from the games' instruction cards):

|Game|A|B|Start|Select|R|L|
|--|--|--|--|--|--|--|
|The Next Space|Shot|Item Shot|Start|Coin|Pause|Save States|
|Paddle Mania|Left Swing|Right Swing|Start|Coin|Pause|Save States|

- Neither game uses button combinations in play. Paddle Mania's I/O test (service menu) exits with **A + B**.

- Saved button maps from the original core (NextSpace) or with other bit layouts must be redefined (OSD Define Buttons).

<br>

<table><tr><th>Game</th><th>Joystick</th><th>Service Menu</th><th>Control Type</th></tr><tr><td><p align="center">The Next Space</p></td><td><p align="center">8-Way</p></td><td><p align="center"><br><img width="112" height="128" src="https://user-images.githubusercontent.com/32810066/228088913-2c313dd3-281c-40c9-ad02-b3513f95ea31.png"></td><td><p align="center">Co-Op</td><tr><td><p align="center">Paddle<br>Mania</p></td><td><p align="center">8-Way</p></td><td><p align="center"><br><img width="112" height="128" src="https://user-images.githubusercontent.com/32810066/228088968-9cd95d72-c22f-44c6-9511-d89564bda02e.png"></td><td><p align="center">Co-Op / VS</td></table>

<br>
<br>

### Keyboard Handler

- Keyboard inputs mapped to mame defaults for the following functions. Player 3 and Player 4 input keys are mapped to [**MAME**](https://docs.mamedev.org/usingmame/defaultkeys.html#player-4-controls) standards.

<br>

|Services|Coin/Start|
|--|--|
|<table> <tr><th>Functions</th><th>Keymap</th></tr><tr><td>Test</td><td>F2</td></tr><tr><td>Reset</td><td>F3</td></tr><tr><td>Service</td><td>9</td></tr><tr><td>Pause</td><td>P</td></tr> </table> | <table><tr><th>Functions</th><th>Keymap</th><tr><tr><td>P1 Start</td><td>1</td></tr><tr><td>P2 Start</td><td>2</td></tr><tr><td>P1 Coin</td><td>5</td></tr><tr><td>P2 Coin</td><td>6</td></tr> </table>|

|Player 1|Player 2|
|--|--|
|<table> <tr><th>Functions</th><th>Keymap</th></tr><tr><td>P1 Up</td><td>Up</td></tr><tr><td>P1 Down</td><td>Down</td></tr><tr><td>P1 Left</td><td>Left</td></tr><tr><td>P1 Right</td><td>Right</td></tr><tr><td>P1 Bttn 1</td><td>L-Ctrl</td></tr><tr><td>P1 Bttn 2</td><td>L-Alt</td></tr><tr><td>P1 Bttn 3</td><td>Space</td></tr> </table> | <table> <tr><th>Functions</th><th>Keymap</th></tr><tr><td>P2 Up</td><td>R</td></tr><tr><td>P2 Down</td><td>F</td></tr><tr><td>P2 Left</td><td>D</td></tr><tr><td>P2 Right</td><td>G</td></tr><tr><td>P2 Bttn 1</td><td>A</td></tr><tr><td>P2 Bttn 2</td><td>S</td></tr><tr><td>P2 Bttn 3</td><td>Q</td></tr> </table>|

|Player 3|Player 4<br>(Numeric Keys)|
|--|--|
|<table> <tr><th>Functions</th><th>Keymap</th></tr><tr><td>P3 Up</td><td>I</td></tr><tr><td>P3 Down</td><td>K</td></tr><tr><td>P3 Left</td><td>J</td></tr><tr><td>P3 Right</td><td>L</td></tr><tr><td>P3 Bttn 1</td><td>R-Ctrl</td></tr><tr><td>P3 Bttn 2</td><td>R-Shift</td></tr> </table> | <table> <tr><th>Functions</th><th>Keymap</th></tr><tr><td>P4 Up</td><td>8</td></tr><tr><td>P4 Down</td><td>2</td></tr><tr><td>P4 Left</td><td>4</td></tr><tr><td>P4 Right</td><td>6</td></tr><tr><td>P4 Bttn 1</td><td>0</td></tr><tr><td>P4 Bttn 2</td><td>.</td></tr> </table>|

