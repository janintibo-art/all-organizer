import 'dart:convert';

import 'package:http/http.dart' as http;

/// Assistant IA branché sur une API compatible OpenAI (Groq, OpenRouter,
/// ou un serveur maison). Sert à identifier une série quand les bases de
/// données ne reconnaissent pas le nom du dossier, et à donner le titre
/// dans les trois écritures : romaji, anglais, français.
class AiService {
  /// Dernier échec, affiché dans les réglages pour ne pas rester aveugle.
  static String? lastError;

  /// Outils réellement utilisés lors de la dernière requête, quand le
  /// système en expose la trace : « web_search », « visit_website »…
  static List<String> lastTools = [];

  /// Systèmes Groq capables d'aller chercher l'information en ligne.
  static const List<String> webCapableModels = [
    'groq/compound',
    'groq/compound-mini',
  ];

  static bool supportsWeb(String model) {
    final m = model.toLowerCase();
    return m.contains('compound') || m.endsWith(':online');
  }

  static String baseUrl(String provider, String custom) {
    switch (provider) {
      case 'groq':
        return 'https://api.groq.com/openai/v1';
      case 'openrouter':
        return 'https://openrouter.ai/api/v1';
      default:
        final trimmed = custom.trim().replaceAll(RegExp(r'/+$'), '');
        return trimmed.isEmpty ? 'https://api.groq.com/openai/v1' : trimmed;
    }
  }

  static Map<String, String> _headers(String key) => {
        'Authorization': 'Bearer $key',
        'Content-Type': 'application/json',
      };

  /// Liste les modèles proposés par le fournisseur.
  static Future<List<String>> listModels({
    required String provider,
    required String apiKey,
    String custom = '',
  }) async {
    if (apiKey.trim().isEmpty) return const [];
    try {
      final res = await http
          .get(Uri.parse('${baseUrl(provider, custom)}/models'),
              headers: _headers(apiKey))
          .timeout(const Duration(seconds: 20));
      if (res.statusCode != 200) return const [];
      final body = jsonDecode(utf8.decode(res.bodyBytes)) as Map<String, dynamic>;
      final data = body['data'] as List? ?? const [];
      final ids = data
          .map((e) => (e as Map)['id']?.toString())
          .whereType<String>()
          .toList()
        ..sort();
      return ids;
    } catch (_) {
      return const [];
    }
  }

  /// Envoie une question et renvoie la réponse, ou null en cas d'échec.
  ///
  /// Deux pièges avec les modèles à raisonnement du type gpt-oss : ils
  /// consomment leur budget de jetons dans un champ « reasoning » séparé et
  /// renvoient un « content » vide. On leur laisse donc de la marge, on leur
  /// demande un raisonnement court, et on lit les deux champs.
  static Future<String?> ask({
    required String provider,
    required String apiKey,
    required String model,
    required String system,
    required String user,
    String custom = '',
    int maxTokens = 1200,
    bool webSearch = false,
  }) async {
    lastError = null;
    lastTools = [];
    if (apiKey.trim().isEmpty) {
      lastError = 'Aucune clé renseignée.';
      return null;
    }
    if (model.trim().isEmpty) {
      lastError = 'Aucun modèle choisi.';
      return null;
    }

    // OpenRouter active la recherche web par un suffixe sur le modèle,
    // Groq par un paramètre dédié : les deux voies sont gérées ici.
    var effectiveModel = model;
    if (webSearch &&
        provider == 'openrouter' &&
        !model.toLowerCase().endsWith(':online')) {
      effectiveModel = '$model:online';
    }

    final payload = <String, dynamic>{
      'model': effectiveModel,
      'temperature': 0.2,
      'max_tokens': maxTokens,
      'messages': [
        {'role': 'system', 'content': system},
        {'role': 'user', 'content': user},
      ],
      if (model.toLowerCase().contains('gpt-oss')) 'reasoning_effort': 'low',
      if (webSearch && model.toLowerCase().contains('compound'))
        'compound_custom': {
          'tools': {
            'enabled_tools': ['web_search', 'visit_website'],
          },
        },
    };

    try {
      final res = await http
          .post(
            Uri.parse('${baseUrl(provider, custom)}/chat/completions'),
            headers: _headers(apiKey),
            body: jsonEncode(payload),
          )
          .timeout(const Duration(seconds: 60));

      if (res.statusCode != 200) {
        lastError = 'HTTP ${res.statusCode} — ${res.body}';
        return null;
      }

      final body = jsonDecode(utf8.decode(res.bodyBytes)) as Map<String, dynamic>;
      final choices = body['choices'] as List? ?? const [];
      if (choices.isEmpty) {
        lastError = 'Réponse sans contenu.';
        return null;
      }

      final choice = choices.first as Map;
      final message = choice['message'] as Map?;

      // Trace des outils : utile pour savoir si la réponse vient du web.
      final executed = message?['executed_tools'] as List? ?? const [];
      lastTools = executed
          .map((t) => (t as Map)['type']?.toString() ?? '')
          .where((t) => t.isNotEmpty)
          .toList();

      final content = message?['content']?.toString().trim();
      if (content != null && content.isNotEmpty) return content;

      // Le contenu est vide : on tente le champ de raisonnement.
      final reasoning = message?['reasoning']?.toString().trim();
      if (reasoning != null && reasoning.isNotEmpty) return reasoning;

      final reason = choice['finish_reason']?.toString() ?? 'inconnue';
      lastError = 'Le modèle a répondu sans texte (raison : $reason). '
          'Augmente le budget de jetons ou choisis un modèle sans raisonnement, '
          'par exemple llama-3.3-70b-versatile.';
      return null;
    } catch (e) {
      lastError = e.toString();
      return null;
    }
  }

  /// Vérifie que la clé et le modèle répondent.
  static Future<String> test({
    required String provider,
    required String apiKey,
    required String model,
    String custom = '',
  }) async {
    if (apiKey.trim().isEmpty) return 'Aucune clé renseignée.';
    if (model.trim().isEmpty) return 'Aucun modèle choisi.';
    final answer = await ask(
      provider: provider,
      apiKey: apiKey,
      model: model,
      custom: custom,
      system: 'Réponds par un seul mot, sans explication.',
      user: 'Dis simplement : ok',
      maxTokens: 800,
    );
    if (answer == null) {
      return 'Échec — ${lastError ?? 'pas de réponse'}';
    }
    final short = answer.length > 120 ? '${answer.substring(0, 120)}…' : answer;
    return 'Connexion réussie — réponse : $short';
  }

  /// Propose des séries à partir d'une demande en français.
  ///
  /// Le modèle ne consulte pas Internet : ses titres sont ensuite vérifiés
  /// contre l'index local avant d'être affichés. Ce qu'il invente disparaît.
  static Future<List<AiSuggestion>> suggest({
    required String request,
    required String provider,
    required String apiKey,
    required String model,
    String custom = '',
    List<String> ownedTitles = const [],
    List<String> candidates = const [],
    int count = 12,
    bool webSearch = false,
  }) async {
    const system =
        'Tu conseilles des séries d\'animation japonaise. Si tu disposes '
        'd\'une recherche web, utilise-la pour vérifier les dates de sortie. '
        'Tu réponds '
        'uniquement par un tableau JSON, sans texte autour ni balises de code. '
        'Chaque élément : {"title":"titre en romaji","reason":"une phrase "'
        '"courte en français"}. Utilise le titre romaji officiel, celui que '
        'les bases de données référencent.';

    final buffer = StringBuffer('Demande : $request\n');

    if (ownedTitles.isNotEmpty) {
      final sample = ownedTitles.take(40).join(', ');
      buffer.write('\nSéries déjà possédées, à ne pas reproposer : $sample\n');
    }

    if (candidates.isNotEmpty) {
      buffer.write('\nChoisis uniquement dans cette liste réelle, sans rien '
          'ajouter :\n${candidates.take(60).join('\n')}\n');
    }

    buffer.write('\nRenvoie au plus $count éléments.');

    final answer = await ask(
      provider: provider,
      apiKey: apiKey,
      model: model,
      custom: custom,
      system: system,
      user: buffer.toString(),
      maxTokens: 2000,
      webSearch: webSearch,
    );
    if (answer == null) return const [];

    try {
      final start = answer.indexOf('[');
      final end = answer.lastIndexOf(']');
      if (start < 0 || end <= start) {
        lastError = 'Réponse illisible.';
        return const [];
      }
      final list = jsonDecode(answer.substring(start, end + 1)) as List;
      final out = <AiSuggestion>[];
      for (final item in list) {
        if (item is! Map) continue;
        final title = item['title']?.toString().trim() ?? '';
        if (title.isEmpty) continue;
        out.add(AiSuggestion(title, item['reason']?.toString().trim() ?? ''));
      }
      return out;
    } catch (e) {
      lastError = e.toString();
      return const [];
    }
  }

  /// Identifie une série à partir d'un nom de dossier.
  static Future<AiTitles?> identify({
    required String folderTitle,
    required String provider,
    required String apiKey,
    required String model,
    String custom = '',
  }) async {
    const system =
        'Tu identifies des séries d\'animation japonaise à partir de noms de '
        'dossiers ou de fichiers, souvent mal orthographiés ou traduits. '
        'Tu réponds uniquement par un objet JSON, sans texte autour, sans '
        'balises de code.';

    final user = 'Nom trouvé sur le disque : "$folderTitle".\n'
        'Identifie la série et réponds avec ce JSON exactement :\n'
        '{"romaji":"","english":"","french":"","japanese":"","year":null,'
        '"confidence":0.0}\n'
        'romaji = titre en lettres latines tel qu\'utilisé au Japon, '
        'english = titre anglais officiel, french = titre français officiel '
        '(ou le titre anglais si aucun titre français n\'existe), '
        'japanese = titre en écriture japonaise. '
        'confidence entre 0 et 1. Si tu ne reconnais pas la série, '
        'mets des chaînes vides et confidence à 0.';

    final answer = await ask(
      provider: provider,
      apiKey: apiKey,
      model: model,
      custom: custom,
      system: system,
      user: user,
      maxTokens: 1500,
    );
    if (answer == null) return null;
    final parsed = AiTitles.parse(answer);
    if (parsed == null) {
      final short =
          answer.length > 200 ? '${answer.substring(0, 200)}…' : answer;
      lastError = 'Réponse illisible : $short';
    }
    return parsed;
  }
}

/// Une proposition de l'IA : un titre, et la raison de la proposition.
class AiSuggestion {
  final String title;
  final String reason;
  const AiSuggestion(this.title, this.reason);
}

class AiTitles {
  final String romaji;
  final String english;
  final String french;
  final String japanese;
  final int? year;
  final double confidence;

  const AiTitles({
    this.romaji = '',
    this.english = '',
    this.french = '',
    this.japanese = '',
    this.year,
    this.confidence = 0,
  });

  bool get usable =>
      confidence >= 0.3 && (romaji.isNotEmpty || english.isNotEmpty);

  /// Meilleure requête à envoyer aux bases de données.
  String get searchQuery => romaji.isNotEmpty ? romaji : english;

  /// Les modèles ajoutent parfois du texte ou des balises autour du JSON.
  static AiTitles? parse(String raw) {
    try {
      final start = raw.indexOf('{');
      final end = raw.lastIndexOf('}');
      if (start < 0 || end <= start) return null;
      final map =
          jsonDecode(raw.substring(start, end + 1)) as Map<String, dynamic>;
      return AiTitles(
        romaji: (map['romaji'] ?? '').toString().trim(),
        english: (map['english'] ?? '').toString().trim(),
        french: (map['french'] ?? '').toString().trim(),
        japanese: (map['japanese'] ?? '').toString().trim(),
        year: map['year'] is num ? (map['year'] as num).toInt() : null,
        confidence: map['confidence'] is num
            ? (map['confidence'] as num).toDouble()
            : 0,
      );
    } catch (_) {
      return null;
    }
  }
}
