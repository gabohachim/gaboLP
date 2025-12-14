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

  static Future<OnlineAlbum?> fetchCoverAndYear({
    required String artist,
    required String album,
  }) async {
    final a = artist.trim();
    final al = album.trim();
    if (a.isEmpty || al.isEmpty) return null;

    // 1) Buscar release en MusicBrainz
    final q = 'release:"$al" AND artist:"$a"';
    final url = Uri.parse(
      '$_mbBase/release/?query=${Uri.encodeQueryComponent(q)}&fmt=json&limit=1',
    );

    final res = await http.get(
      url,
      headers: {
        // MusicBrainz pide User-Agent identificable
        'User-Agent': 'GaBoLP/1.0 (contact: gabolp@example.com)',
      },
    );

    if (res.statusCode != 200) return null;

    final data = jsonDecode(res.body) as Map<String, dynamic>;
    final releases = (data['releases'] as List?) ?? [];
    if (releases.isEmpty) return null;

    final r = releases.first as Map<String, dynamic>;
    final mbid = r['id'] as String?;
    final date = (r['date'] as String?) ?? '';
    final year = date.length >= 4 ? date.substring(0, 4) : null;

    // 2) Cover Art Archive por MBID
    String? coverUrl;
    if (mbid != null) {
      final caa = Uri.parse('$_caaBase/release/$mbid');
      final caaRes = await http.get(caa);
      if (caaRes.statusCode == 200) {
        final caaData = jsonDecode(caaRes.body) as Map<String, dynamic>;
        final images = (caaData['images'] as List?) ?? [];
        if (images.isNotEmpty) {
          final img0 = images.first as Map<String, dynamic>;
          coverUrl = img0['image'] as String?;
        }
      }
    }

    return OnlineAlbum(coverUrl: coverUrl, year: year, mbid: mbid);
  }
}

