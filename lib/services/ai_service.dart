import 'dart:convert';

import 'package:http/http.dart' as http;

/// Assistant IA branché sur une API compatible OpenAI (Groq, OpenRouter,
/// ou un serveur maison). Sert à identifier un titre quand les bases de
/// données ne reconnaissent pas le nom du dossier, et à interpréter les
/// demandes de la recherche IA.
class AiService {
  /// Dernier échec, affiché dans les réglages pour ne pas rester aveugle.
  static String? lastError;

  /// Vrai si la dernière réponse a consulté le web (OpenRouter en fournit
  /// la trace sous forme de citations).
  static bool lastUsedWeb = false;

  /// Modèles retirés par leur fournisseur : une requête vers eux échoue.
  /// Groq a arrêté ses systèmes « compound » le 21 septembre 2026, sans
  /// remplaçant — ce sont eux qui portaient la recherche web chez Groq.
  static const Set<String> retiredModels = {
    'groq/compound',
    'groq/compound-mini',
  };

  static const String defaultModel = 'llama-3.3-70b-versatile';

  static bool isRetired(String model) =>
      retiredModels.contains(model.trim().toLowerCase());

  /// Recherche web disponible pour ce fournisseur. Seul OpenRouter la
  /// propose encore, pour n'importe quel modèle, via le suffixe « :online ».
  /// Elle est facturée à la requête, même avec un modèle gratuit.
  static bool supportsWeb(String provider) => provider == 'openrouter';

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

  /// Liste les modèles proposés par le fournisseur, sans ceux qu'il a
  /// retirés mais qu'il annonce parfois encore.
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
          .where((id) => !isRetired(id))
          .toList()
        ..sort();
      return ids;
    } catch (_) {
      return const [];
    }
  }

  /// Envoie une question et renvoie la réponse, ou null en cas d'échec.
  ///
  /// [jsonMode] demande au fournisseur de garantir un objet JSON valide. Un
  /// serveur maison peut ne pas connaître cette option : on retente alors
  /// sans elle, le texte est de toute façon analysé avec tolérance.
  ///
  /// Les modèles à raisonnement (gpt-oss) consomment leur budget dans un
  /// champ « reasoning » séparé : on leur demande un raisonnement court et
  /// on lit les deux champs.
  static Future<String?> ask({
    required String provider,
    required String apiKey,
    required String model,
    required String system,
    required String user,
    String custom = '',
    int maxTokens = 1200,
    bool webSearch = false,
    bool jsonMode = false,
  }) async {
    lastError = null;
    lastUsedWeb = false;
    if (apiKey.trim().isEmpty) {
      lastError = 'Aucune clé renseignée.';
      return null;
    }
    if (model.trim().isEmpty) {
      lastError = 'Aucun modèle choisi.';
      return null;
    }
    if (isRetired(model)) {
      lastError = _retire(model);
      return null;
    }

    var effectiveModel = model;
    if (webSearch &&
        supportsWeb(provider) &&
        !model.toLowerCase().endsWith(':online')) {
      effectiveModel = '$model:online';
    }

    Map<String, dynamic> payload(bool json) => {
          'model': effectiveModel,
          'temperature': 0.2,
          'max_tokens': maxTokens,
          'messages': [
            {'role': 'system', 'content': system},
            {'role': 'user', 'content': user},
          ],
          if (model.toLowerCase().contains('gpt-oss')) 'reasoning_effort': 'low',
          if (json) 'response_format': {'type': 'json_object'},
        };

    try {
      var res = await _post(provider, custom, apiKey, payload(jsonMode));

      // Option JSON refusée par le serveur : on retente sans elle.
      if (jsonMode &&
          res.statusCode == 400 &&
          res.body.toLowerCase().contains('response_format')) {
        res = await _post(provider, custom, apiKey, payload(false));
      }

      if (res.statusCode != 200) {
        lastError = _lisible(res, model);
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

      // OpenRouter joint les pages consultées sous forme de citations.
      final annotations = message?['annotations'] as List? ?? const [];
      lastUsedWeb = annotations
          .any((a) => a is Map && a['type']?.toString() == 'url_citation');

      final content = message?['content']?.toString().trim();
      if (content != null && content.isNotEmpty) return content;

      final reasoning = message?['reasoning']?.toString().trim();
      if (reasoning != null && reasoning.isNotEmpty) return reasoning;

      final reason = choice['finish_reason']?.toString() ?? 'inconnue';
      lastError = 'Le modèle a répondu sans texte (raison : $reason). '
          'Choisis un modèle sans raisonnement, par exemple $defaultModel.';
      return null;
    } catch (e) {
      lastError = e.toString();
      return null;
    }
  }

  static Future<http.Response> _post(String provider, String custom,
      String apiKey, Map<String, dynamic> payload) {
    return http
        .post(
          Uri.parse('${baseUrl(provider, custom)}/chat/completions'),
          headers: _headers(apiKey),
          body: jsonEncode(payload),
        )
        .timeout(const Duration(seconds: 60));
  }

  static String _retire(String model) =>
      'Le modèle « $model » a été retiré par son fournisseur. '
      'Choisis-en un autre dans Réglages → Assistant IA, par exemple '
      '$defaultModel.';

  /// Traduit les erreurs courantes en français compréhensible.
  static String _lisible(http.Response res, String model) {
    final brut = res.body.toLowerCase();
    if (brut.contains('decommissioned') ||
        brut.contains('model_not_found') ||
        brut.contains('does not exist')) {
      return _retire(model);
    }
    if (res.statusCode == 401) return 'Clé IA refusée.';
    if (res.statusCode == 402) {
      return 'Crédit insuffisant chez le fournisseur. La recherche web '
          'd\'OpenRouter est payante, même avec un modèle gratuit.';
    }
    if (res.statusCode == 429) {
      return 'Trop de requêtes : le quota gratuit est atteint, réessaie '
          'dans une minute.';
    }
    final court =
        res.body.length > 300 ? '${res.body.substring(0, 300)}…' : res.body;
    return 'HTTP ${res.statusCode} — $court';
  }

  /// Extrait le premier objet JSON d'une réponse, même entourée de texte ou
  /// de balises de code. Renvoie null si rien n'est lisible.
  static Map<String, dynamic>? extractObject(String raw) {
    try {
      final start = raw.indexOf('{');
      final end = raw.lastIndexOf('}');
      if (start < 0 || end <= start) return null;
      final decoded = jsonDecode(raw.substring(start, end + 1));
      return decoded is Map<String, dynamic> ? decoded : null;
    } catch (_) {
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

  /// Identifie un titre à partir d'un nom de dossier.
  ///
  /// [nature] vaut « anime », « film » ou « série » : on ne demande pas un
  /// titre romaji pour un film américain, ni un titre français officiel à
  /// une série japonaise qui n'en a jamais eu.
  static Future<AiTitles?> identify({
    required String folderTitle,
    required String provider,
    required String apiKey,
    required String model,
    String custom = '',
    String nature = 'anime',
  }) async {
    final anime = nature == 'anime';
    final quoi = anime
        ? 'séries d\'animation japonaise'
        : (nature == 'film' ? 'films' : 'séries télévisées');

    final system = 'Tu identifies des $quoi à partir de noms de dossiers ou '
        'de fichiers, souvent abrégés, mal orthographiés ou traduits. Les '
        'noms de fichiers contiennent souvent du bruit à ignorer : qualité '
        '(1080p, x265), groupe de diffusion entre crochets, langue (VOSTFR, '
        'MULTI), numéro de saison. Tu réponds uniquement par un objet JSON.';

    final champs = anime
        ? '{"romaji":"","english":"","french":"","japanese":"","original":"",'
            '"year":null,"confidence":0.0}\n'
            'romaji = titre en lettres latines utilisé au Japon, '
            'english = titre anglais officiel, french = titre français '
            'officiel (ou l\'anglais s\'il n\'en existe pas), japanese = '
            'titre en écriture japonaise, original = vide.'
        : '{"original":"","english":"","french":"","romaji":"","japanese":"",'
            '"year":null,"confidence":0.0}\n'
            'original = titre dans sa langue d\'origine, english = titre '
            'anglais, french = titre français d\'exploitation, year = année '
            'de sortie ; romaji et japanese restent vides sauf pour une '
            'œuvre japonaise.';

    final user = 'Nom trouvé sur le disque : "$folderTitle".\n'
        'Identifie le titre et réponds avec ce JSON exactement :\n'
        '$champs\n'
        'confidence entre 0 et 1. Si tu ne reconnais pas l\'œuvre, mets des '
        'chaînes vides et confidence à 0 : une invention est pire qu\'une '
        'absence de réponse.';

    final answer = await ask(
      provider: provider,
      apiKey: apiKey,
      model: model,
      custom: custom,
      system: system,
      user: user,
      maxTokens: 1500,
      jsonMode: true,
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

class AiTitles {
  final String romaji;
  final String english;
  final String french;
  final String japanese;

  /// Titre dans la langue d'origine, pour les œuvres non japonaises.
  final String original;
  final int? year;
  final double confidence;

  const AiTitles({
    this.romaji = '',
    this.english = '',
    this.french = '',
    this.japanese = '',
    this.original = '',
    this.year,
    this.confidence = 0,
  });

  bool get usable =>
      confidence >= 0.3 &&
      (romaji.isNotEmpty || english.isNotEmpty || original.isNotEmpty);

  /// Meilleure requête à envoyer aux bases de données : le romaji pour un
  /// anime, sinon le titre original ou anglais, que TMDB indexe tous deux.
  String get searchQuery {
    if (romaji.isNotEmpty) return romaji;
    if (original.isNotEmpty) return original;
    if (english.isNotEmpty) return english;
    return french;
  }

  static AiTitles? parse(String raw) {
    final map = AiService.extractObject(raw);
    if (map == null) return null;
    String champ(String k) => (map[k] ?? '').toString().trim();
    return AiTitles(
      romaji: champ('romaji'),
      english: champ('english'),
      french: champ('french'),
      japanese: champ('japanese'),
      original: champ('original'),
      year: map['year'] is num ? (map['year'] as num).toInt() : null,
      confidence:
          map['confidence'] is num ? (map['confidence'] as num).toDouble() : 0,
    );
  }
}
