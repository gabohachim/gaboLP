import 'dart:io';
import 'package:flutter/material.dart';

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

  String? coverPreviewUrl;
  String? mbidFound;
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

  // ---------------- UI helpers ----------------

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
                const Text('LP',
                    style: TextStyle(color: Colors.white70, fontWeight: FontWeight.w700)),
                Text('$total',
                    style: const TextStyle(
                        color: Colors.white,
                        fontSize: 22,
                        fontWeight: FontWeight.w900)),
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
                child: Text(text,
                    style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
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
        btn(Icons.search, 'Buscar vinilos', () {
          setState(() => vista = Vista.buscar);
        }),
        const SizedBox(height: 10),
        btn(Icons.library_music, 'Discografías', () {
          Navigator.push(
            context,
            MaterialPageRoute(builder: (_) => const DiscographyScreen()),
          );
        }),
        const SizedBox(height: 10),
        btn(Icons.list, 'Mostrar lista de vinilos', () {
          setState(() => vista = Vista.lista);
        }),
        const SizedBox(height: 10),
        btn(Icons.delete_outline, 'Borrar vinilos', () {
          setState(() => vista = Vista.borrar);
        }),
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

  // ---------------- Buscar ----------------

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
      mostrarAgregar = res.isEmpty && artista.isNotEmpty && album.isNotEmpty;
    });

    artistaCtrl.clear();
    albumCtrl.clear();
    yearCtrl.clear();
  }

  Future<void> buscarCoverYAno() async {
    setState(() {
      buscandoCover = true;
      coverPreviewUrl = null;
      mbidFound = null;
    });

    final options = await MetadataService.fetchCoverCandidates(
      artist: lastArtist,
      album: lastAlbum,
    );

    setState(() => buscandoCover = false);

    if (options.isEmpty) {
      snack('No encontré carátulas');
      return;
    }

    final c = options.first;
    setState(() {
      coverPreviewUrl = c.coverUrl500;
      mbidFound = c.releaseGroupId;
      if (yearCtrl.text.isEmpty && c.year != null) {
        yearCtrl.text = c.year!;
      }
    });
  }

  Future<void> agregar() async {
    await VinylDb.instance.insertVinyl(
      artista: lastArtist,
      album: lastAlbum,
      year: yearCtrl.text.isEmpty ? null : yearCtrl.text,
      coverPath: null,
      mbid: mbidFound,
    );
    snack('Vinilo agregado');
    setState(() {
      vista = Vista.inicio;
      resultados = [];
      mostrarAgregar = false;
    });
  }

  Widget vistaBuscar() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        TextField(controller: artistaCtrl, decoration: const InputDecoration(labelText: 'Artista')),
        const SizedBox(height: 8),
        TextField(controller: albumCtrl, decoration: const InputDecoration(labelText: 'Álbum')),
        const SizedBox(height: 8),
        ElevatedButton(onPressed: buscar, child: const Text('Buscar')),

        if (mostrarAgregar) ...[
          const SizedBox(height: 10),
          ElevatedButton(
            onPressed: buscandoCover ? null : buscarCoverYAno,
            child: const Text('Buscar carátula y año'),
          ),
          const SizedBox(height: 8),
          TextField(controller: yearCtrl, decoration: const InputDecoration(labelText: 'Año')),
          const SizedBox(height: 8),
          ElevatedButton(onPressed: agregar, child: const Text('Agregar vinilo')),
        ],

        const SizedBox(height: 10),
        TextButton(
          onPressed: () => setState(() => vista = Vista.inicio),
          child: const Text('Volver', style: TextStyle(color: Colors.white)),
        ),
      ],
    );
  }

  // ---------------- Lista ----------------

  Widget listaCompleta({required bool conBorrar}) {
    return FutureBuilder<List<Map<String, dynamic>>>(
      future: VinylDb.instance.getAll(),
      builder: (context, snap) {
        if (!snap.hasData) return const CircularProgressIndicator();
        final items = snap.data!;
        return ListView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          itemCount: items.length,
          itemBuilder: (context, i) {
            final v = items[i];
            return Card(
              child: ListTile(
                leading: _leadingCover(v),
                title: Text('LP N° ${v['numero']} — ${v['artista']} — ${v['album']}'),
                onTap: () {
                  showModalBottomSheet(
                    context: context,
                    isScrollControlled: true,
                    builder: (_) => VinylDetailSheet(vinyl: v),
                  );
                },
                trailing: conBorrar
                    ? IconButton(
                        icon: const Icon(Icons.delete),
                        onPressed: () async {
                          await VinylDb.instance.deleteById(v['id'] as int);
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

  // ---------------- Build ----------------

  @override
  Widget build(BuildContext context) {
    return Scaffold(
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
                    contadorLp(),
                    const SizedBox(height: 14),

                    if (vista == Vista.inicio) botonesInicio(),
                    if (vista == Vista.buscar) vistaBuscar(),
                    if (vista == Vista.lista) listaCompleta(conBorrar: false),
                    if (vista == Vista.borrar) listaCompleta(conBorrar: true),

                    if (vista != Vista.inicio)
                      TextButton(
                        onPressed: () => setState(() => vista = Vista.inicio),
                        child: const Text('Volver', style: TextStyle(color: Colors.white)),
                      ),
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
