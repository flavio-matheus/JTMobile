/// Tela de configurações: estação, conexão com o rádio, sincronização, áudio/temporização, logbook
/// e waterfall. Também fornece [bindToWifi] (fixa o app ao Wi-Fi do rádio, via código nativo).
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../core/settings.dart';
import '../engine/alerts.dart';
import '../engine/engine.dart';
import '../engine/radio_sync.dart';
import 'guidance.dart';
import 'theme.dart';

const MethodChannel _net = MethodChannel('br.poinsp.ft_mobile/net');

/// Fixa o tráfego do app na rede Wi-Fi (necessário quando o Wi-Fi do rádio não tem internet).
Future<String> bindToWifi() async {
  try {
    final ok = await _net.invokeMethod<bool>('bindWifi');
    return ok == true ? 'Aplicativo vinculado à rede Wi-Fi atual.' : 'Nenhuma rede Wi-Fi ativa encontrada.';
  } on MissingPluginException {
    return 'Disponível apenas no Android.';
  } catch (e) {
    return 'Falha ao vincular: $e';
  }
}

class SettingsPage extends StatefulWidget {
  const SettingsPage({super.key, required this.engine});
  final Engine engine;

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  Settings get s => widget.engine.settings;
  late final _call = TextEditingController(text: s.callsign);
  late final _grid = TextEditingController(text: s.grid);
  late final _ip = TextEditingController(text: s.radioIp);
  late final _user = TextEditingController(text: s.radioUser);
  late final _pass = TextEditingController(text: s.radioPass);
  late final _cq = TextEditingController(text: s.customCq);
  bool _showPass = false;

  @override
  void dispose() {
    _commit();
    for (final c in [_call, _grid, _ip, _user, _pass, _cq]) {
      c.dispose();
    }
    super.dispose();
  }

  void _commit() {
    s.callsign = _call.text.trim().toUpperCase();
    s.grid = _grid.text.trim().toUpperCase();
    s.radioIp = _ip.text.trim();
    s.radioUser = _user.text.trim();
    s.radioPass = _pass.text;
    s.customCq = _cq.text.trim().isEmpty ? 'CQ' : _cq.text.trim().toUpperCase();
    s.save();
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      onPopInvokedWithResult: (_, _) => _commit(),
      child: Scaffold(
        appBar: AppBar(title: const Text('Configurações')),
        body: ListView(
          padding: const EdgeInsets.all(14),
          children: [
            _section('Estação'),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _call,
                    textCapitalization: TextCapitalization.characters,
                    decoration: const InputDecoration(labelText: 'Indicativo', border: OutlineInputBorder()),
                  ),
                ),
                const SizedBox(width: 10),
                SizedBox(
                  width: 110,
                  child: TextField(
                    controller: _grid,
                    textCapitalization: TextCapitalization.characters,
                    decoration: const InputDecoration(labelText: 'Grid (4/6)', border: OutlineInputBorder()),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            TextField(
              controller: _cq,
              textCapitalization: TextCapitalization.characters,
              decoration: const InputDecoration(
                  labelText: 'Texto do CQ', helperText: 'Ex.: CQ, CQ DX, CQ POTA', border: OutlineInputBorder()),
            ),
            _section('Rádio'),
            DropdownButtonFormField<RadioKind>(
              initialValue: s.radioKind,
              decoration: const InputDecoration(labelText: 'Tipo de conexão', border: OutlineInputBorder()),
              items: const [
                DropdownMenuItem(value: RadioKind.icomWifi, child: Text('Icom IC-705 via Wi-Fi (rede Icom)')),
                DropdownMenuItem(value: RadioKind.simulator, child: Text('Simulador (sem rádio)')),
              ],
              onChanged: (v) => setState(() => s.radioKind = v ?? s.radioKind),
            ),
            if (s.radioKind == RadioKind.icomWifi) ...[
              const SizedBox(height: 10),
              TextField(
                controller: _ip,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(
                    labelText: 'Endereço IP do rádio',
                    helperText: 'Ponto de acesso do IC-705: normalmente 192.168.200.1',
                    border: OutlineInputBorder()),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: _user,
                autocorrect: false,
                decoration: const InputDecoration(labelText: 'Usuário de rede (Network User1)', border: OutlineInputBorder()),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: _pass,
                obscureText: !_showPass,
                autocorrect: false,
                decoration: InputDecoration(
                  labelText: 'Senha de rede',
                  border: const OutlineInputBorder(),
                  suffixIcon: IconButton(
                    icon: Icon(_showPass ? Icons.visibility_off : Icons.visibility),
                    onPressed: () => setState(() => _showPass = !_showPass),
                  ),
                ),
              ),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Ajustar rádio ao conectar'),
                subtitle: const Text('Define USB-D e a frequência da banda escolhida', style: TextStyle(fontSize: 11)),
                value: s.setRadioOnConnect,
                onChanged: (v) => setState(() => s.setRadioOnConnect = v),
              ),
              OutlinedButton.icon(
                icon: const Icon(Icons.wifi_lock),
                label: const Text('Vincular app ao Wi-Fi do rádio'),
                onPressed: () async {
                  final m = await bindToWifi();
                  if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(m)));
                },
              ),
              const SizedBox(height: 8),
              const _HelpCard(),
            ],
            _section('Áudio e TX'),
            _slider('Nível de TX (áudio enviado ao rádio)', s.txLevel, 0.05, 1.0, (v) => setState(() => s.txLevel = v),
                '${(s.txLevel * 100).round()}%'),
            const Padding(
              padding: EdgeInsets.only(bottom: 6),
              child: Text(
                'Dica: ajuste o nível para que o ALC do rádio mal se mexa e a potência seja a desejada (use TUNE).',
                style: TextStyle(color: Pal.dim, fontSize: 11),
              ),
            ),
            _slider('Compensação do relógio', s.clockOffsetMs.toDouble(), -1500, 1500, (v) => setState(() => s.clockOffsetMs = v.round()),
                '${s.clockOffsetMs} ms'),
            _section('Alertas e guia'),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Som nos alertas'),
              subtitle: const Text('Bip ao transmitir, acorde quando uma estação responde, arpejo ao completar o QSO. Usa o volume de MÍDIA.',
                  style: TextStyle(fontSize: 11)),
              value: s.alertSound,
              onChanged: (v) {
                setState(() => s.alertSound = v);
                s.save();
              },
            ),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Vibração nos alertas'),
              value: s.alertVibrate,
              onChanged: (v) {
                setState(() => s.alertVibrate = v);
                s.save();
              },
            ),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Aviso (pop-up) no topo da tela'),
              subtitle: const Text('Desligue para não ver as faixas de aviso; o guia e os sons continuam conforme as opções',
                  style: TextStyle(fontSize: 11)),
              value: s.alertBanner,
              onChanged: (v) {
                setState(() => s.alertBanner = v);
                s.save();
              },
            ),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Piscar a borda da tela'),
              value: s.alertFlash,
              onChanged: (v) {
                setState(() => s.alertFlash = v);
                s.save();
              },
            ),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Auto TX'),
              subtitle: const Text('Responder (↩) já arma a transmissão, como o duplo clique do WSJT-X/JTDX',
                  style: TextStyle(fontSize: 11)),
              value: s.replyEnablesTx,
              onChanged: (v) => setState(() => s.replyEnablesTx = v),
            ),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Auto-sequência do QSO'),
              subtitle: const Text('Avança Tx1 → Tx5 sozinho conforme as respostas recebidas', style: TextStyle(fontSize: 11)),
              value: s.autoSeq,
              onChanged: (v) => setState(() => s.autoSeq = v),
            ),
            _slider('Tentativas por etapa sem resposta', s.txMaxAttempts.toDouble(), 3, 30,
                (v) => setState(() => s.txMaxAttempts = v.round()), '${s.txMaxAttempts}'),
            const Text(
              'Depois deste número de repetições da mesma mensagem, o TX é desarmado. Use ▶ em Meu QSO / TX para reenviar uma etapa.',
              style: TextStyle(color: Pal.dim, fontSize: 11),
            ),
            _section('Áudio do rádio no celular'),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Ouvir o áudio do rádio no alto-falante'),
              subtitle: const Text('Reproduz o "assobio" dos modos digitais. Usa o volume de MÍDIA; desligado durante a TX. '
                  'Cuidado com realimentação se o celular ficar perto do microfone do rádio.',
                  style: TextStyle(fontSize: 11)),
              value: s.monitorSpeaker,
              onChanged: (v) {
                setState(() => s.monitorSpeaker = v);
                s.save();
              },
            ),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Ouvir também o meu áudio de TX'),
              subtitle: const Text(
                  'Com o monitor ligado, toca no celular o sinal que você está transmitindo (e o tom do TUNE) — '
                  'ótimo para avaliar nível e qualidade do áudio enviado ao rádio.',
                  style: TextStyle(fontSize: 11)),
              value: s.monitorTx,
              onChanged: (v) {
                setState(() => s.monitorTx = v);
                s.save();
              },
            ),
            _slider('Volume do monitor', s.monitorVolume, 0, 1, (v) {
              setState(() => s.monitorVolume = v);
              s.save();
            },
                '${(s.monitorVolume * 100).round()}%'),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    icon: const Icon(Icons.volume_up),
                    label: const Text('Testar alertas'),
                    onPressed: () {
                      _commit();
                      widget.engine.alerts.show(AlertKind.reply, 'Teste: estação respondeu!', 'PY2XYZ K1ABC -08');
                    },
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: OutlinedButton.icon(
                    icon: const Icon(Icons.school),
                    label: const Text('Ver tutorial'),
                    onPressed: () => showTutorial(context, simulator: s.radioKind == RadioKind.simulator),
                  ),
                ),
              ],
            ),
            _section('Sincronização com o rádio'),
            DropdownButtonFormField<SyncPolicy>(
              initialValue: s.syncPolicy,
              decoration: const InputDecoration(labelText: 'Ao conectar, quem manda?', border: OutlineInputBorder()),
              items: const [
                DropdownMenuItem(value: SyncPolicy.radioFirst, child: Text('O rádio (app adota frequência/banda do rádio)')),
                DropdownMenuItem(value: SyncPolicy.appFirst, child: Text('O app (envia a banda escolhida ao rádio)')),
              ],
              onChanged: (v) => setState(() => s.syncPolicy = v ?? s.syncPolicy),
            ),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Corrigir modo para USB-D automaticamente'),
              subtitle: const Text('FT8/FT4 exigem USB com DATA ligado', style: TextStyle(fontSize: 11)),
              value: s.autoFixMode,
              onChanged: (v) => setState(() => s.autoFixMode = v),
            ),
            _section('Áudio e temporização'),
            _slider('Buffer de áudio de TX no rádio', s.txBufferMs.toDouble(), 50, 400, (v) => setState(() => s.txBufferMs = v.round()),
                '${s.txBufferMs} ms'),
            const Text(
              'Menor = menos atraso na transmissão, porém mais sensível a oscilações da rede. Reconecte para aplicar.',
              style: TextStyle(color: Pal.dim, fontSize: 11),
            ),
            _slider('Avanço do áudio de TX', s.txAdvanceMs.toDouble(), -300, 500, (v) => setState(() => s.txAdvanceMs = v.round()),
                '${s.txAdvanceMs} ms'),
            const Text(
              'Ajuste fino se os outros operadores reportarem seu DT diferente de 0 (valor positivo = envia mais cedo).',
              style: TextStyle(color: Pal.dim, fontSize: 11),
            ),
            _slider('Compensação de latência de RX', s.rxLatencyMs.toDouble(), -200, 400, (v) => setState(() => s.rxLatencyMs = v.round()),
                '${s.rxLatencyMs} ms'),
            const SizedBox(height: 8),
            _DtCard(engine: widget.engine, onChanged: () => setState(() {})),
            _section('Logbook'),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Registrar QSO sem perguntar'),
              subtitle: const Text('Grava automaticamente ao concluir o contato (sem o diálogo de confirmação)',
                  style: TextStyle(fontSize: 11)),
              value: s.autoLog,
              onChanged: (v) => setState(() => s.autoLog = v),
            ),
            const Text(
              'Integrações com LoTW, QRZ.com, eQSL e Club Log: em desenvolvimento (fase 2). '
              'Por ora use Logbook → Exportar ADIF.',
              style: TextStyle(color: Pal.dim, fontSize: 11),
            ),
            _section('Waterfall'),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Ganho automático'),
              value: s.wfAuto,
              onChanged: (v) => setState(() => s.wfAuto = v),
            ),
            if (!s.wfAuto) ...[
              _slider('Ganho', s.wfGain, 0, 1, (v) => setState(() => s.wfGain = v), '${(s.wfGain * 100).round()}%'),
              _slider('Zero (piso)', s.wfZero, 0, 1, (v) => setState(() => s.wfZero = v), '${(s.wfZero * 100).round()}%'),
            ],
            const SizedBox(height: 24),
            FilledButton(
              onPressed: () async {
                _commit();
                final nav = Navigator.of(context);
                await widget.engine.connectRadio();
                nav.pop();
              },
              child: const Text('Salvar e reconectar'),
            ),
            const SizedBox(height: 24),
          ],
        ),
      ),
    );
  }

  Widget _section(String t) => Padding(
        padding: const EdgeInsets.only(top: 20, bottom: 8),
        child: Text(t.toUpperCase(), style: const TextStyle(color: Pal.accent, fontSize: 12, fontWeight: FontWeight.w800, letterSpacing: 1)),
      );

  Widget _slider(String label, double v, double min, double max, ValueChanged<double> on, String shown) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [Expanded(child: Text(label)), Text(shown, style: kMono)]),
          Slider(value: v.clamp(min, max), min: min, max: max, onChanged: on),
        ],
      );
}

class _HelpCard extends StatelessWidget {
  const _HelpCard();
  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(color: Pal.panel, borderRadius: BorderRadius.circular(10), border: Border.all(color: Pal.line)),
        child: const Text(
          'Configuração do IC-705 (mesma do RS-MS1A):\n'
          '• MENU > SET > WLAN SET > Remote Settings: Network Control = ON.\n'
          '• Cadastre Network User1 (usuário e senha) e use-os aqui.\n'
          '• Portas UDP padrão: 50001 / 50002 / 50003.\n'
          '• Configure DATA MOD = WLAN (áudio de dados pela rede) no menu de conectores do rádio.\n'
          '• Conecte o celular ao Wi-Fi do rádio (modo Access Point) e toque em “Vincular app ao Wi-Fi”.\n'
          '• Feche o RS-MS1A e o JTDX no PC: o rádio aceita apenas um cliente de rede por vez.',
          style: TextStyle(fontSize: 12, color: Pal.dim, height: 1.4),
        ),
      );
}

/// Mostra o DT mediano das últimas decodificações e permite calibrar o relógio por ele.
///
/// O DT (diferença de tempo) das mensagens recebidas deve ficar perto de 0 s. Um valor médio
/// persistentemente positivo/negativo indica que o relógio do celular está adiantado/atrasado.
class _DtCard extends StatelessWidget {
  const _DtCard({required this.engine, required this.onChanged});
  final Engine engine;
  final VoidCallback onChanged;

  @override
  Widget build(BuildContext context) {
    final dt = engine.dtMedianSeconds;
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(color: Pal.panel, borderRadius: BorderRadius.circular(10), border: Border.all(color: Pal.line)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            dt == null ? 'DT mediano: aguardando mais decodificações…' : 'DT mediano: ${dt >= 0 ? '+' : ''}${dt.toStringAsFixed(2)} s',
            style: kMono.copyWith(fontSize: 15, fontWeight: FontWeight.w700),
          ),
          Text(
            'Jitter do áudio: ${engine.audioJitterMs.toStringAsFixed(1)} ms · lacunas preenchidas: ${engine.audioGapsFilled}',
            style: const TextStyle(color: Pal.dim, fontSize: 12),
          ),
          const SizedBox(height: 8),
          OutlinedButton.icon(
            onPressed: dt == null
                ? null
                : () {
                    final adj = engine.calibrateClockFromDt();
                    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Relógio ajustado em ${adj ?? 0} ms')));
                    onChanged();
                  },
            icon: const Icon(Icons.schedule),
            label: const Text('Calibrar relógio pelo DT'),
          ),
        ],
      ),
    );
  }
}
