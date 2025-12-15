import 'dart:io';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as p;

import '../db/vinyl_db.dart';
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

  // Artista seleccionado (para agregar LP con el artista correcto)
  String selectedArtistName = '';

  // Set de tu colección para saber si ya lo tienes
  // clave: "artista|album" normalizado
  Set<String> owned = {};

  @override
  void dispose() {
    bandCtrl.dispose();
    super.dispose();
  }

  void snack(String t) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(t)));
  }

  String _norm(String s) => s.trim().toLowerCase();
  String _key(String artist, String album) => '${_norm(artist)}|${_norm(album)}';

  Future<void> _refreshOwned() async {
    final all = await VinylDb.instance.getAll();
    final set = <String>{};
    for (final v in all) {
      final a = (v['artista'] as String?) ?? '';
      final al = (v['album'] as String?) ?? '';
      if (a.trim().isNotEmpty && al.trim().isNotEmpty) {
        set.add(_key(a, al));
      }
    }
    if (!mounted) return;
    setState(() => owned = set);
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
      selectedArtistName = '';
    });

    final res = await DiscographyService.searchArtist(name);

    if (!mounted) return;
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
      selectedArtistName = artist.name;
    });

    final res = await DiscographyService.getDiscographyAlbums(artist.id);

    if (!mounted) return;
    setState(() {
      albums = res;
      loadingAlbums = false;
    });

    // Actualizar tu colección para marcar cuáles ya tienes
    await _refreshOwned();

    if (res.isEmpty) snack('No encontré álbumes para ese artista');
  }

  Future<void> agregarLpDesdeDiscografia(AlbumItem al) async {
    if (selectedArtistName.trim().isEmpty) {
      snack('Primero elige un artista');
      return;
    }

    final artist = selectedArtistName.trim();
    final album = al.title.trim();
    final year = (al.year ?? '').trim();

    // Doble chequeo por si ya lo tienes
    final k = _key(artist, album);
    if (owned.contains(k)) {
      snack('Ya lo tienes ✅');
      return;
    }

    // Descargar carátula (si existe)
    String? coverPath;
    if (al.coverUrl != null && al.coverUrl!.trim().isNotEmpty) {
      // Si quieres mejor calidad: cambia front-250 por front-500 o front
      final url = al.coverUrl!.replaceAll('front-250', 'front-500');
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

      // Marcar como “ya lo tienes”
      setState(() => owned.add(k));

      snack('Agregado a tu colección ✅');
    } catch (_) {
      // Por si la BD dice que ya existe
      setState(() => owned.add(k));
      snack('Ya lo tenías (Artista + Álbum)');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Discografías')),
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

            // Elegir artista correcto
            if (artistResults.isNotEmpty && albums.isEmpty) ...[
              const Align(
                alignment: Alignment.centerLeft,
                child: Text('Elige el artista correcto:',
                    style: TextStyle(fontWeight: FontWeight.bold)),
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
              Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  'Álbumes de: $selectedArtistName',
                  style: const TextStyle(fontWeight: FontWeight.bold),
                ),
              ),
              const SizedBox(height: 8),
              Expanded(
                child: ListView.builder(
                  itemCount: albums.length,
                  itemBuilder: (context, i) {
                    final al = albums[i];

                    final isOwned = owned.contains(_key(selectedArtistName, al.title));

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
                        // Tocar el álbum => canciones
                        onTap: () {
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) => AlbumTracksScreen(album: al),
                            ),
                          );
                        },
                        // ✅ Botón “Agregar LP” solo si NO lo tienes
                        trailing: isOwned
                            ? const Text('Ya lo tienes ✅',
                                style: TextStyle(fontWeight: FontWeight.w700))
                            : ElevatedButton(
                                onPressed: () => agregarLpDesdeDiscografia(al),
                                child: const Text('Agregar LP'),
                              ),
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
