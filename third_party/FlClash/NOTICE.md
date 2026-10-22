# FlClash components

Source: https://github.com/chen08209/FlClash
Revision: `8d4f9744948751f1273fe871e1d05276fac09b0e`

`lib/ui/flclash/liquid_glass.dart`, `liquid_glass_capture.dart`,
`navigation_dock.dart`, `popup.dart`, `motion.dart`, and `shaders/liquid_glass.frag` are adapted from
FlClash, copyright its respective contributors, under GPL-3.0.
The full upstream license is in this directory's `LICENSE`.

Changes: imports point to Flutter Material and OpenMarkji's `compat.dart`;
navigation destinations use Material icons. The glass rendering, shader,
capture pipeline and spring animations retain the upstream implementation.
The superellipse scene clip explicitly supplies `Clip.antiAlias`, required
by this Flutter SDK's Web interface.
The appearance page follows FlClash's preview and choice layout.
Popup menus retain upstream anchor morphing, spring timing, source capture,
slide-to-pick and value transitions. OpenMarkji adapts typography, icons and
surface colors to its theme; elevated sheet themes are not used here.
Tint opacity and background blur are configurable through the shared glass
scope for docks, segmented bars, toolbars, search fields and popup menus.
Lifted lenses retain their clear optical layer so labels remain readable.
`lib/ui/flclash/floating_header.dart` adapts `lib/ui/sheet_header.dart` at
the same revision, retaining its eight-step eased scrim, 0.9 top opacity
and the scaffold's 16 dp overhang. OpenMarkji's `_GlassGroup` follows
`lib/ui/button.dart`'s `TonalButtonGroup`: one outer elastic press and one
pressed glass pane shared by all actions; theme adapters use local controls.
The navigation bar also provides a text-only mode for segmented controls;
it retains the same lens, pointer tracking, glow, refraction and springs.
Text-only rows use equal spacing and support an unselected row when large
text wraps a control. Reduced-motion mode skips spring travel.

OpenMarkji's original code retains its existing license. These copied
components are GPL-3.0, and a distributed combined application must comply
with that license; they are not relicensed as MIT.
