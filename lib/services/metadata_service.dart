import 'dart:convert';
import 'package:http/http.dart' as http;

class CoverCandidate {
  final String releaseGroupId;
  final String? year;
  final String coverUrl250;
  final String coverUrl500;

  CoverCandidate({
    required this.releaseGroupId,
    required this.coverUrl250,
    required this.coverUrl500,
    this.year,
  });

  String get mbid => releaseGroupId;
}

class AlbumAutoMeta {
  final String? year;
  final String? genre;
  final String? releaseGroupId;
  final String? cover250;
  final String? cover500;

  AlbumAutoMeta({
    this.year,
    this.genre,
    this.releaseGroupId,
    this.cover250,
    this.cover500,
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

  static Future<List<CoverCandidate>> fetchCoverCandidates({
    required String artist,
    required String album,
  }) async {
    final a = artist.trim();
    final al = album.trim();
    if (a.isEmpty || al.isEmpty) return [];

    final q = 'release:"$al" AND artist:"$a"';
    final url = Uri.parse(
      '$_mbBase/release/?query=${Uri.encodeQueryComponent(q)}&fmt=json&limit=20',
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

      final date = (m['date'] as String?) ?? '';
      final year = date.length >= 4 ? date.substring(0, 4) : null;

      final rg = m['release-group'] as Map<String, dynamic>?;
      final rgid = rg?['id'] as String?;
      if (rgid == null) continue;

      if (seen.contains(rgid)) continue;
      seen.add(rgid);

      final u250 = 'https://coverartarchive.org/release-group/$rgid/front-250';
      final u500 = 'https://coverartarchive.org/release-group/$rgid/front-500';

      out.add(CoverCandidate(
        releaseGroupId: rgid,
        year: year,
        coverUrl250: u250,
        coverUrl500: u500,
      ));

      if (out.length >= 8) break;
    }

    return out;
  }

  /// Año + género + cover + releaseGroupId (para autocompletar)
  static Future<AlbumAutoMeta> fetchAutoMetadata({
    required String artist,
    required String album,
  }) async {
    String? rgid;
    String? year;
    String? genre;

    // 1) releaseGroupId y year
    final options = await fetchCoverCandidates(artist: artist, album: album);
    if (options.isNotEmpty) {
      rgid = options.first.releaseGroupId;
      year = options.first.year;
    }

    // 2) género + año más confiable (first-release-date) desde release-group tags
    if (rgid != null && rgid.isNotEmpty) {
      final urlRg = Uri.parse('$_mbBase/release-group/$rgid?inc=tags&fmt=json');
      final resRg = await _getJson(urlRg);

      if (resRg.statusCode == 200) {
        final dataRg = jsonDecode(resRg.body) as Map<String, dynamic>;

        final frd = (dataRg['first-release-date'] as String?) ?? '';
        if ((year == null || year.isEmpty) && frd.length >= 4) {
          year = frd.substring(0, 4);
        }

        final tags = (dataRg['tags'] as List?) ?? [];
        if (tags.isNotEmpty) {
          final t0 = tags.first as Map<String, dynamic>;
          final g = (t0['name'] as String?)?.trim();
          if (g != null && g.isNotEmpty) genre = g;
        }
      }
    }

    return AlbumAutoMeta(
      year: year,
      genre: genre,
      releaseGroupId: rgid,
      cover250: (rgid == null) ? null : 'https://coverartarchive.org/release-group/$rgid/front-250',
      cover500: (rgid == null) ? null : 'https://coverartarchive.org/release-group/$rgid/front-500',
    );
  }
}
