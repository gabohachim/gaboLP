import 'dart:convert';
import 'package:http/http.dart' as http;

class AlbumItem {
  final String releaseGroupId;
  final String title;
  final String? year;
  final String cover250;
  final String cover500;

  AlbumItem({
    required this.releaseGroupId,
    required this.title,
    required this.cover250,
    required this.cover500,
    this.year,
  });
}

class TrackItem {
  final int number;
  final String title;
  final String? length;

  TrackItem({required this.number, required this.title, this.length});
}

class ArtistInfo {
  final String? country;
  final List<String> genres;
  final String? bio;

  ArtistInfo({this.country, required this.genres, this.bio});
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

  static Future<http.Response> _getJson(Uri url) async {
    await _throttle();
    return http.get(url, headers: _headers());
  }

  static String _cover250(String rgid) =>
      'https://coverartarchive.org/release-group/$rgid/front-250';
  static String _cover500(String rgid) =>
      'https://coverartarchive.org/release-group/$rgid/front-500';

  // ---------- Wikipedia bio (reseña corta) ----------
  static Future<String?> _fetchWikipediaBio(String artistName) async {
    try {
      final searchUrl = Uri.parse(
        'https://en.wikipedia.org/w/api.php?action=opensearch&search=${Uri.encodeQueryComponent(artistName)}&limit=1&namespace=0&format=json',
      );
      final sRes = await http.get(searchUrl, headers: {'User-Agent': 'GaBoLP/1.0'});
      if (sRes.statusCode != 200) return null;

      final j = jsonDecode(sRes.body);
      if (j is! List || j.length < 2) return null;

      final titles = j[1];
      if (titles is! List || titles.isEmpty) return null;

      final title = (titles.first as String?)?.trim();
      if (title == null || title.isEmpty) return null;

      final sumUrl = Uri.parse('https://en.wikipedia.org/api/rest_v1/page/summary/$title');
      final sumRes = await http.get(sumUrl, headers: {'User-Agent': 'GaBoLP/1.0'});
      if (sumRes.statusCode != 200) return null;

      final data = jsonDecode(sumRes.body) as Map<String, dynamic>;
      final extract = (data['extract'] as String?)?.trim();
      if (extract == null || extract.isEmpty) return null;

      return extract;
    } catch (_) {
      return null;
    }
  }

  /// ✅ país + géneros + bio banda (para lista y discografías)
  static Future<ArtistInfo> getArtistInfo(String artistName) async {
    final a = artistName.trim();
    if (a.isEmpty) return ArtistInfo(country: null, genres: [], bio: null);

    final urlSearch = Uri.parse(
      '$_mbBase/artist/?query=${Uri.encodeQueryComponent('artist:"$a"')}&fmt=json&limit=1',
    );
    final res = await _getJson(urlSearch);
    if (res.statusCode != 200) return ArtistInfo(country: null, genres: [], bio: null);

    final data = jsonDecode(res.body) as Map<String, dynamic>;
    final artists = (data['artists'] as List?) ?? [];
    if (artists.isEmpty) return ArtistInfo(country: null, genres: [], bio: null);

    final first = artists.first as Map<String, dynamic>;
    final country = (first['country'] as String?)?.trim();

    final tags = (first['tags'] as List?) ?? [];
    final genres = <String>[];
    for (final t in tags.take(5)) {
      final tt = t as Map<String, dynamic>;
      final name = (tt['name'] as String?)?.trim();
      if (name != null && name.isNotEmpty) genres.add(name);
    }

    final bio = await _fetchWikipediaBio(a);

    return ArtistInfo(country: country, genres: genres, bio: bio);
  }

  /// ✅ DISCOGRAFÍA por NOMBRE (esto te faltaba)
  static Future<List<AlbumItem>> getDiscography(String artistName) async {
    final a = artistName.trim();
    if (a.isEmpty) return [];

    final q = 'artist:"$a" AND primarytype:album';
    final url = Uri.parse(
      '$_mbBase/release-group/?query=${Uri.encodeQueryComponent(q)}&fmt=json&limit=40',
    );

    final res = await _getJson(url);
    if (res.statusCode != 200) return [];

    final data = jsonDecode(res.body) as Map<String, dynamic>;
    final rgs = (data['release-groups'] as List?) ?? [];

    final out = <AlbumItem>[];

    for (final x in rgs) {
      final m = x as Map<String, dynamic>;
      final id = m['id'] as String?;
      final title = m['title'] as String?;
      if (id == null || title == null) continue;

      final frd = (m['first-release-date'] as String?) ?? '';
      final year = frd.length >= 4 ? frd.substring(0, 4) : null;

      out.add(AlbumItem(
        releaseGroupId: id,
        title: title,
        year: year,
        cover250: _cover250(id),
        cover500: _cover500(id),
      ));
    }

    // ordenar por año
    out.sort((a, b) {
      final ay = int.tryParse(a.year ?? '') ?? 9999;
      final by = int.tryParse(b.year ?? '') ?? 9999;
      final c = ay.compareTo(by);
      if (c != 0) return c;
      return a.title.toLowerCase().compareTo(b.title.toLowerCase());
    });

    return out;
  }

  /// ✅ TRACKLIST por releaseGroupId
  static Future<List<TrackItem>> getTracksFromReleaseGroup(String rgid) async {
    final urlRg = Uri.parse('$_mbBase/release-group/$rgid?inc=releases&fmt=json');
    final resRg = await _getJson(urlRg);
    if (resRg.statusCode != 200) return [];

    final dataRg = jsonDecode(resRg.body) as Map<String, dynamic>;
    final releases = (dataRg['releases'] as List?) ?? [];
    if (releases.isEmpty) return [];

    final firstReleaseId = (releases.first as Map<String, dynamic>)['id'] as String?;
    if (firstReleaseId == null) return [];

    final urlRel = Uri.parse('$_mbBase/release/$firstReleaseId?inc=recordings&fmt=json');
    final resRel = await _getJson(urlRel);
    if (resRel.statusCode != 200) return [];

    final dataRel = jsonDecode(resRel.body) as Map<String, dynamic>;
    final media = (dataRel['media'] as List?) ?? [];
    if (media.isEmpty) return [];

    final tracksOut = <TrackItem>[];
    int n = 1;

    for (final m in media) {
      final mm = m as Map<String, dynamic>;
      final tracks = (mm['tracks'] as List?) ?? [];
      for (final t in tracks) {
        final tt = t as Map<String, dynamic>;
        final title = (tt['title'] as String?) ?? 'Track';
        final lenMs = tt['length'] as int?;
        tracksOut.add(TrackItem(
          number: n++,
          title: title,
          length: (lenMs == null) ? null : _fmtMs(lenMs),
        ));
      }
    }

    return tracksOut;
  }

  static String _fmtMs(int ms) {
    final totalSec = (ms / 1000).round();
    final m = totalSec ~/ 60;
    final s = totalSec % 60;
    return '${m}:${s.toString().padLeft(2, '0')}';
  }
}
