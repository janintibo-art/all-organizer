import 'package:flutter/material.dart';

import '../main.dart';
import 'root_screen.dart';

/// Ecran de demarrage : l'embleme apparait, un trait rouge se trace sous lui,
/// puis la bibliotheque prend la place. Ecrit en Flutter plutot qu'en splash
/// natif : un seul comportement pour Windows et Android, aucune dependance.
class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1500),
  );

  late final Animation<double> _emblem = CurvedAnimation(
    parent: _controller,
    curve: const Interval(0.0, 0.45, curve: Curves.easeOut),
  );

  late final Animation<double> _stroke = CurvedAnimation(
    parent: _controller,
    curve: const Interval(0.35, 0.75, curve: Curves.easeInOutCubic),
  );

  late final Animation<double> _title = CurvedAnimation(
    parent: _controller,
    curve: const Interval(0.55, 1.0, curve: Curves.easeOut),
  );

  @override
  void initState() {
    super.initState();
    _controller.forward();
    _controller.addStatusListener((status) {
      if (status == AnimationStatus.completed && mounted) {
        Navigator.of(context).pushReplacement(
          PageRouteBuilder(
            transitionDuration: const Duration(milliseconds: 350),
            pageBuilder: (_, __, ___) => const RootScreen(),
            transitionsBuilder: (_, animation, __, child) =>
                FadeTransition(opacity: animation, child: child),
          ),
        );
      }
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Palette.ink,
      body: Center(
        child: AnimatedBuilder(
          animation: _controller,
          builder: (context, _) {
            return Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Opacity(
                  opacity: _emblem.value,
                  child: Transform.scale(
                    scale: 0.92 + 0.08 * _emblem.value,
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(radiusMd * 2),
                      child: Image.asset('assets/icon.png',
                          width: 132, height: 132, fit: BoxFit.cover),
                    ),
                  ),
                ),
                const SizedBox(height: 26),
                SizedBox(
                  height: 3,
                  width: 200,
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: Container(
                      width: 200 * _stroke.value,
                      height: 3,
                      color: Palette.shu,
                    ),
                  ),
                ),
                const SizedBox(height: 22),
                Opacity(
                  opacity: _title.value,
                  child: Column(
                    children: [
                      Text(
                        'All Organizer',
                        style: TextStyle(
                          fontSize: 19,
                          fontWeight: FontWeight.w700,
                          letterSpacing: 0.5,
                          color: Palette.text,
                        ),
                      ),
                      SizedBox(height: 5),
                      Text(
                        'TOUTE MA COLLECTION',
                        style: TextStyle(
                          fontSize: 11,
                          letterSpacing: 3,
                          color: Palette.muted,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}
