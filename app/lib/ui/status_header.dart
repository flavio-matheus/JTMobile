/// Cabeçalho do app: enlace com o rádio, frequência (toque abre o painel do rádio), seletor de modo,
/// relógio UTC, barra de slot (RX/TX), medidores (S/PO/SWR/áudio), avisos de sincronização e bandas.
library;

import 'package:flutter/material.dart';

import '../core/modes.dart';
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
  const StatusHeader({
    super.key,
    required this.engine,
    required this.onSettings,
    required this.onRadio,
    required this.onHelp,
  });

  /// Abre o tutorial "Seu primeiro QSO".
  final VoidCallback onHelp;
  final Engine engine;

  /// Abre as configurações do app.
  final VoidCallback onSettings;

  /// Abre o painel do rádio (toque na frequência).
  final VoidCallback onRadio;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: engine,
      builder: (context, _) {
        final r = engine.radio;
        final st = r?.state;
        final freq = st?.freqHz ?? engine.dialFrequency ?? 0;
        final tx = engine.transmitting || engine.tuning;
        return Container(
          color: Pal.panel,
          padding: const EdgeInsets.fromLTRB(10, 6, 6, 4),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                children: [
                  // A linha tem de caber em telas estreitas (360 dp): selo e relógio se adaptam ao espaço.
                  Expanded(flex: 3, child: Align(alignment: Alignment.centerLeft, child: _ConnPill(engine: engine))),
                  Expanded(
                    flex: 2,
                    child: FittedBox(
                      fit: BoxFit.scaleDown,
                      alignment: Alignment.centerRight,
                      child: _ClockText(engine: engine),
                    ),
                  ),
                  // Menu rápido de avisos e áudio (os mesmos ajustes estão em Configurações)
                  _QuickMenu(engine: engine),
                  IconButton(
                    visualDensity: VisualDensity.compact,
                    style: IconButton.styleFrom(padding: EdgeInsets.zero, minimumSize: const Size(36, 36), tapTargetSize: MaterialTapTargetSize.shrinkWrap),
                    onPressed: onHelp,
                    icon: const Icon(Icons.help_outline, size: 22),
                    tooltip: 'Como fazer um QSO',
                  ),
                  IconButton(
                    visualDensity: VisualDensity.compact,
                    style: IconButton.styleFrom(padding: EdgeInsets.zero, minimumSize: const Size(36, 36), tapTargetSize: MaterialTapTargetSize.shrinkWrap),
                    onPressed: onSettings,
                    icon: const Icon(Icons.settings, size: 22),
                    tooltip: 'Configurações',
                  ),
                ],
              ),
              Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  // Toque na frequência: abre o painel do rádio (sincronização, potência, modo...)
                  InkWell(
                    onTap: onRadio,
                    borderRadius: BorderRadius.circular(8),
                    child: Text(
                      _fmtFreq(freq),
                      style: kMono.copyWith(
                        fontSize: 30,
                        fontWeight: FontWeight.w600,
                        color: tx ? Pal.tx : Pal.text,
                        letterSpacing: 1,
                      ),
                    ),
                  ),
                  const SizedBox(width: 6),
                  Padding(
                    padding: const EdgeInsets.only(bottom: 5),
                    child: Text(_modeText(st), style: const TextStyle(color: Pal.dim, fontSize: 12)),
                  ),
                  const Spacer(),
                  _ModeButton(engine: engine),
                ],
              ),
              _SyncBanner(engine: engine),
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
                  separatorBuilder: (_, _) => const SizedBox(width: 6),
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

  String _modeText(RadioState? st) => st == null || st.mode == null ? 'USB-D' : civModeName(st.mode, st.dataMode);
}

/// Seletor de modo digital (FT8, FT4, JT65...). Modos não implementados aparecem desabilitados.
class _ModeButton extends StatelessWidget {
  const _ModeButton({required this.engine});
  final Engine engine;

  @override
  Widget build(BuildContext context) {
    return PopupMenuButton<ModeSpec>(
      tooltip: 'Modo digital',
      color: Pal.panel2,
      onSelected: engine.setMode,
      itemBuilder: (_) => [
        for (final m in kModes)
          PopupMenuItem<ModeSpec>(
            value: m,
            enabled: m.implemented,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(m.label, style: TextStyle(fontWeight: FontWeight.w700, color: m.implemented ? Pal.text : Pal.dim)),
                Text(m.description, style: const TextStyle(fontSize: 11, color: Pal.dim)),
              ],
            ),
          ),
      ],
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: Pal.rx.withValues(alpha: 0.18),
          border: Border.all(color: Pal.rx),
          borderRadius: BorderRadius.circular(20),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(engine.mode.label, style: const TextStyle(fontWeight: FontWeight.w800, color: Pal.rx)),
            const Icon(Icons.arrow_drop_down, color: Pal.rx, size: 20),
          ],
        ),
      ),
    );
  }
}

/// Faixa de avisos de sincronização app↔rádio (modo errado, frequência fora do padrão).
class _SyncBanner extends StatelessWidget {
  const _SyncBanner({required this.engine});
  final Engine engine;

  @override
  Widget build(BuildContext context) {
    final r = engine.radio;
    if (r == null || r.status != LinkStatus.connected) return const SizedBox.shrink();
    final items = <Widget>[];
    if (!engine.radioModeOk) {
      items.add(_warn('Rádio em ${civModeName(r.state.mode, r.state.dataMode)} — use USB-D', 'Corrigir', engine.fixRadioMode));
    }
    if (engine.radioOffStandardFrequency) {
      final d = engine.dialFrequency!;
      items.add(_warn('Frequência fora do padrão ${engine.mode.label} (${(d / 1e6).toStringAsFixed(3)} MHz)', 'Ir',
          engine.goToStandardSetup));
    }
    if (items.isEmpty) return const SizedBox.shrink();
    return Padding(padding: const EdgeInsets.only(top: 4), child: Column(children: items));
  }

  Widget _warn(String text, String action, VoidCallback onTap) => Container(
        margin: const EdgeInsets.only(bottom: 3),
        padding: const EdgeInsets.fromLTRB(10, 2, 4, 2),
        decoration: BoxDecoration(
          color: Pal.warn.withValues(alpha: 0.14),
          border: Border.all(color: Pal.warn.withValues(alpha: 0.6)),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Row(
          children: [
            const Icon(Icons.sync_problem, size: 16, color: Pal.warn),
            const SizedBox(width: 6),
            Expanded(child: Text(text, style: const TextStyle(fontSize: 11, color: Pal.warn))),
            TextButton(
              style: TextButton.styleFrom(visualDensity: VisualDensity.compact, padding: const EdgeInsets.symmetric(horizontal: 8)),
              onPressed: onTap,
              child: Text(action),
            ),
          ],
        ),
      );
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
      builder: (context, _, _) {
        final t = engine.now();
        final slot = engine.mode.slotSeconds;
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
                  painter: _SlotPainter(progress: (sec / slot).clamp(0.0, 1.0), color: color, decodeAt: engine.mode.decodeAtSeconds / slot),
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
          builder: (context, _, _) {
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

/// Menu rápido (ícone de sino/alto-falante no topo): liga/desliga a faixa de aviso, a borda piscante,
/// o som e a vibração dos alertas e o monitor de áudio no alto-falante do celular.
class _QuickMenu extends StatelessWidget {
  const _QuickMenu({required this.engine});
  final Engine engine;

  @override
  Widget build(BuildContext context) {
    final s = engine.settings;
    final anyOn = s.alertBanner || s.alertSound || s.alertFlash || s.alertVibrate;
    CheckedPopupMenuItem<String> item(String id, String text, bool value) =>
        CheckedPopupMenuItem<String>(value: id, checked: value, child: Text(text));
    return PopupMenuButton<String>(
      tooltip: 'Avisos e áudio',
      color: Pal.panel2,
      padding: EdgeInsets.zero,
      style: IconButton.styleFrom(padding: EdgeInsets.zero, minimumSize: const Size(36, 36), tapTargetSize: MaterialTapTargetSize.shrinkWrap),
      icon: Icon(
        s.monitorSpeaker ? Icons.hearing : (anyOn ? Icons.notifications_active : Icons.notifications_off),
        size: 22,
        color: anyOn || s.monitorSpeaker ? Pal.text : Pal.dim,
      ),
      onSelected: (id) {
        switch (id) {
          case 'banner':
            s.alertBanner = !s.alertBanner;
          case 'flash':
            s.alertFlash = !s.alertFlash;
          case 'sound':
            s.alertSound = !s.alertSound;
          case 'vibrate':
            s.alertVibrate = !s.alertVibrate;
          case 'monitor':
            s.monitorSpeaker = !s.monitorSpeaker;
        }
        s.save(); // notifica o motor (faixa, som, monitor...)
      },
      itemBuilder: (_) => [
        item('banner', 'Aviso (pop-up) no topo', s.alertBanner),
        item('flash', 'Piscar a borda da tela', s.alertFlash),
        item('sound', 'Som dos alertas', s.alertSound),
        item('vibrate', 'Vibração dos alertas', s.alertVibrate),
        const PopupMenuDivider(),
        item('monitor', 'Ouvir o áudio do rádio no celular', s.monitorSpeaker),
      ],
    );
  }
}
