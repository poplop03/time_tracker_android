import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

/// The "Organic" palette from the design system. Wired as a [ThemeExtension]
/// so no widget has to re-pick a colour by hand.
@immutable
class OrganicColors extends ThemeExtension<OrganicColors> {
  const OrganicColors({
    required this.bg,
    required this.surface,
    required this.text,
    required this.accent,
    required this.accent2,
    required this.accent200,
    required this.accent400,
    required this.accent700,
    required this.accent800,
    required this.accent900,
    required this.sage100,
    required this.sage300,
    required this.sage500,
    required this.sage600,
    required this.sage800,
    required this.neutral200,
    required this.neutral300,
    required this.neutral400,
    required this.neutral600,
    required this.neutral700,
  });

  final Color bg;
  final Color surface;
  final Color text;
  final Color accent;
  final Color accent2;
  final Color accent200;
  final Color accent400;
  final Color accent700;
  final Color accent800;
  final Color accent900;
  final Color sage100;
  final Color sage300;
  final Color sage500;
  final Color sage600;
  final Color sage800;
  final Color neutral200;
  final Color neutral300;
  final Color neutral400;
  final Color neutral600;
  final Color neutral700;

  static const OrganicColors standard = OrganicColors(
    bg: Color(0xFFF5EAD8),
    surface: Color(0xFFEBDDC5),
    text: Color(0xFF201E1D),
    accent: Color(0xFFC67139),
    accent2: Color(0xFF7A8A5E),
    accent200: Color(0xFFFFE1D0),
    accent400: Color(0xFFF6A06B),
    accent700: Color(0xFF8C491A),
    accent800: Color(0xFF643312),
    accent900: Color(0xFF402310),
    sage100: Color(0xFFF0FAE1),
    sage300: Color(0xFFCCDBB2),
    sage500: Color(0xFF8FA073),
    sage600: Color(0xFF728157),
    sage800: Color(0xFF3D472B),
    neutral200: Color(0xFFEEE7DB),
    neutral300: Color(0xFFDCD3C4),
    neutral400: Color(0xFFC0B6A5),
    neutral600: Color(0xFF82796A),
    neutral700: Color(0xFF645C50),
  );

  /// Stable dot colours, indexed by an activity's `colorSeed`. The ramp
  /// alternates warm and sage and steps the lightness, so neighbouring seeds
  /// stay apart from each other in a donut.
  static const List<Color> dotRamp = <Color>[
    Color(0xFFC67139), // accent
    Color(0xFF728157), // sage 600
    Color(0xFF8C491A), // accent 700
    Color(0xFFCCDBB2), // sage 300
    Color(0xFFF6A06B), // accent 400
    Color(0xFF3D472B), // sage 800
    Color(0xFF643312), // accent 800
    Color(0xFF8FA073), // sage 500
  ];

  static Color dot(int seed) => dotRamp[seed.abs() % dotRamp.length];

  @override
  OrganicColors copyWith() => this;

  @override
  OrganicColors lerp(ThemeExtension<OrganicColors>? other, double t) => this;
}

/// Corner radii. Cards 32, rows 24, everything interactive is a pill.
class OrganicRadii {
  const OrganicRadii._();
  static const BorderRadius card = BorderRadius.all(Radius.circular(32));
  static const BorderRadius row = BorderRadius.all(Radius.circular(24));
  static const OutlinedBorder pill = StadiumBorder();
}

/// Minimum tap target required everywhere, including small buttons.
const double kMinTapTarget = 44;

ThemeData buildOrganicTheme() {
  const OrganicColors c = OrganicColors.standard;

  final TextTheme body = GoogleFonts.figtreeTextTheme();
  final TextTheme text = body
      .apply(bodyColor: c.text, displayColor: c.text)
      .copyWith(
        displayLarge: GoogleFonts.caprasimo(fontSize: 40, height: 1.1, color: c.text),
        displayMedium: GoogleFonts.caprasimo(fontSize: 32, height: 1.15, color: c.text),
        displaySmall: GoogleFonts.caprasimo(fontSize: 26, height: 1.2, color: c.text),
        headlineMedium: GoogleFonts.caprasimo(fontSize: 22, height: 1.2, color: c.text),
        headlineSmall: GoogleFonts.caprasimo(fontSize: 18, height: 1.25, color: c.text),
        titleMedium: GoogleFonts.figtree(fontSize: 16, fontWeight: FontWeight.w700, color: c.text),
        titleSmall: GoogleFonts.figtree(fontSize: 14, fontWeight: FontWeight.w600, color: c.text),
        bodyLarge: GoogleFonts.figtree(fontSize: 16, color: c.text),
        bodyMedium: GoogleFonts.figtree(fontSize: 14, color: c.neutral700),
        bodySmall: GoogleFonts.figtree(fontSize: 12, fontWeight: FontWeight.w600, color: c.neutral700),
        labelLarge: GoogleFonts.figtree(fontSize: 15, fontWeight: FontWeight.w700, color: c.text),
      );

  final ColorScheme scheme = ColorScheme.fromSeed(
    seedColor: c.accent,
    brightness: Brightness.light,
  ).copyWith(
    primary: c.accent700,
    onPrimary: Colors.white,
    secondary: c.sage600,
    onSecondary: Colors.white,
    surface: c.bg,
    onSurface: c.text,
    surfaceContainerHighest: c.surface,
    outline: c.neutral400,
  );

  return ThemeData(
    useMaterial3: true,
    colorScheme: scheme,
    scaffoldBackgroundColor: c.bg,
    canvasColor: c.bg,
    textTheme: text,
    splashFactory: InkSparkle.splashFactory,
    extensions: const <ThemeExtension<dynamic>>[c],
    dividerTheme: DividerThemeData(color: c.neutral300, thickness: 1, space: 1),
    iconTheme: IconThemeData(color: c.text, size: 20),
    appBarTheme: AppBarTheme(
      backgroundColor: c.bg,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      centerTitle: false,
      titleTextStyle: text.headlineMedium,
    ),
    cardTheme: CardThemeData(
      color: c.surface,
      elevation: 0,
      margin: EdgeInsets.zero,
      shape: const RoundedRectangleBorder(borderRadius: OrganicRadii.card),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        backgroundColor: c.accent700,
        foregroundColor: Colors.white,
        minimumSize: const Size(kMinTapTarget, kMinTapTarget),
        padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 12),
        shape: OrganicRadii.pill,
        textStyle: text.labelLarge,
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        foregroundColor: c.accent700,
        side: BorderSide(color: c.neutral400),
        minimumSize: const Size(kMinTapTarget, kMinTapTarget),
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
        shape: OrganicRadii.pill,
        textStyle: text.labelLarge,
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(
        foregroundColor: c.accent700,
        minimumSize: const Size(kMinTapTarget, kMinTapTarget),
        shape: OrganicRadii.pill,
        textStyle: text.labelLarge,
      ),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: c.neutral200,
      hintStyle: GoogleFonts.figtree(fontSize: 16, color: c.neutral600),
      contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
      border: const OutlineInputBorder(
        borderRadius: BorderRadius.all(Radius.circular(999)),
        borderSide: BorderSide.none,
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: const BorderRadius.all(Radius.circular(999)),
        borderSide: BorderSide(color: c.neutral300),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: const BorderRadius.all(Radius.circular(999)),
        borderSide: BorderSide(color: c.accent700, width: 2),
      ),
    ),
    chipTheme: ChipThemeData(
      backgroundColor: c.neutral200,
      selectedColor: c.accent200,
      side: BorderSide(color: c.neutral300),
      shape: const StadiumBorder(),
      labelStyle: text.bodySmall!,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
    ),
    bottomSheetTheme: BottomSheetThemeData(
      backgroundColor: c.bg,
      surfaceTintColor: Colors.transparent,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(32)),
      ),
    ),
    snackBarTheme: SnackBarThemeData(
      backgroundColor: c.text,
      contentTextStyle: GoogleFonts.figtree(fontSize: 14, color: c.bg),
      behavior: SnackBarBehavior.floating,
      shape: const RoundedRectangleBorder(borderRadius: OrganicRadii.row),
    ),
  );
}

extension OrganicThemeAccess on BuildContext {
  OrganicColors get colors =>
      Theme.of(this).extension<OrganicColors>() ?? OrganicColors.standard;
  TextTheme get texts => Theme.of(this).textTheme;
}
