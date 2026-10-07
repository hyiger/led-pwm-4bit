# 4-Bit LED PWM Controller: KiCad Handoff Spec

Author: hyiger · Rev 0.3 · 2026-10-07

This is the complete brief for the KiCad project. The netlist in [`netlist.txt`](netlist.txt) is the source of truth; section 6 summarises it. Where this document and a datasheet disagree on a pin number, the datasheet wins: stop and report the conflict.

## 1. What to build

A small 2-layer board that dims a 24 V constant-voltage LED strip (about 120 mA) to one of 16 brightness levels. The level is a 4-bit word set by four open-drain outputs of a Prusa GPIO Hackerboard. An ATtiny412 reads the word and drives a low-side N-MOSFET with PWM.

```
24 V in ─ F1 ─ D1 ─┬──────────────── +24V ──── J2.1  strip +
                   ├─ C1, C2, C9                J2.2  strip − ─┐
                   └─ U1 (LDO) ─ +3V3 ─ U2 (ATtiny412)         │
Hackerboard pins 0–3 ─ J3 ─ pull-up + RC ─ U2 inputs           │
                                  U2 PA3 ─ R1 ─ gate Q1 ─ drain┘
USB-serial adapter ─ J4 ─ D3 + R11 (SerialUPDI) ─ U2 PA0/UPDI
```

The board takes only ground and four signals from the Hackerboard. It makes its own 3.3 V from the 24 V rail.

## 2. Hackerboard interface

- Pins 0–3 are open-drain N-MOSFET outputs (DMN3190LDW, 100 Ω gate resistor, 100 kΩ gate pull-down), rated by Prusa to switch 24 V at 500 mA to ground. They have no pull-ups, LEDs or clamps, so nothing on the Hackerboard can back-feed our 3.3 V pull-ups.
- Pins 4–7 are TCA6408A push-pull outputs at 3.3 V through 330 Ω (10 mA). This design does not use them.
- Logic is inverted at the wire: writing 1 turns the transistor on and pulls the pin to ground. Writing 0 leaves it floating.
- `M267 R1 B<0-255>` writes the whole output register in one I2C transaction. With the word on pins 0–3, `M267 R1 B0` to `M267 R1 B15` selects the level directly and all four bits change together. Bits 4–7 are written too.
- Run `M267 R3 B0` once so all pins are outputs (the firmware default). This also stops the 500 ms input polling that can trigger `btn_N` macros.
- Register values persist in the printer's EEPROM and are restored at boot. Until then the TCA6408A powers up with every pin as an input, so all four lines float and read as level 0.
- The Hackerboard must be connected when the printer boots; hot-plugging does not work.
- Connector: Hackerboard J6 is a 1×10 2.54 mm footprint, usually bare holes, so you will probably have to solder in a header. Its silkscreen reads `GND 7 6 5 4 3 2 1 0 GND`. Pin 1 is the square pad at the `0` end. J6 pins 1–5 carry GND, out0, out1, out2, out3 in that order and match J3 one to one.
- Out0–out2 also go to the Hackerboard's 2.5 mm "Shutter" jack. Leave that jack empty.
- Prusa's product page lists the Core One INDX as *not compatible* with the Hackerboard set, although firmware 6.9.1 and 6.10.1 still enable M262–M268 on COREONE_INDX. Check before relying on it with an INDX.

Consequence for this board: each input needs a pull-up to 3.3 V, and the firmware inverts the nibble. A disconnected or unpowered Hackerboard reads as 1111, which inverts to level 0, so the strip is off.

## 3. Electrical requirements

| Item | Requirement |
|---|---|
| Supply | 24 V DC nominal, 20–28 V operating |
| Load | Constant-voltage LED strip, 120 mA nominal; copper sized for 1 A |
| Switching | Low-side N-MOSFET, strip + tied to the protected 24 V rail |
| Levels | 16, gamma-corrected, level 0 fully off, level 15 fully on (100% duty) |
| PWM | 10-bit, about 2.44 kHz |
| Logic rail | 3.3 V from an on-board LDO, under 5 mA load |
| Default state | Strip off during reset, programming, and with inputs disconnected |
| Protection | Input fuse, reverse-polarity diode, clamp diode across the strip |
| Programming | SerialUPDI with any 3.3 V USB-serial adapter on J4, board powered from 24 V |

## 4. Circuit blocks

**Input and protection.** J1 → F1 (resettable fuse) → D1 (series Schottky, reverse-polarity protection) → `+24V`. F1 trips at 1 A, which also keeps D1 (a 1 A part) within rating. D1 protects only the board's own rail: with J3 connected to the printer, swapped J1 wires put supply + on board GND, which J3 pin 1 ties to printer ground (see section 12). C2 and C9 (4.7 µF 50 V X7R 1206 MLCCs, about 2.7 µF each at 24 V) are the bulk capacitance. C2 sits in the PWM loop beside Q1 and J2; C9 sits at U1's input. With no electrolytic, F1's resistance is the only damping of hot-plug ringing on the input; the estimated peak is 30–40 V.

**3.3 V rail.** U1 is an MCP1792-3302 (55 V input, 70 V transient, 100 mA) in SOT-23A. C1 is its input capacitor and C3 its output capacitor. All passives except C2 and C9 (1206) are 0603. The datasheet requires at least 2.2 µF of ceramic on the output and recommends 3.3 µF: C3 (10 µF 10 V X5R) keeps about 5.9 µF at 3.3 V. It recommends 2.2–10 µF on the input. No 0603 part rated 50 V holds much at 24 V: C1 (2.2 µF 50 V X5R) keeps about 0.4 µF, and C9 beside it adds about 2.7 µF. Dissipation is about (28 − 3.3) V × 5 mA ≈ 124 mW at the 28 V maximum, or 104 mW at 24 V nominal.

**MCU.** U2 is an ATtiny412 in SOIC-8, running at 10 MHz from its internal oscillator. C4 decouples it.

**Inputs.** Each of the four lines has a 10 kΩ pull-up to `+3V3` on the connector side, then 1 kΩ in series, then 10 nF to ground at the MCU pin. With all four lines low the pull-ups draw 1.3 mA.

**Output stage.** U2 PA3 → R1 (100 Ω) → gate of Q1. R2 (100 kΩ) holds the gate low while PA3 is high-impedance. Q1 is a ROHM RTR030N05HZGTL (45 V, RDS(on) ≤ 95 mΩ at VGS = 2.5 V, 3 A, TSMT3 on the SOT-23 land): about 11 mV drop and 1.4 mW at 120 mA. Its 45 V rating is the lowest on the 24 V side; the AO3422 (55 V) is not sold by Mouser, and no 55–60 V SOT-23 part in stock there has RDS(on) specified at 3.3 V or below. D2 clamps the drain to `+24V` to absorb wiring inductance.

**Programming.** J4 is a 6-pin FTDI-style header, numbered from the adapter's side. The adapter's TXD (pin 4) reaches the UPDI line through D3, a Schottky with its cathode toward TXD. The adapter's RXD (pin 5) connects to the UPDI line directly. R11 (470 Ω) sits between that line and PA0/UPDI. CTS (pin 2) is tied to GND, so CTS is asserted on adapters that enable handshaking by default. VCC (pin 3) is not connected, because some 3.3 V-logic adapters put 5 V there. DTR (pin 6) is not connected. A dedicated UPDI programmer uses pin 5 (UPDI) and pin 1 (GND). Microchip tools (Atmel-ICE, MPLAB SNAP, PICkit) also need their target-voltage sense lead on +3V3 (TP2), with the board powered from 24 V and "power target from tool" off.

## 5. BOM

All parts come from manufacturers Mouser stocks. Each was checked against its manufacturer's datasheet, and the capacitors against DC-bias data. Mouser availability was read from oemstrade.com on 2026-10-07, because Mouser blocks automated access. No Mouser part number is recorded until it has been read off its live listing; the order CSV matches on manufacturer part numbers.

| Ref | Manufacturer part | Package | Notes |
|---|---|---|---|
| U1 | Microchip MCP1792T-3302H/CB | SOT-23A-3 | Pin 1 GND, 2 VOUT, 3 VIN |
| U2 | Microchip ATTINY412-SSN | SOIC-8 (3.9 mm) | Tube. ATtiny212-SSN also fits |
| Q1 | ROHM RTR030N05HZGTL | TSMT3 (SOT-23 land) | Pin 1 G, 2 S, 3 D. 45 V, ≤ 95 mΩ at 2.5 V |
| D1, D2 | Diodes Inc B160-13-F | SMA | 60 V 1 A Schottky |
| D3 | onsemi BAT54HT1G | SOD-323 | Pin 1 K, 2 A. 30 V |
| F1 | Littelfuse 1812L050/60MR | 1812 | 0.5 A hold, 1 A trip, 60 V, Imax 10 A |
| C1 | Murata GRM188R61H225KE11D, 2.2 µF 50 V X5R | 0603 | U1 input, about 0.4 µF at 24 V |
| C2, C9 | Murata GRM31CR71H475MA12L, 4.7 µF 50 V X7R | 1206 | Bulk, about 2.7 µF each at 24 V |
| C3 | Samsung CL10A106MP8NQWC, 10 µF 10 V X5R | 0603 | U1 output, about 5.9 µF at 3.3 V |
| C4 | KEMET C0603C104K5RACTU, 100 nF 50 V X7R | 0603 | U2 decoupling |
| C5–C8 | KEMET C0603C103K5RACTU, 10 nF 50 V X7R | 0603 | Input filters |
| R1 | YAGEO RC0603FR-07100RL, 100 Ω 1% | 0603 | Gate series |
| R2 | YAGEO RC0603FR-07100KL, 100 kΩ 1% | 0603 | Gate pull-down |
| R3–R6 | YAGEO RC0603FR-0710KL, 10 kΩ 1% | 0603 | Input pull-ups |
| R7–R10 | YAGEO RC0603FR-071KL, 1 kΩ 1% | 0603 | Input series |
| R11 | YAGEO RC0603FR-07470RL, 470 Ω 1% | 0603 | UPDI series |
| J1, J2 | Phoenix Contact 1984617 (PT 1,5/2-3,5-H) | THT | 24 V in, strip out |
| J3 | Würth 61300511121, 1×5 2.54 mm | THT | Hackerboard |
| J4 | Würth 61300611121, 1×6 2.54 mm | THT | FTDI / SerialUPDI |
| TP1–TP5 | Test point | 1 mm pad | +24V, +3V3, GND, PWM, LED− |
| H1, H2 | M3 mounting hole, 3.2 mm | NPTH | No net |

Diode pin numbers follow the KiCad convention: pin 1 cathode, pin 2 anode.

## 6. Netlist

[`netlist.txt`](netlist.txt) lists every net. `check_netlist.py` compares the schematic against it. Compared with Rev 0.1:

```netlist
+24V:     ... C2.1 C9.1 ...         (C9 added)
UPDI:     U2.6 R11.2
UPDI_BUS: J4.5 R11.1 D3.2
UPDI_TX:  J4.4 D3.1
GND:      ... C2.2 C9.2 ... J4.1 J4.2 ...  (J4.2 = CTS)
+3V3:     ... (J4 no longer on +3V3)
NC:       J4.3 J4.6
SEL0:     R7.2 C5.1 U2.5         (PA2)
SEL1:     R8.2 C6.1 U2.4         (PA1)
SEL2:     R9.2 C7.1 U2.3         (PA7)
SEL3:     R10.2 C8.1 U2.2        (PA6)
```

U2 pin map (ATtiny412 SOIC-8): 1 VDD, 2 PA6, 3 PA7, 4 PA1, 5 PA2, 6 PA0/UPDI, 7 PA3, 8 GND. `PWM` stays on PA3 (TCA0 WO0, the default pin; the alternate is PA7).

## 7. Connectors

| Connector | Pin 1 | Pin 2 | Pin 3 | Pin 4 | Pin 5 | Pin 6 |
|---|---|---|---|---|---|---|
| J1, 24 V in | +24 V | GND | | | | |
| J2, strip | Strip + | Strip − | | | | |
| J3, Hackerboard J6 pins 1–5 | GND | Pin 0 (bit 0) | Pin 1 (bit 1) | Pin 2 (bit 2) | Pin 3 (bit 3) | |
| J4, FTDI adapter | GND | CTS (to GND) | VCC (n.c.) | TXD (adapter out) | RXD (adapter in) = UPDI | DTR (n.c.) |

Program with the board powered from 24 V. Never connect the board's 3.3 V to the adapter's VCC.

## 8. PCB constraints

- 2 layers, 1.6 mm FR4, 1 oz copper, outline 40 × 30 mm, two M3 holes. JLCPCB adds a small-board fee when a side is 30 mm or less; 40 × 31 mm avoids it.
- Board Setup > Constraints holds JLCPCB's 2-layer 1 oz absolute minimums: 0.10 mm clearance, track and connection width, 0.05 mm via annular ring, 0.25 mm via diameter, 0.15 mm drill, 0.2 mm hole-to-hole, 0.2 mm copper-to-hole, 0.2 mm copper-to-edge, silk text 1.0 mm high with 0.15 mm stroke. Solder mask: 0 expansion, 0.1 mm minimum web, 0.09 mm mask to copper.
- `led-pwm-4bit.kicad_dru` adds the JLCPCB limits those fields cannot express: PTH ring ≥ 0.18 mm, PTH hole to copper ≥ 0.28 mm, pad hole to hole ≥ 0.45 mm, NPTH ≥ 0.5 mm, pad to silkscreen ≥ 0.15 mm.
- Net classes carry the design values. Default: 0.2 mm clearance, 0.25 mm track, 0.6/0.3 mm via. Power (`+24V_IN`, `VIN_F`, `+24V`, `LED_NEG`, `GND`): 0.5 mm track, enforced as a DRC minimum.
- Ground pour on both layers, stitched with vias. Rule areas keep tracks off B.Cu under Q1 and U2 so the bottom pour stays unbroken there.
- Keep the PWM current loop small: C2, J2, Q1 and D2 together, with Q1's source returning to C2's negative pin by the shortest path.
- C1 within 3 mm of U1 pin 3. C3 within 3 mm of U1 pin 2. C4 directly at U2 pins 1 and 8. C5–C8 at the U2 pins, R3–R6 near J3.
- J1 and J2 on one edge, J3 on the opposite edge, J4 on the top edge for the adapter.
- Silkscreen: polarity at J1 and J2, `GND 0 1 2 3` at J3, adapter pin names at J4, board name, revision, and "hyiger".

## 9. Firmware contract (phase 2)

- Clock: internal 20 MHz oscillator, prescaler 2, giving 10 MHz. This is the limit at 3.3 V. The part starts at 20 MHz / 6 after reset.
- BOD: BODLEVEL2 (2.6 V). The 10 MHz speed grade is guaranteed only down to that level. Never use 4.2 V; chip erase would then fail at 3.3 V.
- Fuses: never change SYSCFG0.RSTPINCFG from UPDI. GPIO or RESET locks out SerialUPDI, and recovery then needs a 12 V high-voltage programmer.
- PWM: TCA0 single-slope on WO0 (PA3), PORTMUX.CTRLC = 0, prescaler 4, PER = 1022. Frequency is 10 MHz / 4 / 1023 = 2444 Hz. A compare value of 1023 gives a constant high output. Do not use split mode.
- Inputs: PA2, PA1, PA7, PA6 as plain inputs (external pull-ups, internal ones off). PA0 stays UPDI.
- Mapping: SEL0 = PA2, SEL1 = PA1, SEL2 = PA7, SEL3 = PA6.
- Level: `level = ~(bit3..bit0) & 0x0F`, with bit 0 = SEL0.
- Debounce: sample every 1 ms and apply a new level only after 20 identical consecutive samples.
- Start-up: set compare to 0 before enabling the PA3 output.
- Lookup table (gamma 2.2, 10-bit):

```c
static const uint16_t LUT[16] = {
    0, 3, 12, 30, 56, 91, 136, 191, 257, 333, 419, 517, 626, 747, 879, 1023
};
```

Level 1 is a 1.2 µs pulse. If it is unstable or invisible on the real strip, raise `LUT[1]` or use a larger timer prescaler. The hardware does not change.

Flashing with avrdude 8.x (7.x chip-erases on every flash write):

```
avrdude -c serialupdi -p t412 -P <port> -U flash:w:firmware.hex:i
```

Keep the default 115200 baud at 3.3 V. In the Arduino IDE with megaTinyCore, use "SerialUPDI - SLOW: 57600 baud", a 10 MHz clock and BOD 2.6 V.

## 10. KiCad workflow and deliverables

1. Target the installed KiCad, checked with `kicad-cli version` (10.0.7).
2. Project name `led-pwm-4bit`. Every symbol and footprint comes from the KiCad standard libraries with pin numbers checked against the datasheets (Q1 uses `Transistor_FET:Q_NMOS_GSD`: 1 G, 2 S, 3 D).
3. `check_netlist.py` exports the netlist with `kicad-cli sch export netlist` and compares it to `netlist.txt`. It must match exactly: same nets, same pins, nothing extra.
4. `kicad-cli sch erc --severity-all --exit-code-violations` and `kicad-cli pcb drc --schematic-parity --severity-all` must report zero violations.
5. Review points: after the schematic passes ERC and the netlist check; after placement; after routing passes DRC.
6. `scripts/export-fab.sh` writes the outputs to `fab/`: schematic PDF, BOM, Mouser BOM-tool order CSV, position file, top and bottom renders, and, once DRC is clean, Gerbers and separate PTH/NPTH drill files zipped for upload.

## 11. Acceptance checks

- Exported netlist equals `netlist.txt`. ERC and DRC report zero violations.
- No unconnected pins except J4.3 and J4.6, which carry no-connect flags. No pin on more than one net.
- Every polarized part (D1, D2, D3, Q1, U1, U2) has its pin 1 checked against the datasheet and the footprint.
- With U2 removed or in reset, `GATE` is held at 0 V by R2.
- Voltage ratings: everything on `+24V_IN`, `VIN_F`, `+24V` or `LED_NEG` is rated at least 35 V.

## 12. Open items

Resolved:

- Hackerboard connector: J6, 1×10 2.54 mm. Pins 1–5 = GND, 0, 1, 2, 3, so J3 is a 1×5 2.54 mm header.
- TCA0 WO0 defaults to PA3 (ATtiny212/412 datasheet DS40002287A, Table 5-2 and PORTMUX.CTRLC).
- F1: Littelfuse 1812L050/60MR (60 V, 0.5 A hold).
- Q1 pin order: ROHM's RTR030N05HZG datasheet gives (1) Gate, (2) Source, (3) Drain.

Still open:

- Core One INDX compatibility of the Hackerboard (see section 2).
- Reverse polarity through J3: if the 24 V comes from the printer's PSU and the J1 wires are swapped, supply + reaches board GND and shorts through J3 pin 1 into the Hackerboard and printer ground. A PPTC (≥ 30 V, 50–100 mA hold) in series with J3 pin 1 would stop it. Not yet decided.
- Mouser part numbers: to be read off Mouser's live listings, or resolved by uploading the order CSV to Mouser's BOM tool.
- Strip current: above 0.5 A, F1 and D1 have to change.
- Where the 24 V comes from. If it is not the printer's own supply, the two grounds still have to be common through J3 pin 1. Route the strip return straight to the supply so only signal current flows through the Hackerboard ground.

Left out on purpose: a TVS on the 24 V input, a status LED (no spare MCU pin), and any isolation between the printer and the strip.

## 13. Sources

- Prusa help article "GPIO Hackerboard" and schematic FDM-MK4-Gpio-02 (BOM05): connector, output stage, G-code.
- Prusa-Firmware-Buddy v6.9.1/v6.10.1, `src/marlin_stubs/M262-M268.cpp`, `src/hw/TCA6408A.cpp`: M267 behaviour and EEPROM persistence.
- Microchip DS20006229D, MCP1792/3: SOT-23A pinout, capacitor requirements, 4.5–55 V input.
- ROHM RTR030N05HZG datasheet Rev.001: 45 V, RDS(on) ≤ 95 mΩ at VGS = 2.5 V, ±12 V gate, pinout.
- Murata, Samsung and KEMET DC-bias data for C1, C2/C9 and C3.
- Microchip DS40002287A, ATtiny212/214/412/414/416: pinout, multiplexing, speed grades, UPDI.
- JLCPCB PCB capabilities page (checked 2026-10-07).
- SpenceKonde AVR-Guidance `UPDI/jtag2updi.md` and the avrdude 8.3 manual: SerialUPDI wiring and commands.

## Revision history

- 0.3 (2026-10-07): Parts sourced from Mouser (Q1 ROHM RTR030N05HZGTL, D3 BAT54HT1G on SOD-323, F1 Littelfuse, J1/J2 Phoenix 1984617, Würth headers, Yageo/KEMET/Murata/Samsung passives); the 47 µF electrolytic replaced by C2 and C9 (4.7 µF 50 V X7R 1206); JLCPCB assembly files dropped.
- 0.2 (2026-10-07): 0603 passives throughout; J4 changed to an FTDI-style SerialUPDI header with D3 and R11; SEL pins permuted for routing; JLCPCB rules; parts selected with LCSC numbers; open items from 0.1 resolved.
- 0.1 (2026-10-07): first handoff.
