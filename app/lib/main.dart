/// Ponto de entrada do JTMobile.
///
/// Carrega as configurações, escolhe o codec nativo (ou um codec vazio fora do Android), cria o
/// [Engine] e abre a interface. Na primeira execução pede indicativo e locator.
library;

import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

import 'package:flutter/foundation.dart';
import 'core/ftx_native.dart';
import 'engine/debug_wav.dart';
import 'core/settings.dart';
import 'engine/engine.dart';
import 'ui/home_page.dart';
import 'ui/theme.dart';

/// Codec vazio usado quando a biblioteca nativa não está disponível (ex.: execução fora do Android).
class _NoCodec extends FtxCodec {
  @override
  List<RawDecode> decode(Float32List samples12k, FtxProtocol proto, {double fMin = 100, double fMax = 3100}) => [];
  @override
  Uint8List? encode(String text, FtxProtocol proto) => null;
  @override
  Float32List synth(Uint8List tones, FtxProtocol proto, double f0, int rate) => Float32List(0);
  @override
  Float32List spectrum(Float32List samples, int nfft) => Float32List(nfft ~/ 2)..fillRange(0, nfft ~/ 2, -100);
  @override
  Decimator newDecimator() => _NoDec();
}

class _NoDec implements Decimator {
  @override
  Float32List process(Int16List input) => Float32List(input.length ~/ 4);
  @override
  void dispose() {}
}

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  SystemChrome.setPreferredOrientations(DeviceOrientation.values);
  final settings = await Settings.load();
  final codec = FtxNative.tryLoad() ?? _NoCodec();
  final engine = Engine(settings: settings, codec: codec);
  try {
    await WakelockPlus.enable();
  } catch (_) {}
  runApp(FtApp(engine: engine));
  if (kDebugMode) debugDecodeWavFiles(codec);
  engine.start();
}

class FtApp extends StatelessWidget {
  const FtApp({super.key, required this.engine});
  final Engine engine;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'JTMobile',
      debugShowCheckedModeBanner: false,
      theme: buildTheme(),
      home: _Gate(engine: engine),
    );
  }
}

/// Na primeira execução pede o indicativo.
class _Gate extends StatefulWidget {
  const _Gate({required this.engine});
  final Engine engine;
  @override
  State<_Gate> createState() => _GateState();
}

class _GateState extends State<_Gate> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (widget.engine.settings.callsign.isEmpty && mounted) _askCall();
    });
  }

  Future<void> _askCall() async {
    final call = TextEditingController();
    final grid = TextEditingController();
    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        title: const Text('Bem-vindo ao JTMobile'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('Informe seu indicativo e locator. O app inicia no modo Simulador; '
                'troque para o IC-705 em Configurações.'),
            const SizedBox(height: 12),
            TextField(
              controller: call,
              textCapitalization: TextCapitalization.characters,
              decoration: const InputDecoration(labelText: 'Indicativo', border: OutlineInputBorder()),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: grid,
              textCapitalization: TextCapitalization.characters,
              decoration: const InputDecoration(labelText: 'Grid (ex.: GH64)', border: OutlineInputBorder()),
            ),
          ],
        ),
        actions: [
          FilledButton(
            onPressed: () {
              final s = widget.engine.settings;
              s.callsign = call.text.trim().toUpperCase();
              s.grid = grid.text.trim().toUpperCase();
              s.save();
              Navigator.pop(ctx);
            },
            child: const Text('Continuar'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) => HomePage(engine: widget.engine);
}
