import 'package:flutter_test/flutter_test.dart';
import 'package:jtmobile/engine/alerts.dart';

class _Quiet implements AlertPlayer {
  final played = <AlertKind>[];
  @override
  Future<void> play(AlertKind kind) async => played.add(kind);
  @override
  Future<void> vibrate(AlertKind kind) async {}
}

void main() {
  test('o início do TX logo após uma resposta não substitui a faixa da resposta (mas toca o som)', () {
    final p = _Quiet();
    final c = AlertCenter(player: p, holdImportant: const Duration(seconds: 5));
    c.show(AlertKind.reply, 'K1ABC respondeu!');
    final flash = c.flashTick;
    c.show(AlertKind.txStart, 'Transmitindo');
    expect(c.current!.kind, AlertKind.reply, reason: 'a resposta continua visível');
    expect(c.flashTick, flash + 1, reason: 'a borda ainda pisca');
    expect(p.played, [AlertKind.reply, AlertKind.txStart]);
    // um QSO completo (importante) pode substituir a resposta
    c.show(AlertKind.qsoComplete, 'QSO completo');
    expect(c.current!.kind, AlertKind.qsoComplete);
    c.dispose();
  });

  test('depois do tempo de retenção, avisos comuns voltam a substituir a faixa', () async {
    final c = AlertCenter(player: _Quiet(), holdImportant: const Duration(milliseconds: 30));
    c.show(AlertKind.reply, 'resposta');
    await Future<void>.delayed(const Duration(milliseconds: 80));
    c.show(AlertKind.txStart, 'Transmitindo');
    expect(c.current!.kind, AlertKind.txStart);
    c.dispose();
  });
}
