import 'package:flutter/material.dart';

import '../db/vinyl_db.dart';
import '../services/discography_service.dart';
import 'album_tracks_screen.dart';

class DiscographyScreen extends StatefulWidget {
  const DiscographyScreen({super.key});

  @override
  State<DiscographyScreen> createState() => _DiscographyScreenState();
}

class _DiscographyScreenState extends State<DiscographyScreen> {
  final artistCtrl = TextEditingController();

  bool loading = false;
  String? msg;

  ArtistInfo? artistInfo;
  List<AlbumItem> albums = [];

  @override
  void dispose() {
    artistCtrl.dispose();
    super.dispose();
  }

  Future<void> buscar() async {
    final name = artistCtrl.text.trim();
    if (name.isEmpty) return;

    setState(() {
      loading = true;
      msg = null;
      artistInfo = null;
      albums = [];
    });

    final info = await DiscographyService.getArtistInfo(name);
    final list = await DiscographyService.getDiscography(name);

    if (!mounted) return;

    setState(() {
      artistInfo = info;
      albums = list;
      loading = false;
      msg = list.isEmpty ? 'No encontré discografía.' : null;
    });
  }

  Future<bool> _yaLoTengo(String artist, String album) async {
    return VinylDb.instance.existsExact(artista: artist, album: album);
  }

  Widget _artistHeader(String artistName) {
    final c = artistInfo?.country;
    final g = artistInfo?.genres ?? [];
    final b = artistInfo?.bio;

    final countryTxt = (c == null || c.isEmpty) ? '—' : c;
    final genreTxt = g.isEmpty ? '—' : g.join(', ');

    String bioTxt = (b == null || b.isEmpty) ? 'Reseña: no disponible' : b;
    if (bioTxt.length > 320) bioTxt = '${bioTxt.substring(0, 320)}…';

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.black.withOpacity(0.08),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.black12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(artistName, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w900)),
          const SizedBox(height: 6),
          Text('País: $countryTxt', style: const TextStyle(fontWeight: FontWeight.w700)),
          const SizedBox(height: 4),
          Text('Género(s): $genreTxt', style: const TextStyle(fontWeight: FontWeight.w700)),
          const SizedBox(height: 10),
          Text(bioTxt),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final artistName = artistCtrl.text.trim();

    return Scaffold(
      appBar: AppBar(title: const Text('Discografías')),
      body: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          children: [
            TextField(
              controller: artistCtrl,
              decoration: const InputDecoration(
                labelText: 'Banda / Artista',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 10),
            ElevatedButton(
              onPressed: loading ? null : buscar,
              child: Text(loading ? 'Buscando...' : 'Buscar'),
            ),
            const SizedBox(height: 10),
            if (artistInfo != null && artistName.isNotEmpty) _artistHeader(artistName),
            if (msg != null)
              Padding(
                padding: const EdgeInsets.only(top: 10),
                child: Text(msg!, style: const TextStyle(fontWeight: FontWeight.w700)),
              ),
            const SizedBox(height: 10),
            Expanded(
              child: ListView.builder(
                itemCount: albums.length,
                itemBuilder: (context, i) {
                  final a = albums[i];
                  final year = a.year ?? '—';

                  return Card(
                    child: ListTile(
                      leading: ClipRRect(
                        borderRadius: BorderRadius.circular(10),
                        child: Image.network(
                          a.cover250,
                          width: 56,
                          height: 56,
                          fit: BoxFit.cover,
                          errorBuilder: (_, __, ___) => const Icon(Icons.album),
                        ),
                      ),
                      title: Text(a.title),
                      subtitle: Text('Año: $year'),
                      onTap: () {
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => AlbumTracksScreen(album: a, artistName: artistName),
                          ),
                        );
                      },
                      trailing: FutureBuilder<bool>(
                        future: _yaLoTengo(artistName, a.title),
                        builder: (context, snap2) {
                          final have = snap2.data ?? false;
                          if (have) {
                            return const Text('Ya lo tienes ✅', style: TextStyle(fontWeight: FontWeight.w800));
                          }
                          return TextButton(
                            onPressed: () async {
                              try {
                                await VinylDb.instance.insertVinyl(
                                  artista: artistName,
                                  album: a.title,
                                  year: a.year,
                                  coverPath: null,
                                  mbid: a.releaseGroupId,
                                );
                                if (mounted) setState(() {});
                              } catch (_) {}
                            },
                            child: const Text('Agregar LP'),
                          );
                        },
                      ),
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
