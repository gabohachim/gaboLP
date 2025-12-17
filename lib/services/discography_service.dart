import 'dart:convert';
import 'package:http/http.dart' as http;

class ArtistHit {
  final String id;
  final String name;
  final String? country;

  ArtistHit({
    required this.id,
    required this.name,
    this.country,
  });
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

class AlbumItem {
  final String id; // release-group mbid
  final String title;
  final String? year;

  AlbumItem({
    required this.id,
    required this.title,
    this.year,
  });
}

class TrackItem {
  final int number;
  final String title;
  final String? length;

  TrackItem({
    required this.number,
    required this.title,
    this.length,
  });
}

class DiscographyService {
  static const _mbBase = 'https://musicbrainz.org/ws/2';
  static const _ua = 'GaBoLP/1.0 ( contact: gabo.hachim@gmail.com )';

  static Map<String, String> get _headers => {
        'User-Agent': _ua,
        'Accept': 'application/json',
      };

  /// ✅ Buscar artistas (autocompletar) con parámetro limit
  static Future<List<ArtistHit>> searchArtists(
    String query, {
    int limit = 10,
  }) async {
    final q = query.trim();
    if (q.isEmpty) return [];

    final uri = Uri.parse('$_mbBase/artist/?query=${Uri.encodeComponent(q)}&fmt=json');
    final r = await http.get(uri, headers: _headers);

    if (r.statusCode != 200) return [];

    final data = jsonDecode(r.body) as Map<String, dynamic>;
    final list = (data['artists'] as List?) ?? [];

    final hits = <ArtistHit>[];
    for (final item in list.take(limit)) {
      final m = item as Map<String, dynamic>;
      hits.add(
        ArtistHit(
          id: (m['id'] ?? '').toString(),
          name: (m['name'] ?? '').toString(),
          country: (m['country'] ?? '').toString().trim().isEmpty ? null : (m['country'] ?? '').toString(),
        ),
      );
    }
    return hits;
  }

  static Future<ArtistInfo> getArtistInfo(String artistName) async {
    final name = artistName.trim();
    if (name.isEmpty) return ArtistInfo(name: artistName);

    final uri = Uri.parse('$_mbBase/artist/?query=${Uri.encodeComponent(name)}&fmt=json');
    final r = await http.get(uri, headers: _headers);
    if (r.statusCode != 200) return ArtistInfo(name: artistName);

    final data = jsonDecode(r.body) as Map<String, dynamic>;
    final list = (data['artists'] as List?) ?? [];
    if (list.isEmpty) return ArtistInfo(name: artistName);

    final first = list.first as Map<String, dynamic>;
    final id = (first['id'] ?? '').toString();
    final country = (first['country'] ?? '').toString().trim().isEmpty ? null : (first['country'] ?? '').toString();

    String? genre;
    if (id.isNotEmpty) {
      final uri2 = Uri.parse('$_mbBase/artist/$id?inc=tags&fmt=json');
      final r2 = await http.get(uri2, headers: _headers);
      if (r2.statusCode == 200) {
        final d2 = jsonDecode(r2.body) as Map<String, dynamic>;
        final tags = (d2['tags'] as List?) ?? [];
        if (tags.isNotEmpty) {
          final t0 = tags.first as Map<String, dynamic>;
          final g = (t0['name'] ?? '').toString().trim();
          if (g.isNotEmpty) genre = g;
        }
      }
    }

    final bioEs = _buildBioEs(
      artist: (first['name'] ?? artistName).toString(),
      country: country,
      genre: genre,
    );

    return ArtistInfo(
      name: (first['name'] ?? artistName).toString(),
      country: country,
      genre: genre,
      bioEs: bioEs,
    );
  }

  static String _buildBioEs({
    required String artist,
    String? country,
    String? genre,
  }) {
    final parts = <String>[];
    parts.add(artist);
    if ((genre ?? '').trim().isNotEmpty) parts.add('es una banda/artista de ${genre!.trim()}');
    if ((country ?? '').trim().isNotEmpty) parts.add('de ${country!.trim()}');
    final base = parts.join(' ');
    return '$base. Una propuesta ideal para fans del sonido clásico en vinilo.';
  }

  static Future<List<AlbumItem>> getDiscographyByArtistName(String artistName) async {
    final name = artistName.trim();
    if (name.isEmpty) return [];

    final artists = await searchArtists(name, limit: 10);
    if (artists.isEmpty) return [];
    return getDiscographyAlbums(artists.first.id);
  }

  static Future<List<AlbumItem>> getDiscographyAlbums(String artistId) async {
    final id = artistId.trim();
    if (id.isEmpty) return [];

    final uri = Uri.parse('$_mbBase/release-group?artist=$id&type=album&limit=100&fmt=json');
    final r = await http.get(uri, headers: _headers);
    if (r.statusCode != 200) return [];

    final data = jsonDecode(r.body) as Map<String, dynamic>;
    final list = (data['release-groups'] as List?) ?? [];

    final albums = <AlbumItem>[];
    for (final item in list) {
      final m = item as Map<String, dynamic>;
      final title = (m['title'] ?? '').toString();
      final rgid = (m['id'] ?? '').toString();
      final firstRelease = (m['first-release-date'] ?? '').toString().trim();
      final year = firstRelease.isNotEmpty && firstRelease.length >= 4 ? firstRelease.substring(0, 4) : null;

      if (title.isNotEmpty && rgid.isNotEmpty) {
        albums.add(AlbumItem(id: rgid, title: title, year: year));
      }
    }

    albums.sort((a, b) {
      final ya = int.tryParse(a.year ?? '') ?? 9999;
      final yb = int.tryParse(b.year ?? '') ?? 9999;
      final c = ya.compareTo(yb);
      if (c != 0) return c;
      return a.title.compareTo(b.title);
    });

    return albums;
  }

  static Future<List<TrackItem>> getTracksFromReleaseGroup(String releaseGroupMbid) async {
    final rg = releaseGroupMbid.trim();
    if (rg.isEmpty) return [];

    final rgUri = Uri.parse('$_mbBase/release-group/$rg?inc=releases&fmt=json');
    final rgRes = await http.get(rgUri, headers: _headers);
    if (rgRes.statusCode != 200) return [];

    final rgData = jsonDecode(rgRes.body) as Map<String, dynamic>;
    final releases = (rgData['releases'] as List?) ?? [];
    if (releases.isEmpty) return [];

    final rel0 = releases.first as Map<String, dynamic>;
    final releaseId = (rel0['id'] ?? '').toString();
    if (releaseId.isEmpty) return [];

    final relUri = Uri.parse('$_mbBase/release/$releaseId?inc=recordings&fmt=json');
    final relRes = await http.get(relUri, headers: _headers);
    if (relRes.statusCode != 200) return [];

    final relData = jsonDecode(relRes.body) as Map<String, dynamic>;
    final media = (relData['media'] as List?) ?? [];
    if (media.isEmpty) return [];

    final out = <TrackItem>[];
    int n = 1;

    for (final m in media) {
      final mm = m as Map<String, dynamic>;
      final tracks = (mm['tracks'] as List?) ?? [];
      for (final t in tracks) {
        final tt = t as Map<String, dynamic>;
        final title = (tt['title'] ?? '').toString().trim();
        final lenMs = tt['length'];
        String? len;
        if (lenMs is int) len = _msToMinSec(lenMs);
        if (title.isNotEmpty) {
          out.add(TrackItem(number: n, title: title, length: len));
          n++;
        }
      }
    }

    return out;
  }

  static String _msToMinSec(int ms) {
    final totalSec = (ms / 1000).round();
    final min = totalSec ~/ 60;
    final sec = totalSec % 60;
    final s2 = sec.toString().padLeft(2, '0');
    return '$min:$s2';
  }
}
