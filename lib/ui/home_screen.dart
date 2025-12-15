import 'dart:io';
import 'package:flutter/material.dart';

import '../db/vinyl_db.dart';
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

  List<Map<String, dynamic>> resultados = [];

  void snack(String t) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(t)));
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
              border: Border.all(color: Colors.white.withOpacity(0.1)),
            ),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Text(
                  'LP',
                  style: TextStyle(color: Colors.white70, fontSize: 14, fontWeight: FontWeight.w700),
                ),
                Text(
                  '$total',
                  style: const TextStyle(color: Colors.white, fontSize: 22, fontWeight: FontWeight.w900),
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
                child: Text(text, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
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
                title: Text(
                  'LP N° ${v['numero']} — ${v['artista']} — ${v['album']}$yearTxt',
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),

                // ✅ NUEVO: abre ventana con carátula + canciones
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
