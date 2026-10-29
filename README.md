# MT Circuit

A native macOS schematic editor and circuit simulator for R, L, C, diode, transistor, op-amp, and logic gate circuits.
Swift, SwiftUI and AppKit only: no web views, Electron, or third-party dependencies.

## Features

- **Schematic editor**: place resistors, capacitors, inductors, diodes, BJTs and MOSFETs (N and
  P type), voltage and current sources, op-amps, logic gates (AND, OR, NOT, NAND, NOR, XOR, XNOR),
  grounds, and net labels on a snapping grid. Draw L-shaped wires, rotate parts, move them
  (attached wires follow), box-select, cut/copy/paste/duplicate, and undo/redo everything.
  Junction dots and red markers on unconnected pins show the connectivity.
- **Simulation** (Modified Nodal Analysis):
  - **DC operating point**: node voltages are annotated on the schematic, with a table of
    element voltages, currents, and power.
  - **Transient**: trapezoidal or backward-Euler integration. Start from rest or from the DC
    operating point. Sources can be DC, step, sine, or pulse.
  - **AC sweep**: Bode magnitude (dBV / dBA) and unwrapped phase over a logarithmic frequency range.
- **Plots** (Swift Charts): pick up to 8 signals, read values with a crosshair synchronized
  across charts, and hover a voltage to highlight its net on the schematic.
- **Equations tab**: the equations the simulator solves for the current analysis: Kirchhoff's
  current law at each node, each source, capacitor, inductor, diode, transistor, and op-amp law
  (with its discretized form in transient analysis, or the tangent of a diode or transistor current
  for Newton iteration), and the MNA matrix system `A·x = b`. Show them with component names
  or with values substituted. Hover a row to highlight it in both the equations and the matrix,
  and to highlight its net on the schematic. The equations come from the schematic itself, so
  they are shown even when the simulation fails.
- **Tutorial** (File ▸ Start Tutorial): twenty-six lessons on electronics fundamentals, from Ohm's
  law and Kirchhoff's laws through RC and RL transients, filters, resonance, diodes, transistors,
  op-amps, and digital logic: logic gates, building XOR from NAND gates, a full adder, an SR latch,
  a ring oscillator, and a NAND gate built from MOSFETs. Each lesson explains a concept, then sets
  a challenge on a starting circuit. A side panel lists the challenge's goals (such as
  `V(out) = 3.3 V ± 1 %`, or `y = A XOR B, for every input`), and the app checks them after every
  edit by running the analyses they need, showing the measured value next to each goal. A truth
  table goal runs a DC analysis for every combination of inputs. Hints, a worked answer, and a solution circuit are available for each lesson.
  Completed lessons are remembered across launches. The lesson is saved with the document, so a
  saved lesson opens in the tutorial again.
- **Dive In** (`⌘↓`, the inspector's Dive In button, or right-click a part): a window of linked
  topics on what is inside each part. The op-amp opens up into a seven-transistor circuit with its
  input, gain, and output stages outlined; point at a stage's explanation to find it in the
  schematic. From there, topics lead to the differential pair, current mirror, and push-pull output
  stage, then to the BJT and down to the pn junction. Drawings show the physics: carriers crossing a
  pn junction with forward or reverse bias, electrons crossing a BJT's base, and a MOSFET's channel
  forming as you raise its gate voltage. A logic gate opens up into the CMOS transistors of its
  function: the inverter, NAND, NOR, AND and OR, and XOR from four NAND gates, plus the SR latch.
  The Logic Gate page shows a gate's transistors as switches that you open and close by setting its
  inputs. Topics with a circuit open it in a new window to simulate, such as the transistor-level
  op-amp in an inverting amplifier, and part topics link to their tutorial lesson. Window ▸ Dive In
  opens the window without a selection.
- **Auto-run**: re-simulates after every edit.
- **Documents**: `.mtcircuit` files (JSON) with standard open, save, autosave, and versions.
  File ▸ New from Example has fourteen starter circuits, also included in `Examples/`.
- **SI values**: type `4.7k`, `10u` / `10µ`, `100n`, `2k2`, `1meg`. `m` is milli; `M` or `meg` is mega.

## Build and run

Requires macOS 14+ and Swift 6 (the Command Line Tools are enough; Xcode is not required).

```sh
make run      # build build/MT Circuit.app (release) and open it
make test     # run the CircuitCore unit tests
make app      # just build the app bundle
make debug    # debug build of the bundle
make package  # build build/MT-Circuit-<version>.dmg for distribution
```

`swift build` works too, but the app must run from the `.app` bundle (made by
`scripts/build-app.sh`), because the document type is declared in `Packaging/Info.plist`.

The version is `CFBundleShortVersionString` in `Packaging/Info.plist`. The app is signed
ad hoc, not notarized, so on another Mac Gatekeeper blocks the first launch: open it from
System Settings ▸ Privacy & Security ▸ Open Anyway.

## Using the editor

| Key | Action |
|---|---|
| `S` / `Esc` | Select tool (Esc also cancels a wire in progress) |
| `W` | Wire: click to start, click to add corners. The wire ends on a pin or another wire. |
| `R` `C` `L` | Place resistor, capacitor, inductor |
| `D` | Place diode |
| `Q` `M` | Place BJT, MOSFET (choose N or P type in the inspector) |
| `V` `I` | Place voltage source, current source |
| `O` | Place op-amp |
| `A` | Place logic gate (pick its function in the inspector) |
| `G` `N` | Place ground, net label |
| `Space`, `⌘R`, right-click while placing | Rotate 90° |
| `⌫` | Delete selection |
| `⌘↩` | Run simulation |
| `⌘↓` | Dive into the selected part |
| Pinch, `⌘+` / `⌘−` / `⌘0` / `⌘9` | Zoom in / out / actual size / fit |

Every circuit needs a ground symbol. Net labels name nets in the results, and labels with
the same name are connected even without a wire. In an AC sweep every source applies its AC
magnitude, 1 by default: set a supply's to 0 to make it an AC ground.

**Sign conventions**: pin 1 of a source is its `+` terminal (or the tail of a current source's
arrow). Element currents are reported flowing from pin 1 to pin 2 *through* the element, as in
SPICE, so a voltage source that delivers power reports a negative current.

**Diodes** follow the Shockley equation `I = Is·(exp(V/(n·Vt)) − 1)`, with saturation current
`Is` (10 fA by default), emission coefficient `n` (1 by default), and `Vt = kT/q` = 25.86 mV
at 27 °C. Pin 1 is the anode, so current flows along the arrow. There is no series resistance,
junction capacitance, or reverse breakdown.

**Transistors** have three pins, in SPICE order: collector, base, emitter for a BJT; drain,
gate, source for a MOSFET. The control pin is on the left. N-type devices have the collector or
drain on top; P-type devices are drawn upside down, with the emitter or source on top toward the
positive supply. Currents are reported into the pins: `Ic(Q1)` and the collector–emitter voltage
for a BJT, `Id(M1)` and the drain–source voltage for a MOSFET.
- **BJTs** follow the Ebers–Moll model in SPICE's transport form: current gain `β` (100 by
  default), saturation current `Is` (10 fA), optional Early voltage `VA`, and a reverse gain of 1.
  There is no junction capacitance or high-injection roll-off.
- **MOSFETs** follow the square law (SPICE level 1) with the body tied to the source: threshold
  voltage `Vth` (1 V by default), `k = µ·Cox·W/L` (2 mA/V²), so `Id = ½·k·(VGS − Vth)²` in
  saturation, and optional channel-length modulation `λ`. A P-channel device conducts when
  `VGS < −Vth`. There are no capacitances.

The inspector shows each transistor's operating region and terminal currents after a DC analysis.

**Op-amps** have their `−` input on top, their `+` input below, and the output on the right.
The output is `A·(V+ − V−)` relative to ground, with open-loop gain `A` (100k by default), and
the inputs draw no current. An op-amp's current `I(U1)` is the current *into* its output pin,
so an output that sources current reads negative, like a source; its voltage is the output
voltage. The model is linear: there are no supply rails, so the output never saturates.

**Logic gates** have their inputs on the left (a NOT gate's one input in line with its output) and
the output on the right. Pick the function in the inspector; the next gate you place gets the same
one. A gate's supply is implicit: its output drives toward 0 V or its supply voltage `V_DD` (5 V by
default), relative to ground, through 50 Ω, and its inputs switch at `V_DD/2` and draw no current.
In between, each input's level is a steep logistic curve, so a gate is smooth enough for Newton
iteration and amplifies near its threshold with a gain of 25, like a CMOS gate. The output follows
the inputs one propagation delay later (10 ns by default): a pure delay, so a ring of `N` inverters
oscillates at `1 / (2·N·t_pd)`. From rest, gate outputs start at 0 V. An output read as 1 is at
least 70 % of `V_DD`, and a 0 at most 30 %. `I(U1)` is the current into the output, as for an op-amp.

## Project layout

```
Sources/CircuitCore/       Platform-independent model and simulation engine
  Model.swift              Components, wires, source waveforms, simulation settings
  Netlist.swift            Connectivity (union-find over grid points) → numbered nodes per pin
  Simulator.swift          MNA assembly for DC, transient, and AC analyses; Newton–Raphson
  Semiconductors.swift     Diode, BJT, and MOSFET models, and Newton step limiting
  Logic.swift              Logic gate functions and model, and the history behind their delay
  Equations.swift          Readable circuit equations and the MNA matrix, for the Equations tab
  LinearAlgebra.swift      Complex numbers and dense LU with partial pivoting
  CircuitEditing.swift     Move / rotate / paste with wire rubber-banding
  SIFormat.swift           SI-prefix parsing and formatting
  Examples.swift           Built-in example circuits
  Lesson.swift             Tutorial lessons and goals, measured by simulating the learner's circuit
  Tutorial.swift           The tutorial's lessons: explanations, challenges, starters, and solutions
  DiveIn.swift             Dive In topics: explanations, figures, links, and their circuits
Sources/MTCircuit/         macOS app
  SchematicCanvasView.swift  AppKit canvas: drawing, mouse, keyboard, edit actions
  SymbolRenderer.swift       Core Graphics schematic symbols and toolbar icons
  EditorModel.swift          Per-window state: tools, selection, clipboard, simulation
  SimulationPanel.swift      Analysis settings, tables, and Swift Charts plots
  EquationsView.swift        Equations tab: circuit laws and the bracketed A·x = b matrix
  InspectorView.swift        Property inspector
  LessonPanel.swift          Tutorial side panel: lesson text, live goal checks, hints, answer
  TutorialModel.swift        Per-window goal checking, and lesson progress kept across launches
  DiveInView.swift           Dive In window: topic list, history, pages, and schematic figures
  DiveInIllustrations.swift  Dive In drawings: pn junction, BJT, MOSFET, resistor, capacitor, inductor, CMOS switches
Tests/CircuitCoreTests/    Swift Testing tests (results checked against analytic solutions)
```

### How the simulator works

Unknowns are the non-ground node voltages, plus one branch current per voltage source,
inductor, capacitor, diode, op-amp, MOSFET, and logic gate, and two (`Ic`, `Ib`) per BJT. Every two-terminal branch obeys `cv·(va − vb) + ci·i = rhs`,
so each analysis only changes the coefficients:

| | DC | t = 0 (from rest) | Backward Euler | Trapezoidal | AC |
|---|---|---|---|---|---|
| Capacitor | `i = 0` | `v = 0` | `(C/h)·v − i = (C/h)·v₀` | `(2C/h)·v − i = (2C/h)·v₀ + i₀` | `jωC·v − i = 0` |
| Inductor | `v = 0` | `i = 0` | `v − (L/h)·i = −(L/h)·i₀` | `v − (2L/h)·i = −(2L/h)·i₀ − v₀` | `v − jωL·i = 0` |

An op-amp is a voltage source from its output to ground whose value is `A·(v+ − v−)`: its
branch row is `vout − A·v+ + A·v− = 0` in every analysis, and its current appears only in the
output node's row.

Diodes, transistors, and logic gates make the equations nonlinear: each of their currents is a
function of a few control voltages (a diode's `V`, a BJT's `VBE` and `VBC`, a MOSFET's `VGS` and
`VDS`, a logic gate's output and input voltages).
DC and transient solutions with them come from Newton–Raphson iteration. Each iteration replaces
every such current by its tangent at the previous iterate, a branch equation
`Σⱼ Gⱼ·vⱼ − i = Σⱼ Gⱼ·vⱼ,ₖ − I(vₖ)` with slopes `Gⱼ = ∂I/∂vⱼ` (for a BJT, the hybrid-π
`g_m`, `g_π`, `g_μ`, `g_o`), and solves the resulting linear system. Iteration stops when successive solutions agree to 1 ppm (plus 1 µV /
1 pA), with steps across a pn junction above its critical voltage, MOSFET gate and drain voltages, and
logic inputs that jump across their threshold limited as in SPICE. If the DC solution does
not converge, the sources are ramped up from zero; a transient step that does not converge is
split in halves, up to 10 times. AC analysis replaces each diode, transistor, and logic gate by its
tangent at the DC operating point: its small-signal model.

A logic gate's output drives toward its function of its inputs one propagation delay earlier. In a
transient analysis, each gate keeps the history of that target over the last `t_pd`, and each time
step reads it back, interpolating between time points. When `t_pd` is shorter than the step, the
delayed time falls inside the step, and the target there depends partly on the present, unknown
inputs, so Newton iteration solves for it.

Transient analysis uses a fixed step. Without diodes, transistors, or logic gates the matrix is factored once
and reused for every step.
A 1 pS `gmin` from each node to ground keeps nodes defined when they are isolated at DC,
such as a node between two capacitors.

## Development notes

- With only the Command Line Tools, the macOS 27 SDK's `@State` macro has no compiler plugin.
  The app therefore declares state explicitly (`private let x = State(initialValue: …)`).
  Keep that pattern unless you build with Xcode.
- For the same reason, `make test` passes `-plugin-path` so the Swift Testing macros load
  in-process. SwiftPM's out-of-process plugin server can fail intermittently on this setup.
- `scripts/export-examples.sh` regenerates `Examples/` from `Examples.swift`.

## License

Licensed under the [Apache License 2.0](LICENSE).
