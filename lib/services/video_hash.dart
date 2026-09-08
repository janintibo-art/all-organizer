import 'dart:io';
import 'dart:typed_data';

/// Empreinte OpenSubtitles : taille du fichier plus la somme des entiers
/// 64 bits des 64 premiers et des 64 derniers kilo-octets.
///
/// C'est ce qui permet de retrouver des sous-titres réellement synchronisés
/// avec ce fichier précis, plutôt qu'une version approchante de la série.
class VideoHash {
  static const int _chunk = 65536;

  static Future<String?> compute(String path) async {
    final entity = File(path);
    if (!entity.existsSync()) return null;

    final size = entity.lengthSync();
    if (size < _chunk * 2) return null;

    RandomAccessFile? handle;
    try {
      // Variable non nullable : Dart ne sait pas conserver une promotion
      // de type à travers un await, il faut donc une référence sûre.
      final file = await entity.open();
      handle = file;

      var hash = BigInt.from(size);

      for (final offset in <int>[0, size - _chunk]) {
        await file.setPosition(offset);
        final bytes = await file.read(_chunk);
        final data = ByteData.sublistView(Uint8List.fromList(bytes));
        for (var i = 0; i + 8 <= data.lengthInBytes; i += 8) {
          hash += BigInt.from(data.getUint64(i, Endian.little));
        }
      }

      // Repli sur 64 bits, comme le fait l'algorithme d'origine.
      final mask = (BigInt.one << 64) - BigInt.one;
      return (hash & mask).toRadixString(16).padLeft(16, '0');
    } catch (_) {
      return null;
    } finally {
      await handle?.close();
    }
  }
}
