import 'package:flutter/material.dart';

import '../repositories/lottery_extra_repository.dart';
import '../repositories/lottery_repository.dart';

class LotteryScreen extends StatefulWidget {
  const LotteryScreen({super.key});

  @override
  State<LotteryScreen> createState() => _LotteryScreenState();
}

class _LotteryScreenState extends State<LotteryScreen> {
  final LotteryRepository _repository = LotteryRepository();
  final LotteryExtraRepository _extra = LotteryExtraRepository();
  late DateTime _month;
  late Future<Map<String, dynamic>> _future;

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    _month = DateTime(now.year, now.month);
    _reload();
  }

  void _reload() {
    _future = _repository.loadMonth(_month.year, _month.month);
  }

  void _changeMonth(int delta) {
    setState(() {
      _month = DateTime(_month.year, _month.month + delta);
      _reload();
    });
  }

  Future<void> _refresh() async {
    setState(_reload);
    await _future;
  }

  void _showError(Object error) {
    if (!mounted) return;
    var message = error.toString();
    message = message.replaceFirst('Bad state: ', '');
    message = message.replaceFirst('Invalid argument(s): ', '');
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
  }

  Future<String?> _paymentMethod() {
    return showDialog<String>(
      context: context,
      builder: (dialogContext) => SimpleDialog(
        title: const Text('Método de pagamento'),
        children: [
          for (final method in const [
            'Transferência bancária',
            'MB Way',
            'Dinheiro',
          ])
            SimpleDialogOption(
              onPressed: () => Navigator.pop(dialogContext, method),
              child: Text(method),
            ),
        ],
      ),
    );
  }

  Future<void> _payDraw(Map<String, dynamic> charge) async {
    final method = await _paymentMethod();
    if (method == null) return;
    try {
      await _repository.payDraw(
        chargeId: charge['id'].toString(),
        paymentMethod: method,
      );
      if (mounted) setState(_reload);
    } catch (error) {
      _showError(error);
    }
  }

  Future<void> _payMonth(Map<String, dynamic> player) async {
    final method = await _paymentMethod();
    if (method == null) return;
    try {
      await _repository.payMonth(
        playerId: player['player_id'].toString(),
        year: _month.year,
        month: _month.month,
        paymentMethod: method,
      );
      if (mounted) setState(_reload);
    } catch (error) {
      _showError(error);
    }
  }

  Future<void> _payFines(Map<String, dynamic> player, double debt) async {
    if (debt <= 0) return;
    final method = await _paymentMethod();
    if (method == null || !mounted) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Receber multas'),
        content: Text(
          'Registar o pagamento de ${_money(debt)} de multas de '
          '${player['member_name'] ?? 'este jogador'}?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Receber'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    try {
      await _repository.payFines(
        playerId: player['player_id'].toString(),
        paymentMethod: method,
      );
      if (mounted) setState(_reload);
    } catch (error) {
      _showError(error);
    }
  }

  Future<void> _receivePrize(Map<String, dynamic> prize) async {
    final remaining = (_asDouble(prize['prize_amount']) -
            _asDouble(prize['received_amount']))
        .clamp(0, double.infinity);
    if (remaining <= 0) return;
    final method = await _paymentMethod();
    if (method == null) return;
    try {
      await _repository.receivePrize(
        prizeId: prize['id'].toString(),
        paymentMethod: method,
      );
      if (mounted) setState(_reload);
    } catch (error) {
      _showError(error);
    }
  }

  Future<void> _manualPrize(
    List<Map<String, dynamic>> players,
    List<Map<String, dynamic>> results,
  ) async {
    if (players.isEmpty || results.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('É necessário existir um jogador ativo e um sorteio registado.'),
        ),
      );
      return;
    }
    final changed = await showDialog<bool>(
      context: context,
      builder: (_) => _ManualPrizeDialog(
        players: players,
        results: results,
        extra: _extra,
      ),
    );
    if (changed == true && mounted) setState(_reload);
  }

  Future<void> _editPlayer(Map<String, dynamic> player) async {
    final changed = await showDialog<bool>(
      context: context,
      builder: (_) => _PlayerDialog(repository: _repository, player: player),
    );
    if (changed == true && mounted) setState(_reload);
  }

  Future<void> _configure(Map<String, dynamic> data) async {
    final changed = await showDialog<bool>(
      context: context,
      builder: (_) => _SettingsDialog(
        repository: _repository,
        drawAmount: _asDouble(data['draw_amount']),
        finePerMiss: _asDouble(data['fine_per_miss']),
      ),
    );
    if (changed == true && mounted) setState(_reload);
  }

  Future<void> _processResult(DateTime date) async {
    final changed = await showDialog<bool>(
      context: context,
      builder: (_) => _ResultDialog(repository: _repository, drawDate: date),
    );
    if (changed == true && mounted) setState(_reload);
  }

  Future<void> _importOfficial() async {
    try {
      final imported = await _repository.importOfficial(
        year: _month.year,
        month: _month.month,
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            imported
                ? 'Resultado oficial importado e processado.'
                : 'O último resultado oficial não pertence a este mês ou já está atualizado.',
          ),
        ),
      );
      setState(_reload);
    } catch (error) {
      _showError(error);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: FutureBuilder<Map<String, dynamic>>(
        future: _future,
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return Center(child: Text('Erro: ${snapshot.error}'));
          }
          if (!snapshot.hasData) {
            return const Center(child: CircularProgressIndicator());
          }

          final data = snapshot.data!;
          final players = List<Map<String, dynamic>>.from(data['players'] as List);
          final active = players.where((row) => row['status'] == 'active').toList();
          final charges = List<Map<String, dynamic>>.from(data['charges'] as List);
          final results = List<Map<String, dynamic>>.from(data['results'] as List);
          final fines = List<Map<String, dynamic>>.from(data['fines'] as List);
          final prizes = List<Map<String, dynamic>>.from(data['prizes'] as List);
          final drawDates = _repository.drawDates(_month.year, _month.month);
          final drawAmount = _asDouble(data['draw_amount']);
          final monthlyPerPlayer = drawDates.length * drawAmount;
          final totalExpected = active.length * monthlyPerPlayer;
          final fineDebt = fines.fold<double>(
            0,
            (sum, row) =>
                sum +
                (_asDouble(row['fine_amount']) - _asDouble(row['paid_amount']))
                    .clamp(0, double.infinity),
          );
          final pendingPrizes = prizes.fold<double>(
            0,
            (sum, row) =>
                sum +
                (_asDouble(row['prize_amount']) -
                        _asDouble(row['received_amount']))
                    .clamp(0, double.infinity),
          );

          return RefreshIndicator(
            onRefresh: _refresh,
            child: ListView(
              padding: const EdgeInsets.fromLTRB(12, 12, 12, 96),
              children: [
                _MonthHeader(
                  month: _month,
                  onPrevious: () => _changeMonth(-1),
                  onNext: () => _changeMonth(1),
                  onCurrent: () {
                    final now = DateTime.now();
                    setState(() {
                      _month = DateTime(now.year, now.month);
                      _reload();
                    });
                  },
                ),
                const SizedBox(height: 10),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    _MetricCard(label: 'Jogadores ativos', value: '${active.length}'),
                    _MetricCard(
                      label: 'Custo mensal / jogador',
                      value: _money(monthlyPerPlayer),
                    ),
                    _MetricCard(
                      label: 'Total previsto do mês',
                      value: _money(totalExpected),
                    ),
                    _MetricCard(label: 'Multas por receber', value: _money(fineDebt)),
                    _MetricCard(
                      label: 'Prémios por receber',
                      value: _money(pendingPrizes),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                if (_repository.canOperateMoney)
                  Wrap(
                    alignment: WrapAlignment.end,
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      OutlinedButton.icon(
                        onPressed: _importOfficial,
                        icon: const Icon(Icons.cloud_download_outlined),
                        label: const Text('Atualizar oficial'),
                      ),
                      OutlinedButton.icon(
                        onPressed: () => _manualPrize(active, results),
                        icon: const Icon(Icons.emoji_events_outlined),
                        label: const Text('Registar prémio'),
                      ),
                      OutlinedButton.icon(
                        onPressed: () => _configure(data),
                        icon: const Icon(Icons.tune),
                        label: const Text('Configurar'),
                      ),
                    ],
                  ),
                const SizedBox(height: 8),
                DefaultTabController(
                  length: 4,
                  child: Column(
                    children: [
                      const TabBar(
                        isScrollable: true,
                        tabs: [
                          Tab(text: 'Quadro mensal'),
                          Tab(text: 'Jogadores e chaves'),
                          Tab(text: 'Resultados e multas'),
                          Tab(text: 'Ranking'),
                        ],
                      ),
                      SizedBox(
                        height: MediaQuery.sizeOf(context).height < 760 ? 560 : 650,
                        child: TabBarView(
                          children: [
                            _MonthlyBoard(
                              repository: _repository,
                              players: active,
                              charges: charges,
                              dates: drawDates,
                              onPayDraw: _repository.canOperateMoney ? _payDraw : null,
                              onPayMonth: _repository.canOperateMoney ? _payMonth : null,
                            ),
                            _PlayersView(
                              players: players,
                              canManage: _repository.canManage,
                              onEdit: _editPlayer,
                            ),
                            _ResultsAndFinesView(
                              dates: drawDates,
                              players: active,
                              results: results,
                              fines: fines,
                              prizes: prizes,
                              canOperate: _repository.canOperateMoney,
                              onProcess: _processResult,
                              onReceiveFines: _payFines,
                              onReceivePrize: _receivePrize,
                              onManualPrize: () => _manualPrize(active, results),
                            ),
                            _RankingView(players: active, fines: fines),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}

class _MonthlyBoard extends StatelessWidget {
  const _MonthlyBoard({
    required this.repository,
    required this.players,
    required this.charges,
    required this.dates,
    required this.onPayDraw,
    required this.onPayMonth,
  });

  final LotteryRepository repository;
  final List<Map<String, dynamic>> players;
  final List<Map<String, dynamic>> charges;
  final List<DateTime> dates;
  final Future<void> Function(Map<String, dynamic>)? onPayDraw;
  final Future<void> Function(Map<String, dynamic>)? onPayMonth;

  @override
  Widget build(BuildContext context) {
    if (players.isEmpty) {
      return const Center(child: Text('Ainda não existem jogadores ativos neste mês.'));
    }
    return SingleChildScrollView(
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: DataTable(
          columnSpacing: MediaQuery.sizeOf(context).width < 700 ? 14 : 24,
          columns: [
            const DataColumn(label: Text('Jogador')),
            for (final date in dates)
              DataColumn(
                label: Text('${_weekday(date)}\n${date.day.toString().padLeft(2, '0')}'),
              ),
            const DataColumn(label: Text('Mês')),
          ],
          rows: players.map((player) {
            final playerId = player['player_id']?.toString();
            return DataRow(cells: [
              DataCell(
                SizedBox(
                  width: 125,
                  child: Text(
                    player['member_name']?.toString() ?? 'Membro',
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ),
              for (final date in dates)
                DataCell(_paymentCell(playerId, date)),
              DataCell(
                onPayMonth == null
                    ? const Icon(Icons.calendar_month_outlined)
                    : IconButton(
                        tooltip: 'Liquidar mês completo',
                        onPressed: () => onPayMonth!(player),
                        icon: const Icon(Icons.payments_outlined),
                      ),
              ),
            ]);
          }).toList(),
        ),
      ),
    );
  }

  Widget _paymentCell(String? playerId, DateTime drawDate) {
    final draw = _dateOnly(drawDate);
    Map<String, dynamic>? charge;
    for (final row in charges) {
      if (row['player_id']?.toString() == playerId &&
          row['draw_date']?.toString() == draw) {
        charge = row;
        break;
      }
    }
    if (charge == null) return const Text('—');
    final paid = _asDouble(charge['paid_amount']) >= _asDouble(charge['amount']);
    if (paid) {
      return const Tooltip(
        message: 'Sorteio liquidado',
        child: Icon(Icons.check_circle, color: Colors.green),
      );
    }
    if (onPayDraw == null) return const Icon(Icons.cancel, color: Colors.red);
    final current = charge;
    return IconButton(
      tooltip: 'Registar pagamento deste sorteio',
      onPressed: () => onPayDraw!(current),
      icon: const Icon(Icons.cancel, color: Colors.red),
    );
  }
}

class _PlayersView extends StatelessWidget {
  const _PlayersView({
    required this.players,
    required this.canManage,
    required this.onEdit,
  });

  final List<Map<String, dynamic>> players;
  final bool canManage;
  final Future<void> Function(Map<String, dynamic>) onEdit;

  @override
  Widget build(BuildContext context) {
    return ListView.builder(
      padding: const EdgeInsets.only(top: 8),
      itemCount: players.length,
      itemBuilder: (context, index) {
        final player = players[index];
        final status = player['status']?.toString() ?? 'non_player';
        return Card(
          child: ListTile(
            leading: CircleAvatar(child: Text(_statusIcon(status))),
            title: Text(player['member_name']?.toString() ?? 'Membro'),
            subtitle: Text(
              '${_statusLabel(status)}\n'
              'Números: ${_notEmpty(player['numbers_text'])} • Estrelas: ${_notEmpty(player['stars_text'])}',
            ),
            isThreeLine: true,
            trailing: canManage
                ? IconButton(
                    tooltip: 'Editar jogador e chave',
                    onPressed: () => onEdit(player),
                    icon: const Icon(Icons.edit_outlined),
                  )
                : null,
          ),
        );
      },
    );
  }
}

class _ResultsAndFinesView extends StatelessWidget {
  const _ResultsAndFinesView({
    required this.dates,
    required this.players,
    required this.results,
    required this.fines,
    required this.prizes,
    required this.canOperate,
    required this.onProcess,
    required this.onReceiveFines,
    required this.onReceivePrize,
    required this.onManualPrize,
  });

  final List<DateTime> dates;
  final List<Map<String, dynamic>> players;
  final List<Map<String, dynamic>> results;
  final List<Map<String, dynamic>> fines;
  final List<Map<String, dynamic>> prizes;
  final bool canOperate;
  final Future<void> Function(DateTime) onProcess;
  final Future<void> Function(Map<String, dynamic>, double) onReceiveFines;
  final Future<void> Function(Map<String, dynamic>) onReceivePrize;
  final VoidCallback onManualPrize;

  @override
  Widget build(BuildContext context) {
    final debtRows = <Map<String, dynamic>>[];
    for (final player in players) {
      final playerId = player['player_id']?.toString();
      final playerFines = fines.where((f) => f['player_id']?.toString() == playerId);
      final total = playerFines.fold<double>(0, (s, f) => s + _asDouble(f['fine_amount']));
      final paid = playerFines.fold<double>(0, (s, f) => s + _asDouble(f['paid_amount']));
      final debt = (total - paid).clamp(0, double.infinity);
      if (total > 0) {
        debtRows.add({'player': player, 'total': total, 'paid': paid, 'debt': debt});
      }
    }

    return ListView(
      padding: const EdgeInsets.only(top: 8),
      children: [
        if (canOperate)
          Align(
            alignment: Alignment.centerRight,
            child: FilledButton.tonalIcon(
              onPressed: onManualPrize,
              icon: const Icon(Icons.emoji_events_outlined),
              label: const Text('Registar prémio manual'),
            ),
          ),
        if (debtRows.isNotEmpty) ...[
          const ListTile(
            leading: Icon(Icons.payments_outlined),
            title: Text('Multas do mês'),
            subtitle: Text('Recebimentos das multas separados da conta de apostas.'),
          ),
          for (final row in debtRows)
            Card(
              child: ListTile(
                title: Text(
                  (row['player'] as Map)['member_name']?.toString() ?? 'Membro',
                ),
                subtitle: Text(
                  'Apurado ${_money(row['total'])} • Pago ${_money(row['paid'])}',
                ),
                trailing: (row['debt'] as double) > 0
                    ? canOperate
                        ? FilledButton.tonal(
                            onPressed: () => onReceiveFines(
                              Map<String, dynamic>.from(row['player'] as Map),
                              row['debt'] as double,
                            ),
                            child: Text('Receber ${_money(row['debt'])}'),
                          )
                        : Text('Dívida ${_money(row['debt'])}')
                    : const Chip(label: Text('Liquidado')),
              ),
            ),
          const Divider(height: 24),
        ],
        ...dates.map((date) {
          final iso = _dateOnly(date);
          Map<String, dynamic>? result;
          for (final row in results) {
            if (row['draw_date']?.toString() == iso) {
              result = row;
              break;
            }
          }
          final resultId = result?['id']?.toString();
          final resultFines = fines
              .where((row) => row['result_id']?.toString() == resultId)
              .toList();
          final resultPrizes = prizes
              .where((row) => row['result_id']?.toString() == resultId)
              .toList();
          final localResult = result;

          return Card(
            child: ExpansionTile(
              leading: const Icon(Icons.casino_outlined),
              title: Text('${_weekday(date)} ${date.day.toString().padLeft(2, '0')}'),
              subtitle: localResult == null
                  ? const Text('Resultado ainda não registado')
                  : Text(
                      '${localResult['source'] == 'jogossantacasa.pt' ? 'Oficial' : 'Manual'}'
                      '${_notEmpty(localResult['official_draw_number']) == '—' ? '' : ' • Sorteio ${localResult['official_draw_number']}'}\n'
                      'Números: ${_listText(localResult['numbers'])} • Estrelas: ${_listText(localResult['stars'])}',
                    ),
              trailing: canOperate
                  ? IconButton(
                      tooltip: localResult == null ? 'Registar resultado' : 'Editar resultado',
                      onPressed: () => onProcess(date),
                      icon: Icon(
                        localResult == null
                            ? Icons.add_circle_outline
                            : Icons.edit_outlined,
                      ),
                    )
                  : null,
              children: localResult == null
                  ? const [
                      Padding(
                        padding: EdgeInsets.all(16),
                        child: Text('Sem comparação enquanto o resultado não estiver registado.'),
                      ),
                    ]
                  : players.map((player) {
                      final playerId = player['player_id']?.toString();
                      Map<String, dynamic>? fine;
                      for (final row in resultFines) {
                        if (row['player_id']?.toString() == playerId) fine = row;
                      }
                      Map<String, dynamic>? prize;
                      for (final row in resultPrizes) {
                        if (row['player_id']?.toString() == playerId) prize = row;
                      }
                      final resultNumbers = _intList(localResult['numbers']).toSet();
                      final resultStars = _intList(localResult['stars']).toSet();
                      final prizePending = prize == null
                          ? 0.0
                          : (_asDouble(prize['prize_amount']) -
                                  _asDouble(prize['received_amount']))
                              .clamp(0, double.infinity);
                      return Padding(
                        padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              player['member_name']?.toString() ?? 'Membro',
                              style: Theme.of(context).textTheme.titleMedium,
                            ),
                            const SizedBox(height: 6),
                            Wrap(
                              spacing: 6,
                              runSpacing: 6,
                              children: [
                                for (final n in _intList(player['numbers']))
                                  _NumberChip(value: '$n', hit: resultNumbers.contains(n)),
                                for (final s in _intList(player['stars']))
                                  _NumberChip(value: '★$s', hit: resultStars.contains(s)),
                              ],
                            ),
                            const SizedBox(height: 8),
                            Wrap(
                              spacing: 8,
                              runSpacing: 8,
                              crossAxisAlignment: WrapCrossAlignment.center,
                              children: [
                                Chip(
                                  label: Text(
                                    fine == null
                                        ? 'Sem multa'
                                        : 'Multa ${_money(fine['fine_amount'])}',
                                  ),
                                ),
                                if (prize != null)
                                  Chip(
                                    avatar: const Icon(Icons.emoji_events_outlined, size: 18),
                                    label: Text(
                                      'Prémio ${_money(prize['prize_amount'])} • ${prize['category']}.º',
                                    ),
                                  ),
                                if (prize != null && prizePending > 0 && canOperate)
                                  FilledButton.tonalIcon(
                                    onPressed: () => onReceivePrize(prize!),
                                    icon: const Icon(Icons.payments_outlined),
                                    label: Text('Receber ${_money(prizePending)}'),
                                  ),
                                if (prize != null && prizePending == 0)
                                  const Chip(label: Text('Prémio recebido')),
                              ],
                            ),
                            const Divider(height: 20),
                          ],
                        ),
                      );
                    }).toList(),
            ),
          );
        }),
      ],
    );
  }
}

class _RankingView extends StatelessWidget {
  const _RankingView({required this.players, required this.fines});

  final List<Map<String, dynamic>> players;
  final List<Map<String, dynamic>> fines;

  @override
  Widget build(BuildContext context) {
    final rows = players.map((player) {
      final id = player['player_id']?.toString();
      final pf = fines.where((f) => f['player_id']?.toString() == id);
      final total = pf.fold<double>(0, (s, f) => s + _asDouble(f['fine_amount']));
      final misses = pf.fold<int>(
        0,
        (s, f) =>
            s +
            (int.tryParse(f['missed_numbers']?.toString() ?? '') ?? 0) +
            (int.tryParse(f['missed_stars']?.toString() ?? '') ?? 0),
      );
      return {'name': player['member_name'], 'fine': total, 'misses': misses};
    }).toList()
      ..sort((a, b) => (a['fine'] as double).compareTo(b['fine'] as double));

    if (rows.isEmpty) return const Center(child: Text('Sem jogadores ativos.'));
    return ListView(
      padding: const EdgeInsets.only(top: 8),
      children: [
        const ListTile(
          leading: Icon(Icons.emoji_events_outlined),
          title: Text('Ranking de pontaria'),
          subtitle: Text('Menor valor de multas = mais acertos.'),
        ),
        for (var i = 0; i < rows.length; i++)
          Card(
            child: ListTile(
              leading: CircleAvatar(child: Text('${i + 1}º')),
              title: Text(rows[i]['name']?.toString() ?? 'Membro'),
              subtitle: Text('${rows[i]['misses']} elementos falhados'),
              trailing: Text(_money(rows[i]['fine'])),
            ),
          ),
        if (rows.length > 1)
          Card(
            child: ListTile(
              leading: const Text('🤣', style: TextStyle(fontSize: 26)),
              title: const Text('Mais azarado do mês'),
              subtitle: Text(rows.last['name']?.toString() ?? 'Membro'),
              trailing: Text(_money(rows.last['fine'])),
            ),
          ),
      ],
    );
  }
}

class _ManualPrizeDialog extends StatefulWidget {
  const _ManualPrizeDialog({
    required this.players,
    required this.results,
    required this.extra,
  });

  final List<Map<String, dynamic>> players;
  final List<Map<String, dynamic>> results;
  final LotteryExtraRepository extra;

  @override
  State<_ManualPrizeDialog> createState() => _ManualPrizeDialogState();
}

class _ManualPrizeDialogState extends State<_ManualPrizeDialog> {
  String? _playerId;
  String? _resultId;
  String _method = 'Transferência bancária';
  int _category = 13;
  final _amount = TextEditingController();
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _playerId = widget.players.first['player_id']?.toString();
    _resultId = widget.results.last['id']?.toString();
  }

  @override
  void dispose() {
    _amount.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final amount = double.tryParse(_amount.text.replaceAll(',', '.'));
    if (_playerId == null || _resultId == null || amount == null || amount <= 0) return;
    setState(() => _saving = true);
    try {
      await widget.extra.registerManualPrize(
        resultId: _resultId!,
        playerId: _playerId!,
        amount: amount,
        paymentMethod: _method,
        category: _category,
      );
      if (mounted) Navigator.pop(context, true);
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$error')));
      setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Registar prémio manual'),
      content: SizedBox(
        width: 430,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              DropdownButtonFormField<String>(
                initialValue: _playerId,
                decoration: const InputDecoration(labelText: 'Jogador'),
                items: widget.players
                    .map(
                      (p) => DropdownMenuItem(
                        value: p['player_id']?.toString(),
                        child: Text(p['member_name']?.toString() ?? 'Membro'),
                      ),
                    )
                    .toList(),
                onChanged: (v) => setState(() => _playerId = v),
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<String>(
                initialValue: _resultId,
                decoration: const InputDecoration(labelText: 'Sorteio'),
                items: widget.results
                    .map(
                      (r) => DropdownMenuItem(
                        value: r['id']?.toString(),
                        child: Text(
                          '${r['draw_date']} • ${_notEmpty(r['official_draw_number'])}',
                        ),
                      ),
                    )
                    .toList(),
                onChanged: (v) => setState(() => _resultId = v),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _amount,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                decoration: const InputDecoration(labelText: 'Valor recebido (€)'),
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<int>(
                initialValue: _category,
                decoration: const InputDecoration(labelText: 'Categoria'),
                items: [
                  for (var i = 1; i <= 13; i++)
                    DropdownMenuItem(value: i, child: Text('$i.º prémio')),
                ],
                onChanged: (v) => setState(() => _category = v ?? _category),
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<String>(
                initialValue: _method,
                decoration: const InputDecoration(labelText: 'Método'),
                items: const [
                  'Transferência bancária',
                  'MB Way',
                  'Dinheiro',
                ]
                    .map((v) => DropdownMenuItem(value: v, child: Text(v)))
                    .toList(),
                onChanged: (v) => setState(() => _method = v ?? _method),
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: _saving ? null : () => Navigator.pop(context, false),
          child: const Text('Cancelar'),
        ),
        FilledButton(
          onPressed: _saving ? null : _save,
          child: const Text('Registar recebimento'),
        ),
      ],
    );
  }
}

class _PlayerDialog extends StatefulWidget {
  const _PlayerDialog({required this.repository, required this.player});
  final LotteryRepository repository;
  final Map<String, dynamic> player;

  @override
  State<_PlayerDialog> createState() => _PlayerDialogState();
}

class _PlayerDialogState extends State<_PlayerDialog> {
  late String _status;
  late final TextEditingController _numbers;
  late final TextEditingController _stars;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _status = widget.player['status']?.toString() ?? 'non_player';
    _numbers = TextEditingController(text: widget.player['numbers_text']?.toString() ?? '');
    _stars = TextEditingController(text: widget.player['stars_text']?.toString() ?? '');
  }

  @override
  void dispose() {
    _numbers.dispose();
    _stars.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    setState(() => _saving = true);
    try {
      await widget.repository.updatePlayer(
        playerId: widget.player['player_id'].toString(),
        status: _status,
        numbers: _numbers.text,
        stars: _stars.text,
      );
      if (mounted) Navigator.pop(context, true);
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$error')));
      setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.player['member_name']?.toString() ?? 'Jogador'),
      content: SizedBox(
        width: 430,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            DropdownButtonFormField<String>(
              initialValue: _status,
              decoration: const InputDecoration(labelText: 'Estado'),
              items: const [
                DropdownMenuItem(value: 'active', child: Text('Ativo')),
                DropdownMenuItem(value: 'inactive', child: Text('Inativo')),
                DropdownMenuItem(value: 'non_player', child: Text('Não jogador')),
              ],
              onChanged: (v) => setState(() => _status = v ?? _status),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _numbers,
              decoration: const InputDecoration(labelText: '5 números da chave'),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _stars,
              decoration: const InputDecoration(labelText: '2 estrelas'),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: _saving ? null : () => Navigator.pop(context, false),
          child: const Text('Cancelar'),
        ),
        FilledButton(onPressed: _saving ? null : _save, child: const Text('Guardar')),
      ],
    );
  }
}

class _SettingsDialog extends StatefulWidget {
  const _SettingsDialog({
    required this.repository,
    required this.drawAmount,
    required this.finePerMiss,
  });
  final LotteryRepository repository;
  final double drawAmount;
  final double finePerMiss;

  @override
  State<_SettingsDialog> createState() => _SettingsDialogState();
}

class _SettingsDialogState extends State<_SettingsDialog> {
  late final TextEditingController _draw;
  late final TextEditingController _fine;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _draw = TextEditingController(text: widget.drawAmount.toStringAsFixed(2));
    _fine = TextEditingController(text: widget.finePerMiss.toStringAsFixed(2));
  }

  @override
  void dispose() {
    _draw.dispose();
    _fine.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final draw = double.tryParse(_draw.text.replaceAll(',', '.'));
    final fine = double.tryParse(_fine.text.replaceAll(',', '.'));
    if (draw == null || fine == null) return;
    setState(() => _saving = true);
    try {
      await widget.repository.saveSettings(drawAmount: draw, finePerMiss: fine);
      if (mounted) Navigator.pop(context, true);
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$error')));
      setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Configuração Euromilhões'),
      content: SizedBox(
        width: 420,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: _draw,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              decoration: const InputDecoration(labelText: 'Custo por sorteio / jogador (€)'),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _fine,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              decoration: const InputDecoration(labelText: 'Multa por elemento falhado (€)'),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: _saving ? null : () => Navigator.pop(context, false),
          child: const Text('Cancelar'),
        ),
        FilledButton(onPressed: _saving ? null : _save, child: const Text('Guardar')),
      ],
    );
  }
}

class _ResultDialog extends StatefulWidget {
  const _ResultDialog({required this.repository, required this.drawDate});
  final LotteryRepository repository;
  final DateTime drawDate;

  @override
  State<_ResultDialog> createState() => _ResultDialogState();
}

class _ResultDialogState extends State<_ResultDialog> {
  final _numbers = TextEditingController();
  final _stars = TextEditingController();
  bool _saving = false;

  @override
  void dispose() {
    _numbers.dispose();
    _stars.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    setState(() => _saving = true);
    try {
      await widget.repository.processResult(
        drawDate: widget.drawDate,
        numbers: _numbers.text,
        stars: _stars.text,
      );
      if (mounted) Navigator.pop(context, true);
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$error')));
      setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text('Resultado ${_datePt(widget.drawDate)}'),
      content: SizedBox(
        width: 420,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: _numbers,
              decoration: const InputDecoration(labelText: '5 números sorteados'),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _stars,
              decoration: const InputDecoration(labelText: '2 estrelas'),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: _saving ? null : () => Navigator.pop(context, false),
          child: const Text('Cancelar'),
        ),
        FilledButton(onPressed: _saving ? null : _save, child: const Text('Processar sorteio')),
      ],
    );
  }
}

class _NumberChip extends StatelessWidget {
  const _NumberChip({required this.value, required this.hit});
  final String value;
  final bool hit;

  @override
  Widget build(BuildContext context) {
    return Chip(
      avatar: Icon(
        hit ? Icons.check_circle : Icons.cancel,
        color: hit ? Colors.green : Colors.red,
        size: 18,
      ),
      label: Text(value),
    );
  }
}

class _MonthHeader extends StatelessWidget {
  const _MonthHeader({
    required this.month,
    required this.onPrevious,
    required this.onNext,
    required this.onCurrent,
  });
  final DateTime month;
  final VoidCallback onPrevious;
  final VoidCallback onNext;
  final VoidCallback onCurrent;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        IconButton(onPressed: onPrevious, icon: const Icon(Icons.chevron_left)),
        Expanded(
          child: Text(
            '${_monthNames[month.month - 1]} ${month.year}',
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.titleLarge,
          ),
        ),
        IconButton(onPressed: onNext, icon: const Icon(Icons.chevron_right)),
        TextButton(onPressed: onCurrent, child: const Text('Hoje')),
      ],
    );
  }
}

class _MetricCard extends StatelessWidget {
  const _MetricCard({required this.label, required this.value});
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: MediaQuery.sizeOf(context).width < 600 ? 165 : 205,
      child: Card(
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(value, style: Theme.of(context).textTheme.titleLarge),
              const SizedBox(height: 3),
              Text(label),
            ],
          ),
        ),
      ),
    );
  }
}

String _statusIcon(String status) => switch (status) {
      'active' => '🟢',
      'inactive' => '🟡',
      _ => '⚪',
    };

String _statusLabel(String status) => switch (status) {
      'active' => 'Ativo',
      'inactive' => 'Inativo',
      _ => 'Não jogador',
    };

String _weekday(DateTime date) => date.weekday == DateTime.tuesday ? 'Ter' : 'Sex';
String _dateOnly(DateTime date) =>
    '${date.year.toString().padLeft(4, '0')}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';
String _datePt(DateTime date) =>
    '${date.day.toString().padLeft(2, '0')}/${date.month.toString().padLeft(2, '0')}/${date.year}';
String _money(Object? value) =>
    '${_asDouble(value).toStringAsFixed(2).replaceAll('.', ',')} €';
String _listText(Object? value) => _intList(value).join(', ');
String _notEmpty(Object? value) {
  final text = value?.toString().trim() ?? '';
  return text.isEmpty ? '—' : text;
}

double _asDouble(Object? value) {
  if (value is num) return value.toDouble();
  return double.tryParse(value?.toString() ?? '') ?? 0;
}

List<int> _intList(Object? value) {
  if (value is List) {
    return value.map((item) => int.parse(item.toString())).toList();
  }
  return const [];
}

const _monthNames = [
  'Janeiro',
  'Fevereiro',
  'Março',
  'Abril',
  'Maio',
  'Junho',
  'Julho',
  'Agosto',
  'Setembro',
  'Outubro',
  'Novembro',
  'Dezembro',
];
