import 'package:flutter/material.dart';
import 'package:media_kit/media_kit.dart';

import 'dart:async';

import 'screens/splash_screen.dart';
import 'services/anime_index.dart';
import 'services/audio_player_service.dart';
import 'services/library_controller.dart';
import 'services/music_controller.dart';
import 'services/seed_database.dart';

/// Un thème complet.
///
/// Les quatre partagent la même bannière : l'application n'a qu'une
/// identité visuelle, seules les couleurs changent.
class AppTheme {
  final String id;
  final String name;
  final String description;
  final String logo;
  final Color ink;
  final Color surface;
  final Color raised;
  final Color line;
  final Color shu;
  final Color kin;
  final Color sakura;
  final Color text;
  final Color muted;

  const AppTheme({
    required this.id,
    required this.name,
    required this.description,
    required this.logo,
    required this.ink,
    required this.surface,
    required this.raised,
    required this.line,
    required this.shu,
    required this.kin,
    required this.sakura,
    required this.text,
    required this.muted,
  });
}

const List<AppTheme> appThemes = [
  AppTheme(
    id: 'encre',
    name: 'Encre',
    description: 'Noir chaud, vermillon de sceau et or',
    logo: 'assets/logo.png',
    ink: Color(0xFF0D0B0B),
    surface: Color(0xFF181311),
    raised: Color(0xFF221A17),
    line: Color(0xFF352724),
    shu: Color(0xFFBF2F25),
    kin: Color(0xFFD6B86A),
    sakura: Color(0xFFE3A2AB),
    text: Color(0xFFF4E7D3),
    muted: Color(0xFF9C8A80),
  ),
  AppTheme(
    id: 'grimoire',
    name: 'Grimoire',
    description: 'Or ancien sur noir profond, rouge sang',
    logo: 'assets/logo.png',
    ink: Color(0xFF0A0908),
    surface: Color(0xFF15110E),
    raised: Color(0xFF1F1913),
    line: Color(0xFF3A2E20),
    shu: Color(0xFFB01B1B),
    kin: Color(0xFFD9B45B),
    sakura: Color(0xFFC98B8B),
    text: Color(0xFFF2E7D0),
    muted: Color(0xFF9A8B72),
  ),
  AppTheme(
    id: 'aventure',
    name: 'Aventure',
    description: 'Bleu nuit, rouge vif et or clair',
    logo: 'assets/logo.png',
    ink: Color(0xFF101820),
    surface: Color(0xFF18222C),
    raised: Color(0xFF22303C),
    line: Color(0xFF2E3E4C),
    shu: Color(0xFFD6453C),
    kin: Color(0xFFF0B840),
    sakura: Color(0xFF7FC4E8),
    text: Color(0xFFF5EEE2),
    muted: Color(0xFF93A3B0),
  ),
  AppTheme(
    id: 'sorciere',
    name: 'Sorcière',
    description: 'Rouge carmin et or, fond terre brûlée',
    logo: 'assets/logo.png',
    ink: Color(0xFF14100E),
    surface: Color(0xFF1F1815),
    raised: Color(0xFF2A211C),
    line: Color(0xFF3B2E26),
    shu: Color(0xFFC2352B),
    kin: Color(0xFFE0B057),
    sakura: Color(0xFFE3A2AB),
    text: Color(0xFFF7EFE2),
    muted: Color(0xFFA2907E),
  ),
];

/// Couleurs actives.
///
/// Elles ne sont volontairement pas constantes : changer de thème réaffecte
/// ces champs, et toute l'application suit au prochain rendu.
class Palette {
  static AppTheme current = appThemes.first;

  static Color ink = current.ink;
  static Color surface = current.surface;
  static Color raised = current.raised;
  static Color line = current.line;
  static Color shu = current.shu;
  static Color kin = current.kin;
  static Color sakura = current.sakura;
  static Color text = current.text;
  static Color muted = current.muted;

  static String get logo => current.logo;

  static void apply(String id) {
    current = appThemes.firstWhere(
      (t) => t.id == id,
      orElse: () => appThemes.first,
    );
    ink = current.ink;
    surface = current.surface;
    raised = current.raised;
    line = current.line;
    shu = current.shu;
    kin = current.kin;
    sakura = current.sakura;
    text = current.text;
    muted = current.muted;
  }
}

/// Arrondis : deux valeurs seulement, pour que tout l'écran respire pareil.
const double radiusSm = 4; // puces, badges, champs
const double radiusMd = 8; // affiches, cartes, boîtes de dialogue

/// Decoration commune des champs de saisie.
/// Definie ici plutot que dans le theme : l'API du theme change souvent
/// d'une version de Flutter a l'autre, celle-ci est stable.
InputDecoration fieldDecoration({
  String? hintText,
  String? labelText,
  Widget? prefixIcon,
  Widget? suffixIcon,
}) {
  final border = OutlineInputBorder(
    borderRadius: BorderRadius.circular(radiusSm),
    borderSide: BorderSide(color: Palette.line),
  );
  return InputDecoration(
    hintText: hintText,
    labelText: labelText,
    prefixIcon: prefixIcon,
    suffixIcon: suffixIcon,
    filled: true,
    fillColor: Palette.surface,
    hintStyle: TextStyle(color: Palette.muted, fontSize: 12.5),
    labelStyle: TextStyle(color: Palette.muted, fontSize: 13),
    border: border,
    enabledBorder: border,
    focusedBorder: border,
    contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
  );
}

/// Barre de titre commune a tous les ecrans.
AppBar darkAppBar({required Widget title, List<Widget>? actions}) {
  return AppBar(
    title: title,
    actions: actions,
    backgroundColor: Palette.ink,
    surfaceTintColor: Colors.transparent,
    foregroundColor: Palette.text,
    elevation: 0,
    centerTitle: false,
    titleTextStyle: TextStyle(
      color: Palette.text,
      fontSize: 20,
      fontWeight: FontWeight.w600,
      letterSpacing: -0.4,
    ),
  );
}

/// Erreurs survenues au démarrage, montrées à l'écran plutôt que
/// silencieusement avalées.
final List<String> startupErrors = [];

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  ErrorWidget.builder = (details) => Container(
        color: Palette.ink,
        padding: const EdgeInsets.all(24),
        alignment: Alignment.center,
        child: SingleChildScrollView(
          child: Text(
            'Une erreur est survenue :\n\n${details.exception}',
            style: TextStyle(color: Palette.text, fontSize: 12, height: 1.5),
          ),
        ),
      );

  try {
    MediaKit.ensureInitialized();
  } catch (e) {
    startupErrors.add('Vidéo : $e');
  }

  try {
    await initAudio();
  } catch (e) {
    startupErrors.add('Audio : $e');
  }

  try {
    await SeedDatabase.load();
  } catch (e) {
    startupErrors.add('Base locale : $e');
  }

  try {
    await library.load();
  } catch (e) {
    startupErrors.add('Bibliothèque : $e');
  }

  // L'index complet est volumineux : on le charge en arriere-plan, la
  // bibliotheque s'affiche sans l'attendre.
  if (library.settings.useIndex) {
    unawaited(AnimeIndex.load());
  }

  try {
    await music.load();
  } catch (e) {
    startupErrors.add('Musique : $e');
  }

  runApp(const AllOrganizerApp());
}

class AllOrganizerApp extends StatelessWidget {
  const AllOrganizerApp({super.key});

  @override
  Widget build(BuildContext context) {
    // Le contrôleur notifie le changement de thème : l'arbre entier
    // se reconstruit avec les nouvelles couleurs.
    return AnimatedBuilder(
      animation: library,
      builder: (context, _) => _buildApp(),
    );
  }

  Widget _buildApp() {
    final base = ThemeData(
      useMaterial3: true,
      brightness: Brightness.dark,
      scaffoldBackgroundColor: Palette.ink,
      colorScheme: ColorScheme.dark(
        primary: Palette.shu,
        secondary: Palette.kin,
        surface: Palette.surface,
        onSurface: Palette.text,
      ),
    );

    return MaterialApp(
      title: 'All Organizer',
      debugShowCheckedModeBanner: false,
      theme: base.copyWith(
        bottomSheetTheme:
            BottomSheetThemeData(backgroundColor: Palette.surface),
        textTheme: base.textTheme.apply(
          bodyColor: Palette.text,
          displayColor: Palette.text,
        ),
        snackBarTheme: SnackBarThemeData(
          backgroundColor: Palette.raised,
          contentTextStyle: TextStyle(color: Palette.text),
        ),
      ),
      home: const SplashScreen(),
    );
  }
}
