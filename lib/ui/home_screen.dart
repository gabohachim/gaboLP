import 'dart:io';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
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

  Future<void> elegirFondo() async {
    final picker = ImagePicker();
    final img = await picker.pickImage(source: ImageSource.gallery);
    if (img == null) return;

    if (!mounted) return;

    // Previsualizar y confirmar
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('¿Usar esta foto de fondo?'),
        content: ClipRRect(
          borderRadius: BorderRadius.circular(10),
          child: Image.file(File(img.path), fit: BoxFit.cover),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancelar'),
          ),
          ElevatedButton(
            onPressed: () {
              setState(() => fondo = File(img.path));
              Navigator.pop(context);
            },
            child: const Text('Usar'),
          ),
        ],
      ),
    );
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
      mostrarAgregar = res.isEmpty && artista.isNotEmpty && album.isNotEmpty;
    });

    if (res.isEmpty) {
      snack('No lo tienes');
    } else {
      snack('Ya lo tienes');
    }
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
            color: Colors.black54,
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
        return Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: Colors.black.withOpacity(0.65),
            borderRadius: BorderRadius.circular(14),
          ),
          child: Text(
            'LP en la lista: $total',
            style: const TextStyle(
              color: Colors.white,
              fontSize: 18,
              fontWeight: FontWeight.w800,
            ),
          ),
        );
      },
    );
  }

  Widget botonesInicio() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        ElevatedButton(
          onPressed: () => setState(() => vista = Vista.buscar),
          child: const Text('Buscar vinilo'),
        ),
        ElevatedButton(
          onPressed: () => setState(() => vista = Vista.lista),
          child: const Text('Mostrar lista de vinilos'),
        ),
        ElevatedButton(
          onPressed: () => setState(() => vista = Vista.borrar),
          child: const Text('Borrar vinilos'),
        ),
      ],
    );
  }

  Widget vistaBuscar() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        TextField(
          controller: artistaCtrl,
          decoration: const InputDecoration(
            labelText: 'Artista',
            filled: true,
          ),
        ),
        const SizedBox(height: 10),
        TextField(
          controller: albumCtrl,
          decoration: const InputDecoration(
            labelText: 'Álbum (opcional para buscar)',
            filled: true,
          ),
        ),
        const SizedBox(height: 10),
        ElevatedButton(
          onPressed: buscar,
          child: const Text('Buscar'),
        ),
        const SizedBox(height: 12),

        // Lista debajo del buscador (cuando escribes artista)
        if (resultados.isNotEmpty)
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.78),
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

        // Si NO lo tienes (y escribiste artista+album), aparece agregar
        if (mostrarAgregar) ...[
          TextField(
            controller: yearCtrl,
            decoration: const InputDecoration(
              labelText: 'Año (opcional)',
              filled: true,
            ),
            keyboardType: TextInputType.number,
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
          child: const Text('Volver'),
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
          return const Text('No tienes vinilos todavía.');
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
              child: ListTile(
                title: Text(
                  'LP N° ${v['numero']} — ${v['artista']} — ${v['album']}$yearTxt',
                ),
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
      appBar: AppBar(title: const Text('Colección vinilos')),
      body: Stack(
        children: [
          Positioned.fill(child: bg),
          Positioned.fill(child: Container(color: Colors.white.withOpacity(0.10))),
          Padding(
            padding: const EdgeInsets.all(16),
            child: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  contadorLp(),
                  const SizedBox(height: 14),

                  if (vista == Vista.inicio) ...[
                    botonesInicio(),
                    const SizedBox(height: 14),
                    ElevatedButton(
                      onPressed: elegirFondo,
                      child: const Text('Actualizar fondo (elegir foto)'),
                    ),
                  ],

                  if (vista == Vista.buscar) vistaBuscar(),

                  if (vista == Vista.lista) ...[
                    listaCompleta(conBorrar: false),
                    const SizedBox(height: 10),
                    TextButton(
                      onPressed: () => setState(() => vista = Vista.inicio),
                      child: const Text('Volver'),
                    ),
                  ],

                  if (vista == Vista.borrar) ...[
                    listaCompleta(conBorrar: true),
                    const SizedBox(height: 10),
                    TextButton(
                      onPressed: () => setState(() => vista = Vista.inicio),
                      child: const Text('Volver'),
                    ),
                  ],
                ],
              ),
            ),
          ),
          gabolpMarca(),
        ],
      ),
    );
  }
}
