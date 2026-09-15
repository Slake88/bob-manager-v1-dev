import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../core/weekly_officer_rules.dart';
import '../repositories/weekly_officer_repository.dart';

class WeeklyOfficerScreen extends StatefulWidget {
  const WeeklyOfficerScreen({super.key});

  @override
  State<WeeklyOfficerScreen> createState() => _WeeklyOfficerScreenState();
}

class _WeeklyOfficerScreenState extends State<WeeklyOfficerScreen> {
  final WeeklyOfficerRepository _repository = WeeklyOfficerRepository();
  late int _year;
  late Future<_WeeklyOfficerData> _future;

  bool get _canManage => _repository.canManage;

  @override
  void initState() {
    super.initState();
    _year = DateTime.now().year;
    _reload();
  }

  void _reload() {
    _future = _load();
  }

  Future<_WeeklyOfficerData> _load() async {
    await _repository.ensureYear(_year);
    final values = await Future.wait([
      _repository.members(),
      _repository.listRotation(),
      _repository.listDinners(_year),
      _repository.listAbsences(_year),
      _repository.listSwaps(),
      _repository.currentMemberId(),
    ]);
    return _WeeklyOfficerData(
      members: List<Map<String, dynamic>>.from(values[0] as List),
      rotation: List<Map<String, dynamic>>.from(values[1] as List),
      dinners: List<Map<String, dynamic>>.from(values[2] as List),
      absences: List<Map<String, dynamic>>.from(values[3] as List),
      swaps: List<Map<String, dynamic>>.from(values[4] as List),
      currentMemberId: values[5] as String?,
    );
  }

  Future<void> _refresh() async {
    setState(_reload);
    await _future;
  }

  void _changeYear(int delta) {
    setState(() {
      _year += delta;
      _reload();
    });
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<_WeeklyOfficerData>(
      future: _future,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }
        if (snapshot.hasError) {
          return _ErrorState(
            message: _errorText(snapshot.error),
            onRetry: _refresh,
          );
        }
        final data = snapshot.data ?? _WeeklyOfficerData.empty();
        return DefaultTabController(
          length: 4,
          child: Column(
            children: [
              _yearHeader(data),
              const TabBar(
                isScrollable: true,
                tabs: [
                  Tab(icon: Icon(Icons.restaurant_outlined), text: 'Escala'),
                  Tab(icon: Icon(Icons.sync_alt_outlined), text: 'Rotação'),
                  Tab(icon: Icon(Icons.swap_horiz_outlined), text: 'Trocas'),
                  Tab(icon: Icon(Icons.history_outlined), text: 'Histórico'),
                ],
              ),
              Expanded(
                child: TabBarView(
                  children: [
                    _scheduleTab(data),
                    _rotationTab(data),
                    _swapsTab(data),
                    _historyTab(data),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _yearHeader(_WeeklyOfficerData data) {
    final next = data.nextRegularDinner;
    final counts = data.officialCounts;
    final activeIds = data.rotation
        .where((row) => row['enabled'] != false)
        .map((row) => row['member_id']?.toString())
        .whereType<String>()
        .toList();
    final activeCounts = activeIds.map((id) => counts[id] ?? 0).toList();
    final minCount =
        activeCounts.isEmpty ? 0 : activeCounts.reduce((a, b) => a < b ? a : b);
    final maxCount =
        activeCounts.isEmpty ? 0 : activeCounts.reduce((a, b) => a > b ? a : b);

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
      child: Column(
        children: [
          Row(
            children: [
              IconButton(
                tooltip: 'Ano anterior',
                onPressed: () => _changeYear(-1),
                icon: const Icon(Icons.chevron_left),
              ),
              Expanded(
                child: Text(
                  'Escala $_year',
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.w800,
                      ),
                ),
              ),
              IconButton(
                tooltip: 'Ano seguinte',
                onPressed: () => _changeYear(1),
                icon: const Icon(Icons.chevron_right),
              ),
              IconButton(
                tooltip: 'Atualizar',
                onPressed: _refresh,
                icon: const Icon(Icons.refresh),
              ),
            ],
          ),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const CircleAvatar(
                    child: Icon(Icons.restaurant_menu_outlined),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Próximo Oficial da Semana',
                          style: TextStyle(fontWeight: FontWeight.w800),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          next == null
                              ? 'Sem quinta-feira planeada.'
                              : '${_datePt(next['dinner_date'])} · '
                                  '${data.dinnerResponsible(next)}',
                        ),
                        const SizedBox(height: 4),
                        Text(
                          activeCounts.isEmpty
                              ? 'Sem membros na rotação.'
                              : 'Equidade anual: $minCount–$maxCount jantar(es) oficial(is) por membro.',
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                      ],
                    ),
                  ),
                  if (_canManage)
                    FilledButton.icon(
                      onPressed: () => _openDinnerDialog(data),
                      icon: const Icon(Icons.add),
                      label: const Text('Extra'),
                    ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _scheduleTab(_WeeklyOfficerData data) {
    final dinners = WeeklyOfficerRules.sortDinnersNearestFirst(data.dinners);
    if (dinners.isEmpty) {
      return RefreshIndicator(
        onRefresh: _refresh,
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          children: const [
            SizedBox(height: 120),
            Center(child: Text('Sem jantares neste ano.')),
          ],
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: _refresh,
      child: ListView.separated(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
        itemCount: dinners.length,
        separatorBuilder: (_, __) => const SizedBox(height: 8),
        itemBuilder: (context, index) {
          final row = dinners[index];
          final regular = row['dinner_kind']?.toString() == 'regular';
          final status = row['status']?.toString() ?? 'planned';
          final assignedToCurrent = data.currentMemberId != null &&
              row['assigned_member_id']?.toString() == data.currentMemberId &&
              status == 'planned' &&
              _dateFrom(row['dinner_date'])
                  .isAfter(DateTime.now().subtract(const Duration(days: 1)));

          return Card(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(14, 12, 8, 12),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SizedBox(
                    width: 62,
                    child: Column(
                      children: [
                        Text(
                          DateFormat('dd', 'pt_PT')
                              .format(_dateFrom(row['dinner_date'])),
                          style: Theme.of(context)
                              .textTheme
                              .headlineSmall
                              ?.copyWith(
                                fontWeight: FontWeight.w900,
                              ),
                        ),
                        Text(
                          DateFormat('MMM', 'pt_PT')
                              .format(_dateFrom(row['dinner_date']))
                              .toUpperCase(),
                          style: Theme.of(context).textTheme.labelSmall,
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Wrap(
                          spacing: 6,
                          runSpacing: 4,
                          children: [
                            Chip(
                              visualDensity: VisualDensity.compact,
                              label: Text(regular
                                  ? 'Quinta oficial'
                                  : 'Extraordinário'),
                            ),
                            Chip(
                              visualDensity: VisualDensity.compact,
                              label: Text(
                                WeeklyOfficerRules.dinnerStatusLabel(status),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 4),
                        Text(
                          data.dinnerResponsible(row),
                          style: const TextStyle(fontWeight: FontWeight.w800),
                        ),
                        if ((row['dish']?.toString().trim() ?? '').isNotEmpty)
                          Text('Jantar: ${row['dish']}'),
                        if ((row['notes']?.toString().trim() ?? '').isNotEmpty)
                          Text(
                            row['notes'].toString(),
                            style: Theme.of(context).textTheme.bodySmall,
                          ),
                        if (assignedToCurrent && data.currentMemberId != null)
                          Padding(
                            padding: const EdgeInsets.only(top: 8),
                            child: OutlinedButton.icon(
                              onPressed: () => _requestSwap(data, row),
                              icon: const Icon(Icons.swap_horiz),
                              label: const Text('Pedir troca'),
                            ),
                          ),
                      ],
                    ),
                  ),
                  if (_canManage)
                    PopupMenuButton<String>(
                      onSelected: (action) async {
                        if (action == 'edit') {
                          await _openDinnerDialog(data, row);
                        } else if (action == 'close') {
                          await _setDinnerClosed(row, true);
                        } else if (action == 'reopen') {
                          await _setDinnerClosed(row, false);
                        }
                      },
                      itemBuilder: (_) => [
                        if (status != 'closed')
                          const PopupMenuItem(
                            value: 'edit',
                            child: Text('Editar'),
                          ),
                        if (regular && status != 'closed')
                          const PopupMenuItem(
                            value: 'close',
                            child: Text('Marcar quinta como fechada'),
                          ),
                        if (regular && status == 'closed')
                          const PopupMenuItem(
                            value: 'reopen',
                            child: Text('Reabrir quinta-feira'),
                          ),
                      ],
                    ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _rotationTab(_WeeklyOfficerData data) {
    if (data.rotation.isEmpty) {
      return const Center(child: Text('Sem membros na rotação.'));
    }
    final counts = data.officialCounts;
    return RefreshIndicator(
      onRefresh: _refresh,
      child: ListView.builder(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
        itemCount: data.rotation.length,
        itemBuilder: (context, index) {
          final row = data.rotation[index];
          final memberId = row['member_id']?.toString() ?? '';
          final member = data.memberById[memberId];
          final absences = data.absences
              .where((a) => a['member_id']?.toString() == memberId)
              .toList();
          final enabled = row['enabled'] != false;
          final status = row['availability_status']?.toString() ?? 'active';
          final force = row['force_included'] == true;

          return Card(
            margin: const EdgeInsets.only(bottom: 8),
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                children: [
                  Row(
                    children: [
                      CircleAvatar(
                        child: Text('${index + 1}'),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              WeeklyOfficerRules.displayMember(member),
                              style:
                                  const TextStyle(fontWeight: FontWeight.w800),
                            ),
                            Text(
                              '${member?['primary_role'] ?? 'Membro'} · '
                              '${counts[memberId] ?? 0} oficial(is)',
                              style: Theme.of(context).textTheme.bodySmall,
                            ),
                          ],
                        ),
                      ),
                      if (!enabled)
                        const Chip(
                          visualDensity: VisualDensity.compact,
                          label: Text('Excluído'),
                        )
                      else if (force)
                        const Chip(
                          visualDensity: VisualDensity.compact,
                          label: Text('Forçado'),
                        )
                      else if (status != 'active')
                        Chip(
                          visualDensity: VisualDensity.compact,
                          label: Text(
                            WeeklyOfficerRules.availabilityLabel(status),
                          ),
                        ),
                      if (_canManage) ...[
                        IconButton(
                          tooltip: 'Subir',
                          onPressed: index == 0
                              ? null
                              : () => _moveRotation(data, index, -1),
                          icon: const Icon(Icons.arrow_upward),
                        ),
                        IconButton(
                          tooltip: 'Descer',
                          onPressed: index == data.rotation.length - 1
                              ? null
                              : () => _moveRotation(data, index, 1),
                          icon: const Icon(Icons.arrow_downward),
                        ),
                        PopupMenuButton<String>(
                          onSelected: (action) async {
                            if (action == 'settings') {
                              await _editRotationMember(data, row);
                            } else if (action == 'absence') {
                              await _addAbsence(data, memberId);
                            }
                          },
                          itemBuilder: (_) => const [
                            PopupMenuItem(
                              value: 'settings',
                              child: Text('Disponibilidade / inclusão'),
                            ),
                            PopupMenuItem(
                              value: 'absence',
                              child: Text('Adicionar férias / ausência'),
                            ),
                          ],
                        ),
                      ],
                    ],
                  ),
                  if (absences.isNotEmpty) ...[
                    const Divider(),
                    ...absences.map(
                      (absence) => Row(
                        children: [
                          Icon(
                            absence['absence_kind'] == 'vacation'
                                ? Icons.beach_access_outlined
                                : Icons.event_busy_outlined,
                            size: 18,
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              '${absence['absence_kind'] == 'vacation' ? 'Férias' : 'Ausência'}: '
                              '${_datePt(absence['starts_on'])}–${_datePt(absence['ends_on'])}',
                              style: Theme.of(context).textTheme.bodySmall,
                            ),
                          ),
                          if (_canManage)
                            IconButton(
                              tooltip: 'Remover período',
                              visualDensity: VisualDensity.compact,
                              onPressed: () => _deleteAbsence(absence),
                              icon: const Icon(Icons.delete_outline, size: 18),
                            ),
                        ],
                      ),
                    ),
                  ],
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _swapsTab(_WeeklyOfficerData data) {
    final ownUpcoming = data.currentMemberUpcomingDinners;

    return RefreshIndicator(
      onRefresh: _refresh,
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
        children: [
          _swapStartCard(data, ownUpcoming),
          const SizedBox(height: 8),
          if (data.swaps.isEmpty)
            const Card(
              child: Padding(
                padding: EdgeInsets.all(20),
                child: Center(child: Text('Sem pedidos de troca.')),
              ),
            )
          else
            ...data.swaps.map((row) {
              final requesterId = row['requester_member_id']?.toString() ?? '';
              final requestedId = row['requested_member_id']?.toString() ?? '';
              final dinnerId = row['dinner_id']?.toString() ?? '';
              final dinner = data.dinnerById[dinnerId];
              final status = row['status']?.toString() ?? 'pending';
              final isRecipient = data.currentMemberId == requestedId;
              final isRequester = data.currentMemberId == requesterId;

              return Card(
                margin: const EdgeInsets.only(bottom: 8),
                child: Padding(
                  padding: const EdgeInsets.all(14),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              '${WeeklyOfficerRules.displayMember(data.memberById[requesterId])} → '
                              '${WeeklyOfficerRules.displayMember(data.memberById[requestedId])}',
                              style:
                                  const TextStyle(fontWeight: FontWeight.w800),
                            ),
                          ),
                          Chip(
                            visualDensity: VisualDensity.compact,
                            label: Text(
                              WeeklyOfficerRules.swapStatusLabel(status),
                            ),
                          ),
                        ],
                      ),
                      Text(
                        dinner == null
                            ? 'Jantar não disponível'
                            : 'Jantar de ${_datePt(dinner['dinner_date'])}',
                      ),
                      if ((row['requester_note']?.toString().trim() ?? '')
                          .isNotEmpty)
                        Text('Nota: ${row['requester_note']}'),
                      if ((row['response_note']?.toString().trim() ?? '')
                          .isNotEmpty)
                        Text('Resposta: ${row['response_note']}'),
                      if (status == 'accepted')
                        Padding(
                          padding: const EdgeInsets.only(top: 6),
                          child: Text(
                            'A aceitação não altera automaticamente a escala. '
                            'Presidente/Vice-Presidente devem fazer a alteração efetiva.',
                            style: Theme.of(context).textTheme.bodySmall,
                          ),
                        ),
                      const SizedBox(height: 8),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          if (status == 'pending' && isRecipient)
                            FilledButton.icon(
                              onPressed: () => _respondSwap(row, true),
                              icon: const Icon(Icons.check),
                              label: const Text('Aceitar'),
                            ),
                          if (status == 'pending' && isRecipient)
                            OutlinedButton.icon(
                              onPressed: () => _respondSwap(row, false),
                              icon: const Icon(Icons.close),
                              label: const Text('Recusar'),
                            ),
                          if (status == 'pending' &&
                              (isRequester || _canManage))
                            TextButton.icon(
                              onPressed: () => _cancelSwap(row),
                              icon: const Icon(Icons.cancel_outlined),
                              label: const Text('Cancelar'),
                            ),
                          if (status == 'accepted' && _canManage)
                            FilledButton.tonalIcon(
                              onPressed: () => _markSwapApplied(row),
                              icon: const Icon(Icons.done_all),
                              label: const Text('Marcar como aplicada'),
                            ),
                        ],
                      ),
                    ],
                  ),
                ),
              );
            }),
        ],
      ),
    );
  }

  Widget _swapStartCard(
    _WeeklyOfficerData data,
    List<Map<String, dynamic>> ownUpcoming,
  ) {
    final currentMemberId = data.currentMemberId;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const CircleAvatar(child: Icon(Icons.swap_horiz)),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Novo pedido de troca',
                    style: TextStyle(fontWeight: FontWeight.w800),
                  ),
                  const SizedBox(height: 4),
                  if (currentMemberId == null)
                    const Text(
                      'Esta conta não está ligada a uma ficha de membro. '
                      'O pedido de troca é feito pelo membro responsável pelo '
                      'jantar, através da sua própria conta.',
                    )
                  else if (ownUpcoming.isEmpty)
                    const Text(
                      'Não tens nenhum jantar futuro planeado atribuído a ti.',
                    )
                  else
                    Text(
                      ownUpcoming.length == 1
                          ? 'Tens 1 jantar futuro que pode ser trocado.'
                          : 'Tens ${ownUpcoming.length} jantares futuros que podem ser trocados.',
                    ),
                ],
              ),
            ),
            if (currentMemberId != null && ownUpcoming.isNotEmpty)
              FilledButton.icon(
                onPressed: () => _startSwapFromTab(data, ownUpcoming),
                icon: const Icon(Icons.add),
                label: const Text('Pedir troca'),
              ),
          ],
        ),
      ),
    );
  }

  Future<void> _startSwapFromTab(
    _WeeklyOfficerData data,
    List<Map<String, dynamic>> ownUpcoming,
  ) async {
    if (ownUpcoming.length == 1) {
      await _requestSwap(data, ownUpcoming.first);
      return;
    }

    final selected = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (dialogContext) => SimpleDialog(
        title: const Text('Qual jantar queres trocar?'),
        children: ownUpcoming
            .map(
              (dinner) => SimpleDialogOption(
                onPressed: () => Navigator.pop(dialogContext, dinner),
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 6),
                  child: Text(
                    '${_datePt(dinner['dinner_date'])} · '
                    '${data.dinnerResponsible(dinner)}',
                  ),
                ),
              ),
            )
            .toList(),
      ),
    );

    if (selected != null && mounted) {
      await _requestSwap(data, selected);
    }
  }

  Widget _historyTab(_WeeklyOfficerData data) {
    final counts = data.officialCounts;
    return RefreshIndicator(
      onRefresh: _refresh,
      child: ListView.builder(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
        itemCount: data.rotation.length,
        itemBuilder: (context, index) {
          final rotation = data.rotation[index];
          final memberId = rotation['member_id']?.toString() ?? '';
          final member = data.memberById[memberId];
          final official = data.dinners
              .where(
                (d) =>
                    WeeklyOfficerRules.countsAsOfficialDinner(d) &&
                    d['assigned_member_id']?.toString() == memberId,
              )
              .toList()
            ..sort(
              (a, b) => _dateFrom(a['dinner_date'])
                  .compareTo(_dateFrom(b['dinner_date'])),
            );
          final extras = data.dinners.where(
            (d) =>
                d['dinner_kind'] == 'extraordinary' &&
                d['assigned_member_id']?.toString() == memberId &&
                d['status'] != 'cancelled',
          );
          final completed =
              official.where((d) => d['status'] == 'completed').toList();
          final future = official.where(
            (d) => !_dateFrom(d['dinner_date']).isBefore(DateTime(
                DateTime.now().year, DateTime.now().month, DateTime.now().day)),
          );

          return Card(
            margin: const EdgeInsets.only(bottom: 8),
            child: ListTile(
              leading: CircleAvatar(child: Text('${counts[memberId] ?? 0}')),
              title: Text(WeeklyOfficerRules.displayMember(member)),
              subtitle: Text(
                'Oficiais: ${counts[memberId] ?? 0} · Extras: ${extras.length}'
                '${completed.isEmpty ? '' : ' · Último concluído: ${_datePt(completed.last['dinner_date'])}'}'
                '${future.isEmpty ? '' : ' · Próximo: ${_datePt(future.first['dinner_date'])}'}',
              ),
            ),
          );
        },
      ),
    );
  }

  Future<void> _moveRotation(
    _WeeklyOfficerData data,
    int index,
    int delta,
  ) async {
    final target = index + delta;
    if (target < 0 || target >= data.rotation.length) return;
    final ids = data.rotation
        .map((row) => row['member_id']?.toString() ?? '')
        .where((id) => id.isNotEmpty)
        .toList();
    final item = ids.removeAt(index);
    ids.insert(target, item);
    try {
      await _repository.reorder(ids);
      if (!mounted) return;
      _message('Ordem atualizada. A escala futura foi recalculada.');
      await _refresh();
    } catch (error) {
      if (mounted) _message(_errorText(error), error: true);
    }
  }

  Future<void> _editRotationMember(
    _WeeklyOfficerData data,
    Map<String, dynamic> row,
  ) async {
    final memberId = row['member_id']?.toString() ?? '';
    final member = data.memberById[memberId];
    bool enabled = row['enabled'] != false;
    bool forceIncluded = row['force_included'] == true;
    String availability = row['availability_status']?.toString() ?? 'active';
    final notes = TextEditingController(text: row['notes']?.toString() ?? '');
    bool saving = false;

    final saved = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: Text(WeeklyOfficerRules.displayMember(member)),
          content: SizedBox(
            width: 480,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Incluído na rotação'),
                  value: enabled,
                  onChanged: saving
                      ? null
                      : (value) => setDialogState(() => enabled = value),
                ),
                DropdownButtonFormField<String>(
                  initialValue: availability,
                  decoration:
                      const InputDecoration(labelText: 'Disponibilidade'),
                  items: const [
                    DropdownMenuItem(value: 'active', child: Text('Ativo')),
                    DropdownMenuItem(value: 'absent', child: Text('Ausente')),
                    DropdownMenuItem(value: 'inactive', child: Text('Inativo')),
                  ],
                  onChanged: saving
                      ? null
                      : (value) {
                          if (value != null) {
                            setDialogState(() => availability = value);
                          }
                        },
                ),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Inclusão forçada'),
                  subtitle: const Text(
                    'Ignora exclusão/indisponibilidade para a escala.',
                  ),
                  value: forceIncluded,
                  onChanged: saving
                      ? null
                      : (value) => setDialogState(() => forceIncluded = value),
                ),
                TextField(
                  controller: notes,
                  decoration: const InputDecoration(labelText: 'Observações'),
                  minLines: 2,
                  maxLines: 4,
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed:
                  saving ? null : () => Navigator.pop(dialogContext, false),
              child: const Text('Cancelar'),
            ),
            FilledButton(
              onPressed: saving
                  ? null
                  : () async {
                      setDialogState(() => saving = true);
                      try {
                        await _repository.setMemberSettings(
                          memberId: memberId,
                          enabled: enabled,
                          availabilityStatus: availability,
                          forceIncluded: forceIncluded,
                          notes: notes.text,
                        );
                        if (dialogContext.mounted) {
                          Navigator.pop(dialogContext, true);
                        }
                      } catch (error) {
                        if (dialogContext.mounted) {
                          ScaffoldMessenger.of(dialogContext).showSnackBar(
                            SnackBar(content: Text(_errorText(error))),
                          );
                          setDialogState(() => saving = false);
                        }
                      }
                    },
              child: const Text('Guardar'),
            ),
          ],
        ),
      ),
    );
    if (saved == true && mounted) await _refresh();
  }

  Future<void> _addAbsence(_WeeklyOfficerData data, String memberId) async {
    String kind = 'vacation';
    DateTime starts = DateTime.now();
    DateTime ends = DateTime.now();
    final notes = TextEditingController();
    bool saving = false;

    final saved = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('Férias / ausência'),
          content: SizedBox(
            width: 480,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                DropdownButtonFormField<String>(
                  initialValue: kind,
                  decoration: const InputDecoration(labelText: 'Tipo'),
                  items: const [
                    DropdownMenuItem(value: 'vacation', child: Text('Férias')),
                    DropdownMenuItem(value: 'absence', child: Text('Ausência')),
                  ],
                  onChanged: saving
                      ? null
                      : (value) {
                          if (value != null) {
                            setDialogState(() => kind = value);
                          }
                        },
                ),
                const SizedBox(height: 10),
                _DateInput(
                  label: 'Início',
                  value: starts,
                  onPick: saving
                      ? null
                      : (value) => setDialogState(() {
                            starts = value;
                            if (ends.isBefore(starts)) ends = starts;
                          }),
                ),
                const SizedBox(height: 10),
                _DateInput(
                  label: 'Fim',
                  value: ends,
                  onPick: saving
                      ? null
                      : (value) => setDialogState(() => ends = value),
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: notes,
                  minLines: 2,
                  maxLines: 4,
                  decoration: const InputDecoration(labelText: 'Observações'),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed:
                  saving ? null : () => Navigator.pop(dialogContext, false),
              child: const Text('Cancelar'),
            ),
            FilledButton(
              onPressed: saving
                  ? null
                  : () async {
                      setDialogState(() => saving = true);
                      try {
                        await _repository.saveAbsence(
                          memberId: memberId,
                          kind: kind,
                          startsOn: starts,
                          endsOn: ends,
                          notes: notes.text,
                        );
                        if (dialogContext.mounted) {
                          Navigator.pop(dialogContext, true);
                        }
                      } catch (error) {
                        if (dialogContext.mounted) {
                          ScaffoldMessenger.of(dialogContext).showSnackBar(
                            SnackBar(content: Text(_errorText(error))),
                          );
                          setDialogState(() => saving = false);
                        }
                      }
                    },
              child: const Text('Guardar'),
            ),
          ],
        ),
      ),
    );
    if (saved == true && mounted) await _refresh();
  }

  Future<void> _deleteAbsence(Map<String, dynamic> absence) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Remover período?'),
        content: const Text('A escala futura será recalculada.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Remover'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    try {
      await _repository.deleteAbsence(absence['id'].toString());
      if (!mounted) return;
      _message('Período removido e escala recalculada.');
      await _refresh();
    } catch (error) {
      if (mounted) _message(_errorText(error), error: true);
    }
  }

  Future<void> _openDinnerDialog(
    _WeeklyOfficerData data, [
    Map<String, dynamic>? row,
  ]) async {
    final regular = row?['dinner_kind']?.toString() == 'regular';
    DateTime date =
        row == null ? DateTime.now() : _dateFrom(row['dinner_date']);
    String? memberId = row?['assigned_member_id']?.toString();
    bool external = (row?['external_name']?.toString().trim() ?? '').isNotEmpty;
    final externalName = TextEditingController(
      text: row?['external_name']?.toString() ?? '',
    );
    final dish = TextEditingController(text: row?['dish']?.toString() ?? '');
    final notes = TextEditingController(text: row?['notes']?.toString() ?? '');
    String status = row?['status']?.toString() ?? 'planned';
    if (status == 'closed') status = 'planned';
    bool saving = false;

    final saved = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: Text(
            row == null
                ? 'Novo jantar extraordinário'
                : regular
                    ? 'Editar quinta oficial'
                    : 'Editar jantar extraordinário',
          ),
          content: SizedBox(
            width: 520,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  _DateInput(
                    label: 'Data',
                    value: date,
                    enabled: !regular,
                    onPick: saving || regular
                        ? null
                        : (value) => setDialogState(() => date = value),
                  ),
                  const SizedBox(height: 10),
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('Pessoa externa'),
                    value: external,
                    onChanged: saving
                        ? null
                        : (value) => setDialogState(() {
                              external = value;
                              if (value) memberId = null;
                            }),
                  ),
                  if (external)
                    TextField(
                      controller: externalName,
                      decoration: const InputDecoration(
                        labelText: 'Nome do amigo / pessoa externa',
                      ),
                    )
                  else
                    DropdownButtonFormField<String>(
                      initialValue: memberId ?? '',
                      decoration: const InputDecoration(labelText: 'Membro'),
                      items: [
                        const DropdownMenuItem(
                          value: '',
                          child: Text('Selecionar membro'),
                        ),
                        ...data.members.map(
                          (member) => DropdownMenuItem(
                            value: member['id'].toString(),
                            child:
                                Text(WeeklyOfficerRules.displayMember(member)),
                          ),
                        ),
                      ],
                      onChanged: saving
                          ? null
                          : (value) => setDialogState(
                                () => memberId = value == null || value.isEmpty
                                    ? null
                                    : value,
                              ),
                    ),
                  const SizedBox(height: 10),
                  TextField(
                    controller: dish,
                    decoration: const InputDecoration(
                      labelText: 'Jantar / prato / o que fez',
                    ),
                  ),
                  const SizedBox(height: 10),
                  TextField(
                    controller: notes,
                    minLines: 2,
                    maxLines: 4,
                    decoration: const InputDecoration(labelText: 'Observações'),
                  ),
                  const SizedBox(height: 10),
                  DropdownButtonFormField<String>(
                    initialValue: status,
                    decoration: const InputDecoration(labelText: 'Estado'),
                    items: const [
                      DropdownMenuItem(
                          value: 'planned', child: Text('Planeado')),
                      DropdownMenuItem(
                        value: 'completed',
                        child: Text('Concluído'),
                      ),
                      DropdownMenuItem(
                        value: 'cancelled',
                        child: Text('Cancelado'),
                      ),
                    ],
                    onChanged: saving
                        ? null
                        : (value) {
                            if (value != null) {
                              setDialogState(() => status = value);
                            }
                          },
                  ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed:
                  saving ? null : () => Navigator.pop(dialogContext, false),
              child: const Text('Cancelar'),
            ),
            FilledButton(
              onPressed: saving
                  ? null
                  : () async {
                      final externalValue = externalName.text.trim();
                      if ((external && externalValue.isEmpty) ||
                          (!external &&
                              (memberId == null || memberId!.isEmpty))) {
                        ScaffoldMessenger.of(dialogContext).showSnackBar(
                          const SnackBar(
                            content:
                                Text('Indica o membro ou a pessoa externa.'),
                          ),
                        );
                        return;
                      }
                      setDialogState(() => saving = true);
                      try {
                        await _repository.saveDinner(
                          dinnerId: row?['id']?.toString(),
                          date: date,
                          memberId: external ? null : memberId,
                          externalName: external ? externalValue : null,
                          dish: dish.text,
                          notes: notes.text,
                          status: status,
                        );
                        if (dialogContext.mounted) {
                          Navigator.pop(dialogContext, true);
                        }
                      } catch (error) {
                        if (dialogContext.mounted) {
                          ScaffoldMessenger.of(dialogContext).showSnackBar(
                            SnackBar(content: Text(_errorText(error))),
                          );
                          setDialogState(() => saving = false);
                        }
                      }
                    },
              child: const Text('Guardar'),
            ),
          ],
        ),
      ),
    );
    if (saved == true && mounted) await _refresh();
  }

  Future<void> _setDinnerClosed(
    Map<String, dynamic> row,
    bool closed,
  ) async {
    String? note;
    if (closed) {
      note = await _askNote(
        'Fechar quinta-feira',
        hint: 'Motivo (opcional)',
        allowEmpty: true,
      );
      if (note == null) return;
    }
    try {
      await _repository.setClosed(
        dinnerId: row['id'].toString(),
        closed: closed,
        notes: note,
      );
      if (!mounted) return;
      _message(
        closed
            ? 'Quinta marcada como fechada. O membro não perdeu a vez.'
            : 'Quinta reaberta e escala futura recalculada.',
      );
      await _refresh();
    } catch (error) {
      if (mounted) _message(_errorText(error), error: true);
    }
  }

  Future<void> _requestSwap(
    _WeeklyOfficerData data,
    Map<String, dynamic> dinner,
  ) async {
    final current = data.currentMemberId;
    if (current == null) {
      _message('O teu utilizador ainda não está ligado a um membro.',
          error: true);
      return;
    }
    final candidates = data.rotation
        .where(
          (r) => r['member_id']?.toString() != current && r['enabled'] != false,
        )
        .map((r) => r['member_id']?.toString())
        .whereType<String>()
        .toList();
    if (candidates.isEmpty) {
      _message('Não existem membros disponíveis para pedir troca.',
          error: true);
      return;
    }

    String selected = candidates.first;
    final note = TextEditingController();
    bool saving = false;
    final sent = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: Text('Pedir troca · ${_datePt(dinner['dinner_date'])}'),
          content: SizedBox(
            width: 480,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                DropdownButtonFormField<String>(
                  initialValue: selected,
                  decoration: const InputDecoration(labelText: 'Pedir a'),
                  items: candidates
                      .map(
                        (id) => DropdownMenuItem(
                          value: id,
                          child: Text(
                            WeeklyOfficerRules.displayMember(
                                data.memberById[id]),
                          ),
                        ),
                      )
                      .toList(),
                  onChanged: saving
                      ? null
                      : (value) {
                          if (value != null) {
                            setDialogState(() => selected = value);
                          }
                        },
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: note,
                  minLines: 2,
                  maxLines: 4,
                  decoration:
                      const InputDecoration(labelText: 'Mensagem (opcional)'),
                ),
                const SizedBox(height: 8),
                const Text(
                  'A troca só altera a escala depois de ser aceite e validada pela Direção.',
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed:
                  saving ? null : () => Navigator.pop(dialogContext, false),
              child: const Text('Cancelar'),
            ),
            FilledButton(
              onPressed: saving
                  ? null
                  : () async {
                      setDialogState(() => saving = true);
                      try {
                        await _repository.requestSwap(
                          dinnerId: dinner['id'].toString(),
                          requestedMemberId: selected,
                          note: note.text,
                        );
                        if (dialogContext.mounted) {
                          Navigator.pop(dialogContext, true);
                        }
                      } catch (error) {
                        if (dialogContext.mounted) {
                          ScaffoldMessenger.of(dialogContext).showSnackBar(
                            SnackBar(content: Text(_errorText(error))),
                          );
                          setDialogState(() => saving = false);
                        }
                      }
                    },
              child: const Text('Enviar pedido'),
            ),
          ],
        ),
      ),
    );
    if (sent == true && mounted) {
      _message('Pedido de troca enviado.');
      await _refresh();
    }
  }

  Future<void> _respondSwap(Map<String, dynamic> row, bool accept) async {
    final note = await _askNote(
      accept ? 'Aceitar pedido' : 'Recusar pedido',
      hint: 'Mensagem (opcional)',
      allowEmpty: true,
    );
    if (note == null) return;
    try {
      await _repository.respondSwap(
        requestId: row['id'].toString(),
        accept: accept,
        note: note,
      );
      if (!mounted) return;
      _message(accept
          ? 'Pedido aceite. Aguarda alteração pela Direção.'
          : 'Pedido recusado.');
      await _refresh();
    } catch (error) {
      if (mounted) _message(_errorText(error), error: true);
    }
  }

  Future<void> _markSwapApplied(Map<String, dynamic> row) async {
    final note = await _askNote(
      'Marcar troca como aplicada',
      hint: 'Observação da alteração feita na escala (opcional)',
      allowEmpty: true,
    );
    if (note == null) return;
    try {
      await _repository.markSwapApplied(
        requestId: row['id'].toString(),
        note: note,
      );
      if (!mounted) return;
      _message('Troca marcada como aplicada.');
      await _refresh();
    } catch (error) {
      if (mounted) _message(_errorText(error), error: true);
    }
  }

  Future<void> _cancelSwap(Map<String, dynamic> row) async {
    try {
      await _repository.cancelSwap(row['id'].toString());
      if (!mounted) return;
      _message('Pedido cancelado.');
      await _refresh();
    } catch (error) {
      if (mounted) _message(_errorText(error), error: true);
    }
  }

  Future<String?> _askNote(
    String title, {
    String hint = 'Observação',
    bool allowEmpty = false,
  }) async {
    final controller = TextEditingController();
    return showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(title),
        content: TextField(
          controller: controller,
          minLines: 2,
          maxLines: 4,
          autofocus: true,
          decoration: InputDecoration(labelText: hint),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () {
              final value = controller.text.trim();
              if (!allowEmpty && value.isEmpty) return;
              Navigator.pop(dialogContext, value);
            },
            child: const Text('Confirmar'),
          ),
        ],
      ),
    );
  }

  void _message(String text, {bool error = false}) {
    final messenger = ScaffoldMessenger.of(context);
    messenger.hideCurrentSnackBar();
    messenger.showSnackBar(
      SnackBar(
        content: Text(text),
        duration: Duration(seconds: error ? 5 : 3),
      ),
    );
  }

  static String _errorText(Object? error) {
    if (error is PostgrestException) return error.message;
    final text = error?.toString() ?? 'Erro desconhecido.';
    return text.replaceFirst('Exception: ', '').replaceFirst('Bad state: ', '');
  }

  static DateTime _dateFrom(dynamic raw) {
    if (raw is DateTime) return raw;
    return DateTime.tryParse(raw?.toString() ?? '') ?? DateTime(1970);
  }

  static String _datePt(dynamic raw) {
    final date = _dateFrom(raw);
    if (date.year == 1970) return '—';
    return DateFormat('dd/MM/yyyy', 'pt_PT').format(date);
  }
}

class _WeeklyOfficerData {
  const _WeeklyOfficerData({
    required this.members,
    required this.rotation,
    required this.dinners,
    required this.absences,
    required this.swaps,
    required this.currentMemberId,
  });

  factory _WeeklyOfficerData.empty() => const _WeeklyOfficerData(
        members: [],
        rotation: [],
        dinners: [],
        absences: [],
        swaps: [],
        currentMemberId: null,
      );

  final List<Map<String, dynamic>> members;
  final List<Map<String, dynamic>> rotation;
  final List<Map<String, dynamic>> dinners;
  final List<Map<String, dynamic>> absences;
  final List<Map<String, dynamic>> swaps;
  final String? currentMemberId;

  Map<String, Map<String, dynamic>> get memberById => {
        for (final member in members)
          if (member['id'] != null) member['id'].toString(): member,
      };

  Map<String, Map<String, dynamic>> get dinnerById => {
        for (final dinner in dinners)
          if (dinner['id'] != null) dinner['id'].toString(): dinner,
      };

  Map<String, int> get officialCounts {
    final result = <String, int>{};
    for (final dinner in dinners) {
      if (!WeeklyOfficerRules.countsAsOfficialDinner(dinner)) continue;
      final memberId = dinner['assigned_member_id']?.toString();
      if (memberId == null) continue;
      result[memberId] = (result[memberId] ?? 0) + 1;
    }
    return result;
  }

  List<Map<String, dynamic>> get currentMemberUpcomingDinners {
    final memberId = currentMemberId;
    if (memberId == null) return const <Map<String, dynamic>>[];

    final today = DateTime.now();
    final start = DateTime(today.year, today.month, today.day);

    return WeeklyOfficerRules.sortDinnersNearestFirst(
      dinners.where((dinner) {
        final date = DateTime.tryParse(dinner['dinner_date']?.toString() ?? '');
        return dinner['status'] == 'planned' &&
            dinner['assigned_member_id']?.toString() == memberId &&
            date != null &&
            !date.isBefore(start);
      }),
    );
  }

  Map<String, dynamic>? get nextRegularDinner {
    final today = DateTime.now();
    final start = DateTime(today.year, today.month, today.day);

    for (final dinner in WeeklyOfficerRules.sortDinnersNearestFirst(dinners)) {
      if (dinner['dinner_kind'] != 'regular' || dinner['status'] != 'planned') {
        continue;
      }
      final date = DateTime.tryParse(dinner['dinner_date']?.toString() ?? '');
      if (date != null && !date.isBefore(start)) return dinner;
    }
    return null;
  }

  String dinnerResponsible(Map<String, dynamic> dinner) {
    final external = dinner['external_name']?.toString().trim() ?? '';
    if (external.isNotEmpty) return external;
    final memberId = dinner['assigned_member_id']?.toString();
    return WeeklyOfficerRules.displayMember(
      memberId == null ? null : memberById[memberId],
    );
  }
}

class _DateInput extends StatelessWidget {
  const _DateInput({
    required this.label,
    required this.value,
    required this.onPick,
    this.enabled = true,
  });

  final String label;
  final DateTime value;
  final ValueChanged<DateTime>? onPick;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(12),
      onTap: !enabled || onPick == null
          ? null
          : () async {
              final picked = await showDatePicker(
                context: context,
                initialDate: value,
                firstDate: DateTime(2020),
                lastDate: DateTime(2100),
              );
              if (picked != null) onPick!(picked);
            },
      child: InputDecorator(
        decoration: InputDecoration(
          labelText: label,
          prefixIcon: const Icon(Icons.calendar_month_outlined),
          enabled: enabled,
        ),
        child: Text(DateFormat('dd/MM/yyyy', 'pt_PT').format(value)),
      ),
    );
  }
}

class _ErrorState extends StatelessWidget {
  const _ErrorState({required this.message, required this.onRetry});

  final String message;
  final Future<void> Function() onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.error_outline, size: 44),
            const SizedBox(height: 12),
            Text(message, textAlign: TextAlign.center),
            const SizedBox(height: 12),
            FilledButton.icon(
              onPressed: onRetry,
              icon: const Icon(Icons.refresh),
              label: const Text('Tentar novamente'),
            ),
          ],
        ),
      ),
    );
  }
}
