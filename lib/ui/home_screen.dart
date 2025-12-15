import 'dart:io';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as p;

import '../db/vinyl_db.dart';
import '../services/metadata_service.dart';
import 'discography_screen.dart';

enum Vista { inicio, buscar, lista, borrar }

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  Vista vista = Vista.inicio;

  // Campos del buscador
  final artistaCtrl = TextEditingController();
  final albumCtrl = TextEditingController();
  final yearCtrl = TextEditingController();

  // Guardamos lo último buscado para poder agregar aunque limpiemos la barra
  String lastArtist = '';
  String lastAlbum = '';

  List<Map<String, dynamic>> resultados = [];
  bool mostrarAgregar = false;

  // Carátula / metadata
  String? coverPreviewUrl;
  String? mbidFound;
  bool buscandoCover = false;

  // Fondo simple (sin botón)
  File? fondo;

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

  // ✅ BUSCAR: guarda lo escrito y limpia la barra
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

      // Guardar última búsqueda (para agregar y buscar carátula)
      lastArtist = artista;
      lastAlbum = album;

      // Mostrar agregar solo si escribió artista+album y no existe
      mostrarAgregar = res.isEmpty && artista.isNotEmpty && album.isNotEmpty;

      // Reset carátula
      coverPreviewUrl = null;
      mbidFound = null;
      buscandoCover = false;
    });

    snack(res.isEmpty ? 'No lo tienes' : 'Ya lo tienes');

    // ✅ limpiar campos del buscador (lo que pediste)
    artistaCtrl.clear();
    albumCtrl.clear();
    yearCtrl.clear();
  }

  // Usar lo escrito si existe, si no usar la última búsqueda
  String _artistForActions() =>
      artistaCtrl.text.trim().isNotEmpty ? artistaCtrl.text.trim() : lastArtist.trim();

  String _albumForActions() =>
      albumCtrl.text.trim().isNotEmpty ? albumCtrl.text.trim() : lastAlbum.trim();

  Future<void> buscarCoverYAno() async {
    final artist = _artistForActions();
    final album = _albumForActions();

    if (artist.isEmpty || album.isEmpty) {
      snack('Falta Artista o Álbum (vuelve a buscar)');
      return;
    }

    setState(() {
      buscandoCover = true;
      coverPreviewUrl = null;
      mbidFound = null;
    });

    final info = await MetadataService.fetchCoverAndYear(
      artist: artist,
      album: album,
    );

    if (!mounted) return;

    if (info == null) {
      setState(() => buscandoCover = false);
      snack('No encontré carátula/año');
      return;
    }

    // Autocompletar año si está vacío
    if (yearCtrl.text.trim().isEmpty && (info.year?.isNotEmpty ?? false)) {
      yearCtrl.text = info.year!;
    }

    setState(() {
      coverPreviewUrl = info.coverUrl;
      mbidFound = info.mbid;
      buscandoCover = false;
    });

    snack('Encontrado ✅');
  }

  Future<void> agregar() async {
    final artista = _artistForActions();
    final album = _albumForActions();
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

      snack('Agregado');

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

  Widget gabolpMarca() {
    return const Positioned(
      right: 10,
      bottom: 8,
      child: IgnorePointer(
        child: Text(
          'GaBoLP',
          style: TextStyle(
            fontSize: 12,
            color: Colors.white70,
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
    );
  }

  // Cuadrado pequeño LP
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
                const Text(
                  'LP',
                  style: TextStyle(
                    color: Colors.white70,
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                Text(
                  '$total',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 22,
                    fontWeight: FontWeight.w900,
                  ),
                ),
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
              Expanded(
                child: Text(
                  text,
                  style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
                ),
              ),
              const Icon(Icons.chevron_right),
            ],
          ),
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        btn(Icons.search, 'Buscar vinilo', () => setState(() => vista = Vista.buscar)),
        const SizedBox(height: 10),

        // ✅ NUEVO BOTÓN: DISCOGRAFÍAS
        btn(Icons.library_music, 'Discografías', () {
          Navigator.push(
            context,
            MaterialPageRoute(builder: (_) => const DiscographyScreen()),
          );
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
          child: Image.file(
            f,
            width: 48,
            height: 48,
            fit: BoxFit.cover,
          ),
        );
      }
    }
    return const Icon(Icons.album);
  }

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
        ElevatedButton(
          onPressed: buscar,
          child: const Text('Buscar'),
        ),
        const SizedBox(height: 12),

        // Resultados debajo del buscador
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
                const Text(
                  'Resultados en tu colección:',
                  style: TextStyle(fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 8),
                ...resultados.map((v) => Padding(
                      padding: const EdgeInsets.symmetric(vertical: 6),
                      child: Row(
                        children: [
                          _leadingCover(v),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              'LP N° ${v['numero']} — ${v['artista']} — ${v['album']}',
                              style: const TextStyle(fontWeight: FontWeight.w600),
                            ),
                          ),
                        ],
                      ),
                    )),
              ],
            ),
          ),

        const SizedBox(height: 12),

        // Si NO lo tienes (y escribió artista+album), aparece agregar + buscar carátula/año
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
                  const Expanded(
                    child: Text(
                      'Carátula encontrada ✅',
                      style: TextStyle(fontWeight: FontWeight.w700),
                    ),
                  ),
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

          ElevatedButton(
            onPressed: agregar,
            child: const Text('Agregar vinilo'),
          ),
        ],

        const SizedBox(height: 10),
        TextButton(
          onPressed: () => setState(() {
            vista = Vista.inicio;
            resultados = [];
            mostrarAgregar = false;
            coverPreviewUrl = null;
            mbidFound = null;
            buscandoCover = false;
            lastArtist = '';
            lastAlbum = '';
          }),
          child: const Text('Volver', style: TextStyle(color: Colors.white)),
        ),
      ],
    );
  }

  Widget listaCompleta({required bool conBorrar}) {
    return FutureBuilder<List<Map<String, dynamic>>>(
      future: VinylDb.instance.getAll(),
      builder: (context, snap) {
        if (!snap.hasData) {
          return const Center(child: CircularProgressIndicator());
        }
        final items = snap.data!;
        if (items.isEmpty) {
          return const Text('No tienes vinilos todavía.',
              style: TextStyle(color: Colors.white));
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

  @override
  Widget build(BuildContext context) {
    final bg = fondo != null
        ? Image.file(fondo!, fit: BoxFit.cover)
        : Container(color: Colors.grey.shade300);

    return Scaffold(
      appBar: null,
      body: Stack(
        children: [
          Positioned.fill(child: bg),
          Positioned.fill(child: Container(color: Colors.black.withOpacity(0.35))),
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: SingleChildScrollView(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    contadorLp(),
                    const SizedBox(height: 14),

                    if (vista == Vista.inicio) botonesInicio(),
                    if (vista == Vista.buscar) vistaBuscar(),

                    if (vista == Vista.lista) ...[
                      listaCompleta(conBorrar: false),
                      const SizedBox(height: 10),
                      TextButton(
                        onPressed: () => setState(() => vista = Vista.inicio),
                        child: const Text('Volver', style: TextStyle(color: Colors.white)),
                      ),
                    ],

                    if (vista == Vista.borrar) ...[
                      listaCompleta(conBorrar: true),
                      const SizedBox(height: 10),
                      TextButton(
                        onPressed: () => setState(() => vista = Vista.inicio),
                        child: const Text('Volver', style: TextStyle(color: Colors.white)),
                      ),
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
