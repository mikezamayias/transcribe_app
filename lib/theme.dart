import 'package:dartnative/dartnative.dart';

class Palette {
  const Palette._({
    required this.canvas,
    required this.ink,
    required this.muted,
    required this.surface,
  });

  final Color canvas;
  final Color ink;
  final Color muted;
  final Color surface;

  static const light = Palette._(
    canvas: Color(0xFFF2F2F7),
    ink: Color(0xFF111111),
    muted: Color(0xFF6B6B70),
    surface: Color(0xFFFFFFFF),
  );

  static const dark = Palette._(
    canvas: Color(0xFF000000),
    ink: Color(0xFFFFFFFF),
    muted: Color(0xFF8E8E93),
    surface: Color(0xFF1C1C1E),
  );

  static Palette of(BuildContext context) =>
      MediaQuery.of(context).platformBrightness == Brightness.dark
          ? dark
          : light;
}
