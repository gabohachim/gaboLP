import 'dart:io';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import '../db/vinyl_db.dart';

enum ModoPantalla { nada, buscar, lista, borrar }

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final artistaCtrl = TextEditingController();
  final albumCtrl = TextEditingController();
  final yearCtrl = TextEditingController();

  ModoPantalla modo = ModoPantalla.nada;
  bool mostrarAgregar = false;
  List<Map<String, dynamic>> resultadosBusqueda = [];
  File? fondo;

  void snack(String msg) {
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(msg)));
  }

  Future<void> buscar() async {
    final res = await VinylDb.instance.search(
      artista: artistaCtrl.text,
      album: albumCtrl.text.isEmpty ? null : albumCtrl.text,
    );

    setState(() {
      resultadosBusqueda = res;
      mostrarAgregar = res.isEmpty;
    });

    snack(res.isEmpty ? 'No lo tienes' : 'Ya lo tienes');
  }

  Future<void> agregar() async {
    await VinylDb.instance.insertVinyl(
      artista: artistaCtrl.text,
      album: albumCtrl.text,
      year: yearCtrl.text,
    );
    snack('Vinilo agregado');
    setState(() {
      mostrarAgregar = false;
      resultadosBusqueda = [];

