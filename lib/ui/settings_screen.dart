import 'package:flutter/material.dart';
import '../services/drive_backup_service.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  bool auto = false;
  DateTime? last;
  bool working = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final a = await DriveBackupService.isAutoEnabled();
    final l = await DriveBackupService.getLastBackupTime();
    if (!mounted) return;
    setState(() {
      auto = a;
      last = l;
    });
  }

  String _fmt(DateTime? d) {
    if (d == null) return 'Nunca';
    final dd = d.toLocal();
    String two(int n) => n.toString().padLeft(2, '0');
    return '${two(dd.day)}/${two(dd.month)}/${dd.year} ${two(dd.hour)}:${two(dd.minute)}';
  }

  void _snack(String t) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(t)));
  }

  Future<void> _toggleAuto(bool v) async {
    setState(() => auto = v);
    await DriveBackupService.setAutoEnabled(v);
    _snack(v ? 'Automático activado ✅' : 'Automático desactivado');
  }

  Future<void> _guardarAhora() async {
    setState(() => working = true);
    try {
      await DriveBackupService.backupNowToCloud();
      await _load();
      _snack('Respaldo en la nube guardado ✅');
    } catch (e) {
      _snack('Error al respaldar: $e');
    } finally {
      if (mounted) setState(() => working = false);
    }
  }

  Future<void> _restaurar() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Restaurar desde la nube'),
        content: const Text('Esto reemplazará tu colección actual. ¿Continuar?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancelar')),
          ElevatedButton(onPressed: () => Navigator.pop(context, true), child: const Text('Sí, restaurar')),
        ],
      ),
    );

    if (ok != true) return;

    setState(() => working = true);
    try {
      await DriveBackupService.restoreFromCloud();
      await _load();
      _snack('Colección restaurada ✅');
    } catch (e) {
      _snack('Error al restaurar: $e');
    } finally {
      if (mounted) setState(() => working = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Ajustes')),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: Colors.black.withOpacity(0.06),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: Colors.black12),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('🛡️ Respaldo en la nube', style: TextStyle(fontWeight: FontWeight.w900, fontSize: 16)),
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      const Expanded(child: Text('Automático')),
                      Switch(value: auto, onChanged: working ? null : _toggleAuto),
                    ],
                  ),
                  const SizedBox(height: 6),
                  Text('Último respaldo: ${_fmt(last)}', style: const TextStyle(fontWeight: FontWeight.w700)),
                ],
              ),
            ),
            const SizedBox(height: 14),
            ElevatedButton.icon(
              onPressed: working ? null : _guardarAhora,
              icon: const Icon(Icons.cloud_upload),
              label: const Text('Guardar lista'),
            ),
            const SizedBox(height: 10),
            OutlinedButton.icon(
              onPressed: working ? null : _restaurar,
              icon: const Icon(Icons.cloud_download),
              label: const Text('Restaurar lista'),
            ),
            const SizedBox(height: 10),
            if (working) const LinearProgressIndicator(),
            const Spacer(),
            const Align(
              alignment: Alignment.bottomRight,
              child: Text('GaBoLP', style: TextStyle(fontWeight: FontWeight.w800, color: Colors.black45)),
            ),
          ],
        ),
      ),
    );
  }
}
