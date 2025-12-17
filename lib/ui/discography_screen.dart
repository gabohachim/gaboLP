import 'package:flutter/material.dart';
import '../services/discography_service.dart';

class DiscographyScreen extends StatefulWidget {
  const DiscographyScreen({super.key});

  @override
  State<DiscographyScreen> createState() => _DiscographyScreenState();
}

class _DiscographyScreenState extends State<DiscographyScreen> {
  final ctrl = TextEditingController();

  bool loading = false;
  List<ArtistHit> artistas = [];

  ArtistHit? seleccionado;
  ArtistInfo? info;
  List<AlbumItem> albums = [];

  @override
  void dispose() {
    ctrl.dispose();
    super.dispose();
  }

  void snack(String t) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(t)));
  }

  Future<void> buscarArtistas(String t) async {
    final q = t.trim();
    if (q.isEmpty) {
      setState(() => artistas = []);
      return;
    }
    setState(() => loading = true);

    final r = await DiscographyService.searchArtists(q, limit: 15);

    if (!mounted) return;
    setState(() {
      artistas = r;
      loading = false;
    });
  }

  Future<void> cargar(ArtistHit a) async {
    FocusScope.of(context).unfocus();
    setState(() {
      seleccionado = a;
      info = null;
      albums = [];
      loading = true;
      ctrl.text = a.name;
      artistas = [];
    });

    try {
      final ai = await DiscographyService.getArtistInfo(a.name);
      final disc = await DiscographyService.getDiscographyAlbums(a.id);

      if (!mounted) return;
      setState(() {
        info = ai;
        albums = disc; // ya viene ordenado por año
        loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => loading = false);
      snack('Error: $e');
    }
  }

  void _showBio() {
    final b = (info?.bioEs ?? '').trim();
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Reseña de la banda'),
        content: SingleChildScrollView(child: Text(b.isEmpty ? 'Sin reseña.' : b)),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cerrar')),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final country = (info?.country ?? '').trim();
    final genre = (info?.genre ?? '').trim();

    return Scaffold(
      appBar: AppBar(title: const Text('Discografías')),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            TextField(
              controller: ctrl,
              onChanged: buscarArtistas,
              decoration: InputDecoration(
                labelText: 'Buscar artista (escribe letras)',
                filled: true,
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(14)),
              ),
            ),
            const SizedBox(height: 10),
            if (loading) const LinearProgressIndicator(),

            // lista de artistas sugeridos
            if (artistas.isNotEmpty)
              Container(
                margin: const EdgeInsets.only(top: 8),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: Colors.black12),
                ),
                child: ListView.separated(
                  shrinkWrap: true,
                  itemCount: artistas.length,
                  separatorBuilder: (_, __) => const Divider(height: 1),
                  itemBuilder: (_, i) {
                    final a = artistas[i];
                    return ListTile(
                      title: Text(a.name),
                      subtitle: Text((a.country ?? '').trim().isEmpty ? '' : 'País: ${a.country}'),
                      onTap: () => cargar(a),
                    );
                  },
                ),
              ),

            const SizedBox(height: 10),

            // info artista
            if (info != null)
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.black.withOpacity(0.06),
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: Colors.black12),
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        '${info!.name}'
                        '${country.isEmpty ? '' : ' • $country'}'
                        '${genre.isEmpty ? '' : ' • $genre'}',
                        style: const TextStyle(fontWeight: FontWeight.w900),
                      ),
                    ),
                    OutlinedButton(
                      onPressed: _showBio,
                      child: const Text('Reseña'),
                    ),
                  ],
                ),
              ),

            const SizedBox(height: 10),

            // albums
            Expanded(
              child: albums.isEmpty
                  ? const Center(child: Text('Busca un artista para ver su discografía.'))
                  : ListView.separated(
                      itemCount: albums.length,
                      separatorBuilder: (_, __) => const Divider(height: 1),
                      itemBuilder: (_, i) {
                        final al = albums[i];
                        final y = (al.year ?? '').trim();
                        return ListTile(
                          title: Text(al.title),
                          subtitle: Text(y.isEmpty ? '' : 'Año: $y'),
                          // luego aquí puedes hacer click para ver tracklist o agregar LP
                          onTap: () {
                            snack('Seleccionado: ${al.title}');
                          },
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }
}
