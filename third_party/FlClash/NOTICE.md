# FlClash components

Source: https://github.com/chen08209/FlClash
Revision: `8d4f9744948751f1273fe871e1d05276fac09b0e`

`lib/ui/flclash/liquid_glass.dart`, `liquid_glass_capture.dart`,
`navigation_dock.dart`, and `shaders/liquid_glass.frag` are adapted from
FlClash, copyright its respective contributors, under GPL-3.0.
The full upstream license is in this directory's `LICENSE`.

Changes: imports point to Flutter Material and OpenMarkji's `compat.dart`;
navigation destinations use Material icons. The glass rendering, shader,
capture pipeline and spring animations retain the upstream implementation.
The superellipse scene clip explicitly supplies `Clip.antiAlias`, required
by this Flutter SDK's Web interface.
The appearance page follows FlClash's preview and choice layout.

OpenMarkji's original code retains its existing license. These copied
components are GPL-3.0, and a distributed combined application must comply
with that license; they are not relicensed as MIT.
