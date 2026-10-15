/// Catálogo de modos digitais do JTMobile.
///
/// Cada modo é descrito por um [ModeSpec] com seus parâmetros de tempo (período T/R, início da
/// transmissão, janela de decodificação), largura de banda e frequências de dial por banda.
/// Os modos *implementados* têm um codec nativo associado ([ModeSpec.ftx]); os demais aparecem
/// na interface como "em desenvolvimento" e servem de guia para quem for implementá-los
/// (veja `docs/MODOS.md` — "Como adicionar um novo modo").
///
/// Para adicionar um modo:
///  1. acrescente um [ModeSpec] em [kModes] (com `implemented: true` quando o codec existir);
///  2. implemente o codec em C/C++ (ou Dart) atrás da interface `FtxCodec`/equivalente;
///  3. registre as frequências de dial em [kBands];
///  4. cubra com testes (gravações de referência do WSJT-X/JTDX) e atualize `docs/MODOS.md`.
library;

import 'ftx_native.dart';

/// Família do codec responsável pelo modo.
enum ModeFamily {
  /// FT8 e FT4 (LDPC 174/91 + CRC14) — implementado via ft8_lib.
  ftx,

  /// JT65 (Reed-Solomon 63,12; 60 s) — a implementar (port do decodificador Koetter-Vardy).
  jt65,

  /// JT9 / JT4 (convolucional K=32 + 60 s) — a implementar.
  jt9,

  /// FST4/FST4W — a implementar.
  fst4,

  /// WSPR (baliza de 2 min, só RX inicialmente) — a implementar.
  wspr,
}

/// Parâmetros de um modo digital.
class ModeSpec {
  const ModeSpec({
    required this.id,
    required this.label,
    required this.description,
    required this.family,
    required this.slotSeconds,
    required this.txStartOffset,
    required this.decodeAtSeconds,
    required this.toneSpacingHz,
    required this.bandwidthHz,
    this.ftx,
    this.implemented = false,
    this.structuredQso = true,
  });

  /// Identificador estável (persistido nas configurações e no ADIF): "FT8", "FT4", "JT65"...
  final String id;

  /// Nome exibido.
  final String label;

  /// Texto curto para a lista de seleção de modo.
  final String description;

  final ModeFamily family;

  /// Duração do período de transmissão/recepção (T/R), em segundos. FT8=15, FT4=7,5, JT65/JT9=60.
  final double slotSeconds;

  /// Atraso entre o início do período e o início do sinal (s). FT8/FT4: 0,5; JT65/JT9: 1,0.
  final double txStartOffset;

  /// Instante (s desde o início do período) em que a decodificação é disparada.
  final double decodeAtSeconds;

  /// Espaçamento entre tons (Hz).
  final double toneSpacingHz;

  /// Largura de banda ocupada (Hz) — usada para desenhar os marcadores Rx/Tx na waterfall.
  final double bandwidthHz;

  /// Codec nativo (ft8_lib) quando o modo pertence à família [ModeFamily.ftx].
  final FtxProtocol? ftx;

  /// `true` quando decodificação e transmissão estão disponíveis.
  final bool implemented;

  /// `true` quando o modo usa o roteiro de QSO estruturado (Tx1..Tx6 / auto-sequência).
  final bool structuredQso;

  /// Código do modo em ADIF (campo MODE).
  String get adifMode => id == 'FT4' ? 'MFSK' : id;

  /// Sub-modo em ADIF (campo SUBMODE), quando aplicável.
  String? get adifSubmode => id == 'FT4' ? 'FT4' : null;
}

/// Todos os modos conhecidos. A ordem é a exibida na interface.
const List<ModeSpec> kModes = [
  ModeSpec(
    id: 'FT8',
    label: 'FT8',
    description: 'Padrão atual do HF: 15 s, 50 Hz de largura',
    family: ModeFamily.ftx,
    slotSeconds: 15.0,
    txStartOffset: 0.5,
    decodeAtSeconds: 14.0,
    toneSpacingHz: 6.25,
    bandwidthHz: 50,
    ftx: FtxProtocol.ft8,
    implemented: true,
  ),
  ModeSpec(
    id: 'FT4',
    label: 'FT4',
    description: 'Rápido (concursos): 7,5 s, 83 Hz de largura',
    family: ModeFamily.ftx,
    slotSeconds: 7.5,
    txStartOffset: 0.5,
    decodeAtSeconds: 6.4,
    toneSpacingHz: 20.8333,
    bandwidthHz: 83,
    ftx: FtxProtocol.ft4,
    implemented: true,
  ),
  ModeSpec(
    id: 'JT65',
    label: 'JT65',
    description: 'Sinais muito fracos / EME: 60 s, 178 Hz  (em desenvolvimento)',
    family: ModeFamily.jt65,
    slotSeconds: 60.0,
    txStartOffset: 1.0,
    decodeAtSeconds: 52.0,
    toneSpacingHz: 2.6917,
    bandwidthHz: 178,
  ),
  ModeSpec(
    id: 'JT9',
    label: 'JT9',
    description: 'Banda estreita (15,6 Hz): 60 s  (em desenvolvimento)',
    family: ModeFamily.jt9,
    slotSeconds: 60.0,
    txStartOffset: 1.0,
    decodeAtSeconds: 52.0,
    toneSpacingHz: 1.736,
    bandwidthHz: 16,
  ),
  ModeSpec(
    id: 'FST4',
    label: 'FST4',
    description: 'Baixas frequências / sinais fracos: 15–1800 s  (em desenvolvimento)',
    family: ModeFamily.fst4,
    slotSeconds: 60.0,
    txStartOffset: 1.0,
    decodeAtSeconds: 52.0,
    toneSpacingHz: 3.125,
    bandwidthHz: 25,
  ),
  ModeSpec(
    id: 'WSPR',
    label: 'WSPR',
    description: 'Balizas de propagação: 2 min, só recepção  (em desenvolvimento)',
    family: ModeFamily.wspr,
    slotSeconds: 120.0,
    txStartOffset: 1.0,
    decodeAtSeconds: 112.0,
    toneSpacingHz: 1.4648,
    bandwidthHz: 6,
    structuredQso: false,
  ),
];

/// Busca um modo pelo [id]; devolve FT8 se desconhecido.
ModeSpec modeById(String id) => kModes.firstWhere((m) => m.id == id, orElse: () => kModes.first);

/// Banda de operação com os limites (Região 2 da IARU) e as frequências de dial por modo.
class Band {
  const Band(this.name, this.lowerHz, this.upperHz, this.dial);

  /// Nome ("20m").
  final String name;

  /// Limites da banda em Hz.
  final int lowerHz, upperHz;

  /// Frequência de dial (Hz) por id de modo. Modos ausentes não têm frequência padrão nesta banda.
  /// ⚠ Confira as frequências em https://www.arrl.org/ e os planos de banda locais antes de operar.
  final Map<String, int> dial;

  /// Frequência de dial padrão do [modeId] nesta banda, ou `null`.
  int? dialFor(String modeId) => dial[modeId];

  /// `true` se [hz] está dentro da banda.
  bool contains(int hz) => hz >= lowerHz && hz <= upperHz;
}

/// Bandas conhecidas (HF + 6 m).
const List<Band> kBands = [
  Band('160m', 1800000, 2000000, {'FT8': 1840000, 'FT4': 1840000}),
  Band('80m', 3500000, 4000000, {'FT8': 3573000, 'FT4': 3575000, 'JT65': 3576000, 'JT9': 3578000}),
  Band('60m', 5300000, 5500000, {'FT8': 5357000, 'FT4': 5357000}),
  Band('40m', 7000000, 7300000, {'FT8': 7074000, 'FT4': 7047500, 'JT65': 7076000, 'JT9': 7078000}),
  Band('30m', 10100000, 10150000, {'FT8': 10136000, 'FT4': 10140000, 'JT65': 10138000, 'JT9': 10140000}),
  Band('20m', 14000000, 14350000, {'FT8': 14074000, 'FT4': 14080000, 'JT65': 14076000, 'JT9': 14078000}),
  Band('17m', 18068000, 18168000, {'FT8': 18100000, 'FT4': 18104000, 'JT65': 18102000, 'JT9': 18104000}),
  Band('15m', 21000000, 21450000, {'FT8': 21074000, 'FT4': 21140000, 'JT65': 21076000, 'JT9': 21078000}),
  Band('12m', 24890000, 24990000, {'FT8': 24915000, 'FT4': 24919000, 'JT65': 24917000, 'JT9': 24919000}),
  Band('10m', 28000000, 29700000, {'FT8': 28074000, 'FT4': 28180000, 'JT65': 28076000, 'JT9': 28078000}),
  Band('6m', 50000000, 54000000, {'FT8': 50313000, 'FT4': 50318000, 'JT65': 50276000}),
];

/// Índice da banda que contém [hz], ou -1.
int bandIndexOf(int hz) => kBands.indexWhere((b) => b.contains(hz));
