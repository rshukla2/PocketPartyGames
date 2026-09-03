import 'package:flutter/material.dart';

enum PartyGameStyle {
  hub,
  trivia,
  imposter,
  stopTimer,
  truthDare,
  pictionary,
  guessNumber,
  actItOut,
  countdown,
}

enum PartyScreenTone { standard, action, secret, success, danger }

@immutable
class PartyPalette {
  const PartyPalette({
    required this.background,
    required this.foreground,
    required this.accent,
    required this.surface,
    required this.onSurface,
    this.secondary,
  });

  final Color background;
  final Color foreground;
  final Color accent;
  final Color surface;
  final Color onSurface;
  final Color? secondary;

  Color get shadow => PartyColors.nearBlack.withValues(alpha: .28);
}

abstract final class PartyColors {
  static const nearBlack = Color(0xFF111111);
  static const purple = Color(0xFF7C3AED);
  static const deepIndigo = Color(0xFF312E81);
  static const violet = Color(0xFFA855F7);
  static const cyan = Color(0xFF00CFF3);
  static const blue = Color(0xFF168BFF);
  static const pink = Color(0xFFF43F8C);
  static const coral = Color(0xFFFF4B4B);
  static const orange = Color(0xFFFF8A00);
  static const yellow = Color(0xFFFFD629);
  static const lime = Color(0xFF9BE000);
  static const green = Color(0xFF21D19F);
  static const white = Color(0xFFFFFFFF);

  // Compatibility aliases for gameplay code that predates the new palette.
  static const background = purple;
  static const indigo = blue;
  static const amber = yellow;
  static const rose = coral;

  static const playerColors = <Color>[
    coral,
    blue,
    green,
    orange,
    violet,
    cyan,
    pink,
    purple,
  ];
}

abstract final class PartyPalettes {
  static const _whiteSurface = PartyColors.white;

  static const library = PartyPalette(
    background: PartyColors.deepIndigo,
    foreground: PartyColors.white,
    accent: PartyColors.yellow,
    secondary: PartyColors.cyan,
    surface: _whiteSurface,
    onSurface: PartyColors.nearBlack,
  );

  static PartyPalette resolve(
    PartyGameStyle style, [
    PartyScreenTone tone = PartyScreenTone.standard,
  ]) {
    final base = switch (style) {
      PartyGameStyle.hub => const PartyPalette(
        background: PartyColors.purple,
        foreground: PartyColors.white,
        accent: PartyColors.yellow,
        secondary: PartyColors.cyan,
        surface: _whiteSurface,
        onSurface: PartyColors.nearBlack,
      ),
      PartyGameStyle.trivia => const PartyPalette(
        background: PartyColors.blue,
        foreground: PartyColors.nearBlack,
        accent: PartyColors.yellow,
        secondary: PartyColors.purple,
        surface: _whiteSurface,
        onSurface: PartyColors.nearBlack,
      ),
      PartyGameStyle.imposter => const PartyPalette(
        background: PartyColors.purple,
        foreground: PartyColors.white,
        accent: PartyColors.yellow,
        secondary: PartyColors.violet,
        surface: _whiteSurface,
        onSurface: PartyColors.nearBlack,
      ),
      PartyGameStyle.stopTimer => const PartyPalette(
        background: PartyColors.orange,
        foreground: PartyColors.nearBlack,
        accent: PartyColors.yellow,
        secondary: PartyColors.coral,
        surface: _whiteSurface,
        onSurface: PartyColors.nearBlack,
      ),
      PartyGameStyle.truthDare => const PartyPalette(
        background: PartyColors.pink,
        foreground: PartyColors.nearBlack,
        accent: PartyColors.yellow,
        secondary: PartyColors.coral,
        surface: _whiteSurface,
        onSurface: PartyColors.nearBlack,
      ),
      PartyGameStyle.pictionary => const PartyPalette(
        background: PartyColors.cyan,
        foreground: PartyColors.nearBlack,
        accent: PartyColors.yellow,
        secondary: PartyColors.blue,
        surface: _whiteSurface,
        onSurface: PartyColors.nearBlack,
      ),
      PartyGameStyle.guessNumber => const PartyPalette(
        background: PartyColors.green,
        foreground: PartyColors.nearBlack,
        accent: PartyColors.lime,
        secondary: PartyColors.blue,
        surface: _whiteSurface,
        onSurface: PartyColors.nearBlack,
      ),
      PartyGameStyle.actItOut => const PartyPalette(
        background: PartyColors.pink,
        foreground: PartyColors.nearBlack,
        accent: PartyColors.yellow,
        secondary: PartyColors.purple,
        surface: _whiteSurface,
        onSurface: PartyColors.nearBlack,
      ),
      PartyGameStyle.countdown => const PartyPalette(
        background: PartyColors.coral,
        foreground: PartyColors.nearBlack,
        accent: PartyColors.yellow,
        secondary: PartyColors.orange,
        surface: _whiteSurface,
        onSurface: PartyColors.nearBlack,
      ),
    };

    return switch ((style, tone)) {
      (_, PartyScreenTone.standard) => base,
      (PartyGameStyle.trivia, PartyScreenTone.action) => _onDark(
        PartyColors.purple,
        PartyColors.yellow,
        PartyColors.blue,
      ),
      (PartyGameStyle.imposter, PartyScreenTone.secret) => _onDark(
        PartyColors.nearBlack,
        PartyColors.violet,
        PartyColors.coral,
      ),
      (PartyGameStyle.imposter, PartyScreenTone.danger) => _onDark(
        PartyColors.coral,
        PartyColors.yellow,
        PartyColors.purple,
      ),
      (PartyGameStyle.stopTimer, PartyScreenTone.action) => _onLight(
        PartyColors.yellow,
        PartyColors.orange,
        PartyColors.coral,
      ),
      (PartyGameStyle.stopTimer, PartyScreenTone.secret) => _onDark(
        PartyColors.nearBlack,
        PartyColors.orange,
        PartyColors.yellow,
      ),
      (PartyGameStyle.truthDare, PartyScreenTone.action) => _onDark(
        PartyColors.coral,
        PartyColors.yellow,
        PartyColors.pink,
      ),
      (PartyGameStyle.truthDare, PartyScreenTone.secret) => _onDark(
        PartyColors.nearBlack,
        PartyColors.coral,
        PartyColors.pink,
      ),
      (PartyGameStyle.pictionary, PartyScreenTone.action) => _onDark(
        PartyColors.blue,
        PartyColors.yellow,
        PartyColors.cyan,
      ),
      (PartyGameStyle.pictionary, PartyScreenTone.secret) => _onDark(
        PartyColors.nearBlack,
        PartyColors.cyan,
        PartyColors.blue,
      ),
      (PartyGameStyle.guessNumber, PartyScreenTone.action) => _onLight(
        PartyColors.lime,
        PartyColors.green,
        PartyColors.blue,
      ),
      (PartyGameStyle.actItOut, PartyScreenTone.action) => _onDark(
        PartyColors.purple,
        PartyColors.yellow,
        PartyColors.pink,
      ),
      (PartyGameStyle.actItOut, PartyScreenTone.secret) => _onDark(
        PartyColors.nearBlack,
        PartyColors.pink,
        PartyColors.violet,
      ),
      (PartyGameStyle.countdown, PartyScreenTone.action) => _onLight(
        PartyColors.orange,
        PartyColors.yellow,
        PartyColors.coral,
      ),
      (PartyGameStyle.countdown, PartyScreenTone.secret) => _onDark(
        PartyColors.purple,
        PartyColors.yellow,
        PartyColors.violet,
      ),
      (PartyGameStyle.countdown, PartyScreenTone.danger) => _onDark(
        PartyColors.blue,
        PartyColors.yellow,
        PartyColors.cyan,
      ),
      (_, PartyScreenTone.success) => _onLight(
        PartyColors.green,
        PartyColors.lime,
        base.background,
      ),
      (_, PartyScreenTone.danger) => _onDark(
        PartyColors.coral,
        PartyColors.yellow,
        base.background,
      ),
      (_, PartyScreenTone.secret) => _onDark(
        PartyColors.nearBlack,
        base.background,
        base.accent,
      ),
      (_, PartyScreenTone.action) => base,
    };
  }

  static PartyPalette _onDark(
    Color background,
    Color accent,
    Color secondary,
  ) => PartyPalette(
    background: background,
    foreground: _accessibleForeground(background),
    accent: accent,
    secondary: secondary,
    surface: _whiteSurface,
    onSurface: PartyColors.nearBlack,
  );

  static PartyPalette _onLight(
    Color background,
    Color accent,
    Color secondary,
  ) => PartyPalette(
    background: background,
    foreground: PartyColors.nearBlack,
    accent: accent,
    secondary: secondary,
    surface: _whiteSurface,
    onSurface: PartyColors.nearBlack,
  );

  static Color _accessibleForeground(Color background) {
    final whiteContrast = 1.05 / (background.computeLuminance() + .05);
    return whiteContrast >= 4.5 ? PartyColors.white : PartyColors.nearBlack;
  }
}

ThemeData buildPartyTheme({PartyPalette? palette}) {
  final colors = palette ?? PartyPalettes.resolve(PartyGameStyle.hub);
  final darkDialog = colors.foreground == PartyColors.white;
  final dialogBackground = darkDialog
      ? PartyColors.nearBlack
      : PartyColors.white;
  final onDialog = darkDialog ? PartyColors.white : PartyColors.nearBlack;
  final scheme = ColorScheme(
    brightness: Brightness.light,
    primary: colors.background,
    onPrimary: colors.foreground,
    secondary: colors.accent,
    onSecondary: PartyColors.nearBlack,
    error: PartyColors.coral,
    onError: PartyColors.white,
    surface: colors.surface,
    onSurface: colors.onSurface,
  );
  const baseText = TextStyle(fontFamily: 'Fredoka');

  return ThemeData(
    colorScheme: scheme,
    scaffoldBackgroundColor: colors.background,
    fontFamily: 'Fredoka',
    useMaterial3: true,
    textTheme: const TextTheme(
      displayLarge: TextStyle(
        fontFamily: 'Fredoka',
        fontSize: 52,
        height: .96,
        fontWeight: FontWeight.w800,
        letterSpacing: -1.2,
      ),
      displaySmall: TextStyle(
        fontFamily: 'Fredoka',
        fontSize: 40,
        height: 1,
        fontWeight: FontWeight.w800,
        letterSpacing: -.8,
      ),
      headlineMedium: TextStyle(
        fontFamily: 'Fredoka',
        fontSize: 30,
        height: 1.05,
        fontWeight: FontWeight.w800,
        letterSpacing: -.4,
      ),
      titleLarge: TextStyle(
        fontFamily: 'Fredoka',
        fontSize: 22,
        fontWeight: FontWeight.w800,
      ),
      titleMedium: TextStyle(
        fontFamily: 'Fredoka',
        fontSize: 18,
        fontWeight: FontWeight.w700,
      ),
      bodyLarge: TextStyle(
        fontFamily: 'Fredoka',
        fontSize: 17,
        height: 1.35,
        fontWeight: FontWeight.w600,
      ),
      bodyMedium: TextStyle(
        fontFamily: 'Fredoka',
        fontSize: 15,
        height: 1.35,
        fontWeight: FontWeight.w500,
      ),
      labelLarge: TextStyle(
        fontFamily: 'Fredoka',
        fontSize: 15,
        fontWeight: FontWeight.w800,
        letterSpacing: .3,
      ),
    ),
    cardTheme: CardThemeData(
      color: colors.surface,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      margin: const EdgeInsets.symmetric(vertical: 5),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(28)),
    ),
    appBarTheme: AppBarTheme(
      backgroundColor: Colors.transparent,
      surfaceTintColor: Colors.transparent,
      foregroundColor: colors.foreground,
      elevation: 0,
      titleTextStyle: baseText.copyWith(
        color: colors.foreground,
        fontSize: 21,
        fontWeight: FontWeight.w800,
      ),
    ),
    dialogTheme: DialogThemeData(
      backgroundColor: dialogBackground,
      surfaceTintColor: Colors.transparent,
      titleTextStyle: baseText.copyWith(
        color: onDialog,
        fontSize: 25,
        fontWeight: FontWeight.w800,
      ),
      contentTextStyle: baseText.copyWith(
        color: onDialog,
        fontSize: 16,
        height: 1.35,
        fontWeight: FontWeight.w500,
      ),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(28)),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: PartyColors.white,
      labelStyle: const TextStyle(
        color: PartyColors.nearBlack,
        fontWeight: FontWeight.w600,
      ),
      floatingLabelStyle: const TextStyle(
        color: PartyColors.nearBlack,
        fontWeight: FontWeight.w800,
      ),
      prefixIconColor: PartyColors.nearBlack,
      suffixIconColor: PartyColors.nearBlack,
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(20),
        borderSide: BorderSide.none,
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(20),
        borderSide: const BorderSide(color: PartyColors.nearBlack, width: 3),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(20),
        borderSide: BorderSide(color: colors.accent, width: 4),
      ),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        minimumSize: const Size(48, 56),
        backgroundColor: PartyColors.white,
        foregroundColor: PartyColors.nearBlack,
        disabledBackgroundColor: PartyColors.white.withValues(alpha: .42),
        disabledForegroundColor: PartyColors.nearBlack.withValues(alpha: .5),
        elevation: 0,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        textStyle: const TextStyle(
          fontFamily: 'Fredoka',
          fontSize: 15,
          fontWeight: FontWeight.w800,
          letterSpacing: .35,
        ),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        minimumSize: const Size(48, 56),
        foregroundColor: colors.foreground,
        side: BorderSide(color: colors.foreground, width: 3),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        textStyle: const TextStyle(
          fontFamily: 'Fredoka',
          fontWeight: FontWeight.w800,
          letterSpacing: .25,
        ),
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(
        minimumSize: const Size(48, 48),
        foregroundColor: colors.foreground,
        textStyle: const TextStyle(
          fontFamily: 'Fredoka',
          fontWeight: FontWeight.w800,
        ),
      ),
    ),
    iconButtonTheme: IconButtonThemeData(
      style: IconButton.styleFrom(
        minimumSize: const Size(48, 48),
        foregroundColor: colors.foreground,
      ),
    ),
    chipTheme: ChipThemeData(
      backgroundColor: PartyColors.white,
      selectedColor: colors.accent,
      secondarySelectedColor: colors.accent,
      labelStyle: const TextStyle(
        color: PartyColors.nearBlack,
        fontWeight: FontWeight.w700,
      ),
      secondaryLabelStyle: const TextStyle(
        color: PartyColors.nearBlack,
        fontWeight: FontWeight.w800,
      ),
      side: const BorderSide(color: PartyColors.nearBlack, width: 2.5),
      shape: const StadiumBorder(),
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 7),
    ),
    segmentedButtonTheme: SegmentedButtonThemeData(
      style: ButtonStyle(
        minimumSize: const WidgetStatePropertyAll<Size>(Size(48, 52)),
        backgroundColor: WidgetStateProperty.resolveWith<Color?>((states) {
          return states.contains(WidgetState.selected)
              ? colors.accent
              : PartyColors.white;
        }),
        foregroundColor: const WidgetStatePropertyAll<Color>(
          PartyColors.nearBlack,
        ),
        side: const WidgetStatePropertyAll<BorderSide>(
          BorderSide(color: PartyColors.nearBlack, width: 2.5),
        ),
        textStyle: const WidgetStatePropertyAll<TextStyle>(
          TextStyle(fontFamily: 'Fredoka', fontWeight: FontWeight.w800),
        ),
      ),
    ),
    listTileTheme: ListTileThemeData(
      textColor: colors.foreground,
      iconColor: colors.foreground,
      titleTextStyle: TextStyle(
        fontFamily: 'Fredoka',
        color: colors.foreground,
        fontSize: 17,
        fontWeight: FontWeight.w700,
      ),
      subtitleTextStyle: TextStyle(
        fontFamily: 'Fredoka',
        color: colors.foreground.withValues(alpha: .8),
        fontSize: 14,
        fontWeight: FontWeight.w500,
      ),
    ),
    switchTheme: SwitchThemeData(
      thumbColor: WidgetStateProperty.resolveWith<Color?>((states) {
        return states.contains(WidgetState.selected)
            ? PartyColors.nearBlack
            : null;
      }),
      trackColor: WidgetStateProperty.resolveWith<Color?>((states) {
        return states.contains(WidgetState.selected) ? colors.accent : null;
      }),
    ),
    snackBarTheme: SnackBarThemeData(
      backgroundColor: PartyColors.nearBlack,
      contentTextStyle: baseText.copyWith(
        color: PartyColors.white,
        fontWeight: FontWeight.w600,
      ),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      behavior: SnackBarBehavior.floating,
    ),
  );
}
