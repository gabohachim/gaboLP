import 'dart:io';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as p;

import '../db/vinyl_db.dart';
import '../services/discography_service.dart';

class AlbumTracksScreen extends StatefulWidget {
  final AlbumItem album;
  final String artistName; // 👈 ahora lo recibimos

  const AlbumTracksScreen({
    super.key,
    required this.album,
    required this.artistName,
  });

  @override
  State<AlbumTracksScreen> createState() => _AlbumTracksScreenState();
}

class _AlbumTracksScreenState extends State<AlbumTracksScreen> {
  bool loading = true;
  List<TrackItem> tracks = [];

  bool checkingOwned = true;
  bool isOwned = false;

  @override
  void initState() {
    super.initState();
    _loadTracks();
    _checkOwned();
  }

  void snack(String t) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(t)));
  }

  String _norm(String s) => s.trim().toLowerCase();
  String _key(String artist, String album) => '${_norm(artist)}|${_norm(album)}';

  Future<void> _checkOwned() async {
    setState(() => checkingOwned = true);
    final res = await VinylDb.instance.search(
      artista: widget.artistName.trim(),
      album: widget.album.title.trim(),
    );
    if (!mounted) return;
    setState(() {
      isOwned = res.isNotEmpty;
      checkingOwned = false;
    });
  }

  Future<String?> _downloadCoverToLocal(String url) async {
    try {
      final res = await http.get(Uri.parse(url));
      if (res.statusCode != 200) return null;

      final dir = await getApplicationDocumentsDirectory();
      final coversDir = Directory(p.join(dir.path, 'covers'));
      if (!await coversDir.exists()) {
        await coversDir.create(recursive: true);
      }

      final ct = res.headers['content-type'] ?? '';
      final ext = ct.contains('png') ? 'png' : 'jpg';

      final filename = 'cover_${DateTime.now().millisecondsSinceEpoch}.$ext';
      final file = File(p.join(coversDir.path, filename));
      await file.writeAsBytes(res.bodyBytes);
      return file.path;
    } catch (_) {
      return null;
    }
  }

  Future<void> _addLp() async {
    if (isOwned) {
      snack('Ya lo tienes ✅');
      return;
    }

    final artist = widget.artistName.trim();
    final album = widget.album.title.trim();
    final year = (widget.album.year ?? '').trim();

    String? coverPath;
    final coverUrl = widget.album.coverUrl;
    if (coverUrl != null && coverUrl.trim().isNotEmpty) {
      // mejor calidad:
      final url = coverUrl.replaceAll('front-250', 'front-500');
      coverPath = await _downloadCoverToLocal(url);
    }

    try {
      await VinylDb.instance.insertVinyl(
        artista: artist,
        album: album,
        year: year.isEmpty ? null : year,
        coverPath: coverPath,
        mbid: null,
      );
      setState(() => isOwned = true);
      snack('Agregado a tu colección ✅');
    } catch (_) {
      setState(() => isOwned = true);
      snack('Ya lo tenías (Artista + Álbum)');
    }
  }

  Future<void> _loadTracks() async {
    setState(() => loading = true);
    final res = await DiscographyService.getTracksFromReleaseGroup(widget.album.id);
    if (!mounted) return;
    setState(() {
      tracks = res;
      loading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final al = widget.album;

    return Scaffold(
      appBar: AppBar(
        title: Text(al.title),
      ),
      body: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          children: [
            Row(
              children: [
                if (al.coverUrl != null)
                  ClipRRect(
                    borderRadius: BorderRadius.circular(10),
                    child: Image.network(
                      al.coverUrl!,
                      width: 85,
                      height: 85,
                      fit: BoxFit.cover,
                      errorBuilder: (_, __, ___) => const Icon(Icons.album, size: 60),
                    ),
                  )
                else
                  const Icon(Icons.album, size: 60),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    '${widget.artistName}\nAño: ${al.year ?? '—'}',
                    style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
                  ),
                ),
              ],
            ),

            const SizedBox(height: 10),

            // ✅ Botón agregar LP en tracklist
            Row(
              children: [
                Expanded(
                  child: checkingOwned
                      ? const LinearProgressIndicator()
                      : isOwned
                          ? Container(
                              padding: const EdgeInsets.symmetric(vertical: 12),
                              alignment: Alignment.center,
                              decoration: BoxDecoration(
                                color: Colors.green.withOpacity(0.15),
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: const Text(
                                'Ya lo tienes ✅',
                                style: TextStyle(fontWeight: FontWeight.w800),
                              ),
                            )
                          : ElevatedButton(
                              onPressed: _addLp,
                              child: const Text('Agregar LP'),
                            ),
                ),
              ],
            ),

            const SizedBox(height: 12),

            if (loading) const LinearProgressIndicator(),
            const SizedBox(height: 10),

            Expanded(
              child: tracks.isEmpty && !loading
                  ? const Center(child: Text('No encontré canciones para este álbum.'))
                  : ListView.builder(
                      itemCount: tracks.length,
                      itemBuilder: (context, i) {
                        final t = tracks[i];
                        return Card(
                          child: ListTile(
                            title: Text('${t.number}. ${t.title}'),
                            trailing: Text(t.length ?? ''),
                          ),
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }
}
