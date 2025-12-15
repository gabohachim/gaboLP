import 'dart:convert';
import 'package:http/http.dart' as http;

class CoverCandidate {
  final String releaseGroupId; // ID del álbum (release-group)
  final String? year;
  final String coverUrl250;
  final String coverUrl500;

  CoverCandidate({
    required this.releaseGroupId,
    required this.coverUrl250,
    required this.coverUrl500,
    this.year,
  });
}

class MetadataService {
  static const _mbBase = 'https://musicbrainz.org/ws/2';

  static DateTime _lastCall = DateTime.fromMillisecondsSinceEpoch(0);

  static Future<void> _throttle() async {
    final now = DateTime.now();
    final diff = now.difference(_lastCall);
    if (diff.inMilliseconds < 1100) {
      await Future.delayed(Duration(milliseconds: 1100 - diff.inMilliseconds));
    }
    _lastCall = DateTime.now();
  }

  static Map<String, String> _headers() => {
        'User-Agent': 'GaBoLP/1.0 (contact: gabo.hachim@gmail.com)',
        'Accept': 'application/json',
      };

  static Future<http.Response> _getJson(Uri url) async {
    await _throttle();
    return http.get(url, headers: _headers());
  }

  /// ✅ Trae opciones de carátulas (pero usando RELEASE-GROUP, mucho más confiable)
  static Future<List<CoverCandidate>> fetchCoverCandidates({
    required String artist,
    required String album,
  }) async {
    final a = artist.trim();
    final al = album.trim();
    if (a.isEmpty || al.isEmpty) return [];

    // Buscar releases, pero nos quedamos con release-group.id (álbum)
    final q = 'release:"$al" AND artist:"$a"';
    final url = Uri.parse(
      '$_mbBase/release/?query=${Uri.encodeQueryComponent(q)}&fmt=json&limit=15',
    );

    final res = await _getJson(url);
    if (res.statusCode != 200) return [];

    final data = jsonDecode(res.body) as Map<String, dynamic>;
    final releases = (data['releases'] as List?) ?? [];
    if (releases.isEmpty) return [];

    final seen = <String>{};
    final out = <CoverCandidate>[];

    for (final r in releases) {
      final m = r as Map<String, dynamic>;

      // Año desde release date (si existe)
      final date = (m['date'] as String?) ?? '';
      final year = date.length >= 4 ? date.substring(0, 4) : null;

      // Sacar release-group id (esto es CLAVE)
      final rg = m['release-group'] as Map<String, dynamic>?;
      final rgid = rg?['id'] as String?;
      if (rgid == null) continue;

      // Evitar duplicados
      if (seen.contains(rgid)) continue;
      seen.add(rgid);

      // Cover Art Archive por release-group
      // Si existe: devuelve imagen; si no: falla y Image.network mostrará broken_image
      final u250 = 'https://coverartarchive.org/release-group/$rgid/front-250';
      final u500 = 'https://coverartarchive.org/release-group/$rgid/front-500';

      out.add(
        CoverCandidate(
          releaseGroupId: rgid,
          year: year,
          coverUrl250: u250,
          coverUrl500: u500,
        ),
      );

      if (out.length >= 8) break; // suficientes opciones
    }

    return out;
  }
}
