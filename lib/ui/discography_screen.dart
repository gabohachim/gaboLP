import 'package:flutter/material.dart';
import '../services/discography_service.dart';
import 'album_tracks_screen.dart';

class DiscographyScreen extends StatefulWidget {
  const DiscographyScreen({super.key});

  @override
  State<DiscographyScreen> createState() => _DiscographyScreenState();
}

class _DiscographyScreenState extends State<DiscographyScreen> {
  final bandCtrl = TextEditingController();

  List<ArtistHit> artistResults = [];
  List<AlbumItem> albums = [];

  bool loadingArtists = false;
  bool loadingAlbums = false;

  @override
  void dispose() {
    bandCtrl.dispose();
    super.dispose();
  }

  void snack(String t) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(t)));
  }

  Future<void> buscarArtista() async {
    final name = bandCtrl.text.trim();
    if (name.isEmpty) {
      snack('Escribe el nombre de la banda/artista');
      return;
    }

    setState(() {
      loadingArtists = true;
      artistResults = [];
      albums = [];
    });

    final res = await DiscographyService.searchArtist(name);

    setState(() {
      artistResults = res;
      loadingArtists = false;
    });

    if (res.isEmpty) snack('No encontré artistas con ese nombre');
  }

  Future<void> cargarDiscografia(ArtistHit artist) async {
    setState(() {
      loadingAlbums = true;
      albums = [];
    });

    final res = await DiscographyService.getDiscographyAlbums(artist.id);

    setState(() {
      albums = res;
      loadingAlbums = false;
    });

    if (res.isEmpty) snack('No encontré álbumes para ese artista');
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Discografías'),
      ),
      body: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          children: [
            TextField(
              controller: bandCtrl,
              decoration: InputDecoration(
                labelText: 'Banda / Artista',
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(14)),
                suffixIcon: IconButton(
                  icon: const Icon(Icons.search),
                  onPressed: buscarArtista,
                ),
              ),
            ),
            const SizedBox(height: 10),

            if (loadingArtists) const LinearProgressIndicator(),

            // Lista de artistas para elegir (por si hay varios iguales)
            if (artistResults.isNotEmpty && albums.isEmpty) ...[
              const Align(
                alignment: Alignment.centerLeft,
                child: Text('Elige el artista correcto:', style: TextStyle(fontWeight: FontWeight.bold)),
              ),
              const SizedBox(height: 8),
              Expanded(
                child: ListView.builder(
                  itemCount: artistResults.length,
                  itemBuilder: (context, i) {
                    final a = artistResults[i];
                    final sub = (a.disambiguation?.trim().isNotEmpty ?? false)
                        ? a.disambiguation!
                        : 'ID: ${a.id.substring(0, 8)}...';
                    return Card(
                      child: ListTile(
                        title: Text(a.name),
                        subtitle: Text(sub),
                        onTap: () => cargarDiscografia(a),
                      ),
                    );
                  },
                ),
              ),
            ],

            if (loadingAlbums) const LinearProgressIndicator(),

            // Discografía (álbumes)
            if (albums.isNotEmpty) ...[
              const SizedBox(height: 6),
              const Align(
                alignment: Alignment.centerLeft,
                child: Text('Álbumes:', style: TextStyle(fontWeight: FontWeight.bold)),
              ),
              const SizedBox(height: 8),
              Expanded(
                child: ListView.builder(
                  itemCount: albums.length,
                  itemBuilder: (context, i) {
                    final al = albums[i];
                    return Card(
                      child: ListTile(
                        leading: al.coverUrl == null
                            ? const Icon(Icons.album)
                            : ClipRRect(
                                borderRadius: BorderRadius.circular(8),
                                child: Image.network(
                                  al.coverUrl!,
                                  width: 48,
                                  height: 48,
                                  fit: BoxFit.cover,
                                  errorBuilder: (_, __, ___) => const Icon(Icons.album),
                                ),
                              ),
                        title: Text(al.title),
                        subtitle: Text(al.year == null ? 'Año: —' : 'Año: ${al.year}'),
                        onTap: () {
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) => AlbumTracksScreen(album: al),
                            ),
                          );
                        },
                      ),
                    );
                  },
                ),
              ),
            ],

            if (artistResults.isEmpty && albums.isEmpty && !loadingArtists)
              const Expanded(
                child: Center(
                  child: Text('Escribe una banda y busca su discografía.'),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

