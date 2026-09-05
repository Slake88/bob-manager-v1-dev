import 'package:flutter/material.dart';

import '../core/app_role.dart';
import '../core/app_session.dart';
import '../core/permissions.dart';
import '../repositories/events_repository.dart';
import '../repositories/member_repository.dart';

class EventsScreen extends StatefulWidget {
  const EventsScreen({super.key});

  @override
  State<EventsScreen> createState() => _EventsScreenState();
}

class _EventsScreenState extends State<EventsScreen> {
  final EventsRepository _events = EventsRepository();
  final MemberRepository _members = MemberRepository();
  late DateTime _month;
  late Future<List<Map<String, dynamic>>> _future;

  AppRole get _role => AppRole.fromValue(AppSession.instance.role);
  bool get _canManage =>
      PermissionPolicy.allows(_role, AppPermission.manageEvents);

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    _month = DateTime(now.year, now.month);
    _reload();
  }

  void _reload() {
    _future = _events.listMonth(_month.year, _month.month);
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

  Future<void> _openEvent([Map<String, dynamic>? event]) async {
    final name = TextEditingController(text: event?['name']?.toString() ?? '');
    final location =
        TextEditingController(text: event?['location']?.toString() ?? '');
    final description =
        TextEditingController(text: event?['description']?.toString() ?? '');
    final budget = TextEditingController(
      text: event?['budget'] == null ? '' : event!['budget'].toString(),
    );
    DateTime? startsAt = _parseDate(event?['starts_at']);
    String status = _normalizeStatus(event?['status']?.toString());
    bool saving = false;

    final saved = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: Text(event == null ? 'Novo evento' : 'Editar evento'),
          content: SizedBox(
            width: 520,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextField(
                    controller: name,
                    decoration: const InputDecoration(
                      labelText: 'Nome do evento',
                      prefixIcon: Icon(Icons.event_outlined),
                    ),
                  ),
                  const SizedBox(height: 10),
                  TextField(
                    controller: location,
                    decoration: const InputDecoration(
                      labelText: 'Local',
                      prefixIcon: Icon(Icons.location_on_outlined),
                    ),
                  ),
                  const SizedBox(height: 10),
                  InkWell(
                    borderRadius: BorderRadius.circular(12),
                    onTap: saving
                        ? null
                        : () async {
                            final initial = startsAt ?? DateTime.now();
                            final pickedDate = await showDatePicker(
                              context: dialogContext,
                              initialDate: initial,
                              firstDate: DateTime(2000),
                              lastDate: DateTime(2100),
                              helpText: 'Selecionar data do evento',
                            );
                            if (pickedDate == null || !dialogContext.mounted) {
                              return;
                            }
                            final pickedTime = await showTimePicker(
                              context: dialogContext,
                              initialTime: TimeOfDay.fromDateTime(initial),
                              helpText: 'Selecionar hora do evento',
                            );
                            if (!dialogContext.mounted) return;
                            final time = pickedTime ?? TimeOfDay.fromDateTime(initial);
                            setDialogState(() {
                              startsAt = DateTime(
                                pickedDate.year,
                                pickedDate.month,
                                pickedDate.day,
                                time.hour,
                                time.minute,
                              );
                            });
                          },
                    child: InputDecorator(
                      decoration: const InputDecoration(
                        labelText: 'Data e hora',
                        prefixIcon: Icon(Icons.calendar_month_outlined),
                        suffixIcon: Icon(Icons.edit_calendar_outlined),
                      ),
                      child: Text(
                        startsAt == null
                            ? 'Selecionar data e hora'
                            : _dateTimePt(startsAt!),
                      ),
                    ),
                  ),
                  const SizedBox(height: 10),
                  TextField(
                    controller: description,
                    minLines: 2,
                    maxLines: 4,
                    decoration: const InputDecoration(
                      labelText: 'Descrição / notas',
                      prefixIcon: Icon(Icons.notes_outlined),
                    ),
                  ),
                  const SizedBox(height: 10),
                  TextField(
                    controller: budget,
                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: true,
                    ),
                    decoration: const InputDecoration(
                      labelText: 'Orçamento (€)',
                      prefixIcon: Icon(Icons.euro_outlined),
                    ),
                  ),
                  const SizedBox(height: 10),
                  DropdownButtonFormField<String>(
                    initialValue: status,
                    decoration: const InputDecoration(
                      labelText: 'Estado',
                      prefixIcon: Icon(Icons.flag_outlined),
                    ),
                    items: const [
                      DropdownMenuItem(value: 'draft', child: Text('Rascunho')),
                      DropdownMenuItem(
                        value: 'published',
                        child: Text('Publicado'),
                      ),
                      DropdownMenuItem(value: 'active', child: Text('Em curso')),
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
              onPressed: saving ? null : () => Navigator.pop(dialogContext, false),
              child: const Text('Cancelar'),
            ),
            FilledButton.icon(
              onPressed: saving
                  ? null
                  : () async {
                      if (name.text.trim().isEmpty) {
                        ScaffoldMessenger.of(dialogContext).showSnackBar(
                          const SnackBar(content: Text('Indica o nome do evento.')),
                        );
                        return;
                      }
                      if (startsAt == null) {
                        ScaffoldMessenger.of(dialogContext).showSnackBar(
                          const SnackBar(
                            content: Text('Seleciona a data do evento.'),
                          ),
                        );
                        return;
                      }
                      setDialogState(() => saving = true);
                      try {
                        await _events.saveEvent(
                          {
                            'name': name.text.trim(),
                            'description': description.text.trim().isEmpty
                                ? null
                                : description.text.trim(),
                            'location': location.text.trim().isEmpty
                                ? null
                                : location.text.trim(),
                            'starts_at': startsAt!.toIso8601String(),
                            'budget': double.tryParse(
                                  budget.text.trim().replaceAll(',', '.'),
                                ) ??
                                0,
                            'status': status,
                          },
                          eventId: event?['id']?.toString(),
                        );
                        if (dialogContext.mounted) {
                          Navigator.pop(dialogContext, true);
                        }
                      } catch (error) {
                        if (dialogContext.mounted) {
                          ScaffoldMessenger.of(dialogContext).showSnackBar(
                            SnackBar(content: Text(_friendlyError(error))),
                          );
                          setDialogState(() => saving = false);
                        }
                      }
                    },
              icon: saving
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.save_outlined),
              label: Text(saving ? 'A guardar...' : 'Guardar'),
            ),
          ],
        ),
      ),
    );

    name.dispose();
    location.dispose();
    description.dispose();
    budget.dispose();
    if (saved == true && mounted) setState(_reload);
  }

  Future<void> _openAnniversary(Map<String, dynamic> item) async {
    final years = int.tryParse(item['anniversary_years']?.toString() ?? '') ?? 0;
    final type = item['calendar_type']?.toString() ?? '';
    final detail = switch (type) {
      'birthday' => years > 0 ? '$years anos' : 'Aniversário',
      'prospect_anniversary' =>
        years == 1 ? '1 ano como Prospect' : '$years anos desde Prospect',
      'full_color_anniversary' =>
        years == 1 ? '1 ano como Full Color' : '$years anos como Full Color',
      _ => '',
    };
    await showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(item['name']?.toString() ?? 'Aniversário'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Data: ${_datePt(_parseDate(item['starts_at']))}'),
            if (detail.isNotEmpty) ...[
              const SizedBox(height: 8),
              Text(detail),
            ],
          ],
        ),
        actions: [
          FilledButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Fechar'),
          ),
        ],
      ),
    );
  }

  Future<void> _openDetails(Map<String, dynamic> event) async {
    await Navigator.of(context).push<void>(
      MaterialPageRoute(
        builder: (_) => EventDetailScreen(
          event: event,
          repository: _events,
          memberRepository: _members,
        ),
      ),
    );
    if (mounted) setState(_reload);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: FutureBuilder<List<Map<String, dynamic>>>(
        future: _future,
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return Center(child: Text('Erro: ${_friendlyError(snapshot.error!)}'));
          }
          if (!snapshot.hasData) {
            return const Center(child: CircularProgressIndicator());
          }
          final items = snapshot.data!;
          final events = items.where((row) => row['calendar_type'] == 'event').length;
          final anniversaries = items.length - events;

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
                    _MetricCard(label: 'Eventos', value: '$events'),
                    _MetricCard(label: 'Aniversários', value: '$anniversaries'),
                    _MetricCard(label: 'Total no mês', value: '${items.length}'),
                  ],
                ),
                const SizedBox(height: 14),
                if (items.isEmpty)
                  const Card(
                    child: ListTile(
                      leading: Icon(Icons.event_busy_outlined),
                      title: Text('Sem eventos ou aniversários neste mês.'),
                    ),
                  )
                else
                  ...items.map((item) => _calendarCard(item)),
              ],
            ),
          );
        },
      ),
      floatingActionButton: _canManage
          ? FloatingActionButton.extended(
              onPressed: _openEvent,
              icon: const Icon(Icons.add),
              label: const Text('Novo evento'),
            )
          : null,
    );
  }

  Widget _calendarCard(Map<String, dynamic> item) {
    final type = item['calendar_type']?.toString() ?? 'event';
    final isEvent = type == 'event';
    final date = _parseDate(item['starts_at']);
    final theme = Theme.of(context);

    final (IconData icon, Color background, Color foreground, String badge) =
        switch (type) {
      'birthday' => (
          Icons.cake_outlined,
          theme.colorScheme.tertiaryContainer,
          theme.colorScheme.onTertiaryContainer,
          'ANIVERSÁRIO'
        ),
      'prospect_anniversary' => (
          Icons.workspace_premium_outlined,
          theme.colorScheme.secondaryContainer,
          theme.colorScheme.onSecondaryContainer,
          'PROSPECT'
        ),
      'full_color_anniversary' => (
          Icons.shield_outlined,
          theme.colorScheme.primaryContainer,
          theme.colorScheme.onPrimaryContainer,
          'FULL COLOR'
        ),
      _ => (
          Icons.event_outlined,
          theme.colorScheme.surfaceContainerHighest,
          theme.colorScheme.onSurfaceVariant,
          _statusLabel(item['status']?.toString())
        ),
    };

    return Card(
      color: isEvent ? null : background.withValues(alpha: 0.58),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: isEvent ? () => _openDetails(item) : () => _openAnniversary(item),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              CircleAvatar(
                backgroundColor: background,
                foregroundColor: foreground,
                child: Icon(icon),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Wrap(
                      spacing: 8,
                      runSpacing: 6,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        Text(
                          item['name']?.toString() ?? 'Evento',
                          style: theme.textTheme.titleMedium,
                        ),
                        Chip(
                          visualDensity: VisualDensity.compact,
                          label: Text(badge),
                        ),
                      ],
                    ),
                    const SizedBox(height: 5),
                    Text(
                      isEvent ? _dateTimePt(date) : _datePt(date),
                      style: theme.textTheme.bodyMedium,
                    ),
                    if (isEvent &&
                        item['location']?.toString().trim().isNotEmpty == true)
                      Padding(
                        padding: const EdgeInsets.only(top: 3),
                        child: Text(
                          item['location'].toString(),
                          style: theme.textTheme.bodySmall,
                        ),
                      ),
                    if (!isEvent &&
                        (int.tryParse(item['anniversary_years']?.toString() ?? '') ??
                                0) >
                            0)
                      Padding(
                        padding: const EdgeInsets.only(top: 3),
                        child: Text(
                          _anniversarySubtitle(item),
                          style: theme.textTheme.bodySmall,
                        ),
                      ),
                  ],
                ),
              ),
              if (isEvent && _canManage)
                IconButton(
                  tooltip: 'Editar evento',
                  onPressed: () => _openEvent(item),
                  icon: const Icon(Icons.edit_outlined),
                )
              else
                const Icon(Icons.chevron_right),
            ],
          ),
        ),
      ),
    );
  }
}

class EventDetailScreen extends StatefulWidget {
  const EventDetailScreen({
    super.key,
    required this.event,
    required this.repository,
    required this.memberRepository,
  });

  final Map<String, dynamic> event;
  final EventsRepository repository;
  final MemberRepository memberRepository;

  @override
  State<EventDetailScreen> createState() => _EventDetailScreenState();
}

class _EventDetailScreenState extends State<EventDetailScreen> {
  late Future<_EventDetailData> _future;

  AppRole get _role => AppRole.fromValue(AppSession.instance.role);
  bool get _canManage => PermissionPolicy.allows(
        _role,
        AppPermission.manageEventParticipants,
      );

  @override
  void initState() {
    super.initState();
    _reload();
  }

  void _reload() {
    final id = widget.event['id'].toString();
    _future = Future.wait([
      widget.repository.participants(id),
      widget.repository.volunteers(id),
      widget.repository.financialSummary(id),
    ]).then(
      (values) => _EventDetailData(
        participants: List<Map<String, dynamic>>.from(values[0] as List),
        volunteers: List<Map<String, dynamic>>.from(values[1] as List),
        finance: Map<String, dynamic>.from(values[2] as Map),
      ),
    );
  }

  Future<void> _addPerson({required bool volunteer}) async {
    final members = await widget.memberRepository.listMembers();
    if (!mounted || members.isEmpty) return;
    String memberId = members.first['id'].toString();
    final extra = TextEditingController();
    final saved = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: Text(volunteer ? 'Adicionar voluntário' : 'Adicionar participante'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                DropdownButtonFormField<String>(
                  initialValue: memberId,
                  decoration: const InputDecoration(labelText: 'Membro'),
                  items: members
                      .map(
                        (member) => DropdownMenuItem<String>(
                          value: member['id'].toString(),
                          child: Text(member['full_name'].toString()),
                        ),
                      )
                      .toList(),
                  onChanged: (value) {
                    if (value != null) setDialogState(() => memberId = value);
                  },
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: extra,
                  decoration: InputDecoration(
                    labelText: volunteer ? 'Função' : 'Acompanhante (opcional)',
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: const Text('Cancelar'),
            ),
            FilledButton(
              onPressed: () async {
                final member = members.firstWhere(
                  (row) => row['id'].toString() == memberId,
                );
                try {
                  if (volunteer) {
                    await widget.repository.addVolunteer(
                      eventId: widget.event['id'].toString(),
                      memberId: memberId,
                      memberName: member['full_name'].toString(),
                      functionName: extra.text.trim().isEmpty
                          ? 'Apoio geral'
                          : extra.text.trim(),
                    );
                  } else {
                    await widget.repository.addParticipant(
                      eventId: widget.event['id'].toString(),
                      memberId: memberId,
                      memberName: member['full_name'].toString(),
                      companionName:
                          extra.text.trim().isEmpty ? null : extra.text.trim(),
                    );
                  }
                  if (dialogContext.mounted) {
                    Navigator.pop(dialogContext, true);
                  }
                } catch (error) {
                  if (dialogContext.mounted) {
                    ScaffoldMessenger.of(dialogContext).showSnackBar(
                      SnackBar(content: Text(_friendlyError(error))),
                    );
                  }
                }
              },
              child: const Text('Adicionar'),
            ),
          ],
        ),
      ),
    );
    extra.dispose();
    if (saved == true && mounted) setState(_reload);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(widget.event['name']?.toString() ?? 'Evento')),
      body: FutureBuilder<_EventDetailData>(
        future: _future,
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return Center(child: Text('Erro: ${_friendlyError(snapshot.error!)}'));
          }
          if (!snapshot.hasData) {
            return const Center(child: CircularProgressIndicator());
          }
          final data = snapshot.data!;
          final budget = _money(widget.event['budget']);
          return ListView(
            padding: const EdgeInsets.all(12),
            children: [
              Card(
                child: ListTile(
                  leading: const Icon(Icons.event_outlined),
                  title: Text(
                    widget.event['location']?.toString().trim().isNotEmpty == true
                        ? widget.event['location'].toString()
                        : 'Sem local definido',
                  ),
                  subtitle: Text(
                    _dateTimePt(_parseDate(widget.event['starts_at'])),
                  ),
                  trailing: Chip(
                    label: Text(_statusLabel(widget.event['status']?.toString())),
                  ),
                ),
              ),
              if (widget.event['description']?.toString().trim().isNotEmpty == true)
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Text(widget.event['description'].toString()),
                  ),
                ),
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Wrap(
                    spacing: 24,
                    runSpacing: 12,
                    children: [
                      _metric('Orçamento', budget),
                      _metric('Receitas', _money(data.finance['income'])),
                      _metric('Despesas', _money(data.finance['expense'])),
                      _metric('Resultado', _money(data.finance['result'])),
                    ],
                  ),
                ),
              ),
              _section(
                'Participantes (${data.participants.length})',
                data.participants
                    .map(
                      (row) => ListTile(
                        leading: const Icon(Icons.person_outline),
                        title: Text(row['member_name']?.toString() ?? 'Membro'),
                        subtitle: row['companion_name'] == null
                            ? null
                            : Text('Acompanhante: ${row['companion_name']}'),
                      ),
                    )
                    .toList(),
                action: _canManage
                    ? IconButton(
                        tooltip: 'Adicionar participante',
                        onPressed: () => _addPerson(volunteer: false),
                        icon: const Icon(Icons.person_add_alt_1_outlined),
                      )
                    : null,
              ),
              _section(
                'Voluntariado (${data.volunteers.length})',
                data.volunteers
                    .map(
                      (row) => ListTile(
                        leading: const Icon(Icons.volunteer_activism_outlined),
                        title: Text(row['member_name']?.toString() ?? 'Membro'),
                        subtitle: Text(
                          row['function_name']?.toString() ?? 'Apoio geral',
                        ),
                      ),
                    )
                    .toList(),
                action: _canManage
                    ? IconButton(
                        tooltip: 'Adicionar voluntário',
                        onPressed: () => _addPerson(volunteer: true),
                        icon: const Icon(Icons.add_task_outlined),
                      )
                    : null,
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _metric(String label, String value) => SizedBox(
        width: 130,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(label, style: Theme.of(context).textTheme.labelLarge),
            Text(value, style: Theme.of(context).textTheme.titleLarge),
          ],
        ),
      );

  Widget _section(String title, List<Widget> children, {Widget? action}) => Card(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      title,
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                  ),
                  if (action != null) action,
                ],
              ),
              const Divider(),
              if (children.isEmpty)
                const ListTile(title: Text('Sem registos.'))
              else
                ...children,
            ],
          ),
        ),
      );
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
        IconButton(
          tooltip: 'Mês anterior',
          onPressed: onPrevious,
          icon: const Icon(Icons.chevron_left),
        ),
        Expanded(
          child: Text(
            '${_monthNames[month.month - 1]} ${month.year}',
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.titleLarge,
          ),
        ),
        IconButton(
          tooltip: 'Mês seguinte',
          onPressed: onNext,
          icon: const Icon(Icons.chevron_right),
        ),
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
      width: 170,
      child: Card(
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(value, style: Theme.of(context).textTheme.titleLarge),
              const SizedBox(height: 2),
              Text(label),
            ],
          ),
        ),
      ),
    );
  }
}

class _EventDetailData {
  const _EventDetailData({
    required this.participants,
    required this.volunteers,
    required this.finance,
  });

  final List<Map<String, dynamic>> participants;
  final List<Map<String, dynamic>> volunteers;
  final Map<String, dynamic> finance;
}

String _normalizeStatus(String? value) {
  return switch (value) {
    'published' => 'published',
    'active' => 'active',
    'completed' => 'completed',
    'cancelled' => 'cancelled',
    _ => 'draft',
  };
}

String _statusLabel(String? status) => switch (status) {
      'published' => 'Publicado',
      'active' => 'Em curso',
      'completed' => 'Concluído',
      'cancelled' => 'Cancelado',
      'anniversary' => 'Aniversário',
      _ => 'Rascunho',
    };

String _anniversarySubtitle(Map<String, dynamic> item) {
  final years = int.tryParse(item['anniversary_years']?.toString() ?? '') ?? 0;
  return switch (item['calendar_type']?.toString()) {
    'birthday' => '$years anos',
    'prospect_anniversary' =>
      years == 1 ? '1 ano desde Prospect' : '$years anos desde Prospect',
    'full_color_anniversary' =>
      years == 1 ? '1 ano como Full Color' : '$years anos como Full Color',
    _ => '',
  };
}

DateTime? _parseDate(Object? value) {
  if (value is DateTime) return value;
  final text = value?.toString().trim() ?? '';
  if (text.isEmpty) return null;
  return DateTime.tryParse(text)?.toLocal();
}

String _datePt(DateTime? date) {
  if (date == null) return 'Sem data';
  return '${date.day.toString().padLeft(2, '0')}/${date.month.toString().padLeft(2, '0')}/${date.year}';
}

String _dateTimePt(DateTime? date) {
  if (date == null) return 'Sem data';
  return '${_datePt(date)} • ${date.hour.toString().padLeft(2, '0')}:${date.minute.toString().padLeft(2, '0')}';
}

String _money(Object? value) {
  final amount = value is num
      ? value.toDouble()
      : double.tryParse(value?.toString() ?? '') ?? 0;
  return '${amount.toStringAsFixed(2).replaceAll('.', ',')} €';
}

String _friendlyError(Object error) {
  return error
      .toString()
      .replaceFirst('Bad state: ', '')
      .replaceFirst('Invalid argument(s): ', '');
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
