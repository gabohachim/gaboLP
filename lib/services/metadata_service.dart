import 'dart:convert';
import 'dart:typed_data';

import 'package:http/http.dart' as http;

import '../models/cover_candidate.dart';

class AlbumSuggest {
  final String title;
  final String? year;
  final String? releaseGroupMbid;

  AlbumSuggest({required this.title, this.year, this.releaseGroupMbid});
}

class AutoMeta {
  final String? year;
  AutoMeta({this.year});
}

class MetadataService {
  // MusicBrainz recomienda un User-Agent identificable
  static const String _ua = 'GaBoLP/1.0 (gabo.hachim@gmail.com)';

  /// Busca álbumes para autocompletar (1 letra ya sirve).
  /// Usa MusicBrainz release-group search.
  static Future<List<AlbumSuggest>> searchAlbumsForArtist({
    required String artistName,
    required String albumQuery,
    int limit = 10,
  }) async {
    final a = artistName.trim();
    final q = albumQuery.trim();
    if (a.isEmpty || q.isEmpty) return [];

    final url = Uri.https('musicbrainz.org', '/ws/2/release-group/', {
      'query': 'artist:"$a" AND releasegroup:"$q"',
      'fmt': 'json',
      'limit': '$limit',
    });

    final r = await http.get(url, headers: {'User-Agent': _ua});
    if (r.statusCode != 200) return [];

    final data = jsonDecode(r.body) as Map<String, dynamic>;
    final list = (data['release-groups'] as List?) ?? [];

    final out = <AlbumSuggest>[];
    for (final it in list) {
      final m = it as Map<String, dynamic>;
      final title = (m['title'] ?? '').toString();
      final firstDate = (m['first-release-date'] ?? '').toString().trim();
      final year = firstDate.length >= 4 ? firstDate.substring(0, 4) : null;
      final id = (m['id'] ?? '').toString();
      if (title.isEmpty) continue;
      out.add(AlbumSuggest(title: title, year: year, releaseGroupMbid: id.isEmpty ? null : id));
    }
    return out;
  }

  /// Metadata automática (por ahora solo año).
  static Future<AutoMeta> fetchAutoMetadata({
    required String artist,
    required String album,
  }) async {
    final q = await searchAlbumsForArtist(artistName: artist, albumQuery: album, limit: 1);
    if (q.isEmpty) return AutoMeta(year: null);
    return AutoMeta(year: q.first.year);
  }

  /// Devuelve hasta [max] candidatos de carátula.
  /// Usamos Cover Art Archive por release-group MBID.
  static Future<List<CoverCandidate>> fetchCoverCandidates({
    required String artist,
    required String album,
    int max = 5,
  }) async {
    final sug = await searchAlbumsForArtist(artistName: artist, albumQuery: album, limit: max);
    if (sug.isEmpty) return [];

    final out = <CoverCandidate>[];

    for (final s in sug) {
      final mbid = s.releaseGroupMbid;
      if (mbid == null || mbid.isEmpty) continue;

      // Cover Art Archive release-group endpoints
      final url250 = 'https://coverartarchive.org/release-group/$mbid/front-250';
      final url500 = 'https://coverartarchive.org/release-group/$mbid/front-500';

      // No validamos existencia aquí para no hacer 2-5 requests extra.
      out.add(CoverCandidate(
        coverUrl250: url250,
        coverUrl500: url500,
        year: s.year,
        mbid: mbid,
      ));
      if (out.length >= max) break;
    }
    return out;
  }

  /// Descarga bytes de imagen (para guardar carátula en archivo)
  static Future<Uint8List?> downloadImageBytes(String url) async {
    try {
      final r = await http.get(Uri.parse(url), headers: {'User-Agent': _ua});
      if (r.statusCode != 200) return null;
      return r.bodyBytes;
    } catch (_) {
      return null;
    }
  }
}
