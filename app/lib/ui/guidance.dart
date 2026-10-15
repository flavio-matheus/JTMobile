/// Elementos de orientação ao operador:
///  * [AlertBanner] — faixa no topo com o alerta atual (TX iniciado, estação respondeu, QSO completo);
///  * [AlertFlash]  — piscar de borda de tela cheia a cada alerta (visível mesmo de relance);
///  * [CoachBanner] — "guia" contextual que diz **o que está acontecendo e qual é o próximo passo**
///    (selecione uma estação → ative o TX → aguarde a resposta → QSO completo);
///  * [showTutorial] — tutorial de boas-vindas (como fazer o primeiro QSO).
library;

import 'dart:async';

import 'package:flutter/material.dart';

import '../engine/alerts.dart';
import '../engine/engine.dart';
import '../radio/radio_link.dart';
import 'theme.dart';

Color _alertColor(AlertKind k) => switch (k) {
      AlertKind.txStart => Pal.tx,
      AlertKind.reply => Pal.rx,
      AlertKind.qsoComplete => const Color(0xFFFFD54F),
      AlertKind.info => Pal.accent,
      AlertKind.warning => Pal.warn,
    };

IconData _alertIcon(AlertKind k) => switch (k) {
      AlertKind.txStart => Icons.cell_tower,
      AlertKind.reply => Icons.mark_chat_unread,
      AlertKind.qsoComplete => Icons.verified,
      AlertKind.info => Icons.info_outline,
      AlertKind.warning => Icons.warning_amber,
    };

/// Faixa de alerta no topo da tela. Toque para fechar.
class AlertBanner extends StatelessWidget {
  const AlertBanner({super.key, required this.alerts});
  final AlertCenter alerts;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: alerts,
      builder: (context, _) {
        final a = alerts.current;
        return AnimatedSwitcher(
          duration: const Duration(milliseconds: 220),
          transitionBuilder: (child, anim) => SlideTransition(
            position: Tween<Offset>(begin: const Offset(0, -1), end: Offset.zero).animate(anim),
            child: FadeTransition(opacity: anim, child: child),
          ),
          child: a == null
              ? const SizedBox.shrink(key: ValueKey('none'))
              : Padding(
                  key: ValueKey('${a.time.microsecondsSinceEpoch}'),
                  padding: const EdgeInsets.fromLTRB(10, 6, 10, 0),
                  child: Material(
                    color: _alertColor(a.kind),
                    elevation: 8,
                    borderRadius: BorderRadius.circular(14),
                    child: InkWell(
                      borderRadius: BorderRadius.circular(14),
                      onTap: alerts.dismiss,
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(14, 10, 8, 10),
                        child: Row(
                          children: [
                            Icon(_alertIcon(a.kind), color: Colors.black87, size: 30),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Text(a.title,
                                      style: const TextStyle(color: Colors.black, fontSize: 17, fontWeight: FontWeight.w800)),
                                  if (a.body.isNotEmpty)
                                    Text(a.body, style: kMono.copyWith(color: Colors.black87, fontSize: 13)),
                                ],
                              ),
                            ),
                            const Icon(Icons.close, color: Colors.black54, size: 20),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
        );
      },
    );
  }
}

/// Borda que "pisca" (e some em ~1,3 s) a cada novo alerta, na cor do alerta.
class AlertFlash extends StatelessWidget {
  const AlertFlash({super.key, required this.alerts});
  final AlertCenter alerts;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: alerts,
      builder: (context, _) {
        if (!alerts.flashEnabled || alerts.flashTick == 0 || alerts.history.isEmpty) return const SizedBox.shrink();
        final color = _alertColor(alerts.history.last.kind);
        return IgnorePointer(
          child: TweenAnimationBuilder<double>(
            key: ValueKey(alerts.flashTick),
            tween: Tween(begin: 1, end: 0),
            duration: const Duration(milliseconds: 1300),
            curve: Curves.easeOut,
            builder: (context, v, _) => Container(
              decoration: BoxDecoration(border: Border.all(color: color.withValues(alpha: 0.95 * v), width: 12 * v + 1)),
            ),
          ),
        );
      },
    );
  }
}

/// Guia contextual: explica o estado atual e oferece o botão do próximo passo.
class CoachBanner extends StatefulWidget {
  const CoachBanner({super.key, required this.engine});
  final Engine engine;

  @override
  State<CoachBanner> createState() => _CoachBannerState();
}

class _CoachBannerState extends State<CoachBanner> {
  Timer? _t;

  @override
  void initState() {
    super.initState();
    // atualiza a contagem regressiva ("em 7 s") uma vez por segundo
    _t = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _t?.cancel();
    super.dispose();
  }

  Engine get e => widget.engine;

  String _step(int i) => switch (i) {
        1 => 'enviando seu grid',
        2 => 'enviando seu relatório',
        3 => 'confirmando o relatório (R)',
        4 => 'enviando RR73',
        5 => 'enviando o 73 final',
        _ => 'chamando CQ',
      };

  /// Calcula (ícone, cor, título, texto, rótulo da ação, ação) do estado atual.
  ({IconData icon, Color color, String title, String text, String? actionLabel, VoidCallback? action}) _state() {
    final r = e.radio;
    final q = e.qso;
    final secs = e.secondsUntilTxSlot().ceil();
    final slotName = e.txParity == 0 ? '1º' : '2º';
    bool recent(DateTime? t, int s) => t != null && e.now().difference(t).inSeconds < s;

    if (r == null || r.status != LinkStatus.connected) {
      return (
        icon: Icons.link_off,
        color: Pal.warn,
        title: 'Rádio desconectado',
        text: 'Toque no selo "Simulador / IC-705" no topo para conectar. Para treinar sem rádio, use o Simulador.',
        actionLabel: 'Conectar',
        action: e.connectRadio,
      );
    }
    if (e.tuning) {
      return (icon: Icons.tune, color: Pal.tx, title: 'TUNE ativo', text: 'Portadora contínua (máx. 10 s). Toque TUNE para parar.', actionLabel: null, action: null);
    }
    if (e.transmitting) {
      return (
        icon: Icons.cell_tower,
        color: Pal.tx,
        title: 'TRANSMITINDO agora',
        text: '${e.txMessageShown ?? ''}\nAguarde o fim do período; a resposta chega no próximo.',
        actionLabel: 'HALT',
        action: e.haltTx,
      );
    }
    if (recent(e.lastQsoAt, 25) && !e.txEnabled && q.dxCall.isEmpty) {
      return (
        icon: Icons.verified,
        color: const Color(0xFFFFD54F),
        title: 'QSO completo com ${e.lastQsoCall}!',
        text: 'Foi para o Logbook (ícone do livro, embaixo). Toque ↩ em outro CQ ou chame CQ geral.',
        actionLabel: 'Chamar CQ',
        action: () {
          e.callCq();
          e.setTxEnabled(true);
        },
      );
    }
    if (e.txEnabled && q.dxCall.isEmpty) {
      return (
        icon: Icons.campaign,
        color: Pal.tx,
        title: 'CQ ativo — aguardando alguém responder',
        text: 'Próxima transmissão no $slotName período, em $secs s. Quando uma estação responder você será avisado (alerta verde + som).',
        actionLabel: 'Parar',
        action: e.haltTx,
      );
    }
    if (e.txEnabled) {
      final replied = recent(e.lastReplyAt, 20) ? '\nÚltima resposta: ${e.lastReplyText}' : '';
      return (
        icon: Icons.sync_alt,
        color: Pal.tx,
        title: 'QSO com ${q.dxCall}: ${_step(q.txIndex)}',
        text: 'Próxima TX no $slotName período, em $secs s (tentativa ${e.txAttempts}/${e.settings.txMaxAttempts}).$replied',
        actionLabel: 'Parar',
        action: e.haltTx,
      );
    }
    if (q.dxCall.isNotEmpty) {
      return (
        icon: Icons.person_pin_circle,
        color: Pal.accent,
        title: '${q.dxCall} selecionada',
        text: 'Toque ATIVAR TX: o app envia "${q.currentMessage}" no $slotName período (em $secs s) e conduz o QSO sozinho.',
        actionLabel: 'Ativar TX',
        action: () => e.setTxEnabled(true),
      );
    }
    return (
      icon: Icons.touch_app,
      color: Pal.rx,
      title: 'Como falar com alguém?',
      text: 'Toque em ↩ numa chamada CQ (verde): o app responde e conduz o QSO até o 73.',
      actionLabel: 'Chamar CQ',
      action: () {
        e.callCq();
        e.setTxEnabled(true);
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: e,
      builder: (context, _) {
        final s = _state();
        return Container(
          margin: const EdgeInsets.fromLTRB(8, 3, 8, 2),
          padding: const EdgeInsets.fromLTRB(10, 4, 6, 4),
          decoration: BoxDecoration(
            color: s.color.withValues(alpha: 0.13),
            border: Border.all(color: s.color.withValues(alpha: 0.7)),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Row(
            children: [
              Icon(s.icon, color: s.color, size: 20),
              const SizedBox(width: 8),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(s.title, style: TextStyle(color: s.color, fontWeight: FontWeight.w800, fontSize: 12.5), maxLines: 1, overflow: TextOverflow.ellipsis),
                    Text(s.text, style: const TextStyle(fontSize: 10.5, color: Pal.text, height: 1.15), maxLines: 2, overflow: TextOverflow.ellipsis),
                  ],
                ),
              ),
              if (s.actionLabel != null)
                FilledButton(
                  style: FilledButton.styleFrom(
                    backgroundColor: s.color,
                    foregroundColor: Colors.black,
                    visualDensity: VisualDensity.compact,
                    padding: const EdgeInsets.symmetric(horizontal: 10),
                    minimumSize: const Size(0, 30),
                  ),
                  onPressed: s.action,
                  child: Text(s.actionLabel!, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 12)),
                ),
            ],
          ),
        );
      },
    );
  }
}

/// Tutorial de boas-vindas: como fazer o primeiro QSO.
Future<void> showTutorial(BuildContext context, {required bool simulator}) {
  Widget step(String n, String title, String text) => Padding(
        padding: const EdgeInsets.only(bottom: 10),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            CircleAvatar(radius: 13, backgroundColor: Pal.accent, child: Text(n, style: const TextStyle(color: Colors.black, fontWeight: FontWeight.w800))),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: const TextStyle(fontWeight: FontWeight.w800)),
                  Text(text, style: const TextStyle(color: Pal.dim, fontSize: 13)),
                ],
              ),
            ),
          ],
        ),
      );
  return showDialog<void>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: const Text('Seu primeiro QSO'),
      content: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            if (simulator)
              Container(
                margin: const EdgeInsets.only(bottom: 12),
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(color: Pal.warn.withValues(alpha: 0.15), borderRadius: BorderRadius.circular(8)),
                child: const Text(
                  'Você está no SIMULADOR: as estações são fictícias e respondem sempre, para você treinar o fluxo completo.',
                  style: TextStyle(fontSize: 12),
                ),
              ),
            step('1', 'Escolha com quem falar',
                'Na aba Atividade, as linhas VERDES com "CQ" são estações chamando. Toque no ícone ↩ de uma delas.'),
            step('2', 'O TX é armado sozinho',
                'O guia (faixa colorida acima da waterfall) mostra o próximo passo e a contagem até a sua transmissão.'),
            step('3', 'Você transmite → ouve a resposta',
                'No seu período o app transmite (alerta VERMELHO + bip). Um período depois a estação responde (alerta VERDE + som de 3 notas).'),
            step('4', 'O app conduz o QSO',
                'Grid → relatório → R-relatório → RR73 → 73. A cada passo você é avisado. HALT interrompe tudo a qualquer momento.'),
            step('5', 'Registre o contato',
                'Ao concluir, um aviso dourado + arpejo; confirme o registro no Logbook (ícone do livro).'),
            const Text(
              'Para chamar geral: toque "Chamar CQ" no guia. Ajuste o volume de MÍDIA do celular para ouvir os alertas.',
              style: TextStyle(fontSize: 12, color: Pal.dim),
            ),
          ],
        ),
      ),
      actions: [FilledButton(onPressed: () => Navigator.pop(ctx), child: const Text('Entendi'))],
    ),
  );
}
