import 'dart:convert';

import 'package:http/http.dart' as http;

/// Traduction des synopsis. Trois fournisseurs au choix :
///  - mymemory      : gratuit, sans cle (5 000 caracteres/jour, 50 000 avec email)
///  - libretranslate: serveur public ou auto-heberge
///  - deepl         : meilleure qualite, cle API gratuite requise
class TranslateApi {
  /// Cache en memoire : evite de reconsommer le quota quotidien
  /// quand la meme description est retraduite.
  static final Map<String, String> _cache = {};

  static void clearCache() => _cache.clear();

  static Future<String?> translate(
    String text, {
    required String provider,
    required String targetLang,
    String? apiKey,
    String? endpoint,
    String? email,
    String sourceLang = 'en',
  }) async {
    final input = text.trim();
    if (input.isEmpty || provider == 'none') return null;

    final key = '$provider|$sourceLang|$targetLang|${input.hashCode}';
    final cached = _cache[key];
    if (cached != null) return cached;

    String? result;
    switch (provider) {
      case 'mymemory':
        result = await _myMemory(input, sourceLang, targetLang, email);
        break;
      case 'libretranslate':
        result = await _libre(input, sourceLang, targetLang, endpoint, apiKey);
        break;
      case 'deepl':
        result = await _deepl(input, sourceLang, targetLang, apiKey);
        break;
    }
    if (result != null && result.trim().isNotEmpty) _cache[key] = result;
    return result;
  }

  /// Decoupe le texte en morceaux courts sans casser les phrases.
  static List<String> _chunks(String text, int max) {
    final parts = <String>[];
    final sentences = text.split(RegExp(r'(?<=[.!?])\s+'));
    var buffer = StringBuffer();
    for (final s in sentences) {
      if (buffer.length + s.length + 1 > max && buffer.isNotEmpty) {
        parts.add(buffer.toString().trim());
        buffer = StringBuffer();
      }
      if (s.length > max) {
        for (var i = 0; i < s.length; i += max) {
          parts.add(s.substring(i, i + max > s.length ? s.length : i + max));
        }
      } else {
        buffer.write('$s ');
      }
    }
    if (buffer.isNotEmpty) parts.add(buffer.toString().trim());
    return parts.where((e) => e.isNotEmpty).toList();
  }

  static Future<String?> _myMemory(
      String text, String from, String to, String? email) async {
    final out = StringBuffer();
    for (final chunk in _chunks(text, 450)) {
      final params = <String, String>{
        'q': chunk,
        'langpair': '$from|$to',
        if (email != null && email.contains('@')) 'de': email,
      };
      final uri = Uri.https('api.mymemory.translated.net', '/get', params);
      try {
        final res = await http.get(uri).timeout(const Duration(seconds: 20));
        if (res.statusCode != 200) return null;
        final body = jsonDecode(utf8.decode(res.bodyBytes)) as Map<String, dynamic>;
        final translated =
            (body['responseData'] as Map?)?['translatedText']?.toString();
        if (translated == null || translated.isEmpty) return null;
        if (translated.toUpperCase().contains('QUERY LENGTH LIMIT') ||
            translated.toUpperCase().contains('MYMEMORY WARNING')) {
          return null;
        }
        out.write('$translated ');
      } catch (_) {
        return null;
      }
      await Future<void>.delayed(const Duration(milliseconds: 350));
    }
    final result = out.toString().trim();
    return result.isEmpty ? null : result;
  }

  static Future<String?> _libre(String text, String from, String to,
      String? endpoint, String? apiKey) async {
    final base = (endpoint == null || endpoint.trim().isEmpty)
        ? 'https://libretranslate.com'
        : endpoint.trim().replaceAll(RegExp(r'/+$'), '');
    try {
      final res = await http
          .post(
            Uri.parse('$base/translate'),
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode({
              'q': text,
              'source': from,
              'target': to,
              'format': 'text',
              if (apiKey != null && apiKey.isNotEmpty) 'api_key': apiKey,
            }),
          )
          .timeout(const Duration(seconds: 30));
      if (res.statusCode != 200) return null;
      final body = jsonDecode(utf8.decode(res.bodyBytes)) as Map<String, dynamic>;
      return body['translatedText']?.toString();
    } catch (_) {
      return null;
    }
  }

  static Future<String?> _deepl(
      String text, String from, String to, String? apiKey) async {
    if (apiKey == null || apiKey.isEmpty) return null;
    final host =
        apiKey.endsWith(':fx') ? 'api-free.deepl.com' : 'api.deepl.com';
    try {
      final res = await http
          .post(
            Uri.https(host, '/v2/translate'),
            headers: {
              'Authorization': 'DeepL-Auth-Key $apiKey',
              'Content-Type': 'application/x-www-form-urlencoded',
            },
            body: {
              'text': text,
              'target_lang': to.toUpperCase(),
              'source_lang': from.toUpperCase(),
            },
          )
          .timeout(const Duration(seconds: 30));
      if (res.statusCode != 200) return null;
      final body = jsonDecode(utf8.decode(res.bodyBytes)) as Map<String, dynamic>;
      final list = body['translations'] as List? ?? const [];
      if (list.isEmpty) return null;
      return (list.first as Map)['text']?.toString();
    } catch (_) {
      return null;
    }
  }
}
