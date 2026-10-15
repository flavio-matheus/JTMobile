/// Tema escuro e paleta semântica da interface (verde = RX/CQ, vermelho = TX/chamada para mim,
/// âmbar = aviso). Escolhido para operação noturna e boa leitura em tela pequena.
library;

import 'package:flutter/material.dart';

/// Cores semânticas usadas em toda a interface (tema escuro, adequado para operação à noite).
class Pal {
  static const bg = Color(0xFF0B1118);
  static const panel = Color(0xFF131C26);
  static const panel2 = Color(0xFF1A2633);
  static const line = Color(0xFF263444);
  static const text = Color(0xFFE6EDF3);
  static const dim = Color(0xFF8B9BAD);
  static const accent = Color(0xFF3DA9FC);
  static const rx = Color(0xFF3DDC84); // marcador/estado RX, CQ
  static const tx = Color(0xFFFF5252); // marcador/estado TX, chamadas para mim
  static const warn = Color(0xFFFFB300);
  static const mine = Color(0xFFFF8A65);
  static const cq = Color(0xFF69F0AE);
}

ThemeData buildTheme() {
  final base = ThemeData.dark(useMaterial3: true);
  return base.copyWith(
    scaffoldBackgroundColor: Pal.bg,
    colorScheme: const ColorScheme.dark(
      primary: Pal.accent,
      secondary: Pal.rx,
      surface: Pal.panel,
      error: Pal.tx,
    ),
    cardColor: Pal.panel,
    dividerColor: Pal.line,
    appBarTheme: const AppBarTheme(backgroundColor: Pal.panel, foregroundColor: Pal.text, elevation: 0),
    textTheme: base.textTheme.apply(bodyColor: Pal.text, displayColor: Pal.text),
    chipTheme: base.chipTheme.copyWith(
      backgroundColor: Pal.panel2,
      side: const BorderSide(color: Pal.line),
      labelStyle: const TextStyle(color: Pal.text, fontSize: 12),
    ),
    sliderTheme: base.sliderTheme.copyWith(trackHeight: 3),
  );
}

const TextStyle kMono = TextStyle(fontFamily: 'monospace', fontFeatures: [FontFeature.tabularFigures()]);
