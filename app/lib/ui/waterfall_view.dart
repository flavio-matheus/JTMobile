import 'dart:math';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../core/models.dart';
import '../engine/engine.dart';
import '../engine/waterfall.dart';
import 'theme.dart';

/// Waterfall interativa:
///  • pinça = zoom (largura de banda visível);
///  • arrastar no modo "Dial" = desliza o espectro sob a mira central, que define a frequência de TX;
///  • arrastar no modo "Explorar" = só navega; toque define RX/TX.
class WaterfallView extends StatefulWidget {
  const WaterfallView({super.key, required this.engine, required this.onDecodeTap});
  final Engine engine;
  final void Function(Decode d) onDecodeTap;

  @override
  State<WaterfallView> createState() => _WaterfallViewState();
}

class _WaterfallViewState extends State<WaterfallView> {
  double _start = 0; // Hz
  double _span = 3000; // Hz visíveis
  bool _dial = true; // true: deslizar define TX
  bool _dragging = false;
  // gesto
  double _gStartSpan = 3000, _gStartView = 0, _gFocalFreq = 0, _gFocalX = 0;
  final List<(Rect, Decode)> _tags = [];

  Engine get e => widget.engine;

  void _sync() {
    if (!mounted || !_dial || _dragging) return;
    final c = _start + _span / 2;
    if ((c - e.settings.txFreq).abs() > 0.5) _centerOn(e.settings.txFreq.toDouble());
  }

  @override
  void dispose() {
    e.removeListener(_sync);
    super.dispose();
  }

  @override
  void initState() {
    super.initState();
    e.addListener(_sync);
    _span = 3000;
    _start = 0;
    // centraliza na frequência de TX se em modo dial
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _setSpan(2000);
      _centerOn(e.settings.txFreq.toDouble());
    });
  }

  void _setSpan(double s) {
    setState(() {
      _span = s.clamp(300.0, kWfMaxHz);
      _clampView();
    });
  }

  void _clampView() {
    _start = _start.clamp(-_span / 2 + 100, kWfMaxHz - _span / 2 - 100 + 0.0);
    if (!_dial) _start = _start.clamp(0.0, max(0.0, kWfMaxHz - _span));
  }

  void _centerOn(double hz) {
    setState(() {
      _start = hz - _span / 2;
      _clampView();
    });
  }

  double _freqAt(double x, double w) => _start + x / w * _span;

  void _setDial(bool v) {
    setState(() {
      _dial = v;
      if (v) {
        _centerOn(e.settings.txFreq.toDouble());
      } else {
        _clampView();
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Expanded(
          child: LayoutBuilder(builder: (context, c) {
            final w = c.maxWidth;
            return GestureDetector(
              behavior: HitTestBehavior.opaque,
              onScaleStart: (d) {
                _dragging = true;
                _gStartSpan = _span;
                _gStartView = _start;
                _gFocalX = d.localFocalPoint.dx;
                _gFocalFreq = _freqAt(d.localFocalPoint.dx, w);
                          },
              onScaleUpdate: (d) {
                if (d.pointerCount >= 2 || (d.scale - 1).abs() > 0.02) {
                  final newSpan = (_gStartSpan / d.horizontalScale.clamp(0.2, 8.0)).clamp(300.0, kWfMaxHz);
                  setState(() {
                    _span = newSpan;
                    _start = _gFocalFreq - d.localFocalPoint.dx / w * _span;
                    _clampView();
                  });
                } else {
                  final df = -(d.localFocalPoint.dx - _gFocalX) / w * _gStartSpan;
                  setState(() {
                    _start = _gStartView + df;
                    _clampView();
                  });
                }
                if (_dial) {
                  e.setTxFreq((_start + _span / 2).round(), persist: false);
                }
              },
              onScaleEnd: (d) {
                _dragging = false;
                if (_dial) e.setTxFreq((_start + _span / 2).round());
              },
              onTapUp: (d) {
                // toque em etiqueta de decodificação?
                for (final t in _tags) {
                  if (t.$1.inflate(6).contains(d.localPosition)) {
                    widget.onDecodeTap(t.$2);
                    return;
                  }
                }
                final f = _freqAt(d.localPosition.dx, w).round();
                if (_dial) {
                  _centerOn(f.toDouble());
                  e.setRxFreq(f);
                  e.setTxFreq(f);
                } else {
                  e.setRxFreq(f);
                }
              },
              onLongPressStart: (d) {
                e.setTxFreq(_freqAt(d.localPosition.dx, w).round());
                if (_dial) _centerOn(e.settings.txFreq.toDouble());
              },
              child: ClipRect(
                child: AnimatedBuilder(
                  animation: Listenable.merge([e.wfTick, e]),
                  builder: (context, _) {
                    final painter = _WfPainter(
                      engine: e,
                      image: e.wfImage,
                      start: _start,
                      span: _span,
                      dial: _dial,
                      tags: _tags,
                    );
                    return CustomPaint(size: Size.infinite, painter: painter);
                  },
                ),
              ),
            );
          }),
        ),
        _controls(),
      ],
    );
  }

  Widget _controls() {
    Widget zoomChip(String label, double span) {
      final sel = (_span - span).abs() < 1;
      return Padding(
        padding: const EdgeInsets.only(right: 6),
        child: ChoiceChip(
          label: Text(label),
          selected: sel,
          visualDensity: VisualDensity.compact,
          onSelected: (_) {
            final c = _start + _span / 2;
            _setSpan(span);
            _centerOn(_dial ? e.settings.txFreq.toDouble() : c);
          },
        ),
      );
    }

    return Container(
      color: Pal.panel,
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          children: [
            SegmentedButton<bool>(
              showSelectedIcon: false,
              style: const ButtonStyle(visualDensity: VisualDensity.compact),
              segments: const [
                ButtonSegment(value: true, label: Text('Dial TX'), icon: Icon(Icons.tune, size: 16)),
                ButtonSegment(value: false, label: Text('Explorar'), icon: Icon(Icons.pan_tool_alt, size: 16)),
              ],
              selected: {_dial},
              onSelectionChanged: (s) => _setDial(s.first),
            ),
            const SizedBox(width: 10),
            const Icon(Icons.zoom_in, size: 18, color: Pal.dim),
            const SizedBox(width: 4),
            zoomChip('500', 500),
            zoomChip('1000', 1000),
            zoomChip('2000', 2000),
            zoomChip('3200', 3200),
          ],
        ),
      ),
    );
  }
}

class _WfPainter extends CustomPainter {
  _WfPainter({
    required this.engine,
    required this.image,
    required this.start,
    required this.span,
    required this.dial,
    required this.tags,
  });

  final Engine engine;
  final ui.Image? image;
  final double start;
  final double span;
  final bool dial;
  final List<(Rect, Decode)> tags;

  static const double rulerH = 22;

  double _x(double hz, double w) => (hz - start) / span * w;

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width, h = size.height;
    canvas.drawRect(Offset.zero & size, Paint()..color = const Color(0xFF00000C));

    final img = image;
    final body = Rect.fromLTWH(0, rulerH, w, h - rulerH);
    if (img != null) {
      // recorte horizontal da imagem (bins) correspondente à janela visível
      final s0 = start / kWfBinHz, s1 = (start + span) / kWfBinHz;
      final srcL = s0.clamp(0.0, kWfBins.toDouble());
      final srcR = s1.clamp(0.0, kWfBins.toDouble());
      if (srcR > srcL) {
        final dstL = _x(srcL * kWfBinHz, w);
        final dstR = _x(srcR * kWfBinHz, w);
        canvas.drawImageRect(
          img,
          Rect.fromLTRB(srcL, 0, srcR, img.height.toDouble()),
          Rect.fromLTRB(dstL, body.top, dstR, body.bottom),
          Paint()..filterQuality = FilterQuality.medium,
        );
      }
    }

    _paintSlotLines(canvas, body, w);
    _paintMarkers(canvas, body, w);
    _paintRuler(canvas, w);
    _paintTags(canvas, body, w);
    _paintOverview(canvas, size);
  }

  void _paintRuler(Canvas canvas, double w) {
    canvas.drawRect(Rect.fromLTWH(0, 0, w, rulerH), Paint()..color = const Color(0xE6101820));
    final steps = [10, 20, 50, 100, 200, 250, 500];
    var step = steps.last.toDouble();
    for (final s in steps) {
      if (span / s <= 9) {
        step = s.toDouble();
        break;
      }
    }
    final first = (start / step).ceil() * step;
    final tp = TextPainter(textDirection: TextDirection.ltr);
    final line = Paint()
      ..color = Pal.dim
      ..strokeWidth = 1;
    for (var f = first; f <= start + span; f += step) {
      final x = _x(f, w);
      canvas.drawLine(Offset(x, rulerH - 6), Offset(x, rulerH), line);
      tp.text = TextSpan(text: f.round().toString(), style: const TextStyle(color: Pal.dim, fontSize: 10));
      tp.layout();
      if (x - tp.width / 2 > 0 && x + tp.width / 2 < w) tp.paint(canvas, Offset(x - tp.width / 2, 3));
    }
  }

  void _paintSlotLines(Canvas canvas, Rect body, double w) {
    final wf = engine.waterfall;
    if (wf.count < 2) return;
    final slotMs = (engine.protocol.slotSeconds * 1000).round();
    final rowH = body.height / kWfRows;
    final p = Paint()
      ..color = const Color(0x66FFFFFF)
      ..strokeWidth = 1;
    final tp = TextPainter(textDirection: TextDirection.ltr);
    var prevSlot = wf.timeOfRow(0) ~/ slotMs;
    for (var i = 1; i < wf.count; i++) {
      final t = wf.timeOfRow(i);
      final slot = t ~/ slotMs;
      if (slot != prevSlot) {
        final y = body.top + i * rowH;
        canvas.drawLine(Offset(0, y), Offset(w, y), p);
        final dt = DateTime.fromMillisecondsSinceEpoch((prevSlot * slotMs), isUtc: true);
        tp.text = TextSpan(
          text: '${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}:${dt.second.toString().padLeft(2, '0')}',
          style: const TextStyle(color: Color(0xCCFFFFFF), fontSize: 10, backgroundColor: Color(0x66000000)),
        );
        tp.layout();
        tp.paint(canvas, Offset(3, y - tp.height));
      }
      prevSlot = slot;
    }
  }

  void _paintMarkers(Canvas canvas, Rect body, double w) {
    final s = engine.settings;
    final bw = engine.protocol.bandwidth;
    void marker(double hz, Color c, String label, {bool above = true}) {
      final x0 = _x(hz, w), x1 = _x(hz + bw, w);
      canvas.drawRect(
        Rect.fromLTRB(x0, body.top, max(x1, x0 + 2), body.bottom),
        Paint()..color = c.withValues(alpha: 0.18),
      );
      canvas.drawLine(Offset(x0, body.top), Offset(x0, body.bottom), Paint()
        ..color = c
        ..strokeWidth = 1.6);
      final tp = TextPainter(
        text: TextSpan(text: label, style: TextStyle(color: Colors.black, fontSize: 10, fontWeight: FontWeight.bold, backgroundColor: c)),
        textDirection: TextDirection.ltr,
      )..layout();
      final lx = (x0 + 2).clamp(0.0, w - tp.width);
      tp.paint(canvas, Offset(lx, above ? body.top + 2 : body.bottom - tp.height - 2));
    }

    marker(s.rxFreq.toDouble(), Pal.rx, ' Rx ${s.rxFreq} ', above: false);
    marker(s.txFreq.toDouble(), Pal.tx, ' Tx ${s.txFreq} ');

    if (dial) {
      // mira central
      final cx = w / 2;
      final p = Paint()
        ..color = Pal.tx.withValues(alpha: 0.9)
        ..strokeWidth = 1;
      final path = Path()
        ..moveTo(cx - 7, 0)
        ..lineTo(cx + 7, 0)
        ..lineTo(cx, 9)
        ..close();
      canvas.drawPath(path, Paint()..color = Pal.tx);
      // tracejado
      for (var y = body.top; y < body.bottom; y += 10) {
        canvas.drawLine(Offset(cx, y), Offset(cx, min(y + 4, body.bottom)), p);
      }
    }
  }

  void _paintTags(Canvas canvas, Rect body, double w) {
    tags.clear();
    // Decodificações do último slot decodificado
    if (engine.decodes.isEmpty) return;
    final lastSlot = engine.decodes.last.slotStart;
    final list = engine.decodes.where((d) => d.slotStart == lastSlot).toList();
    final lanes = <double>[-1e9, -1e9, -1e9, -1e9, -1e9];
    final tp = TextPainter(textDirection: TextDirection.ltr);
    for (final d in list) {
      final call = d.parsed.from ?? d.message.split(' ').first;
      final x = _x(d.freq, w);
      if (x < -60 || x > w + 10) continue;
      final color = d.toMe ? Pal.tx : (d.isCq ? Pal.cq : Colors.white);
      tp.text = TextSpan(
        text: call,
        style: TextStyle(color: Colors.black, fontSize: 10, fontWeight: FontWeight.w700, backgroundColor: color.withValues(alpha: 0.92)),
      );
      tp.layout();
      var lane = 0;
      for (var i = 0; i < lanes.length; i++) {
        if (x > lanes[i] + 4) {
          lane = i;
          break;
        }
        lane = i;
      }
      lanes[lane] = x + tp.width;
      final y = body.top + 18 + lane * 14.0;
      final r = Rect.fromLTWH(x, y, tp.width, tp.height);
      tp.paint(canvas, Offset(x, y));
      // linha até o sinal
      canvas.drawLine(Offset(x, y + tp.height), Offset(x, y + tp.height + 4), Paint()..color = color);
      tags.add((r, d));
    }
  }

  void _paintOverview(Canvas canvas, Size size) {
    const h = 5.0;
    final y = size.height - h;
    canvas.drawRect(Rect.fromLTWH(0, y, size.width, h), Paint()..color = const Color(0xAA000000));
    final x0 = (start / kWfMaxHz * size.width).clamp(0.0, size.width);
    final x1 = ((start + span) / kWfMaxHz * size.width).clamp(0.0, size.width);
    canvas.drawRect(Rect.fromLTRB(x0, y, max(x1, x0 + 3), size.height), Paint()..color = Pal.accent);
  }

  @override
  bool shouldRepaint(covariant _WfPainter old) => true;
}
