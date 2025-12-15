import 'dart:convert';
import 'package:http/http.dart' as http;

class CoverCandidate {
  final String mbid; // release id
  final String? year;
  final String coverUrl250;
  final String coverUrl500;

  CoverCandidate({
    required this.mbid,
    required this.coverUrl250,
    required this.coverUrl500,
    this.year,
  });
}

class OnlineAlbumPick {
  final String mbid;
  final String? year;
  final String? coverUrl; // url 500 ideal

  OnlineAlbumPick({required this.mbid, this.year, this.coverUrl});
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

  static Future<http.Response> _get(Uri url) async {
    await _throttle();
    return http.get(url, headers: _headers());
  }

  // Verifica si existe carátula (hacemos GET pequeñito)
  static Future<bool> _coverExists(String url) async {
    try {
      await _throttle();
      final res = await http.get(Uri.parse(url), headers: {
        'User-Agent': 'GaBoLP/1.0 (contact: gabo.hachim@gmail.com)',
      });
      final ct = res.headers['content-type'] ?? '';
      return res.statusCode == 200 && ct.contains('image');
    } catch (_) {
      return false;
    }
  }

  /// ✅ Devuelve varias opciones de carátula (candidatas)
  static Future<List<CoverCandidate>> fetchCoverCandidates({
    required String artist,
    required String album,
  }) async {
    final a = artist.trim();
    final al = album.trim();
    if (a.isEmpty || al.isEmpty) return [];

    // Buscamos releases (limit 8)
    final q = 'release:"$al" AND artist:"$a"';
    final url = Uri.parse(
      '$_mbBase/release/?query=${Uri.encodeQueryComponent(q)}&fmt=json&limit=8',
    );

    final res = await _get(url);
    if (res.statusCode != 200) return [];

    final data = jsonDecode(res.body) as Map<String, dynamic>;
    final releases = (data['releases'] as List?) ?? [];
    if (releases.isEmpty) return [];

    final out = <CoverCandidate>[];

    for (final r in releases) {
      final m = r as Map<String, dynamic>;
      final mbid = m['id'] as String?;
      if (mbid == null) continue;

      final date = (m['date'] as String?) ?? '';
      final year = date.length >= 4 ? date.substring(0, 4) : null;

      // Cover Art Archive: front directo (si existe -> 200, si no -> 404)
      final u250 = 'https://coverartarchive.org/release/$mbid/front-250';
      final u500 = 'https://coverartarchive.org/release/$mbid/front-500';

      // Filtrar solo los que realmente tengan imagen
      final ok = await _coverExists(u250);
      if (!ok) continue;

      out.add(
        CoverCandidate(
          mbid: mbid,
          year: year,
          coverUrl250: u250,
          coverUrl500: u500,
        ),
      );

      // No mostrar demasiadas (máx 6 opciones)
      if (out.length >= 6) break;
    }

    return out;
  }

  /// ✅ Compatibilidad: devuelve 1 resultado (si solo quieres “auto”)
  static Future<OnlineAlbumPick?> fetchCoverAndYearSingle({
    required String artist,
    required String album,
  }) async {
    final list = await fetchCoverCandidates(artist: artist, album: album);
    if (list.isEmpty) return null;
    final c = list.first;
    return OnlineAlbumPick(mbid: c.mbid, year: c.year, coverUrl: c.coverUrl500);
  }
}
