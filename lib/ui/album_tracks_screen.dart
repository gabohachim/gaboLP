import 'package:flutter/material.dart';
import '../services/discography_service.dart';

class AlbumTracksScreen extends StatefulWidget {
  final AlbumItem album;
  const AlbumTracksScreen({super.key, required this.album});

  @override
  State<AlbumTracksScreen> createState() => _AlbumTracksScreenState();
}

class _AlbumTracksScreenState extends State<AlbumTracksScreen> {
  bool loading = true;
  List<TrackItem> tracks = [];

  @override
  void initState() {
    super.initState();
    _loadTracks();
  }

  Future<void> _loadTracks() async {
    setState(() => loading = true);
    final res = await DiscographyService.getTracksFromReleaseGroup(widget.album.id);
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
                    'Año: ${al.year ?? '—'}',
                    style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
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

