import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:inti/core/theme/app_colors.dart';
import 'package:inti/core/theme/app_tokens.dart';
import 'package:inti/core/theme/app_typography.dart';

/// Construye el [ThemeData] a partir de los tokens. Es el único lugar donde
/// se decide cómo se ven los widgets de Material.
abstract final class AppTheme {
  static ThemeData light() => _build(AppColors.light, Brightness.light);
  static ThemeData dark() => _build(AppColors.dark, Brightness.dark);

  static ThemeData _build(AppColors c, Brightness b) {
    final scheme = ColorScheme(
      brightness: b,
      primary: c.primary,
      onPrimary: c.onPrimary,
      primaryContainer: c.primaryContainer,
      onPrimaryContainer: c.onPrimaryContainer,
      secondary: c.business,
      onSecondary: c.surface,
      secondaryContainer: c.businessContainer,
      onSecondaryContainer: c.ink,
      tertiary: c.transfer,
      onTertiary: c.surface,
      tertiaryContainer: c.transferContainer,
      onTertiaryContainer: c.ink,
      error: c.danger,
      onError: c.onDanger,
      errorContainer: c.dangerContainer,
      onErrorContainer: c.onDangerContainer,
      surface: c.surface,
      onSurface: c.ink,
      onSurfaceVariant: c.inkMuted,
      surfaceContainerLowest: c.surface,
      surfaceContainerLow: c.background,
      surfaceContainer: c.surfaceMuted,
      surfaceContainerHigh: c.surfaceMuted,
      surfaceContainerHighest: c.surfaceSunken,
      outline: c.outlineStrong,
      outlineVariant: c.outline,
      shadow: c.shadow,
      scrim: c.scrim,
      inverseSurface: c.ink,
      onInverseSurface: c.surface,
      inversePrimary: c.heroAccent,
    );
    final text = AppTypography.textTheme(c.ink, c.inkMuted, c.inkSubtle);
    const controlShape = RoundedRectangleBorder(
      borderRadius: AppRadius.controlAll,
    );
    const minButton = Size(AppSize.touch, AppSize.control);
    final overlay = b == Brightness.light
        ? SystemUiOverlayStyle.dark
        : SystemUiOverlayStyle.light;

    return ThemeData(
      useMaterial3: true,
      brightness: b,
      colorScheme: scheme,
      fontFamily: AppTypography.family,
      textTheme: text,
      scaffoldBackgroundColor: c.background,
      canvasColor: c.background,
      dividerColor: c.outline,
      splashFactory: InkSparkle.splashFactory,
      materialTapTargetSize: MaterialTapTargetSize.padded,
      visualDensity: VisualDensity.standard,
      extensions: [c],
      pageTransitionsTheme: const PageTransitionsTheme(
        builders: {
          TargetPlatform.android: FadeForwardsPageTransitionsBuilder(),
          TargetPlatform.iOS: CupertinoPageTransitionsBuilder(),
        },
      ),
      appBarTheme: AppBarTheme(
        backgroundColor: c.background,
        surfaceTintColor: Colors.transparent,
        foregroundColor: c.ink,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: false,
        titleSpacing: AppSpace.gutter,
        // Sin titleTextStyle: la barra toma titleLarge (17) y el título
        // expandido de las pestañas, headlineSmall (22).
        systemOverlayStyle: overlay.copyWith(
          statusBarColor: Colors.transparent,
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          minimumSize: minButton,
          shape: controlShape,
          backgroundColor: c.primary,
          foregroundColor: c.onPrimary,
          disabledBackgroundColor: c.surfaceSunken,
          disabledForegroundColor: c.inkSubtle,
          textStyle: AppTypography.body.copyWith(fontWeight: FontWeight.w600),
          padding: const EdgeInsets.symmetric(horizontal: AppSpace.lg),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          minimumSize: minButton,
          shape: controlShape,
          foregroundColor: c.ink,
          backgroundColor: c.surface,
          side: BorderSide(color: c.outlineStrong),
          textStyle: AppTypography.body.copyWith(fontWeight: FontWeight.w600),
          padding: const EdgeInsets.symmetric(horizontal: AppSpace.lg),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          minimumSize: const Size(AppSize.touch, AppSize.touch),
          shape: controlShape,
          foregroundColor: c.primary,
          textStyle: AppTypography.body.copyWith(fontWeight: FontWeight.w600),
          padding: const EdgeInsets.symmetric(horizontal: AppSpace.sm),
        ),
      ),
      iconButtonTheme: IconButtonThemeData(
        style: IconButton.styleFrom(
          minimumSize: const Size(AppSize.touch, AppSize.touch),
          foregroundColor: c.ink,
          iconSize: AppSize.icon,
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: c.surface,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: AppSpace.md,
          vertical: AppSpace.md,
        ),
        hintStyle: AppTypography.body.copyWith(color: c.inkSubtle),
        helperStyle: AppTypography.caption.copyWith(color: c.inkMuted),
        // Errores en semibold: deben verse antes que cualquier ayuda.
        errorStyle: AppTypography.label.copyWith(color: c.onDangerContainer),
        helperMaxLines: 3,
        errorMaxLines: 3,
        border: OutlineInputBorder(
          borderRadius: AppRadius.controlAll,
          borderSide: BorderSide(color: c.outlineStrong),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: AppRadius.controlAll,
          borderSide: BorderSide(color: c.outlineStrong),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: AppRadius.controlAll,
          borderSide: BorderSide(color: c.primary, width: 2),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: AppRadius.controlAll,
          borderSide: BorderSide(color: c.danger),
        ),
        focusedErrorBorder: OutlineInputBorder(
          borderRadius: AppRadius.controlAll,
          borderSide: BorderSide(color: c.danger, width: 2),
        ),
        disabledBorder: OutlineInputBorder(
          borderRadius: AppRadius.controlAll,
          borderSide: BorderSide(color: c.outline),
        ),
      ),
      chipTheme: ChipThemeData(
        backgroundColor: c.surfaceMuted,
        // Igual que ScopeSwitcher y SegmentedButton: verde suave al elegir.
        selectedColor: c.primaryContainer,
        disabledColor: c.surfaceMuted,
        side: BorderSide.none,
        shape: const RoundedRectangleBorder(borderRadius: AppRadius.pill),
        labelStyle: AppTypography.label.copyWith(color: c.inkMuted),
        secondaryLabelStyle: AppTypography.label.copyWith(
          color: c.onPrimaryContainer,
        ),
        checkmarkColor: c.onPrimaryContainer,
        showCheckmark: false,
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpace.sm,
          vertical: AppSpace.xs,
        ),
      ),
      switchTheme: SwitchThemeData(
        thumbColor: WidgetStateProperty.resolveWith(
          (s) =>
              s.contains(WidgetState.selected) ? c.onPrimary : c.outlineStrong,
        ),
        trackColor: WidgetStateProperty.resolveWith(
          (s) => s.contains(WidgetState.selected) ? c.primary : c.surfaceMuted,
        ),
        trackOutlineColor: WidgetStateProperty.resolveWith(
          (s) => s.contains(WidgetState.selected)
              ? Colors.transparent
              : c.outlineStrong,
        ),
      ),
      segmentedButtonTheme: SegmentedButtonThemeData(
        style: SegmentedButton.styleFrom(
          minimumSize: const Size(AppSize.touch, AppSize.touch),
          backgroundColor: c.surfaceMuted,
          foregroundColor: c.inkMuted,
          // Igual que ScopeSwitcher: la opción elegida en verde suave.
          selectedBackgroundColor: c.primaryContainer,
          selectedForegroundColor: c.onPrimaryContainer,
          side: BorderSide(color: c.outline),
          textStyle: AppTypography.label,
          // Píldora, como ScopeSwitcher.
          shape: const StadiumBorder(),
        ),
      ),
      navigationBarTheme: NavigationBarThemeData(
        height: 68,
        backgroundColor: c.surface,
        surfaceTintColor: Colors.transparent,
        indicatorColor: c.primaryContainer,
        elevation: 0,
        labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
        labelTextStyle: WidgetStateProperty.resolveWith(
          (s) => AppTypography.label.copyWith(
            color: s.contains(WidgetState.selected) ? c.ink : c.inkMuted,
          ),
        ),
        iconTheme: WidgetStateProperty.resolveWith(
          (s) => IconThemeData(
            size: AppSize.icon,
            color: s.contains(WidgetState.selected)
                ? c.onPrimaryContainer
                : c.inkMuted,
          ),
        ),
      ),
      bottomSheetTheme: BottomSheetThemeData(
        backgroundColor: c.surface,
        surfaceTintColor: Colors.transparent,
        modalBackgroundColor: c.surface,
        modalBarrierColor: c.scrim,
        showDragHandle: true,
        dragHandleColor: c.outlineStrong,
        shape: const RoundedRectangleBorder(borderRadius: AppRadius.sheetTop),
        clipBehavior: Clip.antiAlias,
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: c.surface,
        surfaceTintColor: Colors.transparent,
        shape: const RoundedRectangleBorder(borderRadius: AppRadius.cardAll),
        titleTextStyle: AppTypography.subtitle.copyWith(color: c.ink),
        contentTextStyle: AppTypography.body.copyWith(color: c.inkMuted),
      ),
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        backgroundColor: c.ink,
        contentTextStyle: AppTypography.body.copyWith(color: c.surface),
        actionTextColor: c.heroAccent,
        shape: const RoundedRectangleBorder(borderRadius: AppRadius.controlAll),
        insetPadding: const EdgeInsets.all(AppSpace.md),
      ),
      progressIndicatorTheme: ProgressIndicatorThemeData(
        color: c.primary,
        linearTrackColor: c.surfaceSunken,
        circularTrackColor: c.surfaceSunken,
      ),
      dividerTheme: DividerThemeData(color: c.outline, thickness: 1, space: 1),
      listTileTheme: ListTileThemeData(
        contentPadding: const EdgeInsets.symmetric(horizontal: AppSpace.md),
        minVerticalPadding: AppSpace.sm,
        iconColor: c.inkMuted,
        titleTextStyle: AppTypography.body.copyWith(
          color: c.ink,
          fontWeight: FontWeight.w600,
        ),
        subtitleTextStyle: AppTypography.caption.copyWith(color: c.inkSubtle),
      ),
    );
  }
}

/// Acceso corto a los tokens desde cualquier widget.
extension AppThemeX on BuildContext {
  AppColors get colors => Theme.of(this).extension<AppColors>()!;
  TextTheme get text => Theme.of(this).textTheme;
}
