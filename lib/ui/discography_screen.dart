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

  ArtistHit? pickedArtist;
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
      pickedArtist = null;
      artistInfo = null;
      albums = [];
    });

    final hits = await DiscographyService.searchArtists(name);
    if (hits.isEmpty) {
      setState(() {
        loading = false;
        msg = 'No encontré ese artista.';
      });
      return;
    }

    // Elegimos el mejor (score más alto)
    final best = hits.first;

    final info = await DiscographyService.getArtistInfo(best.name);
    final list = await DiscographyService.getDiscographyByArtistId(best.id);

    if (!mounted) return;

    setState(() {
      pickedArtist = best;
      artistInfo = info;
      albums = list;
      loading = false;
      msg = list.isEmpty ? 'No encontré álbumes.' : null;
    });
  }

  Future<bool> _yaLoTengo(String artist, String album) async {
    return VinylDb.instance.existsExact(artista: artist, album: album);
  }

  @override
  Widget build(BuildContext context) {
    final showArtistName = pickedArtist?.name ?? artistCtrl.text.trim();

    final country = (artistInfo?.country ?? pickedArtist?.country ?? '').trim();
    final genres = artistInfo?.genres ?? [];
    String bio = (artistInfo?.bio ?? '').trim();

    if (bio.length > 320) bio = '${bio.substring(0, 320)}…';

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

            if (pickedArtist != null)
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.black.withOpacity(0.06),
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: Colors.black12),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(showArtistName, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w900)),
                    const SizedBox(height: 6),
                    Text('País: ${country.isEmpty ? '—' : country}', style: const TextStyle(fontWeight: FontWeight.w700)),
                    const SizedBox(height: 4),
                    Text(
                      'Género(s): ${genres.isEmpty ? '—' : genres.join(', ')}',
                      style: const TextStyle(fontWeight: FontWeight.w700),
                    ),
                    const SizedBox(height: 8),

                    // ✅ Reseña plegable para que NO tape los discos
                    if (bio.isNotEmpty)
                      ExpansionTile(
                        tilePadding: EdgeInsets.zero,
                        title: const Text('Ver reseña', style: TextStyle(fontWeight: FontWeight.w800)),
                        children: [
                          Padding(
                            padding: const EdgeInsets.only(bottom: 8),
                            child: Text(bio),
                          ),
                        ],
                      ),
                  ],
                ),
              ),

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
                            builder: (_) => AlbumTracksScreen(album: a, artistName: showArtistName),
                          ),
                        );
                      },
                      trailing: FutureBuilder<bool>(
                        future: _yaLoTengo(showArtistName, a.title),
                        builder: (context, snap2) {
                          final have = snap2.data ?? false;
                          if (have) return const Text('Ya lo tienes ✅', style: TextStyle(fontWeight: FontWeight.w800));
                          return TextButton(
                            onPressed: () async {
                              try {
                                await VinylDb.instance.insertVinyl(
                                  artista: showArtistName,
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
