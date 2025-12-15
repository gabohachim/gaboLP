import 'dart:convert';
import 'package:http/http.dart' as http;

class ArtistHit {
  final String id;
  final String name;
  final String? disambiguation;

  ArtistHit({required this.id, required this.name, this.disambiguation});
}

class AlbumItem {
  final String id;
  final String title;
  final String? year;
  final String? coverUrl;

  AlbumItem({
    required this.id,
    required this.title,
    this.year,
    this.coverUrl,
  });
}

class TrackItem {
  final int number;
  final String title;
  final String? length;

  TrackItem({required this.number, required this.title, this.length});
}

class DiscographyService {
  static const _mbBase = 'https://musicbrainz.org/ws/2';

  static DateTime _lastCall = DateTime.fromMillisecondsSinceEpoch(0);

  static Future<void> _throttle() async {
    final now = DateTime.now();
    final diff = now.difference(_lastCall);
    if (diff.inMilliseconds < 1100) {
      await Future.delayed(
        Duration(milliseconds: 1100 - diff.inMilliseconds),
      );
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

  /// Buscar artista
  static Future<List<ArtistHit>> searchArtist(String name) async {
    final q = 'artist:"$name"';
    final url = Uri.parse(
      '$_mbBase/artist/?query=${Uri.encodeQueryComponent(q)}&fmt=json&limit=10',
    );

    final res = await _get(url);
    if (res.statusCode != 200) return [];

    final data = jsonDecode(res.body) as Map<String, dynamic>;
    final artists = (data['artists'] as List?) ?? [];

    return artists.map((a) {
      final m = a as Map<String, dynamic>;
      return ArtistHit(
        id: m['id'],
        name: m['name'],
        disambiguation: m['disambiguation'],
      );
    }).toList();
  }

  /// Discografía
  static Future<List<AlbumItem>> getDiscographyAlbums(String artistId) async {
    final url = Uri.parse(
      '$_mbBase/release-group?artist=$artistId&fmt=json&type=album&limit=100',
    );

    final res = await _get(url);
    if (res.statusCode != 200) return [];

    final data = jsonDecode(res.body) as Map<String, dynamic>;
    final groups = (data['release-groups'] as List?) ?? [];

    return groups.map((g) {
      final m = g as Map<String, dynamic>;
      final date = (m['first-release-date'] as String?) ?? '';
      final year = date.length >= 4 ? date.substring(0, 4) : null;

      return AlbumItem(
        id: m['id'],
        title: m['title'],
        year: year,
        coverUrl:
            'https://coverartarchive.org/release-group/${m['id']}/front-250',
      );
    }).toList();
  }

  /// Canciones
  static Future<List<TrackItem>> getTracksFromReleaseGroup(
      String releaseGroupId) async {
    final r1 = await _get(Uri.parse(
        '$_mbBase/release?release-group=$releaseGroupId&fmt=json&limit=1'));
    if (r1.statusCode != 200) return [];

    final releases = (jsonDecode(r1.body)['releases'] as List?) ?? [];
    if (releases.isEmpty) return [];

    final releaseId = releases.first['id'];

    final r2 = await _get(Uri.parse(
        '$_mbBase/release/$releaseId?fmt=json&inc=recordings'));
    if (r2.statusCode != 200) return [];

    final media = (jsonDecode(r2.body)['media'] as List?) ?? [];
    if (media.isEmpty) return [];

    final tracks = (media.first['tracks'] as List?) ?? [];
    int n = 1;

    return tracks.map((t) {
      final len = t['length'];
      String? dur;
      if (len != null) {
        final s = (len / 1000).round();
        dur = '${s ~/ 60}:${(s % 60).toString().padLeft(2, '0')}';
      }

      return TrackItem(
        number: n++,
        title: t['title'],
        length: dur,
      );
    }).toList();
  }
}

