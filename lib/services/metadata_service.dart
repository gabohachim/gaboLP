import 'dart:convert';
import 'package:http/http.dart' as http;

class OnlineAlbum {
  final String? coverUrl;
  final String? year;
  final String? mbid;

  OnlineAlbum({this.coverUrl, this.year, this.mbid});
}

class MetadataService {
  static const _mbBase = 'https://musicbrainz.org/ws/2';
  static const _caaBase = 'https://coverartarchive.org';

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

  static Future<OnlineAlbum?> fetchCoverAndYear({
    required String artist,
    required String album,
  }) async {
    final q = 'release:"$album" AND artist:"$artist"';
    final url = Uri.parse(
      '$_mbBase/release/?query=${Uri.encodeQueryComponent(q)}&fmt=json&limit=5',
    );

    final res = await _get(url);
    if (res.statusCode != 200) return null;

    final data = jsonDecode(res.body) as Map<String, dynamic>;
    final releases = (data['releases'] as List?) ?? [];
    if (releases.isEmpty) return null;

    for (final r in releases) {
      final m = r as Map<String, dynamic>;
      final mbid = m['id'] as String?;
      final date = (m['date'] as String?) ?? '';
      final year = date.length >= 4 ? date.substring(0, 4) : null;

      if (mbid != null) {
        final caa = Uri.parse('$_caaBase/release/$mbid');
        final caaRes = await _get(caa);

        if (caaRes.statusCode == 200) {
          final caaData = jsonDecode(caaRes.body) as Map<String, dynamic>;
          final images = (caaData['images'] as List?) ?? [];
          if (images.isNotEmpty) {
            final img = images.first as Map<String, dynamic>;
            return OnlineAlbum(
              coverUrl: img['image'],
              year: year,
              mbid: mbid,
            );
          }
        }
      }

      if (year != null) {
        return OnlineAlbum(year: year, mbid: mbid);
      }
    }

    return null;
  }
}
