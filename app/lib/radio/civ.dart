import 'dart:typed_data';

/// Endereços CI-V: IC-705 = 0xA4, controlador (PC/app) = 0xE0.
const int civRadioAddress = 0xA4;
const int civControllerAddress = 0xE0;

/// Estado do rádio extraído das respostas CI-V.
class RadioState {
  int? freqHz;
  int? mode; // 0 LSB, 1 USB, 2 AM, 3 CW, 4 RTTY, 5 FM...
  bool? dataMode;
  bool ptt = false;
  int sMeter = 0; // 0..255 (120 = S9)
  int powerMeter = 0; // 0..255 (potência de saída durante a TX)
  int swrMeter = 0; // 0..255
  int? alc;

  RadioState copy() => RadioState()
    ..freqHz = freqHz
    ..mode = mode
    ..dataMode = dataMode
    ..ptt = ptt
    ..sMeter = sMeter
    ..powerMeter = powerMeter
    ..swrMeter = swrMeter
    ..alc = alc;
}

class CivFrame {
  CivFrame(this.to, this.from, this.payload);
  final int to;
  final int from;

  /// Bytes após o endereço de origem e antes do 0xFD (comando + dados).
  final Uint8List payload;
}

/// Codificação/decodificação de quadros CI-V (formato Icom).
class Civ {
  const Civ._();

  static Uint8List frame(List<int> payload, {int to = civRadioAddress}) =>
      Uint8List.fromList([0xFE, 0xFE, to, civControllerAddress, ...payload, 0xFD]);

  /// Frequência em Hz -> 5 bytes BCD (menos significativo primeiro).
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

  /// 2 bytes BCD (ex.: 0x01 0x20 = 120).
  static int decodeBcd2(List<int> b) => ((b[0] >> 4) * 1000) + ((b[0] & 0xF) * 100) + ((b[1] >> 4) * 10) + (b[1] & 0xF);

  static List<int> encodeBcd2(int v) {
    v = v.clamp(0, 9999);
    return [((v ~/ 1000) << 4) | ((v ~/ 100) % 10), (((v ~/ 10) % 10) << 4) | (v % 10)];
  }

  // ---- Comandos
  static Uint8List readFreq() => frame([0x03]);
  static Uint8List readMode() => frame([0x04]);
  static Uint8List readDataMode() => frame([0x1A, 0x06]);
  static Uint8List readSMeter() => frame([0x15, 0x02]);
  static Uint8List readPowerMeter() => frame([0x15, 0x11]);
  static Uint8List readSwr() => frame([0x15, 0x12]);
  static Uint8List readAlc() => frame([0x15, 0x13]);
  static Uint8List readPtt() => frame([0x1C, 0x00]);
  static Uint8List setFreq(int hz) => frame([0x05, ...encodeFreq(hz)]);
  static Uint8List setMode(int mode, {int filter = 1}) => frame([0x06, mode, filter]);
  static Uint8List setDataMode(bool on, {int filter = 1}) => frame([0x1A, 0x06, on ? 1 : 0, filter]);
  static Uint8List setPtt(bool on) => frame([0x1C, 0x00, on ? 1 : 0]);
  static Uint8List setTune(bool on) => frame([0x1C, 0x01, on ? 2 : 0]);

  /// Extrai quadros completos (FE FE ... FD) de [buf] (que pode ter fragmentos).
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

  /// Aplica a resposta/notificação [f] ao [state]. Retorna true se algo mudou.
  static bool apply(RadioState state, CivFrame f) {
    final p = f.payload;
    if (p.isEmpty || f.from != civRadioAddress) return false;
    switch (p[0]) {
      case 0x00: // notificação de frequência (transceive)
      case 0x03:
        if (p.length >= 6) {
          state.freqHz = decodeFreq(p.sublist(1, 6));
          return true;
        }
        break;
      case 0x01: // notificação de modo
      case 0x04:
        if (p.length >= 2) {
          state.mode = p[1];
          return true;
        }
        break;
      case 0x1A:
        if (p.length >= 4 && p[1] == 0x06) {
          state.dataMode = p[2] != 0;
          return true;
        }
        break;
      case 0x1C:
        if (p.length >= 3 && p[1] == 0x00) {
          state.ptt = p[2] != 0;
          return true;
        }
        break;
      case 0x15:
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
String sMeterLabel(int raw) {
  // 0..120 => S0..S9 (13,3 por ponto); 120..241 => S9..S9+60 dB (aprox. 2 por dB)
  if (raw <= 120) {
    final s = (raw / 120 * 9).round();
    return 'S$s';
  }
  final over = ((raw - 120) / 121 * 60).round();
  return over == 0 ? 'S9' : 'S9+$over';
}
