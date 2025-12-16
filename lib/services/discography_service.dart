import 'dart:convert';
import 'package:http/http.dart' as http;

class ArtistHit {
  final String id;
  final String name;
  final String? country;
  final int? score;

  ArtistHit({required this.id, required this.name, this.country, this.score});
}

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

  static bool _looksLikeYearTag(String s) {
    final t = s.toLowerCase().trim();
    if (t.isEmpty) return true;
    if (t.contains('year')) return true;
    if (t.contains('years')) return true;
    final reDecade = RegExp(r'^\d{2,4}s$');
    if (reDecade.hasMatch(t)) return true;
    final reDigits = RegExp(r'\d');
    if (reDigits.hasMatch(t)) return true;
    return false;
  }

  static List<String> _pickGenres(List tags) {
    final out = <String>[];
    for (final t in tags) {
      if (t is! Map<String, dynamic>) continue;
      final name = (t['name'] as String?)?.trim();
      if (name == null || name.isEmpty) continue;
      if (_looksLikeYearTag(name)) continue;
      out.add(name);
      if (out.length >= 5) break;
    }
    return out;
  }

  static String _cover250(String rgid) =>
      'https://coverartarchive.org/release-group/$rgid/front-250';
  static String _cover500(String rgid) =>
      'https://coverartarchive.org/release-group/$rgid/front-500';

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

  /// Autocomplete bandas
  static Future<List<ArtistHit>> searchArtists(String name) async {
    final n = name.trim();
    if (n.isEmpty) return [];

    final url = Uri.parse(
      '$_mbBase/artist/?query=${Uri.encodeQueryComponent(n)}&fmt=json&limit=12',
    );

    final res = await _getJson(url);
    if (res.statusCode != 200) return [];

    final data = jsonDecode(res.body) as Map<String, dynamic>;
    final artists = (data['artists'] as List?) ?? [];
    final out = <ArtistHit>[];

    for (final a in artists) {
      final m = a as Map<String, dynamic>;
      final id = m['id'] as String?;
      final name = m['name'] as String?;
      if (id == null || name == null) continue;

      out.add(ArtistHit(
        id: id,
        name: name,
        country: (m['country'] as String?)?.trim(),
        score: m['score'] as int?,
      ));
    }

    out.sort((a, b) => (b.score ?? 0).compareTo(a.score ?? 0));
    return out;
  }

  static Future<ArtistInfo> getArtistInfoById(String artistId, {String? artistName}) async {
    final id = artistId.trim();
    if (id.isEmpty) return ArtistInfo(country: null, genres: [], bio: null);

    final url = Uri.parse('$_mbBase/artist/$id?inc=tags&fmt=json');
    final res = await _getJson(url);

    String? country;
    List<String> genres = [];
    String? nameForBio = artistName;

    if (res.statusCode == 200) {
      final data = jsonDecode(res.body) as Map<String, dynamic>;
      nameForBio ??= (data['name'] as String?)?.trim();
      country = (data['country'] as String?)?.trim();

      final tags = (data['tags'] as List?) ?? [];
      genres = _pickGenres(tags);
    }

    final bio = (nameForBio == null || nameForBio!.isEmpty) ? null : await _fetchWikipediaBio(nameForBio!);

    return ArtistInfo(country: country, genres: genres, bio: bio);
  }

  static Future<List<AlbumItem>> getDiscographyByArtistId(String artistId) async {
    final id = artistId.trim();
    if (id.isEmpty) return [];

    final url = Uri.parse('$_mbBase/release-group/?artist=$id&fmt=json&limit=100');
    final res = await _getJson(url);
    if (res.statusCode != 200) return [];

    final data = jsonDecode(res.body) as Map<String, dynamic>;
    final rgs = (data['release-groups'] as List?) ?? [];

    final out = <AlbumItem>[];
    for (final x in rgs) {
      final m = x as Map<String, dynamic>;
      final primaryType = (m['primary-type'] as String?)?.toLowerCase().trim();
      if (primaryType != 'album') continue;

      final rgid = m['id'] as String?;
      final title = m['title'] as String?;
      if (rgid == null || title == null) continue;

      final frd = (m['first-release-date'] as String?) ?? '';
      final year = frd.length >= 4 ? frd.substring(0, 4) : null;

      out.add(AlbumItem(
        releaseGroupId: rgid,
        title: title,
        year: year,
        cover250: _cover250(rgid),
        cover500: _cover500(rgid),
      ));
    }

    out.sort((a, b) {
      final ay = int.tryParse(a.year ?? '') ?? 9999;
      final by = int.tryParse(b.year ?? '') ?? 9999;
      final c = ay.compareTo(by);
      if (c != 0) return c;
      return a.title.toLowerCase().compareTo(b.title.toLowerCase());
    });

    return out;
  }

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
