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

  // autocomplete artista
  Timer? _debounceArtist;
  bool buscandoArtistas = false;
  List<ArtistHit> sugerenciasArtistas = [];
  ArtistHit? artistaElegido;

  // autocomplete álbum
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

  // ---------- AUTOCOMPLETE ARTISTA ----------
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

    _debounceArtist = Timer(const Duration(milliseconds: 450), () async {
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
      // limpiar álbum porque cambió artista
      albumCtrl.clear();
      albumElegido = null;
      sugerenciasAlbums = [];
    });
  }

  // ---------- AUTOCOMPLETE ÁLBUM ----------
  void _onAlbumChanged(String v) {
    _debounceAlbum?.cancel();
    final q = v.trim();
    final artistName = artistaCtrl.text.trim();

    setState(() {
      albumElegido = null;
    });

    if (artistName.isEmpty || q.isEmpty) {
      setState(() {
        sugerenciasAlbums = [];
        buscandoAlbums = false;
      });
      return;
    }

    _debounceAlbum = Timer(const Duration(milliseconds: 450), () async {
      setState(() => buscandoAlbums = true);
      final hits = await MetadataService.searchAlbumsForArtist(
        artistName: artistName,
        albumQuery: q,
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

  // ---------- COVER LOCAL ----------
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

  // ---------- AUTOCOMPLETAR META ----------
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
    });

    try {
      final meta = await MetadataService.fetchAutoMetadata(
        artist: lastArtist,
        album: lastAlbum,
      );

      // si hay artista elegido, mejor info por ID (más preciso)
      ArtistInfo aInfo;
      if (artistaElegido != null) {
        aInfo = await DiscographyService.getArtistInfoById(artistaElegido!.id, artistName: artistaElegido!.name);
      } else {
        aInfo = await DiscographyService.getArtistInfoById(
          (await DiscographyService.searchArtists(lastArtist)).isNotEmpty
              ? (await DiscographyService.searchArtists(lastArtist)).first.id
              : '',
          artistName: lastArtist,
        );
      }

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

  // ---------- BUSCAR EN COLECCIÓN ----------
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
    });

    snack(res.isEmpty ? 'No lo tienes' : 'Ya lo tienes');

    // ✅ limpiar barra después de buscar
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
    if (bio.isNotEmpty) {
      bioShort = bio.length > 220 ? '${bio.substring(0, 220)}…' : bio;
    }

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
      });
    } catch (_) {
      snack('Ese vinilo ya existe (Artista + Álbum)');
    }
  }

  // ---------- UI ----------
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

  Widget _leadingCover(Map<String, dynamic> v) {
    final cp = (v['coverPath'] as String?)?.trim() ?? '';
    if (cp.isNotEmpty) {
      final f = File(cp);
      if (f.existsSync()) {
        return ClipRRect(
          borderRadius: BorderRadius.circular(8),
          child: Image.file(f, width: 48, height: 48, fit: BoxFit.cover),
        );
      }
    }
    return const Icon(Icons.album);
  }

  void _showBioFromVinyl(Map<String, dynamic> v) {
    final bio = (v['artistBio'] as String?)?.trim() ?? '';
    if (bio.isEmpty) return;

    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: Text('Reseña — ${v['artista']}'),
        content: SizedBox(
          width: double.maxFinite,
          child: SingleChildScrollView(child: Text(bio)),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cerrar')),
        ],
      ),
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
            labelText: 'Álbum (autocompletar)',
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

        if (resultados.isNotEmpty)
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.85),
              borderRadius: BorderRadius.circular(14),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Resultados en tu colección:', style: TextStyle(fontWeight: FontWeight.bold)),
                const SizedBox(height: 8),
                ...resultados.map((v) {
                  final y = (v['year'] as String?)?.trim() ?? '';
                  final yTxt = y.isEmpty ? '' : ' ($y)';
                  return Padding(
                    padding: const EdgeInsets.symmetric(vertical: 6),
                    child: Row(
                      children: [
                        _leadingCover(v),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            'LP N° ${v['numero']} — ${v['artista']} — ${v['album']}$yTxt',
                            style: const TextStyle(fontWeight: FontWeight.w600),
                          ),
                        ),
                      ],
                    ),
                  );
                }).toList(),
              ],
            ),
          ),

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
                  const Expanded(child: Text('Carátula automática ✅', style: TextStyle(fontWeight: FontWeight.w800))),
                ],
              ),
            ),

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

  Widget listaCompleta({required bool conBorrar}) {
    return FutureBuilder<List<Map<String, dynamic>>>(
      future: VinylDb.instance.getAll(),
      builder: (context, snap) {
        if (!snap.hasData) return const Center(child: CircularProgressIndicator());
        final items = snap.data!;
        if (items.isEmpty) {
          return const Text('No tienes vinilos todavía.', style: TextStyle(color: Colors.white));
        }

        return ListView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          itemCount: items.length,
          itemBuilder: (context, i) {
            final v = items[i];

            final year = (v['year'] as String?)?.trim() ?? '';
            final genre = (v['genre'] as String?)?.trim() ?? '';
            final country = (v['country'] as String?)?.trim() ?? '';

            final yearTxt = year.isEmpty ? '—' : year;
            final genreTxt = genre.isEmpty ? '—' : genre;
            final countryTxt = country.isEmpty ? '—' : country;

            final hasBio = ((v['artistBio'] as String?)?.trim() ?? '').isNotEmpty;

            return Card(
              color: Colors.white.withOpacity(0.88),
              child: ListTile(
                leading: _leadingCover(v),
                title: Text('LP N° ${v['numero']} — ${v['artista']} — ${v['album']}'),
                subtitle: Text('Año: $yearTxt   •   Género: $genreTxt   •   País: $countryTxt'),
                onTap: () {
                  showModalBottomSheet(
                    context: context,
                    isScrollControlled: true,
                    backgroundColor: Colors.white,
                    shape: const RoundedRectangleBorder(
                      borderRadius: BorderRadius.vertical(top: Radius.circular(18)),
                    ),
                    builder: (_) => SizedBox(
                      height: MediaQuery.of(context).size.height * 0.90,
                      child: VinylDetailSheet(vinyl: v),
                    ),
                  );
                },
                trailing: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (hasBio)
                      IconButton(
                        tooltip: 'Reseña',
                        icon: const Icon(Icons.info_outline),
                        onPressed: () => _showBioFromVinyl(v),
                      ),
                    if (conBorrar)
                      IconButton(
                        icon: const Icon(Icons.delete),
                        onPressed: () async {
                          await VinylDb.instance.deleteById(v['id'] as int);
                          snack('Borrado');
                          setState(() {});
                        },
                      ),
                  ],
                ),
              ),
            );
          },
        );
      },
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
                    if (vista == Vista.lista) listaCompleta(conBorrar: false),
                    if (vista == Vista.borrar) listaCompleta(conBorrar: true),
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
