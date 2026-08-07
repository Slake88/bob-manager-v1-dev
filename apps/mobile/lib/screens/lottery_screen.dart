import 'package:flutter/material.dart';

import '../repositories/lottery_repository.dart';

class LotteryScreen extends StatefulWidget {
  const LotteryScreen({super.key});

  @override
  State<LotteryScreen> createState() => _LotteryScreenState();
}

class _LotteryScreenState extends State<LotteryScreen> {
  final LotteryRepository _repository = LotteryRepository();
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
        weeklyAmount: _asDouble(data['weekly_amount']),
        finePerMiss: _asDouble(data['fine_per_miss']),
      ),
    );
    if (changed == true && mounted) setState(_reload);
  }

  Future<void> _payWeek(Map<String, dynamic> charge) async {
    final method = await _paymentMethod();
    if (method == null) return;
    try {
      await _repository.payWeek(
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

  Future<void> _processResult(DateTime date) async {
    final changed = await showDialog<bool>(
      context: context,
      builder: (_) => _ResultDialog(
        repository: _repository,
        drawDate: date,
      ),
    );
    if (changed == true && mounted) setState(_reload);
  }

  Future<String?> _paymentMethod() {
    return showDialog<String>(
      context: context,
      builder: (context) => SimpleDialog(
        title: const Text('Método de pagamento'),
        children: [
          for (final method in const [
            'Transferência bancária',
            'MB Way',
            'Dinheiro',
          ])
            SimpleDialogOption(
              onPressed: () => Navigator.pop(context, method),
              child: Text(method),
            ),
        ],
      ),
    );
  }

  void _showError(Object error) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(error.toString().replaceFirst('Bad state: ', ''))),
    );
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
          final drawDates = _repository.drawDates(_month.year, _month.month);
          final weeklyAmount = _asDouble(data['weekly_amount']);
          final weeks = drawDates.map(_repository.weekStart).map(_dateOnly).toSet();
          final monthlyPerPlayer = weeks.length * weeklyAmount;
          final totalExpected = active.length * monthlyPerPlayer;
          final fineTotal = fines.fold<double>(
            0,
            (total, row) => total + _asDouble(row['fine_amount']),
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
                    _MetricCard(
                      label: 'Multas apuradas',
                      value: _money(fineTotal),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                if (_repository.canOperateMoney)
                  Align(
                    alignment: Alignment.centerRight,
                    child: OutlinedButton.icon(
                      onPressed: () => _configure(data),
                      icon: const Icon(Icons.tune),
                      label: const Text('Configurar'),
                    ),
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
                        height: 610,
                        child: TabBarView(
                          children: [
                            _MonthlyBoard(
                              repository: _repository,
                              players: active,
                              charges: charges,
                              dates: drawDates,
                              onPayWeek: _repository.canOperateMoney ? _payWeek : null,
                              onPayMonth: _repository.canOperateMoney ? _payMonth : null,
                            ),
                            _PlayersView(
                              players: players,
                              canManage: _repository.canManage,
                              onEdit: _editPlayer,
                            ),
                            _ResultsView(
                              dates: drawDates,
                              players: active,
                              results: results,
                              fines: fines,
                              canProcess: _repository.canOperateMoney,
                              onProcess: _processResult,
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
    required this.onPayWeek,
    required this.onPayMonth,
  });

  final LotteryRepository repository;
  final List<Map<String, dynamic>> players;
  final List<Map<String, dynamic>> charges;
  final List<DateTime> dates;
  final Future<void> Function(Map<String, dynamic>)? onPayWeek;
  final Future<void> Function(Map<String, dynamic>)? onPayMonth;

  @override
  Widget build(BuildContext context) {
    if (players.isEmpty) {
      return const Center(
        child: Text('Ainda não existem jogadores ativos neste mês.'),
      );
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        return SingleChildScrollView(
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: DataTable(
              columnSpacing: constraints.maxWidth < 700 ? 14 : 24,
              columns: [
                const DataColumn(label: Text('Jogador')),
                for (final date in dates)
                  DataColumn(label: Text('${_weekday(date)}\n${date.day.toString().padLeft(2, '0')}')),
                const DataColumn(label: Text('Mês')),
              ],
              rows: players.map((player) {
                final playerId = player['player_id']?.toString();
                return DataRow(
                  cells: [
                    DataCell(
                      SizedBox(
                        width: 130,
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
                  ],
                );
              }).toList(),
            ),
          ),
        );
      },
    );
  }

  Widget _paymentCell(String? playerId, DateTime drawDate) {
    final week = _dateOnly(repository.weekStart(drawDate));
    Map<String, dynamic>? charge;
    for (final row in charges) {
      if (row['player_id']?.toString() == playerId && row['week_start']?.toString() == week) {
        charge = row;
        break;
      }
    }
    if (charge == null) return const Text('—');
    final paid = _asDouble(charge['paid_amount']) >= _asDouble(charge['amount']);
    if (paid) {
      return const Tooltip(
        message: 'Semana liquidada',
        child: Icon(Icons.check_circle, color: Colors.green),
      );
    }
    if (onPayWeek == null) {
      return const Icon(Icons.cancel, color: Colors.red);
    }
    final current = charge;
    return IconButton(
      tooltip: 'Registar pagamento desta semana',
      onPressed: () => onPayWeek!(current!),
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
              'Números: ${player['numbers_text']?.toString().isEmpty == false ? player['numbers_text'] : '—'}  •  '
              'Estrelas: ${player['stars_text']?.toString().isEmpty == false ? player['stars_text'] : '—'}',
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

class _ResultsView extends StatelessWidget {
  const _ResultsView({
    required this.dates,
    required this.players,
    required this.results,
    required this.fines,
    required this.canProcess,
    required this.onProcess,
  });

  final List<DateTime> dates;
  final List<Map<String, dynamic>> players;
  final List<Map<String, dynamic>> results;
  final List<Map<String, dynamic>> fines;
  final bool canProcess;
  final Future<void> Function(DateTime) onProcess;

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.only(top: 8),
      children: dates.map((date) {
        final iso = _dateOnly(date);
        Map<String, dynamic>? result;
        for (final row in results) {
          if (row['draw_date']?.toString() == iso) {
            result = row;
            break;
          }
        }
        final resultId = result?['id']?.toString();
        final resultFines = fines.where((row) => row['result_id']?.toString() == resultId).toList();
        return Card(
          child: ExpansionTile(
            leading: const Icon(Icons.casino_outlined),
            title: Text('${_weekday(date)} ${date.day.toString().padLeft(2, '0')}'),
            subtitle: result == null
                ? const Text('Resultado ainda não registado')
                : Text(
                    'Números: ${_listText(result['numbers'])} • Estrelas: ${_listText(result['stars'])}',
                  ),
            trailing: canProcess
                ? IconButton(
                    tooltip: result == null ? 'Registar resultado' : 'Editar resultado',
                    onPressed: () => onProcess(date),
                    icon: Icon(result == null ? Icons.add_circle_outline : Icons.edit_outlined),
                  )
                : null,
            children: result == null
                ? const [
                    Padding(
                      padding: EdgeInsets.all(16),
                      child: Text('Sem comparação de chaves enquanto o resultado não for registado.'),
                    ),
                  ]
                : players.map((player) {
                    Map<String, dynamic>? fine;
                    for (final row in resultFines) {
                      if (row['player_id']?.toString() == player['player_id']?.toString()) {
                        fine = row;
                        break;
                      }
                    }
                    final resultNumbers = _intList(result!['numbers']).toSet();
                    final resultStars = _intList(result['stars']).toSet();
                    return ListTile(
                      title: Text(player['member_name']?.toString() ?? 'Membro'),
                      subtitle: Wrap(
                        spacing: 6,
                        runSpacing: 6,
                        children: [
                          for (final number in _intList(player['numbers']))
                            _NumberChip(value: '$number', hit: resultNumbers.contains(number)),
                          for (final star in _intList(player['stars']))
                            _NumberChip(value: '★$star', hit: resultStars.contains(star)),
                        ],
                      ),
                      trailing: Text(
                        fine == null ? '—' : _money(_asDouble(fine['fine_amount'])),
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                    );
                  }).toList(),
          ),
        );
      }).toList(),
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
      final playerId = player['player_id']?.toString();
      final playerFines = fines.where((row) => row['player_id']?.toString() == playerId);
      final totalFine = playerFines.fold<double>(0, (sum, row) => sum + _asDouble(row['fine_amount']));
      final misses = playerFines.fold<int>(
        0,
        (sum, row) => sum +
            (int.tryParse(row['missed_numbers']?.toString() ?? '') ?? 0) +
            (int.tryParse(row['missed_stars']?.toString() ?? '') ?? 0),
      );
      return {
        'name': player['member_name'],
        'fine': totalFine,
        'misses': misses,
      };
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
        for (var index = 0; index < rows.length; index++)
          Card(
            child: ListTile(
              leading: CircleAvatar(child: Text('${index + 1}º')),
              title: Text(rows[index]['name']?.toString() ?? 'Membro'),
              subtitle: Text('${rows[index]['misses']} elementos falhados'),
              trailing: Text(_money(rows[index]['fine'] as double)),
            ),
          ),
        const SizedBox(height: 12),
        if (rows.length > 1)
          Card(
            child: ListTile(
              leading: const Text('🤣', style: TextStyle(fontSize: 26)),
              title: const Text('Mais azarado do mês'),
              subtitle: Text(rows.last['name']?.toString() ?? 'Membro'),
              trailing: Text(_money(rows.last['fine'] as double)),
            ),
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
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$error')));
        setState(() => _saving = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.player['member_name']?.toString() ?? 'Jogador'),
      content: SizedBox(
        width: 430,
        child: SingleChildScrollView(
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
                onChanged: (value) => setState(() => _status = value ?? _status),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _numbers,
                decoration: const InputDecoration(
                  labelText: '5 números da chave',
                  hintText: '4, 12, 23, 37, 48',
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _stars,
                decoration: const InputDecoration(
                  labelText: '2 estrelas',
                  hintText: '3, 9',
                ),
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(onPressed: _saving ? null : () => Navigator.pop(context, false), child: const Text('Cancelar')),
        FilledButton(onPressed: _saving ? null : _save, child: const Text('Guardar')),
      ],
    );
  }
}

class _SettingsDialog extends StatefulWidget {
  const _SettingsDialog({
    required this.repository,
    required this.weeklyAmount,
    required this.finePerMiss,
  });

  final LotteryRepository repository;
  final double weeklyAmount;
  final double finePerMiss;

  @override
  State<_SettingsDialog> createState() => _SettingsDialogState();
}

class _SettingsDialogState extends State<_SettingsDialog> {
  late final TextEditingController _weekly;
  late final TextEditingController _fine;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _weekly = TextEditingController(text: widget.weeklyAmount.toStringAsFixed(2));
    _fine = TextEditingController(text: widget.finePerMiss.toStringAsFixed(2));
  }

  @override
  void dispose() {
    _weekly.dispose();
    _fine.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final weekly = double.tryParse(_weekly.text.replaceAll(',', '.'));
    final fine = double.tryParse(_fine.text.replaceAll(',', '.'));
    if (weekly == null || fine == null) return;
    setState(() => _saving = true);
    try {
      await widget.repository.saveSettings(weeklyAmount: weekly, finePerMiss: fine);
      if (mounted) Navigator.pop(context, true);
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$error')));
        setState(() => _saving = false);
      }
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
              controller: _weekly,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              decoration: const InputDecoration(labelText: 'Valor semanal por jogador (€)'),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _fine,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              decoration: const InputDecoration(labelText: 'Multa por elemento falhado (€)'),
            ),
            const SizedBox(height: 12),
            const Text('Sorteios: terça-feira e sexta-feira.'),
          ],
        ),
      ),
      actions: [
        TextButton(onPressed: _saving ? null : () => Navigator.pop(context, false), child: const Text('Cancelar')),
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
  final TextEditingController _numbers = TextEditingController();
  final TextEditingController _stars = TextEditingController();
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
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$error')));
        setState(() => _saving = false);
      }
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
              decoration: const InputDecoration(labelText: '5 números sorteados', hintText: '5, 12, 21, 33, 48'),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _stars,
              decoration: const InputDecoration(labelText: '2 estrelas', hintText: '2, 9'),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(onPressed: _saving ? null : () => Navigator.pop(context, false), child: const Text('Cancelar')),
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
      avatar: Icon(hit ? Icons.check_circle : Icons.cancel, color: hit ? Colors.green : Colors.red, size: 18),
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
      width: 205,
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
String _money(Object? value) => '${_asDouble(value).toStringAsFixed(2).replaceAll('.', ',')} €';
String _listText(Object? value) => _intList(value).join(', ');

double _asDouble(Object? value) {
  if (value is num) return value.toDouble();
  return double.tryParse(value?.toString() ?? '') ?? 0;
}

List<int> _intList(Object? value) {
  if (value is List) return value.map((item) => int.parse(item.toString())).toList();
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
