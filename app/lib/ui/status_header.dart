import 'package:flutter/material.dart';

import '../core/ftx_native.dart';
import '../core/models.dart';
import '../engine/engine.dart';
import '../radio/civ.dart';
import '../radio/radio_link.dart';
import 'theme.dart';

String _fmtFreq(int hz) {
  final s = hz.toString().padLeft(8, '0');
  final mhz = s.substring(0, s.length - 6);
  final khz = s.substring(s.length - 6, s.length - 3);
  final h = s.substring(s.length - 3);
  return '${int.parse(mhz)}.$khz.$h';
}

class StatusHeader extends StatelessWidget {
  const StatusHeader({super.key, required this.engine, required this.onSettings});
  final Engine engine;
  final VoidCallback onSettings;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: engine,
      builder: (context, _) {
        final r = engine.radio;
        final st = r?.state;
        final freq = st?.freqHz ?? engine.dialFrequency;
        final tx = engine.transmitting || engine.tuning;
        return Container(
          color: Pal.panel,
          padding: const EdgeInsets.fromLTRB(10, 6, 6, 4),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                children: [
                  _ConnPill(engine: engine),
                  const Spacer(),
                  _ClockText(engine: engine),
                  IconButton(
                    visualDensity: VisualDensity.compact,
                    onPressed: onSettings,
                    icon: const Icon(Icons.settings, size: 22),
                    tooltip: 'Configurações',
                  ),
                ],
              ),
              Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    _fmtFreq(freq),
                    style: kMono.copyWith(
                      fontSize: 30,
                      fontWeight: FontWeight.w600,
                      color: tx ? Pal.tx : Pal.text,
                      letterSpacing: 1,
                    ),
                  ),
                  const SizedBox(width: 6),
                  Padding(
                    padding: const EdgeInsets.only(bottom: 5),
                    child: Text(_modeText(st), style: const TextStyle(color: Pal.dim, fontSize: 12)),
                  ),
                  const Spacer(),
                  SegmentedButton<FtxProtocol>(
                    showSelectedIcon: false,
                    style: const ButtonStyle(visualDensity: VisualDensity.compact),
                    segments: const [
                      ButtonSegment(value: FtxProtocol.ft8, label: Text('FT8')),
                      ButtonSegment(value: FtxProtocol.ft4, label: Text('FT4')),
                    ],
                    selected: {engine.protocol},
                    onSelectionChanged: (s) => engine.setProtocol(s.first),
                  ),
                ],
              ),
              const SizedBox(height: 4),
              _SlotBar(engine: engine),
              const SizedBox(height: 4),
              _Meters(engine: engine),
              const SizedBox(height: 2),
              SizedBox(
                height: 34,
                child: ListView.separated(
                  scrollDirection: Axis.horizontal,
                  itemCount: kBands.length,
                  separatorBuilder: (_, __) => const SizedBox(width: 6),
                  itemBuilder: (context, i) => ChoiceChip(
                    label: Text(kBands[i].name),
                    selected: engine.settings.bandIndex == i,
                    visualDensity: VisualDensity.compact,
                    onSelected: (_) => engine.setBand(i),
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  String _modeText(RadioState? st) {
    if (st == null || st.mode == null) return 'USB-D';
    const names = {0: 'LSB', 1: 'USB', 2: 'AM', 3: 'CW', 4: 'RTTY', 5: 'FM', 7: 'CW-R', 8: 'RTTY-R'};
    final m = names[st.mode] ?? '?';
    return st.dataMode == true ? '$m-D' : m;
  }
}

class _ConnPill extends StatelessWidget {
  const _ConnPill({required this.engine});
  final Engine engine;

  @override
  Widget build(BuildContext context) {
    final r = engine.radio;
    final status = r?.status ?? LinkStatus.disconnected;
    final color = switch (status) {
      LinkStatus.connected => Pal.rx,
      LinkStatus.connecting => Pal.warn,
      LinkStatus.error => Pal.tx,
      LinkStatus.disconnected => Pal.dim,
    };
    final sim = engine.settings.radioKind.name == 'simulator';
    final ping = r?.pingMs;
    final lost = r?.lostPackets ?? 0;
    return InkWell(
      borderRadius: BorderRadius.circular(16),
      onTap: () {
        if (status == LinkStatus.connected || status == LinkStatus.connecting) {
          engine.disconnectRadio();
        } else {
          engine.connectRadio();
        }
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.15),
          border: Border.all(color: color.withValues(alpha: 0.6)),
          borderRadius: BorderRadius.circular(16),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(sim ? Icons.science : Icons.wifi, size: 15, color: color),
            const SizedBox(width: 5),
            ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 190),
              child: Text(
                status == LinkStatus.connected
                    ? '${sim ? 'Simulador' : 'IC-705 Wi-Fi'}${ping != null ? ' · ${ping}ms' : ''}${lost > 0 ? ' · perdas $lost' : ''}'
                    : (r?.statusText ?? 'Desconectado – toque para conectar'),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(color: color, fontSize: 12, fontWeight: FontWeight.w600),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ClockText extends StatelessWidget {
  const _ClockText({required this.engine});
  final Engine engine;

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<int>(
      valueListenable: engine.clockTick,
      builder: (context, v, _) {
        if (v % 5 != 0) {
          // atualiza apenas a cada 100 ms
        }
        final t = engine.now();
        String two(int n) => n.toString().padLeft(2, '0');
        final off = engine.settings.clockOffsetMs;
        return Row(
          children: [
            Text('${two(t.hour)}:${two(t.minute)}:${two(t.second)}',
                style: kMono.copyWith(fontSize: 18, fontWeight: FontWeight.w600)),
            const SizedBox(width: 4),
            const Text('UTC', style: TextStyle(color: Pal.dim, fontSize: 11)),
            if (off != 0)
              Padding(
                padding: const EdgeInsets.only(left: 4),
                child: Text('${off > 0 ? '+' : ''}${off}ms', style: const TextStyle(color: Pal.warn, fontSize: 10)),
              ),
          ],
        );
      },
    );
  }
}

class _SlotBar extends StatelessWidget {
  const _SlotBar({required this.engine});
  final Engine engine;

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<int>(
      valueListenable: engine.clockTick,
      builder: (context, _, __) {
        final t = engine.now();
        final slot = engine.protocol.slotSeconds;
        final sec = engine.secondsIntoSlot(t);
        final parity = engine.slotIndexAt(t) % 2;
        final tx = engine.transmitting || engine.tuning;
        final color = tx ? Pal.tx : Pal.rx;
        final label = tx
            ? (engine.tuning ? 'TUNE ${engine.settings.txFreq} Hz' : 'TX ${engine.settings.txFreq} Hz  ${engine.txMessageShown ?? ''}')
            : (engine.txEnabled
                ? 'RX · próxima TX no ${engine.txParity == 0 ? '1º' : '2º'} slot'
                : (engine.decoding ? 'Decodificando…' : 'Recebendo'));
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                  decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(4)),
                  child: Text(tx ? 'TX' : 'RX',
                      style: const TextStyle(color: Colors.black, fontWeight: FontWeight.w800, fontSize: 11)),
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: kMono.copyWith(fontSize: 12, color: tx ? Pal.tx : Pal.dim)),
                ),
                Text('slot ${parity == 0 ? '1º' : '2º'} · ${sec.toStringAsFixed(1)}/${slot.toStringAsFixed(slot == slot.roundToDouble() ? 0 : 1)}s',
                    style: kMono.copyWith(fontSize: 11, color: Pal.dim)),
              ],
            ),
            const SizedBox(height: 3),
            ClipRRect(
              borderRadius: BorderRadius.circular(3),
              child: SizedBox(
                height: 6,
                child: CustomPaint(
                  painter: _SlotPainter(progress: (sec / slot).clamp(0.0, 1.0), color: color, decodeAt: 1 - (engine.protocol == FtxProtocol.ft8 ? 1.0 : 1.1) / slot),
                  size: Size.infinite,
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}

class _SlotPainter extends CustomPainter {
  _SlotPainter({required this.progress, required this.color, required this.decodeAt});
  final double progress;
  final Color color;
  final double decodeAt;
  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawRect(Offset.zero & size, Paint()..color = Pal.panel2);
    canvas.drawRect(Rect.fromLTWH(0, 0, size.width * progress, size.height), Paint()..color = color);
    canvas.drawRect(Rect.fromLTWH(size.width * decodeAt - 1, 0, 2, size.height), Paint()..color = Colors.white54);
  }

  @override
  bool shouldRepaint(covariant _SlotPainter old) => old.progress != progress || old.color != color;
}

class _Meters extends StatelessWidget {
  const _Meters({required this.engine});
  final Engine engine;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: engine,
      builder: (context, _) {
        final st = engine.radio?.state;
        final tx = engine.transmitting || engine.tuning;
        return ValueListenableBuilder<int>(
          valueListenable: engine.wfTick,
          builder: (context, _, __) {
            // nível de áudio ideal: ~ -30 .. -15 dBFS (ruído de fundo)
            final lvl = ((engine.rxLevelDb + 70) / 70).clamp(0.0, 1.0);
            final lvlColor = engine.rxLevelDb > -12 ? Pal.tx : (engine.rxLevelDb < -50 ? Pal.warn : Pal.rx);
            return Row(
              children: [
                _Bar(
                  label: tx ? 'PO' : 'S',
                  value: tx ? (st?.powerMeter ?? 0) / 255.0 : (st?.sMeter ?? 0) / 241.0,
                  color: tx ? Pal.tx : Pal.accent,
                  text: tx ? '${((st?.powerMeter ?? 0) / 255 * 100).round()}%' : sMeterLabel(st?.sMeter ?? 0),
                ),
                const SizedBox(width: 8),
                if (tx)
                  _Bar(
                    label: 'SWR',
                    value: (st?.swrMeter ?? 0) / 255.0,
                    color: (st?.swrMeter ?? 0) > 120 ? Pal.tx : Pal.rx,
                    text: _swr(st?.swrMeter ?? 0),
                  )
                else
                  _Bar(label: 'Áudio', value: lvl, color: lvlColor, text: '${engine.rxLevelDb.round()} dB'),
                const SizedBox(width: 8),
                Text(
                  engine.decodesLastSlot > 0 || engine.lastDecodeSeconds > 0
                      ? '${engine.decodesLastSlot} dec · ${engine.lastDecodeSeconds.toStringAsFixed(2)}s'
                      : '—',
                  style: kMono.copyWith(fontSize: 11, color: Pal.dim),
                ),
              ],
            );
          },
        );
      },
    );
  }

  String _swr(int raw) {
    // 0..48 ≈ 1.0..1.5 ; 48..80 ≈ 1.5..2.0 ; 80..120 ≈ 2.0..3.0 ; 120.. > 3
    if (raw <= 48) return (1.0 + raw / 96).toStringAsFixed(1);
    if (raw <= 80) return (1.5 + (raw - 48) / 64).toStringAsFixed(1);
    if (raw <= 120) return (2.0 + (raw - 80) / 40).toStringAsFixed(1);
    return '>3';
  }
}

class _Bar extends StatelessWidget {
  const _Bar({required this.label, required this.value, required this.color, required this.text});
  final String label;
  final double value;
  final Color color;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Row(
        children: [
          SizedBox(width: 34, child: Text(label, style: const TextStyle(fontSize: 11, color: Pal.dim))),
          Expanded(
            child: ClipRRect(
              borderRadius: BorderRadius.circular(3),
              child: LinearProgressIndicator(
                minHeight: 8,
                value: value.clamp(0.0, 1.0),
                backgroundColor: Pal.panel2,
                valueColor: AlwaysStoppedAnimation(color),
              ),
            ),
          ),
          SizedBox(width: 42, child: Text(text, textAlign: TextAlign.right, style: kMono.copyWith(fontSize: 10, color: Pal.dim))),
        ],
      ),
    );
  }
}
