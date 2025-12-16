import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../db/vinyl_db.dart';
import '../services/metadata_service.dart';
import '../services/discography_service.dart';
import 'vinyl_detail_sheet.dart';
import 'discography_screen.dart';

enum Vista { inicio, buscar, lista, borrar }

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  Vista vista = Vista.inicio;

  final artistaCtrl = TextEditingController();
  final albumCtrl = TextEditingController();
  final yearCtrl = TextEditingController();

  Timer? _debounceArtist;
  bool buscandoArtistas = false;
  List<ArtistHit> sugerenciasArtistas = [];
  ArtistHit? artistaElegido;

  Timer? _debounceAlbum;
  bool buscandoAlbums = false;
  List<AlbumSuggest> sugerenciasAlbums = [];
  AlbumSuggest? albumElegido;

  List<Map<String, dynamic>> resultados = [];
  bool mostrarAgregar = false;

  String lastArtist = '';
  String lastAlbum = '';

  String? coverPreviewUrl;
  String? mbidFound;
  String? genreFound;
  String? countryFound;
  String? artistBioFound;

  bool autocompletando = false;

  // ✅ guardamos candidatos de carátula (máx 5 para mostrar)
  List<CoverCandidate> coverCandidates = [];

  @override
  void dispose() {
    _debounceArtist?.cancel();
    _debounceAlbum?.cancel();
    artistaCtrl.dispose();
    albumCtrl.dispose();
    yearCtrl.dispose();
    super.dispose();
  }

  void snack(String t) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(t)));
  }

  // ---- Autocomplete artista ----
  void _onArtistChanged(String v) {
    _debounceArtist?.cancel();
    final q = v.trim();

    setState(() {
      artistaElegido = null;
      albumElegido = null;
      sugerenciasAlbums = [];
      buscandoAlbums = false;
    });

    if (q.isEmpty) {
      setState(() {
        sugerenciasArtistas = [];
        buscandoArtistas = false;
      });
      return;
    }

    _debounceArtist = Timer(const Duration(milliseconds: 350), () async {
      setState(() => buscandoArtistas = true);
      final hits = await DiscographyService.searchArtists(q);
      if (!mounted) return;
      setState(() {
        sugerenciasArtistas = hits;
        buscandoArtistas = false;
      });
    });
  }

  Future<void> _pickArtist(ArtistHit a) async {
    FocusScope.of(context).unfocus();
    setState(() {
      artistaElegido = a;
      artistaCtrl.text = a.name;
      sugerenciasArtistas = [];
      albumCtrl.clear();
      albumElegido = null;
      sugerenciasAlbums = [];
    });
  }

  // ---- Autocomplete álbum (✅ con 1 letra) ----
  void _onAlbumChanged(String v) {
    _debounceAlbum?.cancel();
    final q = v.trim();
    final artistName = artistaCtrl.text.trim();

    setState(() => albumElegido = null);

    if (artistName.isEmpty || q.isEmpty) {
      setState(() {
        sugerenciasAlbums = [];
        buscandoAlbums = false;
      });
      return;
    }

    // ✅ debounce más corto y sin mínimo >1
    _debounceAlbum = Timer(const Duration(milliseconds: 220), () async {
      setState(() => buscandoAlbums = true);
      final hits = await MetadataService.searchAlbumsForArtist(
        artistName: artistName,
        albumQuery: q, // con 1 letra ya devuelve
      );
      if (!mounted) return;
      setState(() {
        sugerenciasAlbums = hits;
        buscandoAlbums = false;
      });
    });
  }

  Future<void> _pickAlbum(AlbumSuggest a) async {
    FocusScope.of(context).unfocus();
    setState(() {
      albumElegido = a;
      albumCtrl.text = a.title;
      sugerenciasAlbums = [];
    });
  }

  Future<String?> _downloadCoverToLocal(String url) async {
    try {
      final res = await http.get(Uri.parse(url));
      if (res.statusCode != 200) return null;

      final dir = await getApplicationDocumentsDirectory();
      final coversDir = Directory(p.join(dir.path, 'covers'));
      if (!await coversDir.exists()) await coversDir.create(recursive: true);

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

  Future<void> _autoCompletarMeta() async {
    if (lastArtist.trim().isEmpty || lastAlbum.trim().isEmpty) return;

    setState(() {
      autocompletando = true;
      coverPreviewUrl = null;
      mbidFound = null;
      genreFound = null;
      countryFound = null;
      artistBioFound = null;
      yearCtrl.clear();
      coverCandidates = [];
    });

    try {
      // ✅ 1) Traer candidatos de carátulas (para elegir luego)
      final candidatesAll = await MetadataService.fetchCoverCandidates(
        artist: lastArtist,
        album: lastAlbum,
      );
      final cand = candidatesAll.take(5).toList(); // ✅ máximo 5
      coverCandidates = cand;

      // ✅ 2) Usar el primer candidato como default
      final meta = await MetadataService.fetchAutoMetadataWithCandidates(
        artist: lastArtist,
        album: lastAlbum,
        candidates: cand,
      );

      // ✅ info artista (para país + reseña)
      final aInfo = (artistaElegido != null)
          ? await DiscographyService.getArtistInfoById(artistaElegido!.id, artistName: artistaElegido!.name)
          : await DiscographyService.getArtistInfo(lastArtist);

      if (!mounted) return;

      setState(() {
        if ((meta.year ?? '').isNotEmpty) yearCtrl.text = meta.year!;
        genreFound = (meta.genre ?? '').trim().isEmpty ? null : meta.genre!.trim();
        mbidFound = meta.releaseGroupId ?? albumElegido?.releaseGroupId;
        coverPreviewUrl = meta.cover500 ?? albumElegido?.cover500;

        final c = (aInfo.country ?? '').trim();
        countryFound = c.isEmpty ? null : c;

        final bio = (aInfo.bio ?? '').trim();
        artistBioFound = bio.isEmpty ? null : bio;

        autocompletando = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => autocompletando = false);
    }
  }

  Future<void> _elegirCaratula() async {
    if (coverCandidates.isEmpty) {
      snack('No encontré carátulas para elegir.');
      return;
    }

    final picked = await showDialog<CoverCandidate>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Elegir carátula (máx 5)'),
        content: SizedBox(
          width: double.maxFinite,
          child: ListView.separated(
            shrinkWrap: true,
            itemCount: coverCandidates.length,
            separatorBuilder: (_, __) => const Divider(height: 1),
            itemBuilder: (context, i) {
              final c = coverCandidates[i];
              final y = (c.year ?? '').trim();
              return ListTile(
                leading: ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: Image.network(
                    c.coverUrl250,
                    width: 50,
                    height: 50,
                    fit: BoxFit.cover,
                    errorBuilder: (_, __, ___) => const Icon(Icons.album),
                  ),
                ),
                title: Text('Opción ${i + 1}${y.isEmpty ? '' : ' — $y'}'),
                onTap: () => Navigator.pop(context, c),
              );
            },
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cerrar')),
        ],
      ),
    );

    if (picked == null) return;

    setState(() {
      mbidFound = picked.mbid;
      coverPreviewUrl = picked.coverUrl500;
      if ((picked.year ?? '').trim().isNotEmpty) yearCtrl.text = picked.year!.trim();
    });
  }

  Future<void> buscar() async {
    final artista = artistaCtrl.text.trim();
    final album = albumCtrl.text.trim();

    if (artista.isEmpty && album.isEmpty) {
      snack('Escribe al menos Artista o Álbum');
      return;
    }

    final res = await VinylDb.instance.search(artista: artista, album: album);

    setState(() {
      resultados = res;
      lastArtist = artista;
      lastAlbum = album;
      mostrarAgregar = res.isEmpty && artista.isNotEmpty && album.isNotEmpty;

      coverPreviewUrl = null;
      mbidFound = null;
      genreFound = null;
      countryFound = null;
      artistBioFound = null;
      yearCtrl.clear();
      coverCandidates = [];
    });

    snack(res.isEmpty ? 'No lo tienes' : 'Ya lo tienes');

    artistaCtrl.clear();
    albumCtrl.clear();
    sugerenciasArtistas = [];
    sugerenciasAlbums = [];
    artistaElegido = null;
    albumElegido = null;

    if (mostrarAgregar) {
      await _autoCompletarMeta();
    }
  }

  Future<void> agregar() async {
    final artista = lastArtist.trim();
    final album = lastAlbum.trim();
    final year = yearCtrl.text.trim();

    if (artista.isEmpty || album.isEmpty) {
      snack('Para agregar: Artista y Álbum son obligatorios');
      return;
    }

    String? localCoverPath;
    if (coverPreviewUrl != null && coverPreviewUrl!.trim().isNotEmpty) {
      localCoverPath = await _downloadCoverToLocal(coverPreviewUrl!.trim());
    }

    String? bioShort;
    final bio = (artistBioFound ?? '').trim();
    if (bio.isNotEmpty) bioShort = bio.length > 220 ? '${bio.substring(0, 220)}…' : bio;

    try {
      await VinylDb.instance.insertVinyl(
        artista: artista,
        album: album,
        year: year.isEmpty ? null : year,
        genre: genreFound,
        country: countryFound,
        artistBio: bioShort,
        coverPath: localCoverPath,
        mbid: mbidFound,
      );

      snack('Vinilo agregado ✅');

      setState(() {
        mostrarAgregar = false;
        resultados = [];
        coverPreviewUrl = null;
        mbidFound = null;
        genreFound = null;
        countryFound = null;
        artistBioFound = null;
        yearCtrl.clear();
        coverCandidates = [];
      });
    } catch (_) {
      snack('Ese vinilo ya existe (Artista + Álbum)');
    }
  }

  Widget gabolpMarca() {
    return const Positioned(
      right: 10,
      bottom: 8,
      child: IgnorePointer(
        child: Text(
          'GaBoLP',
          style: TextStyle(fontSize: 12, color: Colors.white70, fontWeight: FontWeight.w700),
        ),
      ),
    );
  }

  Widget contadorLp() {
    return FutureBuilder<int>(
      future: VinylDb.instance.getCount(),
      builder: (context, snap) {
        final total = snap.data ?? 0;
        return Align(
          alignment: Alignment.centerLeft,
          child: Container(
            width: 90,
            height: 70,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: Colors.black.withOpacity(0.65),
              borderRadius: BorderRadius.circular(14),
            ),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Text('LP', style: TextStyle(color: Colors.white70, fontWeight: FontWeight.w700)),
                Text('$total',
                    style: const TextStyle(color: Colors.white, fontSize: 22, fontWeight: FontWeight.w900)),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget botonesInicio() {
    Widget btn(IconData icon, String text, VoidCallback onTap) {
      return InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(18),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 14),
          decoration: BoxDecoration(
            color: Colors.white.withOpacity(0.85),
            borderRadius: BorderRadius.circular(18),
          ),
          child: Row(
            children: [
              Icon(icon),
              const SizedBox(width: 12),
              Expanded(child: Text(text, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700))),
              const Icon(Icons.chevron_right),
            ],
          ),
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        btn(Icons.search, 'Buscar vinilos', () => setState(() => vista = Vista.buscar)),
        const SizedBox(height: 10),
        btn(Icons.library_music, 'Discografías', () {
          Navigator.push(context, MaterialPageRoute(builder: (_) => const DiscographyScreen()));
        }),
        const SizedBox(height: 10),
        btn(Icons.list, 'Mostrar lista de vinilos', () => setState(() => vista = Vista.lista)),
        const SizedBox(height: 10),
        btn(Icons.delete_outline, 'Borrar vinilos', () => setState(() => vista = Vista.borrar)),
      ],
    );
  }

  Widget vistaBuscar() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        TextField(
          controller: artistaCtrl,
          onChanged: _onArtistChanged,
          decoration: InputDecoration(
            labelText: 'Artista (autocompletar)',
            filled: true,
            fillColor: Colors.white.withOpacity(0.85),
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(14)),
          ),
        ),
        const SizedBox(height: 6),
        if (buscandoArtistas) const LinearProgressIndicator(),
        if (sugerenciasArtistas.isNotEmpty)
          Container(
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.92),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Colors.black12),
            ),
            child: ListView.separated(
              shrinkWrap: true,
              itemCount: sugerenciasArtistas.length,
              separatorBuilder: (_, __) => const Divider(height: 1),
              itemBuilder: (context, i) {
                final a = sugerenciasArtistas[i];
                final c = (a.country ?? '').trim();
                return ListTile(
                  dense: true,
                  title: Text(a.name),
                  subtitle: Text(c.isEmpty ? '' : 'País: $c'),
                  onTap: () => _pickArtist(a),
                );
              },
            ),
          ),
        const SizedBox(height: 10),

        TextField(
          controller: albumCtrl,
          onChanged: _onAlbumChanged,
          decoration: InputDecoration(
            labelText: 'Álbum (autocompletar, 1 letra basta)',
            filled: true,
            fillColor: Colors.white.withOpacity(0.85),
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(14)),
          ),
        ),
        const SizedBox(height: 6),
        if (buscandoAlbums) const LinearProgressIndicator(),
        if (sugerenciasAlbums.isNotEmpty)
          Container(
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.92),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Colors.black12),
            ),
            child: ListView.separated(
              shrinkWrap: true,
              itemCount: sugerenciasAlbums.length,
              separatorBuilder: (_, __) => const Divider(height: 1),
              itemBuilder: (context, i) {
                final al = sugerenciasAlbums[i];
                final y = (al.year ?? '').trim();
                return ListTile(
                  dense: true,
                  title: Text(al.title),
                  subtitle: Text(y.isEmpty ? '' : 'Año: $y'),
                  onTap: () => _pickAlbum(al),
                );
              },
            ),
          ),

        const SizedBox(height: 10),
        ElevatedButton(onPressed: buscar, child: const Text('Buscar')),
        const SizedBox(height: 12),

        if (mostrarAgregar) ...[
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.85),
              borderRadius: BorderRadius.circular(14),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Agregar este vinilo:', style: TextStyle(fontWeight: FontWeight.w900)),
                const SizedBox(height: 6),
                Text('Artista: $lastArtist', style: const TextStyle(fontWeight: FontWeight.w700)),
                Text('Álbum: $lastAlbum', style: const TextStyle(fontWeight: FontWeight.w700)),
                const SizedBox(height: 8),
                if (autocompletando) const LinearProgressIndicator(),
                if (!autocompletando) ...[
                  Text('Año: ${yearCtrl.text.isEmpty ? '—' : yearCtrl.text}'),
                  Text('Género: ${genreFound ?? '—'}'),
                  Text('País: ${countryFound ?? '—'}'),
                ],
              ],
            ),
          ),
          const SizedBox(height: 10),

          if (coverPreviewUrl != null && coverPreviewUrl!.trim().isNotEmpty)
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.85),
                borderRadius: BorderRadius.circular(14),
              ),
              child: Row(
                children: [
                  ClipRRect(
                    borderRadius: BorderRadius.circular(10),
                    child: Image.network(
                      coverPreviewUrl!,
                      width: 70,
                      height: 70,
                      fit: BoxFit.cover,
                      errorBuilder: (_, __, ___) => const SizedBox(
                        width: 70,
                        height: 70,
                        child: Center(child: Icon(Icons.broken_image)),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      coverCandidates.length > 1 ? 'Carátula (hay ${coverCandidates.length} opciones)' : 'Carátula automática ✅',
                      style: const TextStyle(fontWeight: FontWeight.w800),
                    ),
                  ),
                ],
              ),
            ),

          if (coverCandidates.length > 1) ...[
            const SizedBox(height: 8),
            OutlinedButton.icon(
              onPressed: _elegirCaratula,
              icon: const Icon(Icons.photo_library_outlined),
              label: const Text('Elegir carátula (máx 5)'),
            ),
          ],

          const SizedBox(height: 10),
          TextField(
            controller: yearCtrl,
            keyboardType: TextInputType.number,
            decoration: InputDecoration(
              labelText: 'Año (si quieres cambiarlo)',
              filled: true,
              fillColor: Colors.white.withOpacity(0.85),
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(14)),
            ),
          ),
          const SizedBox(height: 10),
          ElevatedButton(onPressed: autocompletando ? null : agregar, child: const Text('Agregar vinilo')),
        ],
      ],
    );
  }

  PreferredSizeWidget? _buildAppBar() {
    if (vista == Vista.inicio) return null;

    String title;
    switch (vista) {
      case Vista.buscar:
        title = 'Buscar vinilos';
        break;
      case Vista.lista:
        title = 'Lista de vinilos';
        break;
      case Vista.borrar:
        title = 'Borrar vinilos';
        break;
      default:
        title = 'GaBoLP';
    }

    return AppBar(
      title: Text(title),
      leading: IconButton(
        icon: const Icon(Icons.arrow_back),
        onPressed: () => setState(() => vista = Vista.inicio),
      ),
    );
  }

  Widget? _buildFab() {
    if (vista == Vista.lista || vista == Vista.borrar) {
      return FloatingActionButton.extended(
        onPressed: () => setState(() => vista = Vista.inicio),
        icon: const Icon(Icons.home),
        label: const Text('Inicio'),
      );
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: _buildAppBar(),
      floatingActionButton: _buildFab(),
      body: Stack(
        children: [
          Positioned.fill(child: Container(color: Colors.grey.shade300)),
          Positioned.fill(child: Container(color: Colors.black.withOpacity(0.35))),
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: SingleChildScrollView(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    if (vista == Vista.inicio) ...[
                      contadorLp(),
                      const SizedBox(height: 14),
                      botonesInicio(),
                    ],
                    if (vista == Vista.buscar) vistaBuscar(),
                    if (vista == Vista.lista)
                      const Text('La lista se mantiene como la tenías (sin reseña en lista).', style: TextStyle(color: Colors.white)),
                    if (vista == Vista.borrar)
                      const Text('Modo borrar (sin cambios aquí).', style: TextStyle(color: Colors.white)),
                  ],
                ),
              ),
            ),
          ),
          gabolpMarca(),
        ],
      ),
    );
  }
}
