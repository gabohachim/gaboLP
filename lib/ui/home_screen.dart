import 'dart:io';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../db/vinyl_db.dart';
import '../services/metadata_service.dart';
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

  List<Map<String, dynamic>> resultados = [];
  bool mostrarAgregar = false;

  String lastArtist = '';
  String lastAlbum = '';

  String? coverPreviewUrl; // url elegida (500)
  String? mbidFound; // releaseGroupId
  bool buscandoCover = false;

  @override
  void dispose() {
    artistaCtrl.dispose();
    albumCtrl.dispose();
    yearCtrl.dispose();
    super.dispose();
  }

  void snack(String t) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(t)));
  }

  // -------------------- Descargar y guardar carátula --------------------

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

  // -------------------- Buscar en tu colección --------------------

  Future<void> buscar() async {
    final artista = artistaCtrl.text.trim();
    final album = albumCtrl.text.trim();

    if (artista.isEmpty && album.isEmpty) {
      snack('Escribe al menos Artista o Álbum');
      return;
    }

    final res = await VinylDb.instance.search(
      artista: artista,
      album: album,
    );

    setState(() {
      resultados = res;
      lastArtist = artista;
      lastAlbum = album;

      // permitir agregar solo si hay artista+álbum y no existe
      mostrarAgregar = res.isEmpty && artista.isNotEmpty && album.isNotEmpty;

      // reset preview
      coverPreviewUrl = null;
      mbidFound = null;
      buscandoCover = false;
    });

    snack(res.isEmpty ? 'No lo tienes' : 'Ya lo tienes');

    // ✅ limpiar barra después de buscar
    artistaCtrl.clear();
    albumCtrl.clear();
    yearCtrl.clear();
  }

  // -------------------- Elegir carátula (varias opciones) --------------------

  Future<void> _showCoverPicker(List<CoverCandidate> options) async {
    final picked = await showModalBottomSheet<CoverCandidate>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(18)),
      ),
      builder: (ctx) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text(
                  'Elige una carátula',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.w900),
                ),
                const SizedBox(height: 10),
                Flexible(
                  child: ListView.separated(
                    shrinkWrap: true,
                    itemCount: options.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 8),
                    itemBuilder: (context, i) {
                      final c = options[i];
                      return InkWell(
                        onTap: () => Navigator.pop(ctx, c),
                        borderRadius: BorderRadius.circular(14),
                        child: Container(
                          padding: const EdgeInsets.all(10),
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(14),
                            border: Border.all(color: Colors.black12),
                          ),
                          child: Row(
                            children: [
                              ClipRRect(
                                borderRadius: BorderRadius.circular(10),
                                child: Image.network(
                                  c.coverUrl250,
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
                                  'Año: ${c.year ?? '—'}',
                                  style: const TextStyle(fontWeight: FontWeight.w800),
                                ),
                              ),
                              const Icon(Icons.chevron_right),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
                ),
                const SizedBox(height: 10),
                TextButton(
                  onPressed: () => Navigator.pop(ctx, null),
                  child: const Text('Cancelar'),
                ),
              ],
            ),
          ),
        );
      },
    );

    if (picked == null) return;

    setState(() {
      coverPreviewUrl = picked.coverUrl500;
      mbidFound = picked.releaseGroupId;
    });

    if (yearCtrl.text.trim().isEmpty && (picked.year?.isNotEmpty ?? false)) {
      yearCtrl.text = picked.year!;
    }

    snack('Carátula seleccionada ✅');
  }

  Future<void> buscarCoverYAno() async {
    if (lastArtist.trim().isEmpty || lastAlbum.trim().isEmpty) {
      snack('Primero busca (Artista + Álbum)');
      return;
    }

    setState(() {
      buscandoCover = true;
      coverPreviewUrl = null;
      mbidFound = null;
    });

    final options = await MetadataService.fetchCoverCandidates(
      artist: lastArtist,
      album: lastAlbum,
    );

    if (!mounted) return;

    setState(() => buscandoCover = false);

    if (options.isEmpty) {
      snack('No encontré carátulas');
      return;
    }

    if (options.length == 1) {
      final c = options.first;
      setState(() {
        coverPreviewUrl = c.coverUrl500;
        mbidFound = c.releaseGroupId;
      });
      if (yearCtrl.text.trim().isEmpty && (c.year?.isNotEmpty ?? false)) {
        yearCtrl.text = c.year!;
      }
      snack('Carátula encontrada ✅');
      return;
    }

    await _showCoverPicker(options);
  }

  // -------------------- Agregar vinilo a la BD --------------------

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

    try {
      await VinylDb.instance.insertVinyl(
        artista: artista,
        album: album,
        year: year.isEmpty ? null : year,
        coverPath: localCoverPath,
        mbid: mbidFound,
      );

      snack('Vinilo agregado ✅');

      setState(() {
        mostrarAgregar = false;
        resultados = [];
        coverPreviewUrl = null;
        mbidFound = null;
        buscandoCover = false;
        yearCtrl.clear();
      });
    } catch (_) {
      snack('Ese vinilo ya existe (Artista + Álbum)');
    }
  }

  // -------------------- UI --------------------

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
              border: Border.all(color: Colors.white.withOpacity(0.10)),
            ),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Text('LP', style: TextStyle(color: Colors.white70, fontSize: 14, fontWeight: FontWeight.w700)),
                Text('$total', style: const TextStyle(color: Colors.white, fontSize: 22, fontWeight: FontWeight.w900)),
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

  // ✅ ARREGLO 1: resultados muestran año
  Widget vistaBuscar() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        TextField(
          controller: artistaCtrl,
          decoration: InputDecoration(
            labelText: 'Artista',
            filled: true,
            fillColor: Colors.white.withOpacity(0.85),
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(14)),
          ),
        ),
        const SizedBox(height: 10),
        TextField(
          controller: albumCtrl,
          decoration: InputDecoration(
            labelText: 'Álbum (opcional para buscar)',
            filled: true,
            fillColor: Colors.white.withOpacity(0.85),
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(14)),
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

                // ✅ aquí va el arreglo del año:
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
            child: Text(
              'Agregar este vinilo:\nArtista: $lastArtist\nÁlbum: $lastAlbum',
              style: const TextStyle(fontWeight: FontWeight.w700),
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
                  const Expanded(child: Text('Carátula elegida ✅', style: TextStyle(fontWeight: FontWeight.w800))),
                ],
              ),
            ),

          const SizedBox(height: 10),

          TextField(
            controller: yearCtrl,
            keyboardType: TextInputType.number,
            decoration: InputDecoration(
              labelText: 'Año (opcional, se autocompleta si se encuentra)',
              filled: true,
              fillColor: Colors.white.withOpacity(0.85),
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(14)),
            ),
          ),
          const SizedBox(height: 10),

          ElevatedButton(
            onPressed: buscandoCover ? null : buscarCoverYAno,
            child: Text(buscandoCover ? 'Buscando...' : 'Buscar carátula y año (internet)'),
          ),
          const SizedBox(height: 10),

          ElevatedButton(onPressed: agregar, child: const Text('Agregar vinilo')),
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
            final yearTxt = year.isEmpty ? '' : ' ($year)';

            return Card(
              color: Colors.white.withOpacity(0.88),
              child: ListTile(
                leading: _leadingCover(v),
                title: Text('LP N° ${v['numero']} — ${v['artista']} — ${v['album']}$yearTxt'),
                onTap: () {
                  showModalBottomSheet(
                    context: context,
                    isScrollControlled: true,
                    backgroundColor: Colors.white,
                    shape: const RoundedRectangleBorder(
                      borderRadius: BorderRadius.vertical(top: Radius.circular(18)),
                    ),
                    builder: (_) => SizedBox(
                      height: MediaQuery.of(context).size.height * 0.85,
                      child: VinylDetailSheet(vinyl: v),
                    ),
                  );
                },
                trailing: conBorrar
                    ? IconButton(
                        icon: const Icon(Icons.delete),
                        onPressed: () async {
                          await VinylDb.instance.deleteById(v['id'] as int);
                          snack('Borrado');
                          setState(() {});
                        },
                      )
                    : null,
              ),
            );
          },
        );
      },
    );
  }

  // ✅ ARREGLO 2: AppBar + botón flotante Inicio (para listas largas)
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
                    // Si estás en inicio, mostramos contador arriba (como siempre)
                    if (vista == Vista.inicio) ...[
                      contadorLp(),
                      const SizedBox(height: 14),
                      botonesInicio(),
                    ],

                    if (vista == Vista.buscar) ...[
                      vistaBuscar(),
                    ],

                    if (vista == Vista.lista) ...[
                      listaCompleta(conBorrar: false),
                    ],

                    if (vista == Vista.borrar) ...[
                      listaCompleta(conBorrar: true),
                    ],
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
