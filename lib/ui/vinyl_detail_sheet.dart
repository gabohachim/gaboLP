import 'dart:io';
import 'package:flutter/material.dart';

import '../services/discography_service.dart';

class VinylDetailSheet extends StatefulWidget {
  final Map<String, dynamic> vinyl;

  const VinylDetailSheet({super.key, required this.vinyl});

  @override
  State<VinylDetailSheet> createState() => _VinylDetailSheetState();
}

class _VinylDetailSheetState extends State<VinylDetailSheet> {
  bool loading = false;
  List<TrackItem> tracks = [];
  String? err;

  @override
  void initState() {
    super.initState();
    _loadTracks();
  }

  String? _releaseGroupMbid() {
    // intenta varias keys por compatibilidad
    final v = widget.vinyl;
    final a = (v['mbid'] ?? '').toString().trim();
    if (a.isNotEmpty) return a;
    final b = (v['releaseGroupMbid'] ?? '').toString().trim();
    if (b.isNotEmpty) return b;
    final c = (v['rgMbid'] ?? '').toString().trim();
    if (c.isNotEmpty) return c;
    return null;
  }

  Future<void> _loadTracks() async {
    final mbid = _releaseGroupMbid();
    if (mbid == null) {
      setState(() {
        err = 'Este vinilo no tiene MBID guardado, no puedo traer tracklist.';
      });
      return;
    }

    setState(() {
      loading = true;
      err = null;
      tracks = [];
    });

    try {
      final list = await DiscographyService.getTracksFromReleaseGroup(mbid);
      if (!mounted) return;
      setState(() {
        tracks = list;
        loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        loading = false;
        err = 'No se pudo cargar el tracklist: $e';
      });
    }
  }

  Widget _cover() {
    final cp = (widget.vinyl['coverPath'] ?? '').toString().trim();
    if (cp.isNotEmpty) {
      final f = File(cp);
      if (f.existsSync()) {
        return ClipRRect(
          borderRadius: BorderRadius.circular(16),
          child: Image.file(f, height: 220, width: 220, fit: BoxFit.cover),
        );
      }
    }
    return Container(
      height: 220,
      width: 220,
      decoration: BoxDecoration(
        color: Colors.black12,
        borderRadius: BorderRadius.circular(16),
      ),
      child: const Center(child: Icon(Icons.album, size: 80)),
    );
  }

  void _showBio() {
    final bio = (widget.vinyl['bio'] ?? '').toString().trim();
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Reseña de la banda'),
        content: SingleChildScrollView(
          child: Text(bio.isEmpty ? 'Sin reseña.' : bio),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cerrar')),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final v = widget.vinyl;

    final numero = (v['numero'] ?? '').toString();
    final artista = (v['artista'] ?? v['artist'] ?? '').toString();
    final album = (v['album'] ?? '').toString();
    final year = (v['year'] ?? '').toString().trim();
    final genre = (v['genre'] ?? '').toString().trim();
    final country = (v['country'] ?? '').toString().trim();

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            Container(
              height: 5,
              width: 60,
              decoration: BoxDecoration(
                color: Colors.black26,
                borderRadius: BorderRadius.circular(999),
              ),
            ),
            const SizedBox(height: 14),

            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _cover(),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('LP N° $numero', style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 16)),
                      const SizedBox(height: 6),
                      Text(artista, style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 18)),
                      const SizedBox(height: 4),
                      Text(album, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 16)),
                      const SizedBox(height: 10),
                      Text('Año: ${year.isEmpty ? '—' : year}'),
                      Text('Género: ${genre.isEmpty ? '—' : genre}'),
                      Text('País: ${country.isEmpty ? '—' : country}'),
                      const SizedBox(height: 12),
                      OutlinedButton.icon(
                        onPressed: _showBio,
                        icon: const Icon(Icons.description_outlined),
                        label: const Text('Reseña'),
                      ),
                    ],
                  ),
                ),
              ],
            ),

            const SizedBox(height: 16),
            const Divider(),

            Row(
              children: [
                const Expanded(
                  child: Text('Canciones', style: TextStyle(fontWeight: FontWeight.w900, fontSize: 16)),
                ),
                IconButton(
                  tooltip: 'Recargar tracklist',
                  onPressed: loading ? null : _loadTracks,
                  icon: const Icon(Icons.refresh),
                ),
              ],
            ),

            if (loading) const LinearProgressIndicator(),
            if (err != null) Padding(padding: const EdgeInsets.only(top: 10), child: Text(err!)),
            const SizedBox(height: 8),

            Expanded(
              child: tracks.isEmpty
                  ? const Center(child: Text('Sin tracklist todavía.'))
                  : ListView.separated(
                      itemCount: tracks.length,
                      separatorBuilder: (_, __) => const Divider(height: 1),
                      itemBuilder: (context, i) {
                        final t = tracks[i];
                        return ListTile(
                          dense: true,
                          leading: Text('${t.number}', style: const TextStyle(fontWeight: FontWeight.w800)),
                          title: Text(t.title),
                          trailing: Text(t.length ?? ''),
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
