import 'package:flutter/material.dart';

import '../main.dart';
import '../models/server_profile.dart';
import '../services/library_controller.dart';
import '../services/server_api.dart';
import '../services/wake.dart';
import 'settings_screen.dart';

/// Gestion des serveurs : ajout, test de connexion, réveil.
class ServersScreen extends StatefulWidget {
  const ServersScreen({super.key});

  @override
  State<ServersScreen> createState() => _ServersScreenState();
}

class _ServersScreenState extends State<ServersScreen> {
  final Map<String, String> _etats = {};
  final Set<String> _occupes = {};

  Future<void> _tester(ServerProfile s) async {
    setState(() {
      _occupes.add(s.id);
      _etats[s.id] = 'Test en cours…';
    });

    final reponse = await ServerApi.ping(s);
    if (!mounted) return;

    if (reponse != null) {
      setState(() {
        _occupes.remove(s.id);
        _etats[s.id] = 'En ligne · $reponse';
      });
      return;
    }

    // Le serveur ne répond pas : on tente le réveil si c'est prévu.
    if (library.settings.autoWake && s.hasWake) {
      final ok = await Wake.wakeAndWait(
        s,
        onProgress: (message) {
          if (mounted) setState(() => _etats[s.id] = message);
        },
      );
      if (!mounted) return;
      setState(() {
        _occupes.remove(s.id);
        _etats[s.id] =
            ok ? 'En ligne après réveil.' : (Wake.lastError ?? 'Échec.');
      });
      return;
    }

    setState(() {
      _occupes.remove(s.id);
      _etats[s.id] = ServerApi.lastError ?? 'Injoignable.';
    });
  }

  /// Parcourt le serveur et verse son contenu dans la bibliothèque.
  Future<void> _analyser(ServerProfile s) async {
    setState(() {
      _occupes.add(s.id);
      _etats[s.id] = 'Analyse en cours…';
    });
    final resultat = await library.scanServer(s);
    if (!mounted) return;
    setState(() {
      _occupes.remove(s.id);
      _etats[s.id] = resultat;
    });
  }

  Future<void> _reveiller(ServerProfile s) async {
    setState(() {
      _occupes.add(s.id);
      _etats[s.id] = 'Réveil…';
    });
    final ok = await Wake.wakeAndWait(
      s,
      onProgress: (message) {
        if (mounted) setState(() => _etats[s.id] = message);
      },
    );
    if (!mounted) return;
    setState(() {
      _occupes.remove(s.id);
      _etats[s.id] = ok
          ? 'En ligne après réveil.'
          : (Wake.lastError ?? 'Le serveur n\'a pas répondu.');
    });
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: app,
      builder: (context, _) {
        return Scaffold(
          appBar: darkAppBar(
            title: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  children: [
                    Container(width: 3, height: 18, color: Palette.shu),
                    const SizedBox(width: 8),
                    const Text('Serveurs'),
                  ],
                ),
                Padding(
                  padding: const EdgeInsets.only(left: 11, top: 1),
                  child: Text(
                      library.servers.isEmpty
                          ? 'Aucun serveur enregistré'
                          : '${library.servers.length} serveur(s)',
                      style: TextStyle(
                          color: Palette.muted,
                          fontSize: 10.5,
                          letterSpacing: 0.8)),
                ),
              ],
            ),
            actions: [
              IconButton(
                tooltip: 'Réglages',
                onPressed: () => Navigator.of(context).push(
                  MaterialPageRoute(builder: (_) => const SettingsScreen()),
                ),
                icon: const Icon(Icons.tune),
              ),
            ],
          ),
          floatingActionButton: FloatingActionButton.extended(
            onPressed: () => _editer(null),
            backgroundColor: Palette.shu,
            foregroundColor: Colors.white,
            icon: const Icon(Icons.add),
            label: const Text('Ajouter'),
          ),
          body: library.servers.isEmpty
              ? _vide()
              : ListView(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 100),
                  children: [
                    for (final s in library.servers) _carte(s),
                  ],
                ),
        );
      },
    );
  }

  Widget _carte(ServerProfile s) {
    final titres = library.items.where((a) => a.serverId == s.id).length;
    final etat = _etats[s.id];
    final occupe = _occupes.contains(s.id);

    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
      decoration: BoxDecoration(
        color: Palette.surface,
        border: Border.all(
            color: titres > 0 ? Palette.shu : Palette.line,
            width: titres > 0 ? 2 : 1),
        borderRadius: BorderRadius.circular(radiusMd),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.dns_outlined,
                  size: 18, color: titres > 0 ? Palette.shu : Palette.kin),
              const SizedBox(width: 8),
              Expanded(
                child: Text(s.name,
                    style: TextStyle(
                        color: Palette.text,
                        fontSize: 15,
                        fontWeight: FontWeight.w700)),
              ),
              if (titres > 0)
                Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: Palette.shu,
                    borderRadius: BorderRadius.circular(radiusSm),
                  ),
                  child: Text('$titres titres',
                      style: const TextStyle(
                          color: Colors.white,
                          fontSize: 10.5,
                          fontWeight: FontWeight.w700)),
                ),
              PopupMenuButton<String>(
                color: Palette.surface,
                icon: Icon(Icons.more_vert, color: Palette.muted, size: 20),
                onSelected: (choix) {
                  switch (choix) {
                    case 'scan':
                      _analyser(s);
                      break;
                    case 'modifier':
                      _editer(s);
                      break;
                    case 'supprimer':
                      _confirmerSuppression(s);
                      break;
                  }
                },
                itemBuilder: (_) => const [
                  PopupMenuItem(value: 'scan', child: Text('Analyser')),
                  PopupMenuItem(value: 'modifier', child: Text('Modifier')),
                  PopupMenuItem(value: 'supprimer', child: Text('Supprimer')),
                ],
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(s.baseUrl,
              style: TextStyle(color: Palette.muted, fontSize: 12)),
          if (s.hasWake)
            Padding(
              padding: const EdgeInsets.only(top: 2),
              child: Text('Réveil : ${s.wakeUrl}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(color: Palette.muted, fontSize: 11)),
            ),
          if (etat != null) ...[
            const SizedBox(height: 8),
            Row(
              children: [
                if (occupe)
                  SizedBox(
                    width: 12,
                    height: 12,
                    child: CircularProgressIndicator(
                        strokeWidth: 2, color: Palette.shu),
                  ),
                if (occupe) const SizedBox(width: 8),
                Expanded(
                  child: Text(etat,
                      style: TextStyle(
                          color: etat.startsWith('En ligne')
                              ? Palette.kin
                              : Palette.shu,
                          fontSize: 12,
                          height: 1.4)),
                ),
              ],
            ),
          ],
          const SizedBox(height: 10),
          Wrap(
            spacing: 10,
            runSpacing: 8,
            children: [
              OutlinedButton.icon(
                onPressed: occupe ? null : () => _tester(s),
                icon: const Icon(Icons.wifi_tethering, size: 18),
                label: const Text('Tester'),
              ),
              OutlinedButton.icon(
                onPressed: occupe || library.busy ? null : () => _analyser(s),
                icon: const Icon(Icons.travel_explore, size: 18),
                label: const Text('Analyser'),
              ),
              if (s.hasWake)
                OutlinedButton.icon(
                  onPressed: occupe ? null : () => _reveiller(s),
                  icon: const Icon(Icons.power_settings_new, size: 18),
                  label: const Text('Réveiller le PC'),
                ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _vide() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Image.asset(Palette.logo, width: 240, fit: BoxFit.contain),
            const SizedBox(height: 24),
            Text('Aucun serveur',
                style: TextStyle(
                    color: Palette.text,
                    fontSize: 18,
                    fontWeight: FontWeight.w600)),
            const SizedBox(height: 8),
            Text(
              'Lance le script serveur sur ton PC, puis saisis ici l\'adresse '
              'qu\'il affiche, du type http://192.168.1.42:8321',
              textAlign: TextAlign.center,
              style: TextStyle(
                  color: Palette.muted, height: 1.5, fontSize: 13.5),
            ),
            const SizedBox(height: 20),
            FilledButton.icon(
              onPressed: () => _editer(null),
              style: FilledButton.styleFrom(backgroundColor: Palette.shu),
              icon: const Icon(Icons.add),
              label: const Text('Ajouter un serveur'),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _confirmerSuppression(ServerProfile s) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: Palette.surface,
        title: Text('Supprimer « ${s.name} » ?'),
        content: const Text(
            'Les positions de lecture mémorisées pour ce serveur seront '
            'également effacées.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Annuler')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Palette.shu),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Supprimer'),
          ),
        ],
      ),
    );
    if (ok == true) await library.removeServer(s);
  }

  Future<void> _editer(ServerProfile? existant) async {
    final nom = TextEditingController(text: existant?.name ?? '');
    final url = TextEditingController(text: existant?.url ?? '');
    final jeton = TextEditingController(text: existant?.token ?? '');
    final reveil = TextEditingController(text: existant?.wakeUrl ?? '');
    final attente = TextEditingController(
        text: (existant?.wakeWaitSeconds ?? 60).toString());

    final ok = await showModalBottomSheet<bool>(
      context: context,
      backgroundColor: Palette.surface,
      isScrollControlled: true,
      builder: (ctx) => Padding(
        padding: EdgeInsets.only(
          left: 16,
          right: 16,
          top: 16,
          bottom: MediaQuery.of(ctx).viewInsets.bottom + 24,
        ),
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                children: [
                  Container(width: 3, height: 16, color: Palette.shu),
                  const SizedBox(width: 8),
                  Text(existant == null ? 'Nouveau serveur' : 'Modifier',
                      style: TextStyle(
                          color: Palette.text,
                          fontSize: 16,
                          fontWeight: FontWeight.w700)),
                ],
              ),
              const SizedBox(height: 16),
              _champ(nom, 'Nom', 'Le PC du salon'),
              _champ(url, 'Adresse du serveur', 'http://192.168.1.42:8321',
                  clavier: TextInputType.url),
              _champ(jeton, 'Jeton', 'Laisse vide si le serveur n\'en '
                  'demande pas'),
              const SizedBox(height: 6),
              Text('Réveil à distance',
                  style: TextStyle(
                      color: Palette.text,
                      fontSize: 14,
                      fontWeight: FontWeight.w700)),
              const SizedBox(height: 4),
              Text(
                'Adresse appelée pour allumer le PC. Colle celle de ton '
                'module, quel qu\'il soit — Tasmota, ESPHome ou un montage '
                'maison.',
                style: TextStyle(
                    color: Palette.muted, fontSize: 11.5, height: 1.4),
              ),
              const SizedBox(height: 10),
              _champ(reveil, 'Adresse de réveil',
                  'http://192.168.1.50/cm?cmnd=Power%20on',
                  clavier: TextInputType.url),
              _champ(attente, 'Délai d\'attente après réveil (secondes)', '60',
                  clavier: TextInputType.number),
              const SizedBox(height: 8),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton(
                      onPressed: () => Navigator.pop(ctx, false),
                      child: const Text('Annuler')),
                  const SizedBox(width: 8),
                  FilledButton(
                    style:
                        FilledButton.styleFrom(backgroundColor: Palette.shu),
                    onPressed: () => Navigator.pop(ctx, true),
                    child: Text(existant == null ? 'Ajouter' : 'Enregistrer'),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );

    if (ok != true) return;

    final delai = int.tryParse(attente.text.trim()) ?? 60;
    if (existant == null) {
      await library.addServer(
        name: nom.text,
        url: url.text,
        token: jeton.text,
        wakeUrl: reveil.text,
        wakeWaitSeconds: delai.clamp(10, 600),
      );
    } else {
      existant.name = nom.text.trim().isEmpty ? existant.name : nom.text.trim();
      existant.url = url.text;
      existant.token = jeton.text;
      existant.wakeUrl = reveil.text;
      existant.wakeWaitSeconds = delai.clamp(10, 600);
      await library.updateServer(existant);
    }
  }

  Widget _champ(
    TextEditingController controller,
    String label,
    String hint, {
    TextInputType clavier = TextInputType.text,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: TextField(
        controller: controller,
        keyboardType: clavier,
        style: TextStyle(color: Palette.text, fontSize: 14),
        decoration: fieldDecoration(hintText: hint, labelText: label),
      ),
    );
  }
}
