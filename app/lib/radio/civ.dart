/// Protocolo CI-V (Icom Communications Interface V): codificação de comandos e leitura de respostas.
///
/// Formato de um quadro:  `FE FE <destino> <origem> <comando> [subcomando] [dados...] FD`
/// No IC-705 o endereço padrão do rádio é `0xA4`; o controlador (este app) usa `0xE0`.
/// Referência: manual "CI-V Reference Guide" do IC-705 (Icom).
///
/// Este arquivo é puro (sem I/O) e totalmente coberto por testes em `test/core_test.dart`.
library;

import 'dart:typed_data';

/// Endereço CI-V do IC-705.
const int civRadioAddress = 0xA4;

/// Endereço CI-V do controlador (este app).
const int civControllerAddress = 0xE0;

/// Espelho do estado do rádio, atualizado pelas respostas/notificações CI-V.
///
/// Campos `null` significam "ainda não lido". A sincronização bidirecional app<->rádio
/// (`engine/radio_sync.dart`) compara este estado com o do app.
class RadioState {
  /// Frequência do VFO ativo em Hz.
  int? freqHz;

  /// Modo de operação: 0 LSB, 1 USB, 2 AM, 3 CW, 4 RTTY, 5 FM, 7 CW-R, 8 RTTY-R.
  int? mode;

  /// Largura de filtro selecionada (1 = FIL1, 2 = FIL2, 3 = FIL3).
  int? filter;

  /// `true` se o modo de dados (DATA, ex.: USB-D) está ativo.
  bool? dataMode;

  /// Potência de saída configurada, escala 0..255 (≈ 0..100 % da potência máxima).
  int? rfPower;

  /// Pré-amplificador: 0 desligado, 1 P.AMP1, 2 P.AMP2.
  int? preamp;

  /// Atenuador em dB (0 desligado, 20 ligado).
  int? att;

  /// `true` enquanto o rádio transmite.
  bool ptt = false;

  /// S-meter bruto, 0..241 (120 = S9).
  int sMeter = 0;

  /// Medidor de potência de saída durante a TX, 0..255.
  int powerMeter = 0;

  /// Medidor de ROE (SWR) durante a TX, 0..255.
  int swrMeter = 0;

  /// Medidor de ALC durante a TX, 0..255.
  int? alc;

  /// Cópia independente do estado.
  RadioState copy() => RadioState()
    ..freqHz = freqHz
    ..mode = mode
    ..filter = filter
    ..dataMode = dataMode
    ..rfPower = rfPower
    ..preamp = preamp
    ..att = att
    ..ptt = ptt
    ..sMeter = sMeter
    ..powerMeter = powerMeter
    ..swrMeter = swrMeter
    ..alc = alc;

  /// `true` quando o rádio está em USB com DATA ligado (USB-D), o ajuste correto para FT8/FT4.
  bool get isUsbData => mode == 1 && dataMode == true;
}

/// Quadro CI-V já separado dos delimitadores.
class CivFrame {
  CivFrame(this.to, this.from, this.payload);

  /// Endereço de destino.
  final int to;

  /// Endereço de origem.
  final int from;

  /// Bytes entre o endereço de origem e o `0xFD` final (comando + subcomando + dados).
  final Uint8List payload;
}

/// Codificação/decodificação de quadros CI-V (formato Icom).
class Civ {
  const Civ._();

  /// Monta um quadro completo a partir de [payload] (comando + dados).
  static Uint8List frame(List<int> payload, {int to = civRadioAddress}) =>
      Uint8List.fromList([0xFE, 0xFE, to, civControllerAddress, ...payload, 0xFD]);

  /// Frequência em Hz -> 5 bytes BCD, byte menos significativo primeiro (ex.: 14.074.000 Hz).
  static List<int> encodeFreq(int hz) {
    final out = <int>[];
    var f = hz;
    for (var i = 0; i < 5; i++) {
      final lo = f % 10;
      f ~/= 10;
      final hi = f % 10;
      f ~/= 10;
      out.add((hi << 4) | lo);
    }
    return out;
  }

  /// Inverso de [encodeFreq].
  static int decodeFreq(List<int> b) {
    var f = 0;
    var mul = 1;
    for (final v in b.take(5)) {
      f += (v & 0x0F) * mul;
      mul *= 10;
      f += ((v >> 4) & 0x0F) * mul;
      mul *= 10;
    }
    return f;
  }

  /// 2 bytes BCD (4 dígitos) -> inteiro (ex.: `01 20` = 120). Usado em medidores e níveis.
  static int decodeBcd2(List<int> b) => ((b[0] >> 4) * 1000) + ((b[0] & 0xF) * 100) + ((b[1] >> 4) * 10) + (b[1] & 0xF);

  /// Inteiro 0..9999 -> 2 bytes BCD.
  static List<int> encodeBcd2(int v) {
    v = v.clamp(0, 9999);
    return [((v ~/ 1000) << 4) | ((v ~/ 100) % 10), (((v ~/ 10) % 10) << 4) | (v % 10)];
  }

  // ------------------------------------------------------------------ leituras
  static Uint8List readFreq() => frame([0x03]);
  static Uint8List readMode() => frame([0x04]);
  static Uint8List readDataMode() => frame([0x1A, 0x06]);
  static Uint8List readSMeter() => frame([0x15, 0x02]);
  static Uint8List readPowerMeter() => frame([0x15, 0x11]);
  static Uint8List readSwr() => frame([0x15, 0x12]);
  static Uint8List readAlc() => frame([0x15, 0x13]);
  static Uint8List readPtt() => frame([0x1C, 0x00]);
  static Uint8List readRfPower() => frame([0x14, 0x0A]);
  static Uint8List readPreamp() => frame([0x16, 0x02]);
  static Uint8List readAtt() => frame([0x11]);

  // ------------------------------------------------------------------ escritas
  static Uint8List setFreq(int hz) => frame([0x05, ...encodeFreq(hz)]);
  static Uint8List setMode(int mode, {int filter = 1}) => frame([0x06, mode, filter]);
  static Uint8List setDataMode(bool on, {int filter = 1}) => frame([0x1A, 0x06, on ? 1 : 0, filter]);
  static Uint8List setPtt(bool on) => frame([0x1C, 0x00, on ? 1 : 0]);
  static Uint8List setTune(bool on) => frame([0x1C, 0x01, on ? 2 : 0]);
  static Uint8List setRfPower(int raw) => frame([0x14, 0x0A, ...encodeBcd2(raw)]);
  static Uint8List setPreamp(int v) => frame([0x16, 0x02, v]);
  static Uint8List setAtt(int db) => frame([0x11, db == 0 ? 0x00 : 0x20]);

  /// Extrai quadros completos (FE FE ... FD) de [buf] (que pode conter fragmentos).
  static List<CivFrame> parse(List<int> buf) {
    final frames = <CivFrame>[];
    var i = 0;
    while (i + 5 < buf.length) {
      if (buf[i] == 0xFE && buf[i + 1] == 0xFE) {
        var j = i + 4;
        while (j < buf.length && buf[j] != 0xFD) {
          j++;
        }
        if (j >= buf.length) break;
        frames.add(CivFrame(buf[i + 2], buf[i + 3], Uint8List.fromList(buf.sublist(i + 4, j))));
        i = j + 1;
      } else {
        i++;
      }
    }
    return frames;
  }

  /// Aplica a resposta/notificação [f] ao [state]. Retorna `true` se algum campo mudou/foi lido.
  static bool apply(RadioState state, CivFrame f) {
    final p = f.payload;
    if (p.isEmpty || f.from != civRadioAddress) return false;
    switch (p[0]) {
      case 0x00: // notificação de frequência (CI-V transceive)
      case 0x03:
        if (p.length >= 6) {
          state.freqHz = decodeFreq(p.sublist(1, 6));
          return true;
        }
        break;
      case 0x01: // notificação de modo (transceive)
      case 0x04:
        if (p.length >= 2) {
          state.mode = p[1];
          if (p.length >= 3) state.filter = p[2];
          return true;
        }
        break;
      case 0x1A:
        if (p.length >= 4 && p[1] == 0x06) {
          state.dataMode = p[2] != 0;
          if (state.dataMode == true) state.filter = p[3];
          return true;
        }
        break;
      case 0x1C:
        if (p.length >= 3 && p[1] == 0x00) {
          state.ptt = p[2] != 0;
          return true;
        }
        break;
      case 0x14: // níveis: 0A = potência de RF
        if (p.length >= 4 && p[1] == 0x0A) {
          state.rfPower = decodeBcd2(p.sublist(2, 4)).clamp(0, 255);
          return true;
        }
        break;
      case 0x16: // funções: 02 = pré-amplificador
        if (p.length >= 3 && p[1] == 0x02) {
          state.preamp = p[2];
          return true;
        }
        break;
      case 0x11: // atenuador
        if (p.length >= 2) {
          state.att = p[1] == 0 ? 0 : 20;
          return true;
        }
        break;
      case 0x15: // medidores
        if (p.length >= 4) {
          final v = decodeBcd2(p.sublist(2, 4));
          switch (p[1]) {
            case 0x02:
              state.sMeter = v;
              return true;
            case 0x11:
              state.powerMeter = v;
              return true;
            case 0x12:
              state.swrMeter = v;
              return true;
            case 0x13:
              state.alc = v;
              return true;
          }
        }
        break;
    }
    return false;
  }
}

/// Converte o valor bruto do S-meter (0..241) numa legenda "S9+10" etc.
///
/// 0..120 corresponde a S0..S9; 120..241 a S9..S9+60 dB (aproximadamente 2 unidades por dB).
String sMeterLabel(int raw) {
  if (raw <= 120) {
    final s = (raw / 120 * 9).round();
    return 'S$s';
  }
  final over = ((raw - 120) / 121 * 60).round();
  return over == 0 ? 'S9' : 'S9+$over';
}

/// Nome do modo CI-V (0 = LSB, 1 = USB...), com sufixo "-D" quando DATA está ligado.
String civModeName(int? mode, bool? data) {
  const names = {0: 'LSB', 1: 'USB', 2: 'AM', 3: 'CW', 4: 'RTTY', 5: 'FM', 7: 'CW-R', 8: 'RTTY-R'};
  if (mode == null) return '—';
  final m = names[mode] ?? '?';
  return data == true ? '$m-D' : m;
}
