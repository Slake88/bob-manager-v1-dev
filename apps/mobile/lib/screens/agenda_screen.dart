import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../core/agenda_rules.dart';
import '../repositories/agenda_repository.dart';

class AgendaScreen extends StatefulWidget {
  const AgendaScreen({super.key});

  @override
  State<AgendaScreen> createState() => _AgendaScreenState();
}

class _AgendaScreenState extends State<AgendaScreen> {
  final AgendaRepository _repository = AgendaRepository();

  late DateTime _month;
  late DateTime _selectedDay;
  late Future<_AgendaData> _future;
  String _filter = 'all';

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    _month = DateTime(now.year, now.month);
    _selectedDay = DateTime(now.year, now.month, now.day);
    _reload();
  }

  void _reload() {
    _future = _load();
  }

  Future<_AgendaData> _load() async {
    final grid = AgendaRules.monthGrid(_month);
    await _repository.ensureDinnerYears(grid.first, grid.last);
    final values = await Future.wait([
      _repository.calendar(grid.first, grid.last),
      _repository.canManage(),
    ]);
    return _AgendaData(
      rows: List<Map<String, dynamic>>.from(values[0] as List),
      canManage: values[1] as bool,
    );
  }

  Future<void> _refresh() async {
    setState(_reload);
    await _future;
  }

  void _changeMonth(int delta) {
    final next = DateTime(_month.year, _month.month + delta);
    setState(() {
      _month = next;
      _selectedDay = DateTime(next.year, next.month, 1);
      _reload();
    });
  }

  void _goToday() {
    final now = DateTime.now();
    setState(() {
      _month = DateTime(now.year, now.month);
      _selectedDay = DateTime(now.year, now.month, now.day);
      _reload();
    });
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<_AgendaData>(
      future: _future,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }
        if (snapshot.hasError) {
          return _AgendaErrorState(
            message: _errorText(snapshot.error),
            onRetry: _refresh,
          );
        }

        final data = snapshot.data ?? const _AgendaData.empty();
        final filtered = data.rows
            .where((row) => AgendaRules.matchesFilter(row, _filter))
            .toList();

        return RefreshIndicator(
          onRefresh: _refresh,
          child: ListView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 28),
            children: [
              _header(data),
              const SizedBox(height: 10),
              _filters(),
              const SizedBox(height: 12),
              _calendar(filtered),
              const SizedBox(height: 16),
              _selectedDayHeader(filtered),
              const SizedBox(height: 8),
              ..._dayCards(filtered, data),
            ],
          ),
        );
      },
    );
  }

  Widget _header(_AgendaData data) {
    final label = DateFormat('MMMM yyyy', 'pt_PT').format(_month);
    final title = label.isEmpty
        ? label
        : '${label[0].toUpperCase()}${label.substring(1)}';

    return Card(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(10, 10, 10, 10),
        child: Row(
          children: [
            IconButton(
              tooltip: 'Mês anterior',
              onPressed: () => _changeMonth(-1),
              icon: const Icon(Icons.chevron_left),
            ),
            Expanded(
              child: Column(
                children: [
                  Text(
                    title,
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.titleLarge?.copyWith(
                          fontWeight: FontWeight.w900,
                        ),
                  ),
                  TextButton(
                    onPressed: _goToday,
                    child: const Text('Hoje'),
                  ),
                ],
              ),
            ),
            IconButton(
              tooltip: 'Mês seguinte',
              onPressed: () => _changeMonth(1),
              icon: const Icon(Icons.chevron_right),
            ),
            if (data.canManage)
              FilledButton.icon(
                onPressed: () => _openEditor(),
                icon: const Icon(Icons.add),
                label: const Text('Novo'),
              ),
          ],
        ),
      ),
    );
  }

  Widget _filters() {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: AgendaRules.filterLabels.entries.map((entry) {
          return Padding(
            padding: const EdgeInsets.only(right: 8),
            child: FilterChip(
              selected: _filter == entry.key,
              label: Text(entry.value),
              onSelected: (_) => setState(() => _filter = entry.key),
            ),
          );
        }).toList(),
      ),
    );
  }

  Widget _calendar(List<Map<String, dynamic>> rows) {
    final days = AgendaRules.monthGrid(_month);
    const week = ['SEG', 'TER', 'QUA', 'QUI', 'SEX', 'SÁB', 'DOM'];

    return Card(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(10, 12, 10, 12),
        child: Column(
          children: [
            Row(
              children: week
                  .map(
                    (day) => Expanded(
                      child: Text(
                        day,
                        textAlign: TextAlign.center,
                        style: Theme.of(context).textTheme.labelSmall?.copyWith(
                              fontWeight: FontWeight.w800,
                            ),
                      ),
                    ),
                  )
                  .toList(),
            ),
            const SizedBox(height: 8),
            GridView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: days.length,
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 7,
                childAspectRatio: 0.92,
                crossAxisSpacing: 4,
                mainAxisSpacing: 4,
              ),
              itemBuilder: (context, index) {
                final day = days[index];
                final dayItems = rows
                    .where(
                      (row) => AgendaRules.sameDay(
                        AgendaRules.rowDate(row),
                        day,
                      ),
                    )
                    .toList();
                return _dayCell(day, dayItems);
              },
            ),
          ],
        ),
      ),
    );
  }

  Widget _dayCell(
    DateTime day,
    List<Map<String, dynamic>> items,
  ) {
    final selected = AgendaRules.sameDay(day, _selectedDay);
    final today = AgendaRules.sameDay(day, DateTime.now());
    final inside = AgendaRules.inMonth(day, _month);
    final scheme = Theme.of(context).colorScheme;

    return InkWell(
      borderRadius: BorderRadius.circular(10),
      onTap: () => setState(() => _selectedDay = day),
      child: Container(
        padding: const EdgeInsets.all(5),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            width: selected ? 2 : 1,
            color: selected
                ? scheme.primary
                : today
                    ? scheme.secondary
                    : scheme.outlineVariant,
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '${day.day}',
              style: TextStyle(
                fontWeight:
                    selected || today ? FontWeight.w900 : FontWeight.w600,
                color: inside ? null : scheme.outline,
              ),
            ),
            const Spacer(),
            if (items.isNotEmpty)
              Align(
                alignment: Alignment.bottomRight,
                child: Container(
                  constraints:
                      const BoxConstraints(minWidth: 22, minHeight: 22),
                  padding: const EdgeInsets.symmetric(horizontal: 5),
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    shape: items.length < 10
                        ? BoxShape.circle
                        : BoxShape.rectangle,
                    borderRadius:
                        items.length < 10 ? null : BorderRadius.circular(10),
                    color: items.any(AgendaRules.isHighPriority)
                        ? scheme.errorContainer
                        : scheme.secondaryContainer,
                  ),
                  child: Text(
                    '${items.length}',
                    style: Theme.of(context).textTheme.labelSmall?.copyWith(
                          fontWeight: FontWeight.w900,
                        ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _selectedDayHeader(List<Map<String, dynamic>> rows) {
    final count = rows
        .where(
          (row) => AgendaRules.sameDay(AgendaRules.rowDate(row), _selectedDay),
        )
        .length;
    return Row(
      children: [
        Expanded(
          child: Text(
            DateFormat("EEEE, d 'de' MMMM", 'pt_PT').format(_selectedDay),
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w900,
                ),
          ),
        ),
        Chip(label: Text('$count')),
      ],
    );
  }

  List<Widget> _dayCards(
    List<Map<String, dynamic>> rows,
    _AgendaData data,
  ) {
    final dayRows = rows
        .where(
          (row) => AgendaRules.sameDay(AgendaRules.rowDate(row), _selectedDay),
        )
        .toList()
      ..sort(
        (a, b) => AgendaRules.rowDate(a).compareTo(AgendaRules.rowDate(b)),
      );

    if (dayRows.isEmpty) {
      return const [
        Card(
          child: Padding(
            padding: EdgeInsets.all(20),
            child: Center(child: Text('Sem registos para este dia.')),
          ),
        ),
      ];
    }

    return dayRows.map((row) => _agendaCard(row, data)).toList();
  }

  Widget _agendaCard(
    Map<String, dynamic> row,
    _AgendaData data,
  ) {
    final date = AgendaRules.rowDate(row);
    final allDay = row['all_day'] == true;
    final subtitle = row['subtitle']?.toString().trim() ?? '';
    final status = row['item_status']?.toString() ?? '';
    final editable = data.canManage &&
        row['source_type']?.toString() == 'agenda' &&
        row['can_edit'] == true;

    return Card(
      child: ListTile(
        leading: CircleAvatar(child: Icon(_iconFor(row))),
        title: Text(
          row['title']?.toString() ?? 'Agenda',
          style: const TextStyle(fontWeight: FontWeight.w800),
        ),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              allDay
                  ? AgendaRules.kindLabel(row)
                  : '${AgendaRules.kindLabel(row)} · ${DateFormat('HH:mm').format(date)}',
            ),
            if (subtitle.isNotEmpty) Text(subtitle),
            if (status == 'cancelled')
              const Text('Cancelado')
            else if (status == 'overdue')
              const Text('Prazo ultrapassado'),
          ],
        ),
        isThreeLine: subtitle.isNotEmpty || status == 'overdue',
        trailing: editable
            ? PopupMenuButton<String>(
                onSelected: (action) async {
                  if (action == 'edit') {
                    final id = row['item_id']?.toString() ?? '';
                    if (id.isEmpty) return;
                    final existing = await _repository.manualItem(id);
                    if (!mounted || existing == null) return;
                    await _openEditor(existing: existing);
                  } else if (action == 'cancel') {
                    await _cancelManual(row);
                  }
                },
                itemBuilder: (_) => const [
                  PopupMenuItem(value: 'edit', child: Text('Editar')),
                  PopupMenuItem(value: 'cancel', child: Text('Cancelar')),
                ],
              )
            : null,
      ),
    );
  }

  IconData _iconFor(Map<String, dynamic> row) {
    final source = row['source_type']?.toString() ?? '';
    final kind = row['item_kind']?.toString() ?? '';
    if (source == 'event') return Icons.event_outlined;
    if (source == 'weekly_dinner') return Icons.restaurant_menu_outlined;
    if (source == 'document') return Icons.description_outlined;
    if (source == 'fee') return Icons.payments_outlined;
    if (source == 'member') {
      if (kind == 'birthday') return Icons.cake_outlined;
      if (kind == 'full_colors') return Icons.verified_outlined;
      return Icons.person_add_alt_1_outlined;
    }
    if (kind == 'meeting') return Icons.groups_outlined;
    if (kind == 'deadline') return Icons.schedule_outlined;
    return Icons.notifications_none_outlined;
  }

  Future<void> _openEditor({Map<String, dynamic>? existing}) async {
    final editing = existing != null;
    final title = TextEditingController(
      text: existing?['title']?.toString() ?? '',
    );
    final description = TextEditingController(
      text: existing?['description']?.toString() ?? '',
    );
    final location = TextEditingController(
      text: existing?['location']?.toString() ?? '',
    );

    var type = existing?['item_type']?.toString() ?? 'meeting';
    var audience = existing?['audience']?.toString() ?? 'all';
    var priority = existing?['priority']?.toString() ?? 'normal';
    var status = existing?['status']?.toString() ?? 'planned';
    var allDay = existing?['all_day'] == true;
    var notify = false;

    final parsed = existing?['starts_at'] == null
        ? null
        : DateTime.tryParse(existing!['starts_at'].toString())?.toLocal();
    var date = parsed ?? _selectedDay;
    var time = TimeOfDay.fromDateTime(parsed ?? DateTime.now());

    final saved = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setLocal) {
          Future<void> pickDate() async {
            final value = await showDatePicker(
              context: context,
              initialDate: date,
              firstDate: DateTime(2020),
              lastDate: DateTime(2100),
            );
            if (value != null) setLocal(() => date = value);
          }

          Future<void> pickTime() async {
            final value = await showTimePicker(
              context: context,
              initialTime: time,
            );
            if (value != null) setLocal(() => time = value);
          }

          return AlertDialog(
            title: Text(editing ? 'Editar Agenda' : 'Novo item da Agenda'),
            content: SizedBox(
              width: 520,
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    DropdownButtonFormField<String>(
                      initialValue: type,
                      decoration: const InputDecoration(labelText: 'Tipo'),
                      items: const [
                        DropdownMenuItem(
                            value: 'meeting', child: Text('Reunião')),
                        DropdownMenuItem(
                            value: 'deadline', child: Text('Prazo')),
                        DropdownMenuItem(
                            value: 'reminder', child: Text('Lembrete')),
                      ],
                      onChanged: (value) {
                        if (value != null) setLocal(() => type = value);
                      },
                    ),
                    const SizedBox(height: 10),
                    TextField(
                      controller: title,
                      decoration: const InputDecoration(labelText: 'Título'),
                    ),
                    const SizedBox(height: 10),
                    TextField(
                      controller: description,
                      maxLines: 3,
                      decoration: const InputDecoration(labelText: 'Descrição'),
                    ),
                    const SizedBox(height: 10),
                    TextField(
                      controller: location,
                      decoration: const InputDecoration(labelText: 'Local'),
                    ),
                    const SizedBox(height: 10),
                    SwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      value: allDay,
                      title: const Text('Dia inteiro'),
                      onChanged: (value) => setLocal(() => allDay = value),
                    ),
                    Row(
                      children: [
                        Expanded(
                          child: OutlinedButton.icon(
                            onPressed: pickDate,
                            icon: const Icon(Icons.calendar_today_outlined),
                            label: Text(DateFormat('dd/MM/yyyy').format(date)),
                          ),
                        ),
                        if (!allDay) ...[
                          const SizedBox(width: 8),
                          Expanded(
                            child: OutlinedButton.icon(
                              onPressed: pickTime,
                              icon: const Icon(Icons.schedule_outlined),
                              label: Text(time.format(context)),
                            ),
                          ),
                        ],
                      ],
                    ),
                    const SizedBox(height: 10),
                    DropdownButtonFormField<String>(
                      initialValue: audience,
                      decoration:
                          const InputDecoration(labelText: 'Visibilidade'),
                      items: const [
                        DropdownMenuItem(value: 'all', child: Text('Todos')),
                        DropdownMenuItem(
                          value: 'direction',
                          child: Text('Apenas Direção'),
                        ),
                      ],
                      onChanged: (value) {
                        if (value != null) setLocal(() => audience = value);
                      },
                    ),
                    const SizedBox(height: 10),
                    DropdownButtonFormField<String>(
                      initialValue: priority,
                      decoration:
                          const InputDecoration(labelText: 'Prioridade'),
                      items: const [
                        DropdownMenuItem(value: 'low', child: Text('Baixa')),
                        DropdownMenuItem(
                            value: 'normal', child: Text('Normal')),
                        DropdownMenuItem(value: 'high', child: Text('Alta')),
                      ],
                      onChanged: (value) {
                        if (value != null) setLocal(() => priority = value);
                      },
                    ),
                    if (editing) ...[
                      const SizedBox(height: 10),
                      DropdownButtonFormField<String>(
                        initialValue: status,
                        decoration: const InputDecoration(labelText: 'Estado'),
                        items: const [
                          DropdownMenuItem(
                            value: 'planned',
                            child: Text('Planeado'),
                          ),
                          DropdownMenuItem(
                            value: 'completed',
                            child: Text('Concluído'),
                          ),
                          DropdownMenuItem(
                            value: 'cancelled',
                            child: Text('Cancelado'),
                          ),
                        ],
                        onChanged: (value) {
                          if (value != null) setLocal(() => status = value);
                        },
                      ),
                    ],
                    SwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      value: notify,
                      title: const Text('Notificar agora'),
                      subtitle: const Text(
                        'Cria uma notificação interna para os destinatários.',
                      ),
                      onChanged: (value) => setLocal(() => notify = value),
                    ),
                  ],
                ),
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(dialogContext, false),
                child: const Text('Fechar'),
              ),
              FilledButton(
                onPressed: title.text.trim().isEmpty
                    ? null
                    : () => Navigator.pop(dialogContext, true),
                child: const Text('Guardar'),
              ),
            ],
          );
        },
      ),
    );

    if (saved != true) {
      title.dispose();
      description.dispose();
      location.dispose();
      return;
    }

    try {
      final start = allDay
          ? DateTime(date.year, date.month, date.day)
          : DateTime(
              date.year,
              date.month,
              date.day,
              time.hour,
              time.minute,
            );
      await _repository.saveManualItem(
        itemId: existing?['id']?.toString(),
        itemType: type,
        title: title.text,
        description: description.text,
        startsAt: start,
        allDay: allDay,
        location: location.text,
        audience: audience,
        priority: priority,
        status: status,
        notifyNow: notify,
      );
      if (!mounted) return;
      setState(() {
        _selectedDay = DateTime(date.year, date.month, date.day);
        _month = DateTime(date.year, date.month);
        _reload();
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
              editing ? 'Agenda atualizada.' : 'Item adicionado à Agenda.'),
        ),
      );
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(_errorText(error))),
      );
    } finally {
      title.dispose();
      description.dispose();
      location.dispose();
    }
  }

  Future<void> _cancelManual(Map<String, dynamic> row) async {
    final id = row['item_id']?.toString() ?? '';
    if (id.isEmpty) return;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Cancelar item?'),
        content: Text(row['title']?.toString() ?? 'Este item da Agenda'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Não'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Cancelar item'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    try {
      await _repository.cancelManualItem(id);
      if (!mounted) return;
      setState(_reload);
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(_errorText(error))),
      );
    }
  }

  static String _errorText(Object? error) {
    final text = error?.toString() ?? 'Erro inesperado.';
    return text.replaceFirst('PostgrestException(message: ', '').trim();
  }
}

class _AgendaData {
  const _AgendaData({
    required this.rows,
    required this.canManage,
  });

  const _AgendaData.empty()
      : rows = const <Map<String, dynamic>>[],
        canManage = false;

  final List<Map<String, dynamic>> rows;
  final bool canManage;
}

class _AgendaErrorState extends StatelessWidget {
  const _AgendaErrorState({
    required this.message,
    required this.onRetry,
  });

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
            const Icon(Icons.error_outline, size: 42),
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
