# GPL-3.0 components

Upstream maintainer: chen08209 and the original contributors.
Source repository: https://api.github.com/repositories/678716433
Revision: `8d4f9744948751f1273fe871e1d05276fac09b0e`

`lib/ui/glass/liquid_glass.dart`, `liquid_glass_capture.dart`,
`navigation_dock.dart`, `popup.dart`, `motion.dart`, and `shaders/liquid_glass.frag` are adapted from
the upstream repository, copyright its respective contributors, under GPL-3.0.
The full upstream license is in this directory's `LICENSE`.

Changes: imports point to Flutter Material and OpenMarkji's `compat.dart`;
navigation destinations use Material icons. The glass rendering, shader,
capture pipeline and spring animations retain the upstream implementation.
The superellipse scene clip explicitly supplies `Clip.antiAlias`, required
by this Flutter SDK's Web interface.
The appearance page follows the upstream preview and choice layout.
Popup menus retain upstream anchor morphing, spring timing, source capture,
slide-to-pick and value transitions. OpenMarkji adapts typography, icons and
surface colors to its theme; elevated sheet themes are not used here.
Tint opacity and background blur are configurable through the shared glass
scope for docks, segmented bars, toolbars, search fields and popup menus.
Lifted lenses retain their clear optical layer so labels remain readable.
`lib/ui/glass/floating_header.dart` adapts `lib/ui/sheet_header.dart` at
the same revision, retaining its eight-step eased scrim, 0.9 top opacity
and the scaffold's 16 dp overhang. OpenMarkji's `_GlassGroup` follows
`lib/ui/button.dart`'s `TonalButtonGroup`: one outer elastic press and one
pressed glass pane shared by all actions; theme adapters use local controls.
The navigation bar also provides a text-only mode for segmented controls;
it retains the same lens, pointer tracking, glow, refraction and springs.
Text-only rows use equal spacing and support an unselected row when large
text wraps a control. Reduced-motion mode skips spring travel.

`lib/ui/glass/dialog.dart` adapts `lib/ui/dialog.dart` at the same revision:
alert glass, rim and shadows, the 404 ms spring entry, glass-aware fading,
fade-only dismissal, and elastic panel presses. OpenMarkji retains its own
update/download/install workflow, connects the pane to shared appearance
preferences, and disables route travel in reduced-motion mode.
The about page in `lib/ui/support.dart` follows `lib/views/about.dart`'s
96 dp logo, compact matching pills, typography, spacing and grouped links;
content and actions are adapted to OpenMarkji.

OpenMarkji's original code retains its existing license. These copied
components are GPL-3.0, and a distributed combined application must comply
with that license; they are not relicensed as MIT.
