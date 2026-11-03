import 'package:flutter/material.dart';

import '../core/app_session.dart';
import '../core/permissions.dart';
import '../repositories/events_advanced_repository.dart';
import '../repositories/events_repository.dart';
import 'events_module_screen.dart';

class EventsManagementV2Screen extends StatefulWidget {
  const EventsManagementV2Screen({super.key, this.refreshToken = 0});

  final int refreshToken;

  @override
  State<EventsManagementV2Screen> createState() =>
      _EventsManagementV2ScreenState();
}

class _EventsManagementV2ScreenState extends State<EventsManagementV2Screen> {
  final EventsAdvancedRepository _advanced = EventsAdvancedRepository();
  final EventsRepository _events = EventsRepository();
  late Future<List<dynamic>> _future;
  String _statusFilter = 'all';

  bool get _canManage => AppSession.instance.can(AppPermission.manageEvents);

  @override
  void initState() {
    super.initState();
    _reload();
  }

  @override
  void didUpdateWidget(covariant EventsManagementV2Screen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.refreshToken != widget.refreshToken) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) setState(_reload);
      });
    }
  }

  void _reload() {
    _future = Future.wait<dynamic>([
      _advanced.listProposals(),
      _events.listEvents(),
    ]);
  }

  Future<void> _refresh() async {
    setState(_reload);
    await _future;
  }

  Future<void> _openProposals() async {
    await Navigator.of(context).push<void>(
      MaterialPageRoute(
        builder: (_) => EventProposalsScreen(repository: _advanced),
      ),
    );
    if (mounted) setState(_reload);
  }

  Future<void> _openEvent(Map<String, dynamic> event) async {
    final deleted = await Navigator.of(context).push<bool>(
      MaterialPageRoute<bool>(
        builder: (_) =>
            EventAdvancedScreen(event: event, repository: _advanced),
      ),
    );
    if (!mounted) return;
    setState(_reload);
    if (deleted == true) {
      _snack(context, 'Evento eliminado.');
    }
  }

  Future<void> _editEvent(Map<String, dynamic> event) async {
    if (!_canManage) return;

    final name = TextEditingController(text: event['name']?.toString() ?? '');
    final location = TextEditingController(
      text: event['location']?.toString() ?? '',
    );
    final description = TextEditingController(
      text: event['description']?.toString() ?? '',
    );
    final budget = TextEditingController(
      text: event['budget'] == null ? '' : event['budget'].toString(),
    );
    final capacity = TextEditingController(
      text: event['capacity'] == null ? '' : event['capacity'].toString(),
    );

    DateTime? startsAt = _parseDate(event['starts_at'])?.toLocal();
    DateTime? endsAt = _parseDate(event['ends_at'])?.toLocal();
    String eventKind = _normalizeEventKind(event['event_kind']);
    String status = _normalizeStatus(event['status']);
    bool saving = false;

    final saved = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('Editar evento'),
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
                  DropdownButtonFormField<String>(
                    initialValue: eventKind,
                    decoration: const InputDecoration(
                      labelText: 'Tipo de evento',
                      prefixIcon: Icon(Icons.category_outlined),
                    ),
                    items: const [
                      DropdownMenuItem(value: 'general', child: Text('Evento')),
                      DropdownMenuItem(value: 'ride', child: Text('Passeio')),
                      DropdownMenuItem(
                        value: 'rock_ride_in',
                        child: Text('Rock & Ride In'),
                      ),
                    ],
                    onChanged: saving
                        ? null
                        : (value) {
                            if (value != null) {
                              setDialogState(() => eventKind = value);
                            }
                          },
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
                            final time =
                                pickedTime ?? TimeOfDay.fromDateTime(initial);
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
                        labelText: 'Início — data e hora',
                        prefixIcon: Icon(Icons.calendar_month_outlined),
                        suffixIcon: Icon(Icons.edit_calendar_outlined),
                      ),
                      child: Text(
                        startsAt == null
                            ? 'Selecionar início'
                            : _dateTimePt(startsAt!),
                      ),
                    ),
                  ),
                  const SizedBox(height: 10),
                  InkWell(
                    borderRadius: BorderRadius.circular(12),
                    onTap: saving
                        ? null
                        : () async {
                            final initial =
                                endsAt ??
                                startsAt?.add(const Duration(hours: 2)) ??
                                DateTime.now();
                            final pickedDate = await showDatePicker(
                              context: dialogContext,
                              initialDate: initial,
                              firstDate: DateTime(2000),
                              lastDate: DateTime(2100),
                              helpText: 'Selecionar data de fim',
                            );
                            if (pickedDate == null || !dialogContext.mounted) {
                              return;
                            }
                            final pickedTime = await showTimePicker(
                              context: dialogContext,
                              initialTime: TimeOfDay.fromDateTime(initial),
                              helpText: 'Selecionar hora de fim',
                            );
                            if (!dialogContext.mounted) return;
                            final time =
                                pickedTime ?? TimeOfDay.fromDateTime(initial);
                            setDialogState(() {
                              endsAt = DateTime(
                                pickedDate.year,
                                pickedDate.month,
                                pickedDate.day,
                                time.hour,
                                time.minute,
                              );
                            });
                          },
                    child: InputDecorator(
                      decoration: InputDecoration(
                        labelText: 'Fim — data e hora (opcional)',
                        prefixIcon: const Icon(Icons.event_available_outlined),
                        suffixIcon: endsAt == null
                            ? const Icon(Icons.edit_calendar_outlined)
                            : IconButton(
                                tooltip: 'Remover data de fim',
                                onPressed: saving
                                    ? null
                                    : () => setDialogState(() => endsAt = null),
                                icon: const Icon(Icons.clear),
                              ),
                      ),
                      child: Text(
                        endsAt == null
                            ? 'Sem data de fim definida'
                            : _dateTimePt(endsAt!),
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
                  TextField(
                    controller: capacity,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(
                      labelText: 'Capacidade prevista (opcional)',
                      prefixIcon: Icon(Icons.groups_outlined),
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
                      DropdownMenuItem(
                        value: 'active',
                        child: Text('Em curso'),
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
              onPressed: saving
                  ? null
                  : () => Navigator.pop(dialogContext, false),
              child: const Text('Cancelar'),
            ),
            FilledButton.icon(
              onPressed: saving
                  ? null
                  : () async {
                      if (name.text.trim().isEmpty) {
                        _snack(dialogContext, 'Indica o nome do evento.');
                        return;
                      }
                      if (startsAt == null) {
                        _snack(dialogContext, 'Seleciona a data do evento.');
                        return;
                      }
                      if (endsAt != null && !endsAt!.isAfter(startsAt!)) {
                        _snack(
                          dialogContext,
                          'A data de fim tem de ser posterior ao início.',
                        );
                        return;
                      }
                      final capacityText = capacity.text.trim();
                      final parsedCapacity = capacityText.isEmpty
                          ? null
                          : int.tryParse(capacityText);
                      if (capacityText.isNotEmpty &&
                          (parsedCapacity == null || parsedCapacity <= 0)) {
                        _snack(
                          dialogContext,
                          'A capacidade tem de ser um número inteiro superior a zero.',
                        );
                        return;
                      }

                      setDialogState(() => saving = true);
                      try {
                        await _events.saveEvent(
                          {
                            ...event,
                            'name': name.text.trim(),
                            'description': description.text.trim().isEmpty
                                ? null
                                : description.text.trim(),
                            'location': location.text.trim().isEmpty
                                ? null
                                : location.text.trim(),
                            'starts_at': startsAt!.toIso8601String(),
                            'ends_at': endsAt?.toIso8601String(),
                            'event_kind': eventKind,
                            'capacity': parsedCapacity,
                            'budget':
                                double.tryParse(
                                  budget.text.trim().replaceAll(',', '.'),
                                ) ??
                                0,
                            'status': status,
                          },
                          eventId: event['id']?.toString(),
                        );
                        if (dialogContext.mounted) {
                          Navigator.pop(dialogContext, true);
                        }
                      } catch (error) {
                        if (dialogContext.mounted) {
                          _snack(dialogContext, _friendly(error));
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
    capacity.dispose();

    if (saved == true && mounted) {
      setState(_reload);
      _snack(context, 'Evento atualizado.');
    }
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<List<dynamic>>(
      future: _future,
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return Center(child: Text('Erro: ${_friendly(snapshot.error!)}'));
        }
        if (!snapshot.hasData) {
          return const Center(child: CircularProgressIndicator());
        }

        final proposals = List<Map<String, dynamic>>.from(
          snapshot.data![0] as List,
        );
        final events = List<Map<String, dynamic>>.from(
          snapshot.data![1] as List,
        );
        final pending =
            proposals.where((row) => row['status'] == 'submitted').length;
        final visibleEvents = _statusFilter == 'all'
            ? events
            : events
                .where((row) => row['status']?.toString() == _statusFilter)
                .toList();

        return RefreshIndicator(
          onRefresh: _refresh,
          child: ListView(
            padding: const EdgeInsets.fromLTRB(12, 12, 12, 96),
            children: [
              Card(
                child: ListTile(
                  leading: const CircleAvatar(
                    child: Icon(Icons.how_to_vote_outlined),
                  ),
                  title: const Text('Propostas de eventos'),
                  subtitle: Text(
                    pending == 0
                        ? 'Sem propostas pendentes'
                        : '$pending proposta${pending == 1 ? '' : 's'} por decidir',
                  ),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: _openProposals,
                ),
              ),
              const SizedBox(height: 12),
              Text(
                'Operação dos eventos',
                style: Theme.of(context).textTheme.titleLarge,
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  ChoiceChip(
                    label: const Text('Todos'),
                    selected: _statusFilter == 'all',
                    onSelected: (_) => setState(() => _statusFilter = 'all'),
                  ),
                  ChoiceChip(
                    label: const Text('Rascunho'),
                    selected: _statusFilter == 'draft',
                    onSelected: (_) => setState(() => _statusFilter = 'draft'),
                  ),
                  ChoiceChip(
                    label: const Text('Publicado'),
                    selected: _statusFilter == 'published',
                    onSelected: (_) =>
                        setState(() => _statusFilter = 'published'),
                  ),
                  ChoiceChip(
                    label: const Text('Em curso'),
                    selected: _statusFilter == 'active',
                    onSelected: (_) => setState(() => _statusFilter = 'active'),
                  ),
                  ChoiceChip(
                    label: const Text('Concluído'),
                    selected: _statusFilter == 'completed',
                    onSelected: (_) =>
                        setState(() => _statusFilter = 'completed'),
                  ),
                  ChoiceChip(
                    label: const Text('Cancelado'),
                    selected: _statusFilter == 'cancelled',
                    onSelected: (_) =>
                        setState(() => _statusFilter = 'cancelled'),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              if (events.isEmpty)
                const Card(
                  child: ListTile(
                    leading: Icon(Icons.event_busy_outlined),
                    title: Text('Ainda não existem eventos.'),
                  ),
                )
              else if (visibleEvents.isEmpty)
                const Card(
                  child: ListTile(
                    leading: Icon(Icons.filter_alt_off_outlined),
                    title: Text('Sem eventos neste estado.'),
                  ),
                )
              else
                ...visibleEvents.map(
                  (event) => Card(
                    child: ListTile(
                      leading: CircleAvatar(
                        child: Icon(_eventIcon(event['event_kind'])),
                      ),
                      title: Text(event['name']?.toString() ?? 'Evento'),
                      subtitle: Text(
                        '${eventKindLabel(event['event_kind'])} • ${_eventStatusLabel(event['status'])} • ${_date(event['starts_at'])}\n${event['location']?.toString().trim().isNotEmpty == true ? event['location'] : 'Local por definir'}',
                      ),
                      isThreeLine: true,
                      trailing: _canManage
                          ? Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                IconButton(
                                  tooltip: 'Editar evento',
                                  onPressed: () => _editEvent(event),
                                  icon: const Icon(Icons.edit_outlined),
                                ),
                                const Icon(Icons.chevron_right),
                              ],
                            )
                          : const Icon(Icons.chevron_right),
                      onTap: () => _openEvent(event),
                    ),
                  ),
                ),
            ],
          ),
        );
      },
    );
  }
}

IconData _eventIcon(Object? kind) => switch (kind?.toString()) {
      'ride' => Icons.two_wheeler_outlined,
      'rock_ride_in' => Icons.music_note_outlined,
      _ => Icons.event_outlined,
    };

String _eventStatusLabel(Object? status) => switch (status?.toString()) {
      'published' => 'Publicado',
      'active' => 'Em curso',
      'completed' => 'Concluído',
      'cancelled' => 'Cancelado',
      _ => 'Rascunho',
    };

String _normalizeEventKind(Object? value) => switch (value?.toString()) {
      'ride' => 'ride',
      'rock_ride_in' => 'rock_ride_in',
      _ => 'general',
    };

String _normalizeStatus(Object? value) => switch (value?.toString()) {
      'published' => 'published',
      'active' => 'active',
      'completed' => 'completed',
      'cancelled' => 'cancelled',
      _ => 'draft',
    };

DateTime? _parseDate(Object? value) {
  if (value is DateTime) return value;
  return DateTime.tryParse(value?.toString() ?? '');
}

String _date(Object? value) {
  final date = _parseDate(value)?.toLocal();
  if (date == null) return 'Data por definir';
  return '${date.day.toString().padLeft(2, '0')}/${date.month.toString().padLeft(2, '0')}/${date.year}';
}

String _dateTimePt(DateTime value) {
  final date = value.toLocal();
  return '${date.day.toString().padLeft(2, '0')}/${date.month.toString().padLeft(2, '0')}/${date.year} • ${date.hour.toString().padLeft(2, '0')}:${date.minute.toString().padLeft(2, '0')}';
}

String _friendly(Object error) {
  if (error is StateError) return error.message.toString();
  if (error is ArgumentError) {
    return error.message?.toString() ?? 'Dados inválidos.';
  }
  final text = error.toString();
  return text.startsWith('Exception: ') ? text.substring(11) : text;
}

void _snack(BuildContext context, String text) {
  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(content: Text(text)));
}
