import 'dart:convert';
import 'package:http/http.dart' as http;

class ArtistHit {
  final String id;
  final String name;
  final String? country;

  ArtistHit({required this.id, required this.name, this.country});
}

class ArtistInfo {
  final String name;
  final String? country;
  final String? genre;
  final String? bioEs;

  ArtistInfo({
    required this.name,
    this.country,
    this.genre,
    this.bioEs,
  });
}

class DiscographyService {
  static const String _ua = 'GaBoLP/1.0 (gabo.hachim@gmail.com)';

  /// Autocompletar artistas (busca por letras)
  static Future<List<ArtistHit>> searchArtists(String query, {int limit = 10}) async {
    final q = query.trim();
    if (q.isEmpty) return [];

    final url = Uri.https('musicbrainz.org', '/ws/2/artist/', {
      'query': 'artist:"$q"',
      'fmt': 'json',
      'limit': '$limit',
    });

    final r = await http.get(url, headers: {'User-Agent': _ua});
    if (r.statusCode != 200) return [];

    final data = jsonDecode(r.body) as Map<String, dynamic>;
    final list = (data['artists'] as List?) ?? [];

    final out = <ArtistHit>[];
    for (final it in list) {
      final m = it as Map<String, dynamic>;
      final id = (m['id'] ?? '').toString();
      final name = (m['name'] ?? '').toString();
      final country = (m['country'] ?? '').toString().trim();
      if (id.isEmpty || name.isEmpty) continue;
      out.add(ArtistHit(id: id, name: name, country: country.isEmpty ? null : country));
    }
    return out;
  }

  /// Info del artista: país + género (tag) + bio (Wikipedia ES si existe)
  static Future<ArtistInfo> getArtistInfo(String artistName) async {
    final hits = await searchArtists(artistName, limit: 1);
    final name = hits.isEmpty ? artistName : hits.first.name;
    final country = hits.isEmpty ? null : hits.first.country;

    String? genre;
    try {
      final url = Uri.https('musicbrainz.org', '/ws/2/artist/', {
        'query': 'artist:"$name"',
        'fmt': 'json',
        'limit': '1',
      });
      final r = await http.get(url, headers: {'User-Agent': _ua});
      if (r.statusCode == 200) {
        final data = jsonDecode(r.body) as Map<String, dynamic>;
        final artists = (data['artists'] as List?) ?? [];
        if (artists.isNotEmpty) {
          final a = artists.first as Map<String, dynamic>;
          final tags = (a['tags'] as List?) ?? [];
          if (tags.isNotEmpty) {
            final t0 = tags.first as Map<String, dynamic>;
            final g = (t0['name'] ?? '').toString().trim();
            if (g.isNotEmpty) genre = g;
          }
        }
      }
    } catch (_) {}

    // Bio en español (muy corto) desde Wikipedia REST (si existe)
    String? bioEs;
    try {
      final title = Uri.encodeComponent(name.replaceAll(' ', '_'));
      final url = Uri.parse('https://es.wikipedia.org/api/rest_v1/page/summary/$title');
      final r = await http.get(url, headers: {'User-Agent': _ua});
      if (r.statusCode == 200) {
        final data = jsonDecode(r.body) as Map<String, dynamic>;
        final extract = (data['extract'] ?? '').toString().trim();
        if (extract.isNotEmpty) {
          bioEs = extract.length > 220 ? '${extract.substring(0, 220)}…' : extract;
        }
      }
    } catch (_) {}

    return ArtistInfo(name: name, country: country, genre: genre, bioEs: bioEs);
  }
}
