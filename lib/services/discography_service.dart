import 'dart:convert';
import 'package:http/http.dart' as http;

/// Model para autocompletar artistas
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

/// Info de artista (para mostrar país/género/bio)
class ArtistInfo {
  final String name;
  final String? country;
  final String? genre; // ✅ lo pedías
  final String? bioEs; // ✅ reseña en español (simple)

  ArtistInfo({
    required this.name,
    this.country,
    this.genre,
    this.bioEs,
  });
}

/// Item de álbum para discografía
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

/// ✅ Tracklist
class TrackItem {
  final int number;
  final String title;
  final String? length; // mm:ss

  TrackItem({
    required this.number,
    required this.title,
    this.length,
  });
}

class DiscographyService {
  static const _mbBase = 'https://musicbrainz.org/ws/2';
  static const _ua =
      'GaBoLP/1.0 ( contact: gabo.hachim@gmail.com )'; // User-Agent recomendado

  static Map<String, String> get _headers => {
        'User-Agent': _ua,
        'Accept': 'application/json',
      };

  /// Buscar artistas (autocompletar)
  static Future<List<ArtistHit>> searchArtists(String query) async {
    final q = query.trim();
    if (q.isEmpty) return [];

    final uri = Uri.parse('$_mbBase/artist/?query=${Uri.encodeComponent(q)}&fmt=json');
    final r = await http.get(uri, headers: _headers);

    if (r.statusCode != 200) return [];

    final data = jsonDecode(r.body) as Map<String, dynamic>;
    final list = (data['artists'] as List?) ?? [];

    // Tomar 10 máx para que sea rápido
    final hits = <ArtistHit>[];
    for (final item in list.take(10)) {
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

  /// Info simple de artista (país + tags como "género" + bio en español)
  /// Nota: MusicBrainz no siempre trae bio. Para "bioEs" usamos un texto corto generado
  /// a partir de tags + país (para que siempre haya algo y sea estable).
  static Future<ArtistInfo> getArtistInfo(String artistName) async {
    final name = artistName.trim();
    if (name.isEmpty) {
      return ArtistInfo(name: artistName);
    }

    // Buscar el artista más probable por nombre
    final uri = Uri.parse('$_mbBase/artist/?query=${Uri.encodeComponent(name)}&fmt=json');
    final r = await http.get(uri, headers: _headers);
    if (r.statusCode != 200) {
      return ArtistInfo(name: artistName);
    }

    final data = jsonDecode(r.body) as Map<String, dynamic>;
    final list = (data['artists'] as List?) ?? [];
    if (list.isEmpty) return ArtistInfo(name: artistName);

    final first = list.first as Map<String, dynamic>;
    final id = (first['id'] ?? '').toString();
    final country = (first['country'] ?? '').toString().trim().isEmpty ? null : (first['country'] ?? '').toString();

    // Traer tags (género aproximado)
    String? genre;
    if (id.isNotEmpty) {
      final uri2 = Uri.parse('$_mbBase/artist/$id?inc=tags&fmt=json');
      final r2 = await http.get(uri2, headers: _headers);
      if (r2.statusCode == 200) {
        final d2 = jsonDecode(r2.body) as Map<String, dynamic>;
        final tags = (d2['tags'] as List?) ?? [];
        if (tags.isNotEmpty) {
          // primer tag como género aproximado
          final t0 = tags.first as Map<String, dynamic>;
          final g = (t0['name'] ?? '').toString().trim();
          if (g.isNotEmpty) genre = g;
        }
      }
    }

    // Bio simple en español (corto)
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

  /// Discografía por artista (release-groups tipo album), ordenada por año
  static Future<List<AlbumItem>> getDiscographyByArtistName(String artistName) async {
    final name = artistName.trim();
    if (name.isEmpty) return [];

    // Buscar artista y usar su id
    final artists = await searchArtists(name);
    if (artists.isEmpty) return [];

    return getDiscographyAlbums(artists.first.id);
  }

  /// Discografía por id de artista (release-group)
  static Future<List<AlbumItem>> getDiscographyAlbums(String artistId) async {
    final id = artistId.trim();
    if (id.isEmpty) return [];

    final uri = Uri.parse(
      '$_mbBase/release-group?artist=$id&type=album&limit=100&fmt=json',
    );
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

    // ordenar por año asc (los sin año al final)
    albums.sort((a, b) {
      final ya = int.tryParse(a.year ?? '') ?? 9999;
      final yb = int.tryParse(b.year ?? '') ?? 9999;
      final c = ya.compareTo(yb);
      if (c != 0) return c;
      return a.title.compareTo(b.title);
    });

    return albums;
  }

  /// ✅ Tracklist desde un release-group MBID:
  /// 1) toma un release del release-group
  /// 2) trae recordings/tracks
  static Future<List<TrackItem>> getTracksFromReleaseGroup(String releaseGroupMbid) async {
    final rg = releaseGroupMbid.trim();
    if (rg.isEmpty) return [];

    // 1) release-group -> obtener releases
    final rgUri = Uri.parse('$_mbBase/release-group/$rg?inc=releases&fmt=json');
    final rgRes = await http.get(rgUri, headers: _headers);
    if (rgRes.statusCode != 200) return [];

    final rgData = jsonDecode(rgRes.body) as Map<String, dynamic>;
    final releases = (rgData['releases'] as List?) ?? [];
    if (releases.isEmpty) return [];

    // tomar el primer release
    final rel0 = releases.first as Map<String, dynamic>;
    final releaseId = (rel0['id'] ?? '').toString();
    if (releaseId.isEmpty) return [];

    // 2) release -> recordings (tracks)
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
