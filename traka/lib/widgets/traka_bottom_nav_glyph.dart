import 'package:flutter/material.dart';

/// Ikon tab navigasi bawah: extrusion bertingkat + gradien cahaya (highlight → bayangan)
/// agar terasa timbul/3D tanpa aset raster.
class TrakaBottomNavGlyph extends StatelessWidget {
  const TrakaBottomNavGlyph({
    super.key,
    required this.icon,
    this.outlinedIcon,
    required this.selected,
    required this.selectedColor,
    required this.unselectedColor,
    this.size = 30,
  });

  final IconData icon;
  final IconData? outlinedIcon;
  final bool selected;
  final Color selectedColor;
  final Color unselectedColor;
  final double size;

  static const List<double> _shadowAlphas = [0.2, 0.14, 0.09];
  static const List<Offset> _shadowOffsets = [
    Offset(1.55, 2.25),
    Offset(1.0, 1.45),
    Offset(0.52, 0.75),
  ];

  @override
  Widget build(BuildContext context) {
    final data = selected ? icon : (outlinedIcon ?? icon);
    final fg = selected ? selectedColor : unselectedColor;
    final extrude = selected ? 1.02 : 0.88;
    final shadowTint = Color.lerp(fg, Colors.black, selected ? 0.52 : 0.58)!;

    final shadows = <Widget>[
      for (var i = 0; i < _shadowOffsets.length; i++)
        Transform.translate(
          offset: Offset(
            _shadowOffsets[i].dx * extrude,
            _shadowOffsets[i].dy * extrude,
          ),
          child: Icon(
            data,
            size: size,
            color: shadowTint.withValues(
              alpha: (selected ? _shadowAlphas[i] : _shadowAlphas[i] * 0.75),
            ),
          ),
        ),
    ];

    final hi = Color.lerp(fg, Colors.white, selected ? 0.4 : 0.26)!;
    final lo = Color.lerp(fg, Colors.black, selected ? 0.32 : 0.24)!;
    final mainIcon = ShaderMask(
      blendMode: BlendMode.srcIn,
      shaderCallback: (Rect bounds) {
        return LinearGradient(
          begin: const Alignment(-0.85, -0.95),
          end: const Alignment(0.85, 1.0),
          colors: [
            hi,
            fg,
            Color.lerp(fg, lo, 0.65)!,
            lo,
          ],
          stops: selected ? const [0.0, 0.35, 0.72, 1.0] : const [0.0, 0.4, 0.78, 1.0],
        ).createShader(bounds);
      },
      child: Icon(data, size: size, color: Colors.white),
    );

    return SizedBox(
      width: size + 10,
      height: size + 8,
      child: Stack(
        alignment: Alignment.center,
        clipBehavior: Clip.none,
        children: [
          ...shadows,
          Transform.scale(
            scale: selected ? 1.06 : 1.0,
            alignment: Alignment.center,
            child: mainIcon,
          ),
        ],
      ),
    );
  }
}
