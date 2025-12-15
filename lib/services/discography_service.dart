import 'dart:convert';
import 'package:http/http.dart' as http;

class ArtistHit {
  final String id;
  final String name;
  final String? disambiguation;

  ArtistHit({required this.id, required this.name, this.disambiguation});
}

class AlbumItem {
  final String id; // release-group id
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
  final String? length; // mm:ss

  TrackItem({required this.number, required this.title, this.length});
}

class DiscographyService {
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

  static Future<List<ArtistHit>> searchArtist(String name) async {
    final q = 'artist:"${name.trim()}"';
    final url = Uri.parse('$_mbBase/artist/?query=${Uri.encodeQueryComponent(q)}&fmt=json&limit=10');

    final res = await _get(url);
    if (res.statusCode != 200) return [];

    final data = jsonDecode(res.body) as Map<String, dynamic>;
    final artists = (data['artists'] as List?) ?? [];

    return artists.map((a) {
      final m = a as Map<String, dynamic>;
      return ArtistHit(
        id: (m['id'] as String),
        name: (m['name'] as String),
        disambiguation: (m['disambiguation'] as String?),
      );
    }).toList();
  }

  /// Discografía de álbumes ordenada por AÑO (sin año al final)
  static Future<List<AlbumItem>> getDiscographyAlbums(String artistId) async {
    final url = Uri.parse(
      '$_mbBase/release-group?artist=$artistId&fmt=json&limit=100&type=album',
    );

    final res = await _get(url);
    if (res.statusCode != 200) return [];

    final data = jsonDecode(res.body) as Map<String, dynamic>;
    final rgs = (data['release-groups'] as List?) ?? [];

    final items = <AlbumItem>[];
    for (final it in rgs) {
      final m = it as Map<String, dynamic>;
      final id = m['id'] as String;
      final title = (m['title'] as String?) ?? 'Álbum';
      final firstDate = (m['first-release-date'] as String?) ?? '';
      final year = firstDate.length >= 4 ? firstDate.substring(0, 4) : null;

      // Cover
      final coverUrl = 'https://coverartarchive.org/release-group/$id/front-250';

      items.add(AlbumItem(id: id, title: title, year: year, coverUrl: coverUrl));
    }

    // ✅ Orden por año (sin año => al final), y si empatan, por título
    items.sort((a, b) {
      final ay = int.tryParse(a.year ?? '');
      final by = int.tryParse(b.year ?? '');

      if (ay == null && by == null) {
        return a.title.toLowerCase().compareTo(b.title.toLowerCase());
      }
      if (ay == null) return 1;  // a al final
      if (by == null) return -1; // b al final

      final c = ay.compareTo(by);
      if (c != 0) return c;
      return a.title.toLowerCase().compareTo(b.title.toLowerCase());
    });

    return items;
  }

  static Future<List<TrackItem>> getTracksFromReleaseGroup(String releaseGroupId) async {
    final url1 = Uri.parse('$_mbBase/release?release-group=$releaseGroupId&fmt=json&limit=1');
    final res1 = await _get(url1);
    if (res1.statusCode != 200) return [];

    final data1 = jsonDecode(res1.body) as Map<String, dynamic>;
    final releases = (data1['releases'] as List?) ?? [];
    if (releases.isEmpty) return [];

    final releaseId = (releases.first as Map<String, dynamic>)['id'] as String;

    final url2 = Uri.parse('$_mbBase/release/$releaseId?fmt=json&inc=recordings');
    final res2 = await _get(url2);
    if (res2.statusCode != 200) return [];

    final data2 = jsonDecode(res2.body) as Map<String, dynamic>;
    final media = (data2['media'] as List?) ?? [];
    if (media.isEmpty) return [];

    final tracks = ((media.first as Map<String, dynamic>)['tracks'] as List?) ?? [];
    final out = <TrackItem>[];

    int n = 1;
    for (final t in tracks) {
      final tm = t as Map<String, dynamic>;
      final title = (tm['title'] as String?) ?? 'Track';

      final lenMs = tm['length'] as int?;
      String? len;
      if (lenMs != null) {
        final totalSec = (lenMs / 1000).round();
        final min = totalSec ~/ 60;
        final sec = totalSec % 60;
        len = '${min.toString().padLeft(2, '0')}:${sec.toString().padLeft(2, '0')}';
      }

      out.add(TrackItem(number: n, title: title, length: len));
      n++;
    }

    return out;
  }
}
