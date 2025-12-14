import 'dart:io';
import 'package:flutter/material.dart';
import '../db/vinyl_db.dart';

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

  // Fondo se mantiene en código (por si después lo reactivas),
  // pero SIN botón para cambiarlo.
  File? fondo;

  @override
  void dispose() {
    artistaCtrl.dispose();
    albumCtrl.dispose();
    yearCtrl.dispose();
    super.dispose();
  }

  void snack(String t) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(t)));
  }

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
      // Agregar solo si no existe y si escribió artista+album (año opcional)
      mostrarAgregar = res.isEmpty && artista.isNotEmpty && album.isNotEmpty;
    });

    snack(res.isEmpty ? 'No lo tienes' : 'Ya lo tienes');
  }

  Future<void> agregar() async {
    final artista = artistaCtrl.text.trim();
    final album = albumCtrl.text.trim();
    final year = yearCtrl.text.trim();

    if (artista.isEmpty || album.isEmpty) {
      snack('Para agregar: Artista y Álbum son obligatorios');
      return;
    }

    try {
      await VinylDb.instance.insertVinyl(
        artista: artista,
        album: album,
        year: year.isEmpty ? null : year,
      );
      snack('Agregado');
      setState(() {
        mostrarAgregar = false;
        resultados = [];
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

  // ✅ Cuadrado pequeño: "LP" + número
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
                const Text('Resultados en tu colección:',
                    style: TextStyle(fontWeight: FontWeight.bold)),
                const SizedBox(height: 8),
                ...resultados.map((v) => Padding(
                      padding: const EdgeInsets.symmetric(vertical: 4),
                      child: Text(
                        'LP N° ${v['numero']} — ${v['artista']} — ${v['album']}',
                        style: const TextStyle(fontWeight: FontWeight.w600),
                      ),
                    )),
              ],
            ),
          ),

        const SizedBox(height: 12),

        if (mostrarAgregar) ...[
          TextField(
            controller: yearCtrl,
            keyboardType: TextInputType.number,
            decoration: InputDecoration(
              labelText: 'Año (opcional)',
              filled: true,
              fillColor: Colors.white.withOpacity(0.85),
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(14)),
            ),
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
        if (!snap.hasData) return const Center(child: CircularProgressIndicator());
        final items = snap.data!;
        if (items.isEmpty) return const Text('No tienes vinilos todavía.', style: TextStyle(color: Colors.white));

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
      // ✅ sin AppBar => más “pantalla completa”
      appBar: null,
      body: Stack(
        children: [
          Positioned.fill(child: bg),
          // Capa oscura para lectura
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

                    if (vista == Vista.inicio) ...[
                      botonesInicio(),
                    ],

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
