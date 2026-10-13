import 'package:flutter/material.dart';

/// Los colores de estado de la web del radar (mismos valores), para que la app y la web se reconozcan.
@immutable
class ColoresDeEstado extends ThemeExtension<ColoresDeEstado> {
  const ColoresDeEstado({
    required this.enPlazo,
    required this.enPlazoFondo,
    required this.pendiente,
    required this.pendienteFondo,
    required this.anulada,
    required this.anuladaFondo,
    required this.cerrada,
    required this.cerradaFondo,
    required this.textoSuave,
  });

  static const claro = ColoresDeEstado(
    enPlazo: Color(0xFF15703A),
    enPlazoFondo: Color(0xFFE2F4E9),
    pendiente: Color(0xFF8A4B06),
    pendienteFondo: Color(0xFFFBEFD9),
    anulada: Color(0xFFA61B1B),
    anuladaFondo: Color(0xFFFBE4E4),
    cerrada: Color(0xFF4A5565),
    cerradaFondo: Color(0xFFE9EDF2),
    textoSuave: Color(0xFF556070),
  );

  static const oscuro = ColoresDeEstado(
    enPlazo: Color(0xFF6FD29A),
    enPlazoFondo: Color(0xFF163423),
    pendiente: Color(0xFFF2B866),
    pendienteFondo: Color(0xFF3A2A12),
    anulada: Color(0xFFFF9B9B),
    anuladaFondo: Color(0xFF3D1C1C),
    cerrada: Color(0xFFB3BDCA),
    cerradaFondo: Color(0xFF262F3A),
    textoSuave: Color(0xFF9BA7B6),
  );

  final Color enPlazo;
  final Color enPlazoFondo;
  final Color pendiente;
  final Color pendienteFondo;
  final Color anulada;
  final Color anuladaFondo;
  final Color cerrada;
  final Color cerradaFondo;
  final Color textoSuave;

  @override
  ColoresDeEstado copyWith() => this;

  @override
  ColoresDeEstado lerp(ColoresDeEstado? other, double t) => t < 0.5 || other == null ? this : other;
}

extension ColoresDelTema on BuildContext {
  ColoresDeEstado get estados => Theme.of(this).extension<ColoresDeEstado>()!;
}

ThemeData temaClaro() => _tema(
  Brightness.light,
  const ColorScheme.light(
    primary: Color(0xFF1D4ED8),
    primaryContainer: Color(0xFFE3EAFC),
    onPrimaryContainer: Color(0xFF0D1420),
    // Los filtros y chips seleccionados usan el secundario: el mismo azul suave, no el verde azulado por defecto.
    secondary: Color(0xFF1D4ED8),
    secondaryContainer: Color(0xFFE3EAFC),
    onSecondaryContainer: Color(0xFF0D1420),
    surfaceContainerLowest: Color(0xFFFFFFFF),
    surfaceContainerLow: Color(0xFFF6F7F9),
    surfaceContainer: Color(0xFFF1F3F6),
    surfaceContainerHigh: Color(0xFFE9EDF2),
    onSurface: Color(0xFF1C2430),
    onSurfaceVariant: Color(0xFF556070),
    outline: Color(0xFFB5BFCC),
    outlineVariant: Color(0xFFD7DDE5),
    error: Color(0xFFA61B1B),
  ),
  ColoresDeEstado.claro,
);

ThemeData temaOscuro() => _tema(
  Brightness.dark,
  const ColorScheme.dark(
    primary: Color(0xFF7EA2FF),
    onPrimary: Color(0xFF0D1420),
    primaryContainer: Color(0xFF1F2C4A),
    onPrimaryContainer: Color(0xFFE5E9EF),
    secondary: Color(0xFF7EA2FF),
    onSecondary: Color(0xFF0D1420),
    secondaryContainer: Color(0xFF1F2C4A),
    onSecondaryContainer: Color(0xFFE5E9EF),
    surface: Color(0xFF11161C),
    surfaceContainerLowest: Color(0xFF0C1015),
    surfaceContainerLow: Color(0xFF151B22),
    surfaceContainer: Color(0xFF1A222B),
    surfaceContainerHigh: Color(0xFF262F3A),
    onSurface: Color(0xFFE5E9EF),
    onSurfaceVariant: Color(0xFF9BA7B6),
    outline: Color(0xFF435163),
    outlineVariant: Color(0xFF2D3946),
    error: Color(0xFFFF9B9B),
  ),
  ColoresDeEstado.oscuro,
);

const fuente = 'IBM Plex Sans';

/// Un tema plano: listas sobre el fondo, separadas por líneas finas, sin tarjetas con borde ni sombras. La jerarquía
/// la marcan el tamaño y el peso del texto, no las cajas.
ThemeData _tema(Brightness brillo, ColorScheme colores, ColoresDeEstado estados) {
  final base = ThemeData(colorScheme: colores, brightness: brillo, useMaterial3: true, fontFamily: fuente);
  final texto = base.textTheme.copyWith(
    headlineSmall: base.textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w600, letterSpacing: -0.4),
    titleLarge: base.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w600, letterSpacing: -0.2),
    titleMedium: base.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600),
    titleSmall: base.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w600, height: 1.3),
    labelSmall: base.textTheme.labelSmall?.copyWith(fontWeight: FontWeight.w600, letterSpacing: 0.8),
  );
  return base.copyWith(
    textTheme: texto,
    scaffoldBackgroundColor: colores.surface,
    extensions: [estados],
    appBarTheme: AppBarTheme(
      backgroundColor: colores.surface,
      surfaceTintColor: Colors.transparent,
      scrolledUnderElevation: 0,
      centerTitle: false,
      titleTextStyle: texto.headlineSmall?.copyWith(color: colores.onSurface),
    ),
    cardTheme: CardThemeData(
      elevation: 0,
      margin: EdgeInsets.zero,
      color: colores.surfaceContainer,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
    ),
    navigationBarTheme: NavigationBarThemeData(
      backgroundColor: colores.surface,
      surfaceTintColor: Colors.transparent,
      indicatorColor: Colors.transparent,
      height: 64,
      labelTextStyle: WidgetStateProperty.resolveWith(
        (estado) => texto.labelMedium?.copyWith(
          fontWeight: estado.contains(WidgetState.selected) ? FontWeight.w600 : FontWeight.w500,
          color: estado.contains(WidgetState.selected) ? colores.primary : colores.onSurfaceVariant,
        ),
      ),
      iconTheme: WidgetStateProperty.resolveWith(
        (estado) =>
            IconThemeData(color: estado.contains(WidgetState.selected) ? colores.primary : colores.onSurfaceVariant),
      ),
    ),
    chipTheme: base.chipTheme.copyWith(
      side: BorderSide.none,
      backgroundColor: colores.surfaceContainer,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      labelStyle: texto.labelLarge,
    ),
    searchBarTheme: SearchBarThemeData(
      elevation: const WidgetStatePropertyAll(0),
      backgroundColor: WidgetStatePropertyAll(colores.surfaceContainer),
      shape: WidgetStatePropertyAll(RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))),
      constraints: const BoxConstraints(minHeight: 48),
      hintStyle: WidgetStatePropertyAll(texto.bodyLarge?.copyWith(color: colores.onSurfaceVariant)),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: colores.surfaceContainer,
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide.none),
    ),
    dividerTheme: DividerThemeData(color: colores.outlineVariant, space: 1, thickness: 1),
  );
}

/// Cifras con dígitos del mismo ancho, para que los importes se alineen.
const cifras = TextStyle(fontFeatures: [FontFeature.tabularFigures()]);
