import 'package:flutter/material.dart';

import '../core/app_session.dart';
import '../core/permissions.dart';
import '../repositories/events_advanced_repository.dart';
import '../repositories/events_repository.dart';
import '../repositories/member_repository.dart';
import 'events_agenda_v2_screen.dart';
import 'events_screen.dart';
import 'roadbook_stops_screen.dart';

class EventsModuleScreen extends StatefulWidget {
  const EventsModuleScreen({super.key});

  @override
  State<EventsModuleScreen> createState() => _EventsModuleScreenState();
}

class _EventsModuleScreenState extends State<EventsModuleScreen> {
  int _index = 0;
  int _agendaRefreshToken = 0;
  int _managementRefreshToken = 0;

  void _selectTab(int value) {
    if (value == _index) return;
    setState(() {
      _index = value;
      if (value == 0) {
        _agendaRefreshToken++;
      } else {
        _managementRefreshToken++;
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: IndexedStack(
        index: _index,
        children: [
          EventsScreen(refreshToken: _agendaRefreshToken),
          EventsAdvancedHomeScreen(refreshToken: _managementRefreshToken),
        ],
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _index,
        onDestinationSelected: _selectTab,
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.calendar_month_outlined),
            selectedIcon: Icon(Icons.calendar_month),
            label: 'Agenda',
          ),
          NavigationDestination(
            icon: Icon(Icons.event_note_outlined),
            selectedIcon: Icon(Icons.event_note),
            label: 'Gestão',
          ),
        ],
      ),
    );
  }
}

class EventsAdvancedHomeScreen extends StatefulWidget {
  const EventsAdvancedHomeScreen({super.key, this.refreshToken = 0});

  final int refreshToken;

  @override
  State<EventsAdvancedHomeScreen> createState() =>
      _EventsAdvancedHomeScreenState();
}

class _EventsAdvancedHomeScreenState extends State<EventsAdvancedHomeScreen> {
  final EventsAdvancedRepository _advanced = EventsAdvancedRepository();
  final EventsRepository _events = EventsRepository();
  late Future<List<dynamic>> _future;
  String _statusFilter = 'all';

  @override
  void initState() {
    super.initState();
    _reload();
  }

  @override
  void didUpdateWidget(covariant EventsAdvancedHomeScreen oldWidget) {
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
        final pending = proposals
            .where((row) => row['status'] == 'submitted')
            .length;
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
                      trailing: const Icon(Icons.chevron_right),
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

class EventProposalsScreen extends StatefulWidget {
  const EventProposalsScreen({super.key, required this.repository});

  final EventsAdvancedRepository repository;

  @override
  State<EventProposalsScreen> createState() => _EventProposalsScreenState();
}

class _EventProposalsScreenState extends State<EventProposalsScreen> {
  late Future<List<Map<String, dynamic>>> _future;

  @override
  void initState() {
    super.initState();
    _reload();
  }

  void _reload() => _future = widget.repository.listProposals();

  Future<void> _newProposal() async {
    final name = TextEditingController();
    final location = TextEditingController();
    final description = TextEditingController();
    String kind = 'general';
    DateTime? startsAt;
    bool saving = false;

    final saved = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('Propor evento'),
          content: SizedBox(
            width: 520,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextField(
                    controller: name,
                    decoration: const InputDecoration(labelText: 'Nome'),
                  ),
                  const SizedBox(height: 10),
                  DropdownButtonFormField<String>(
                    initialValue: kind,
                    decoration: const InputDecoration(labelText: 'Tipo'),
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
                              setDialogState(() => kind = value);
                            }
                          },
                  ),
                  const SizedBox(height: 10),
                  TextField(
                    controller: location,
                    decoration: const InputDecoration(labelText: 'Local'),
                  ),
                  const SizedBox(height: 10),
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: const Icon(Icons.calendar_month_outlined),
                    title: Text(
                      startsAt == null
                          ? 'Data por definir'
                          : _dateTime(startsAt),
                    ),
                    trailing: const Icon(Icons.edit_calendar_outlined),
                    onTap: saving
                        ? null
                        : () async {
                            final picked = await showDatePicker(
                              context: dialogContext,
                              initialDate: startsAt ?? DateTime.now(),
                              firstDate: DateTime.now().subtract(
                                const Duration(days: 365),
                              ),
                              lastDate: DateTime.now().add(
                                const Duration(days: 3650),
                              ),
                            );
                            if (picked == null || !dialogContext.mounted) {
                              return;
                            }
                            final time = await showTimePicker(
                              context: dialogContext,
                              initialTime: TimeOfDay.fromDateTime(
                                startsAt ?? DateTime.now(),
                              ),
                            );
                            if (!dialogContext.mounted) return;
                            final resolved =
                                time ?? const TimeOfDay(hour: 9, minute: 0);
                            setDialogState(() {
                              startsAt = DateTime(
                                picked.year,
                                picked.month,
                                picked.day,
                                resolved.hour,
                                resolved.minute,
                              );
                            });
                          },
                  ),
                  const SizedBox(height: 10),
                  TextField(
                    controller: description,
                    minLines: 2,
                    maxLines: 4,
                    decoration: const InputDecoration(
                      labelText: 'Descrição / notas',
                    ),
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
                      if (name.text.trim().isEmpty) return;
                      setDialogState(() => saving = true);
                      try {
                        await widget.repository.submitProposal(
                          name: name.text,
                          description: description.text,
                          location: location.text,
                          startsAt: startsAt,
                          eventKind: kind,
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
              icon: const Icon(Icons.send_outlined),
              label: Text(saving ? 'A enviar...' : 'Enviar'),
            ),
          ],
        ),
      ),
    );
    name.dispose();
    location.dispose();
    description.dispose();
    if (saved == true && mounted) setState(_reload);
  }

  Future<void> _decision(Map<String, dynamic> row, bool approve) async {
    final notes = TextEditingController();
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(approve ? 'Aprovar proposta' : 'Rejeitar proposta'),
        content: TextField(
          controller: notes,
          minLines: 2,
          maxLines: 4,
          decoration: const InputDecoration(labelText: 'Observação'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: Text(approve ? 'Aprovar' : 'Rejeitar'),
          ),
        ],
      ),
    );
    if (confirmed != true) {
      notes.dispose();
      return;
    }
    try {
      if (approve) {
        await widget.repository.approveProposal(
          row['id'].toString(),
          notes: notes.text,
        );
      } else {
        await widget.repository.rejectProposal(
          row['id'].toString(),
          notes: notes.text,
        );
      }
      if (mounted) setState(_reload);
    } catch (error) {
      if (mounted) _snack(context, _friendly(error));
    } finally {
      notes.dispose();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Propostas de eventos')),
      body: FutureBuilder<List<Map<String, dynamic>>>(
        future: _future,
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return Center(child: Text(_friendly(snapshot.error!)));
          }
          if (!snapshot.hasData) {
            return const Center(child: CircularProgressIndicator());
          }
          final rows = snapshot.data!;
          return ListView(
            padding: const EdgeInsets.fromLTRB(12, 12, 12, 96),
            children: [
              if (rows.isEmpty)
                const Card(child: ListTile(title: Text('Sem propostas.')))
              else
                ...rows.map((row) {
                  final pending = row['status'] == 'submitted';
                  final mine =
                      row['proposed_by']?.toString() ==
                      AppSession.instance.profileId;
                  return Card(
                    child: Padding(
                      padding: const EdgeInsets.all(12),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Expanded(
                                child: Text(
                                  row['name']?.toString() ?? 'Proposta',
                                  style: Theme.of(context)
                                      .textTheme
                                      .titleMedium,
                                ),
                              ),
                              Chip(
                                label: Text(proposalStatusLabel(row['status'])),
                              ),
                            ],
                          ),
                          const SizedBox(height: 4),
                          Text(
                            '${eventKindLabel(row['event_kind'])} • ${_date(row['starts_at'])}',
                          ),
                          if (row['location']?.toString().trim().isNotEmpty ==
                              true)
                            Padding(
                              padding: const EdgeInsets.only(top: 4),
                              child: Text(row['location'].toString()),
                            ),
                          if (row['description']
                                  ?.toString()
                                  .trim()
                                  .isNotEmpty ==
                              true)
                            Padding(
                              padding: const EdgeInsets.only(top: 8),
                              child: Text(row['description'].toString()),
                            ),
                          if (pending && widget.repository.canApprove) ...[
                            const SizedBox(height: 10),
                            Wrap(
                              spacing: 8,
                              children: [
                                FilledButton.icon(
                                  onPressed: () => _decision(row, true),
                                  icon: const Icon(Icons.check),
                                  label: const Text('Aprovar'),
                                ),
                                OutlinedButton.icon(
                                  onPressed: () => _decision(row, false),
                                  icon: const Icon(Icons.close),
                                  label: const Text('Rejeitar'),
                                ),
                              ],
                            ),
                          ] else if (pending && mine) ...[
                            const SizedBox(height: 8),
                            TextButton.icon(
                              onPressed: () async {
                                try {
                                  await widget.repository.withdrawProposal(
                                    row['id'].toString(),
                                  );
                                  if (mounted) setState(_reload);
                                } catch (error) {
                                  if (mounted) {
                                    _snack(this.context, _friendly(error));
                                  }
                                }
                              },
                              icon: const Icon(Icons.undo),
                              label: const Text('Retirar proposta'),
                            ),
                          ],
                        ],
                      ),
                    ),
                  );
                }),
            ],
          );
        },
      ),
      floatingActionButton: widget.repository.canPropose
          ? FloatingActionButton.extended(
              onPressed: _newProposal,
              icon: const Icon(Icons.add),
              label: const Text('Propor'),
            )
          : null,
    );
  }
}

class EventAdvancedScreen extends StatefulWidget {
  const EventAdvancedScreen({
    super.key,
    required this.event,
    required this.repository,
  });

  final Map<String, dynamic> event;
  final EventsAdvancedRepository repository;

  @override
  State<EventAdvancedScreen> createState() => _EventAdvancedScreenState();
}

class _EventAdvancedScreenState extends State<EventAdvancedScreen> {
  final EventsRepository _events = EventsRepository();
  late Future<Map<String, dynamic>> _future;
  bool _deleting = false;

  String get _eventId => widget.event['id'].toString();
  bool get _canManageEvent =>
      AppSession.instance.can(AppPermission.manageEvents);

  @override
  void initState() {
    super.initState();
    _reload();
  }

  void _reload() => _future = widget.repository.overview(_eventId);

  Future<void> _open(Widget screen) async {
    await Navigator.of(context)
        .push<void>(MaterialPageRoute(builder: (_) => screen));
    if (mounted) setState(_reload);
  }

  Future<void> _deleteEvent() async {
    if (_deleting || !_canManageEvent) return;
    final eventName = widget.event['name']?.toString().trim().isNotEmpty == true
        ? widget.event['name'].toString().trim()
        : 'este evento';
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (confirmContext) => AlertDialog(
        title: const Text('Eliminar evento'),
        content: Text(
          'Queres eliminar o evento “$eventName”?\n\n'
          'Roadbooks, paragens, participantes, voluntários, turnos, tarefas e outros dados operacionais associados serão eliminados. '
          'Registos financeiros ou de inventário relacionados são preservados, mas deixam de ficar associados ao evento.\n\n'
          'Esta ação não pode ser anulada.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(confirmContext, false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(confirmContext).colorScheme.error,
              foregroundColor: Theme.of(confirmContext).colorScheme.onError,
            ),
            onPressed: () => Navigator.pop(confirmContext, true),
            child: const Text('Eliminar'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    setState(() => _deleting = true);
    try {
      await _events.deleteEvent(_eventId);
      if (!mounted) return;
      Navigator.of(context).pop(true);
    } catch (error) {
      if (!mounted) return;
      setState(() => _deleting = false);
      _snack(context, _friendly(error));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(widget.event['name']?.toString() ?? 'Evento')),
      body: FutureBuilder<Map<String, dynamic>>(
        future: _future,
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return Center(child: Text(_friendly(snapshot.error!)));
          }
          if (!snapshot.hasData) {
            return const Center(child: CircularProgressIndicator());
          }
          final data = snapshot.data!;
          return ListView(
            padding: const EdgeInsets.all(12),
            children: [
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          CircleAvatar(
                            child: Icon(_eventIcon(widget.event['event_kind'])),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  eventKindLabel(widget.event['event_kind']),
                                  style: Theme.of(context).textTheme.titleLarge,
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  widget.event['location']
                                              ?.toString()
                                              .trim()
                                              .isNotEmpty ==
                                          true
                                      ? widget.event['location'].toString()
                                      : 'Local por definir',
                                ),
                              ],
                            ),
                          ),
                          Chip(
                            label: Text(
                              _eventStatusLabel(widget.event['status']),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 16),
                      const Divider(height: 1),
                      const SizedBox(height: 12),
                      _EventInfoRow(
                        icon: Icons.play_circle_outline,
                        label: 'Início',
                        value: _dateTimeValue(widget.event['starts_at']),
                      ),
                      const SizedBox(height: 8),
                      _EventInfoRow(
                        icon: Icons.stop_circle_outlined,
                        label: 'Fim',
                        value: _dateTimeValue(
                          widget.event['ends_at'],
                          empty: 'Por definir',
                        ),
                      ),
                      const SizedBox(height: 8),
                      _EventInfoRow(
                        icon: Icons.groups_outlined,
                        label: 'Capacidade prevista',
                        value: _capacityLabel(widget.event['capacity']),
                      ),
                      const SizedBox(height: 8),
                      _EventInfoRow(
                        icon: Icons.euro_outlined,
                        label: 'Orçamento',
                        value: _moneyValue(widget.event['budget']),
                      ),
                      if (widget.event['description']
                              ?.toString()
                              .trim()
                              .isNotEmpty ==
                          true) ...[
                        const SizedBox(height: 12),
                        const Divider(height: 1),
                        const SizedBox(height: 12),
                        Text(
                          'Descrição / notas',
                          style: Theme.of(context).textTheme.labelLarge,
                        ),
                        const SizedBox(height: 4),
                        Text(widget.event['description'].toString()),
                      ],
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 8),
              _HubTile(
                icon: Icons.groups_outlined,
                title: 'Participantes e acompanhantes',
                subtitle: 'Gerir inscrições e acompanhantes',
                onTap: () => _open(
                  EventDetailV2Screen(
                    event: widget.event,
                    repository: _events,
                    memberRepository: MemberRepository(),
                  ),
                ),
              ),
              _HubTile(
                icon: Icons.route_outlined,
                title: 'Roadbook',
                subtitle: '${data['routes']} percurso(s)',
                onTap: () => _open(
                  _RoadbookPage(
                    eventId: _eventId,
                    repository: widget.repository,
                  ),
                ),
              ),
              _HubTile(
                icon: Icons.health_and_safety_outlined,
                title: 'Vista de emergência',
                subtitle: 'Contactos dos participantes do passeio',
                onTap: () => _open(
                  _EmergencyEventPage(
                    eventId: _eventId,
                    repository: widget.repository,
                  ),
                ),
              ),
              _HubTile(
                icon: Icons.construction_outlined,
                title: 'Operação',
                subtitle:
                    '${data['tasks_open']} tarefa(s) abertas • ${data['shifts']} turno(s) • ${data['incidents_open']} incidente(s)',
                onTap: () => _open(
                  _EventOperationsPage(
                    eventId: _eventId,
                    repository: widget.repository,
                  ),
                ),
              ),
              _HubTile(
                icon: Icons.music_note_outlined,
                title: 'Rock & Ride In',
                subtitle:
                    '${data['bands']} bandas • ${data['exhibitors']} expositores • ${data['sponsors']} apoios',
                onTap: () => _open(
                  _RockRidePage(
                    eventId: _eventId,
                    repository: widget.repository,
                  ),
                ),
              ),
              if (_canManageEvent) ...[
                const SizedBox(height: 12),
                Card(
                  child: ListTile(
                    leading: Icon(
                      Icons.delete_outline,
                      color: Theme.of(context).colorScheme.error,
                    ),
                    title: Text(
                      'Eliminar evento',
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.error,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    subtitle: const Text(
                      'Remove este evento e os dados operacionais associados.',
                    ),
                    trailing: _deleting
                        ? const SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : Icon(
                            Icons.chevron_right,
                            color: Theme.of(context).colorScheme.error,
                          ),
                    onTap: _deleting ? null : _deleteEvent,
                  ),
                ),
              ],
            ],
          );
        },
      ),
    );
  }
}

class _EventInfoRow extends StatelessWidget {
  const _EventInfoRow({
    required this.icon,
    required this.label,
    required this.value,
  });

  final IconData icon;
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 20),
        const SizedBox(width: 10),
        SizedBox(
          width: 145,
          child: Text(label, style: Theme.of(context).textTheme.labelLarge),
        ),
        const SizedBox(width: 8),
        Expanded(child: Text(value)),
      ],
    );
  }
}

class _GuestsPage extends StatefulWidget {
  const _GuestsPage({required this.eventId, required this.repository});

  final String eventId;
  final EventsAdvancedRepository repository;

  @override
  State<_GuestsPage> createState() => _GuestsPageState();
}

class _GuestsPageState extends State<_GuestsPage> {
  final EventsRepository _events = EventsRepository();
  late Future<List<Map<String, dynamic>>> _future;

  @override
  void initState() {
    super.initState();
    _reload();
  }

  void _reload() => _future = widget.repository.listGuests(widget.eventId);

  Future<void> _add() async {
    final participants = await _events.participants(widget.eventId);
    if (!mounted) return;
    if (participants.isEmpty) {
      _snack(
        context,
        'Adiciona primeiro o membro aos participantes do evento.',
      );
      return;
    }
    Map<String, dynamic> host = participants.first;
    final name = TextEditingController();
    final saved = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('Novo acompanhante'),
          content: SizedBox(
            width: 480,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                DropdownButtonFormField<String>(
                  initialValue: host['member_id'].toString(),
                  decoration: const InputDecoration(
                    labelText: 'Membro anfitrião',
                  ),
                  items: participants
                      .map(
                        (row) => DropdownMenuItem<String>(
                          value: row['member_id'].toString(),
                          child: Text(
                            row['member_name']?.toString() ?? 'Membro',
                          ),
                        ),
                      )
                      .toList(),
                  onChanged: (value) {
                    if (value == null) return;
                    setDialogState(() {
                      host = participants.firstWhere(
                        (row) => row['member_id'].toString() == value,
                      );
                    });
                  },
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: name,
                  decoration: const InputDecoration(
                    labelText: 'Nome do acompanhante',
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
                if (name.text.trim().isEmpty) return;
                try {
                  await widget.repository.addGuest(
                    eventId: widget.eventId,
                    hostMemberId: host['member_id'].toString(),
                    registrationId: host['id'].toString(),
                    name: name.text,
                  );
                  if (dialogContext.mounted) {
                    Navigator.pop(dialogContext, true);
                  }
                } catch (error) {
                  if (dialogContext.mounted) {
                    _snack(dialogContext, _friendly(error));
                  }
                }
              },
              child: const Text('Guardar'),
            ),
          ],
        ),
      ),
    );
    name.dispose();
    if (saved == true && mounted) setState(_reload);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Acompanhantes')),
      body: _SimpleFutureList(
        future: _future,
        emptyText: 'Sem acompanhantes registados.',
        title: (row) => row['name']?.toString() ?? 'Acompanhante',
        subtitle: (row) => row['status']?.toString() ?? 'confirmed',
      ),
      floatingActionButton: widget.repository.canManageParticipants
          ? FloatingActionButton.extended(
              onPressed: _add,
              icon: const Icon(Icons.add),
              label: const Text('Adicionar'),
            )
          : null,
    );
  }
}

class _RoadbookPage extends StatefulWidget {
  const _RoadbookPage({required this.eventId, required this.repository});

  final String eventId;
  final EventsAdvancedRepository repository;

  @override
  State<_RoadbookPage> createState() => _RoadbookPageState();
}

class _RoadbookPageState extends State<_RoadbookPage> {
  late Future<List<Map<String, dynamic>>> _future;

  @override
  void initState() {
    super.initState();
    _reload();
  }

  void _reload() => _future = widget.repository.listRoutes(widget.eventId);

  Future<void> _refreshRoadbooks() async {
    final next = widget.repository.listRoutes(widget.eventId);
    if (!mounted) return;
    setState(() {
      _future = next;
    });
    await next;
  }

  Future<void> _editRoadbook({Map<String, dynamic>? route}) async {
    final editing = route != null;
    final name = TextEditingController(
      text: route?['name']?.toString() ?? 'Roadbook principal',
    );
    final start = TextEditingController(
      text: route?['start_location']?.toString() ?? '',
    );
    final end = TextEditingController(
      text: route?['end_location']?.toString() ?? '',
    );
    final distance = TextEditingController(
      text: route?['distance_km']?.toString() ?? '',
    );
    final saved = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(editing ? 'Editar roadbook' : 'Novo roadbook'),
        content: SizedBox(
          width: 500,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: name,
                  decoration: const InputDecoration(labelText: 'Nome'),
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: start,
                  decoration: const InputDecoration(labelText: 'Partida'),
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: end,
                  decoration: const InputDecoration(labelText: 'Destino'),
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: distance,
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                  decoration: const InputDecoration(
                    labelText: 'Distância (km)',
                  ),
                ),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () async {
              if (name.text.trim().isEmpty) return;
              try {
                await widget.repository.saveRoute(widget.eventId, {
                  'name': name.text.trim(),
                  'start_location': _nullText(start.text),
                  'end_location': _nullText(end.text),
                  'distance_km': double.tryParse(
                    distance.text.replaceAll(',', '.'),
                  ),
                }, id: route?['id']?.toString());
                if (dialogContext.mounted) {
                  Navigator.pop(dialogContext, true);
                }
              } catch (error) {
                if (dialogContext.mounted) {
                  _snack(dialogContext, _friendly(error));
                }
              }
            },
            child: const Text('Guardar'),
          ),
        ],
      ),
    );
    name.dispose();
    start.dispose();
    end.dispose();
    distance.dispose();
    if (saved == true && mounted) {
      try {
        await _refreshRoadbooks();
        if (mounted) {
          _snack(
            context,
            editing ? 'Roadbook atualizado.' : 'Roadbook adicionado.',
          );
        }
      } catch (error) {
        if (mounted) _snack(context, _friendly(error));
      }
    }
  }

  Future<void> _deleteRoadbook(Map<String, dynamic> route) async {
    final routeId = route['id']?.toString().trim() ?? '';
    if (routeId.isEmpty) {
      _snack(context, 'Não foi possível identificar o Roadbook.');
      return;
    }
    final routeName = route['name']?.toString().trim() ?? '';
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Eliminar roadbook'),
        content: Text(
          routeName.isEmpty
              ? 'Queres eliminar este Roadbook? Todas as paragens associadas serão também eliminadas. Esta ação não pode ser anulada.'
              : 'Queres eliminar o Roadbook "$routeName"? Todas as paragens associadas serão também eliminadas. Esta ação não pode ser anulada.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(dialogContext).colorScheme.error,
              foregroundColor: Theme.of(dialogContext).colorScheme.onError,
            ),
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Eliminar'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    try {
      await widget.repository.deleteRoute(
        eventId: widget.eventId,
        routeId: routeId,
      );
      await _refreshRoadbooks();
      if (mounted) _snack(context, 'Roadbook eliminado.');
    } catch (error) {
      if (mounted) _snack(context, _friendly(error));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Roadbook')),
      body: FutureBuilder<List<Map<String, dynamic>>>(
        future: _future,
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return Center(child: Text(_friendly(snapshot.error!)));
          }
          if (!snapshot.hasData) {
            return const Center(child: CircularProgressIndicator());
          }
          final rows = snapshot.data!;
          return ListView(
            padding: const EdgeInsets.fromLTRB(12, 12, 12, 96),
            children: rows.isEmpty
                ? [
                    const Card(
                      child: ListTile(title: Text('Sem roadbook configurado.')),
                    ),
                  ]
                : rows
                      .map(
                        (row) => Card(
                          child: ListTile(
                            leading: const Icon(Icons.route_outlined),
                            title: Text(row['name']?.toString() ?? 'Roadbook'),
                            subtitle: Text(
                              '${row['start_location'] ?? 'Partida'} → ${row['end_location'] ?? 'Destino'}${row['distance_km'] == null ? '' : ' • ${row['distance_km']} km'}',
                            ),
                            trailing: widget.repository.canManageRoadbook
                                ? Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      IconButton(
                                        tooltip: 'Editar roadbook',
                                        onPressed: () =>
                                            _editRoadbook(route: row),
                                        icon: const Icon(Icons.edit_outlined),
                                      ),
                                      IconButton(
                                        tooltip: 'Eliminar roadbook',
                                        color: Theme.of(context)
                                            .colorScheme
                                            .error,
                                        onPressed: () => _deleteRoadbook(row),
                                        icon: const Icon(Icons.delete_outline),
                                      ),
                                      const Icon(Icons.chevron_right),
                                    ],
                                  )
                                : const Icon(Icons.chevron_right),
                            onTap: () async {
                              await Navigator.of(context).push<void>(
                                MaterialPageRoute(
                                  builder: (_) => RoadbookStopsScreen(
                                    eventId: widget.eventId,
                                    route: row,
                                    repository: widget.repository,
                                  ),
                                ),
                              );
                              if (mounted) {
                                await _refreshRoadbooks();
                              }
                            },
                          ),
                        ),
                      )
                      .toList(),
          );
        },
      ),
      floatingActionButton: widget.repository.canManageRoadbook
          ? FloatingActionButton.extended(
              onPressed: () => _editRoadbook(),
              icon: const Icon(Icons.add),
              label: const Text('Roadbook'),
            )
          : null,
    );
  }
}

class _RouteStopsPage extends StatefulWidget {
  const _RouteStopsPage({
    required this.eventId,
    required this.route,
    required this.repository,
  });

  final String eventId;
  final Map<String, dynamic> route;
  final EventsAdvancedRepository repository;

  @override
  State<_RouteStopsPage> createState() => _RouteStopsPageState();
}

class _RouteStopsPageState extends State<_RouteStopsPage> {
  late Future<List<Map<String, dynamic>>> _future;
  bool _reordering = false;

  @override
  void initState() {
    super.initState();
    _reload();
  }

  String get _routeId => widget.route['id'].toString();

  void _reload() => _future = widget.repository.listRouteStops(_routeId);

  Future<void> _refreshStops() async {
    final next = widget.repository.listRouteStops(_routeId);
    if (!mounted) return;
    setState(() {
      _future = next;
    });
    await next;
  }

  int _nextStopSequence(List<Map<String, dynamic>> current) {
    var highest = 0;
    for (final row in current) {
      final sequence = int.tryParse(row['sequence_no']?.toString() ?? '') ?? 0;
      if (sequence > highest) highest = sequence;
    }
    return highest + 1;
  }

  Future<void> _editStop(
    List<Map<String, dynamic>> current, {
    Map<String, dynamic>? stop,
  }) async {
    final editing = stop != null;
    final name = TextEditingController(
      text: editing ? stop['name']?.toString() ?? '' : '',
    );
    final location = TextEditingController(
      text: editing ? stop['location']?.toString() ?? '' : '',
    );
    final saved = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(editing ? 'Editar paragem' : 'Nova paragem'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: name,
              decoration: const InputDecoration(labelText: 'Nome'),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: location,
              decoration: const InputDecoration(labelText: 'Local'),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () async {
              if (name.text.trim().isEmpty) return;
              try {
                await widget.repository.saveRouteStop(
                  eventId: widget.eventId,
                  routeId: _routeId,
                  id: editing ? stop['id']?.toString() : null,
                  values: {
                    'sequence_no': editing
                        ? stop['sequence_no'] ?? current.indexOf(stop) + 1
                        : _nextStopSequence(current),
                    'name': name.text.trim(),
                    'location': _nullText(location.text),
                  },
                );
                if (dialogContext.mounted) {
                  Navigator.pop(dialogContext, true);
                }
              } catch (error) {
                if (dialogContext.mounted) {
                  _snack(dialogContext, _friendly(error));
                }
              }
            },
            child: const Text('Guardar'),
          ),
        ],
      ),
    );
    name.dispose();
    location.dispose();
    if (saved == true && mounted) {
      try {
        await _refreshStops();
        if (mounted) {
          _snack(
            context,
            editing ? 'Paragem atualizada.' : 'Paragem adicionada.',
          );
        }
      } catch (error) {
        if (mounted) _snack(context, _friendly(error));
      }
    }
  }

  Future<void> _deleteStop(Map<String, dynamic> stop) async {
    final stopId = stop['id']?.toString().trim() ?? '';
    if (stopId.isEmpty) {
      _snack(context, 'Não foi possível identificar a paragem.');
      return;
    }
    final stopName = stop['name']?.toString().trim() ?? '';
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Eliminar paragem'),
        content: Text(
          stopName.isEmpty
              ? 'Queres eliminar esta paragem? Esta ação não pode ser anulada.'
              : 'Queres eliminar a paragem "$stopName"? Esta ação não pode ser anulada.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(dialogContext).colorScheme.error,
              foregroundColor: Theme.of(dialogContext).colorScheme.onError,
            ),
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Eliminar'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    try {
      await widget.repository.deleteRouteStop(
        eventId: widget.eventId,
        routeId: _routeId,
        stopId: stopId,
      );
      await _refreshStops();
      if (mounted) _snack(context, 'Paragem eliminada.');
    } catch (error) {
      if (mounted) _snack(context, _friendly(error));
    }
  }

  Future<void> _reorderStops(
    List<Map<String, dynamic>> current,
    int oldIndex,
    int newIndex,
  ) async {
    if (_reordering) return;
    if (oldIndex == newIndex) return;

    final reordered = List<Map<String, dynamic>>.from(current);
    final moved = reordered.removeAt(oldIndex);
    reordered.insert(newIndex, moved);
    for (var index = 0; index < reordered.length; index++) {
      reordered[index]['sequence_no'] = index + 1;
    }

    setState(() {
      _reordering = true;
      current
        ..clear()
        ..addAll(reordered);
    });

    try {
      await widget.repository.reorderRouteStops(
        eventId: widget.eventId,
        routeId: _routeId,
        stopIds: reordered.map((row) => row['id'].toString()).toList(),
      );
      await _refreshStops();
      if (mounted) _snack(context, 'Ordem das paragens atualizada.');
    } catch (error) {
      try {
        await _refreshStops();
      } catch (_) {
        // Mantém a mensagem do erro original de reordenação.
      }
      if (mounted) _snack(context, _friendly(error));
    } finally {
      if (mounted) {
        setState(() {
          _reordering = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.route['name']?.toString() ?? 'Roadbook'),
      ),
      body: FutureBuilder<List<Map<String, dynamic>>>(
        future: _future,
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return Center(child: Text(_friendly(snapshot.error!)));
          }
          if (!snapshot.hasData) {
            return const Center(child: CircularProgressIndicator());
          }
          final rows = snapshot.data!;
          final canManage = widget.repository.canManageRoadbook;
          return Column(
            children: [
              Expanded(
                child: rows.isEmpty
                    ? ListView(
                        padding: const EdgeInsets.all(12),
                        children: const [
                          Card(child: ListTile(title: Text('Sem paragens.'))),
                        ],
                      )
                    : ReorderableListView.builder(
                        padding: const EdgeInsets.fromLTRB(12, 12, 12, 12),
                        buildDefaultDragHandles: false,
                        itemCount: rows.length,
                        onReorderItem: canManage
                            ? (oldIndex, newIndex) async {
                                await _reorderStops(rows, oldIndex, newIndex);
                              }
                            : (_, __) {},
                        itemBuilder: (context, index) {
                          final row = rows[index];
                          return Card(
                            key: ValueKey(
                              'route-stop-${row['id']?.toString() ?? index}',
                            ),
                            child: ListTile(
                              leading: CircleAvatar(
                                child: Text('${row['sequence_no'] ?? ''}'),
                              ),
                              title: Text(row['name']?.toString() ?? 'Paragem'),
                              subtitle: Text(
                                row['location']?.toString() ??
                                    'Local por definir',
                              ),
                              trailing: canManage
                                  ? Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        IconButton(
                                          tooltip: 'Editar paragem',
                                          onPressed: _reordering
                                              ? null
                                              : () =>
                                                    _editStop(rows, stop: row),
                                          icon: const Icon(Icons.edit_outlined),
                                        ),
                                        IconButton(
                                          tooltip: 'Eliminar paragem',
                                          color: Theme.of(context)
                                              .colorScheme
                                              .error,
                                          onPressed: _reordering
                                              ? null
                                              : () => _deleteStop(row),
                                          icon: const Icon(
                                            Icons.delete_outline,
                                          ),
                                        ),
                                        Tooltip(
                                          message: 'Arrastar para reordenar',
                                          child: ReorderableDragStartListener(
                                            index: index,
                                            enabled: !_reordering,
                                            child: const Padding(
                                              padding: EdgeInsets.all(12),
                                              child: Icon(Icons.drag_handle),
                                            ),
                                          ),
                                        ),
                                      ],
                                    )
                                  : null,
                            ),
                          );
                        },
                      ),
              ),
              if (canManage)
                SafeArea(
                  top: false,
                  minimum: const EdgeInsets.fromLTRB(12, 8, 12, 12),
                  child: SizedBox(
                    width: double.infinity,
                    child: FilledButton.icon(
                      onPressed: _reordering ? null : () => _editStop(rows),
                      icon: const Icon(Icons.add_location_alt_outlined),
                      label: const Text('Adicionar paragem'),
                    ),
                  ),
                ),
            ],
          );
        },
      ),
    );
  }
}

class _EmergencyEventPage extends StatelessWidget {
  const _EmergencyEventPage({required this.eventId, required this.repository});

  final String eventId;
  final EventsAdvancedRepository repository;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Emergência do passeio')),
      body: FutureBuilder<List<Map<String, dynamic>>>(
        future: repository.emergencyContacts(eventId),
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return Center(child: Text(_friendly(snapshot.error!)));
          }
          if (!snapshot.hasData) {
            return const Center(child: CircularProgressIndicator());
          }
          final rows = snapshot.data!;
          return ListView(
            padding: const EdgeInsets.all(12),
            children: [
              const Card(
                child: ListTile(
                  leading: Icon(Icons.health_and_safety_outlined),
                  title: Text('Uso apenas em situação de emergência'),
                  subtitle: Text(
                    'Mostra os contactos dos membros inscritos neste evento.',
                  ),
                ),
              ),
              ...rows.map((row) {
                final emergency = row['emergency_contact'];
                final emergencyText = emergency is Map
                    ? emergency.entries
                          .map((entry) => '${entry.key}: ${entry.value}')
                          .join(' • ')
                    : emergency?.toString() ?? 'Sem contacto de emergência';
                return Card(
                  child: ListTile(
                    leading: const CircleAvatar(
                      child: Icon(Icons.person_outline),
                    ),
                    title: Text(
                      row['nickname']?.toString().trim().isNotEmpty == true
                          ? row['nickname'].toString()
                          : row['full_name']?.toString() ?? 'Membro',
                    ),
                    subtitle: Text(
                      'Telefone: ${row['phone'] ?? '—'}\n$emergencyText',
                    ),
                    isThreeLine: true,
                  ),
                );
              }),
            ],
          );
        },
      ),
    );
  }
}

class _RockRidePage extends StatefulWidget {
  const _RockRidePage({required this.eventId, required this.repository});

  final String eventId;
  final EventsAdvancedRepository repository;

  @override
  State<_RockRidePage> createState() => _RockRidePageState();
}

class _RockRidePageState extends State<_RockRidePage> {
  late Future<List<dynamic>> _future;

  @override
  void initState() {
    super.initState();
    _reload();
  }

  void _reload() {
    _future = Future.wait<dynamic>([
      widget.repository.listBands(widget.eventId),
      widget.repository.listExhibitors(widget.eventId),
      widget.repository.listSponsors(widget.eventId),
      widget.repository.getOctaneConfig(widget.eventId),
    ]);
  }

  Future<void> _addNamed(String type) async {
    final name = TextEditingController();
    final extra = TextEditingController();
    final saved = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(switch (type) {
          'band' => 'Nova banda',
          'exhibitor' => 'Novo expositor',
          _ => 'Novo patrocinador',
        }),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: name,
              decoration: const InputDecoration(labelText: 'Nome'),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: extra,
              decoration: InputDecoration(
                labelText: type == 'exhibitor'
                    ? 'Categoria'
                    : 'Valor acordado (€)',
              ),
              keyboardType: type == 'exhibitor'
                  ? TextInputType.text
                  : const TextInputType.numberWithOptions(decimal: true),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () async {
              if (name.text.trim().isEmpty) return;
              try {
                if (type == 'band') {
                  await widget.repository.saveBand(widget.eventId, {
                    'name': name.text.trim(),
                    'agreed_value':
                        double.tryParse(extra.text.replaceAll(',', '.')) ?? 0,
                    'status': 'planned',
                  });
                } else if (type == 'exhibitor') {
                  await widget.repository.saveExhibitor(widget.eventId, {
                    'name': name.text.trim(),
                    'category': _nullText(extra.text),
                    'status': 'planned',
                  });
                } else {
                  await widget.repository.saveSponsor(widget.eventId, {
                    'name': name.text.trim(),
                    'agreed_value':
                        double.tryParse(extra.text.replaceAll(',', '.')) ?? 0,
                    'status': 'planned',
                  });
                }
                if (dialogContext.mounted) {
                  Navigator.pop(dialogContext, true);
                }
              } catch (error) {
                if (dialogContext.mounted) {
                  _snack(dialogContext, _friendly(error));
                }
              }
            },
            child: const Text('Guardar'),
          ),
        ],
      ),
    );
    name.dispose();
    extra.dispose();
    if (saved == true && mounted) setState(_reload);
  }

  Future<void> _octanes(Map<String, dynamic>? current) async {
    final unit = TextEditingController(
      text: '${current?['unit_price'] ?? 1.5}',
    );
    final five = TextEditingController(
      text: '${current?['five_card_price'] ?? 7}',
    );
    final ten = TextEditingController(
      text: '${current?['ten_card_price'] ?? 13}',
    );
    final saved = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Configuração de Octanas'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: unit,
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
              ),
              decoration: const InputDecoration(labelText: '1 Octana (€)'),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: five,
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
              ),
              decoration: const InputDecoration(
                labelText: 'Cartão 5 Octanas (€)',
              ),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: ten,
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
              ),
              decoration: const InputDecoration(labelText: 'Cartão 10 + 1 (€)'),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () async {
              try {
                await widget.repository.saveOctaneConfig(widget.eventId, {
                  'unit_price':
                      double.tryParse(unit.text.replaceAll(',', '.')) ?? 1.5,
                  'five_card_units': 5,
                  'five_card_price':
                      double.tryParse(five.text.replaceAll(',', '.')) ?? 7,
                  'ten_card_units': 10,
                  'ten_card_price':
                      double.tryParse(ten.text.replaceAll(',', '.')) ?? 13,
                  'ten_card_bonus': 1,
                  'active': true,
                }, id: current?['id']?.toString());
                if (dialogContext.mounted) {
                  Navigator.pop(dialogContext, true);
                }
              } catch (error) {
                if (dialogContext.mounted) {
                  _snack(dialogContext, _friendly(error));
                }
              }
            },
            child: const Text('Guardar'),
          ),
        ],
      ),
    );
    unit.dispose();
    five.dispose();
    ten.dispose();
    if (saved == true && mounted) setState(_reload);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Rock & Ride In')),
      body: FutureBuilder<List<dynamic>>(
        future: _future,
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return Center(child: Text(_friendly(snapshot.error!)));
          }
          if (!snapshot.hasData) {
            return const Center(child: CircularProgressIndicator());
          }
          final bands = List<Map<String, dynamic>>.from(
            snapshot.data![0] as List,
          );
          final exhibitors = List<Map<String, dynamic>>.from(
            snapshot.data![1] as List,
          );
          final sponsors = List<Map<String, dynamic>>.from(
            snapshot.data![2] as List,
          );
          final octanes = snapshot.data![3] as Map<String, dynamic>?;
          final canWrite =
              widget.repository.canManageRockRide ||
              widget.repository.canManageFinance;
          return ListView(
            padding: const EdgeInsets.all(12),
            children: [
              _EntitySection(
                title: 'Bandas',
                icon: Icons.music_note_outlined,
                rows: bands,
                canAdd: canWrite,
                onAdd: () => _addNamed('band'),
              ),
              _EntitySection(
                title: 'Expositores',
                icon: Icons.storefront_outlined,
                rows: exhibitors,
                canAdd: canWrite,
                onAdd: () => _addNamed('exhibitor'),
              ),
              _EntitySection(
                title: 'Patrocinadores / Apoios',
                icon: Icons.handshake_outlined,
                rows: sponsors,
                canAdd: canWrite,
                onAdd: () => _addNamed('sponsor'),
              ),
              Card(
                child: ListTile(
                  leading: const Icon(Icons.local_gas_station_outlined),
                  title: const Text('Octanas'),
                  subtitle: Text(
                    octanes == null
                        ? 'Configuração ainda não definida'
                        : '1 = ${octanes['unit_price']} € • 5 = ${octanes['five_card_price']} € • ${octaneCardTotalUnits(octanes)} = ${octanes['ten_card_price']} €',
                  ),
                  trailing: canWrite ? const Icon(Icons.edit_outlined) : null,
                  onTap: canWrite ? () => _octanes(octanes) : null,
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

class _EventOperationsPage extends StatefulWidget {
  const _EventOperationsPage({required this.eventId, required this.repository});

  final String eventId;
  final EventsAdvancedRepository repository;

  @override
  State<_EventOperationsPage> createState() => _EventOperationsPageState();
}

class _EventOperationsPageState extends State<_EventOperationsPage> {
  final MemberRepository _members = MemberRepository();
  final EventsRepository _events = EventsRepository();
  late Future<List<dynamic>> _future;
  bool _reorderingProgram = false;

  @override
  void initState() {
    super.initState();
    _reload();
  }

  void _reload() {
    _future = Future.wait<dynamic>([
      widget.repository.listTasks(widget.eventId),
      widget.repository.listTaskAssignees(widget.eventId),
      widget.repository.listShifts(widget.eventId),
      widget.repository.listShiftMembers(widget.eventId),
      widget.repository.listProgram(widget.eventId),
      widget.repository.listIncidents(widget.eventId),
      _events.volunteers(widget.eventId),
      _members.listMembers(),
    ]);
  }

  Future<void> _refresh() async {
    setState(_reload);
    await _future;
  }

  String _memberName(String? memberId, List<Map<String, dynamic>> members) {
    if (memberId == null) return 'Membro';
    for (final member in members) {
      if (member['id']?.toString() == memberId) {
        final nickname = member['nickname']?.toString().trim() ?? '';
        final fullName = member['full_name']?.toString().trim() ?? '';
        return nickname.isNotEmpty
            ? nickname
            : (fullName.isNotEmpty ? fullName : 'Membro');
      }
    }
    return 'Membro';
  }

  Future<Map<String, dynamic>?> _pickVolunteer(
    List<Map<String, dynamic>> volunteers,
    Set<String> excludedMemberIds,
  ) async {
    final available = volunteers
        .where(
          (row) => !excludedMemberIds.contains(row['member_id']?.toString()),
        )
        .toList();
    if (available.isEmpty) {
      if (mounted) {
        _snack(
          context,
          volunteers.isEmpty
              ? 'Adiciona primeiro voluntários ao evento.'
              : 'Todos os voluntários já estão atribuídos.',
        );
      }
      return null;
    }
    return showDialog<Map<String, dynamic>>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Selecionar voluntário'),
        content: SizedBox(
          width: 480,
          height: 420,
          child: ListView.builder(
            itemCount: available.length,
            itemBuilder: (context, index) {
              final volunteer = available[index];
              return ListTile(
                leading: const CircleAvatar(
                  child: Icon(Icons.volunteer_activism_outlined),
                ),
                title: Text(volunteer['member_name']?.toString() ?? 'Membro'),
                subtitle: Text(
                  volunteer['function_name']?.toString() ?? 'Apoio geral',
                ),
                onTap: () => Navigator.pop(dialogContext, volunteer),
              );
            },
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Cancelar'),
          ),
        ],
      ),
    );
  }

  Future<DateTime?> _pickDateTime(
    BuildContext dialogContext,
    DateTime initial,
    String helpText,
  ) async {
    final date = await showDatePicker(
      context: dialogContext,
      initialDate: initial,
      firstDate: DateTime(2000),
      lastDate: DateTime(2100),
      helpText: helpText,
    );
    if (date == null || !dialogContext.mounted) return null;
    final time = await showTimePicker(
      context: dialogContext,
      initialTime: TimeOfDay.fromDateTime(initial),
      helpText: helpText,
    );
    if (!dialogContext.mounted) return null;
    final resolved = time ?? TimeOfDay.fromDateTime(initial);
    return DateTime(
      date.year,
      date.month,
      date.day,
      resolved.hour,
      resolved.minute,
    );
  }

  Future<void> _editTask([Map<String, dynamic>? task]) async {
    final title = TextEditingController(text: task?['title']?.toString() ?? '');
    final description = TextEditingController(
      text: task?['description']?.toString() ?? '',
    );
    final notes = TextEditingController(text: task?['notes']?.toString() ?? '');
    String priority = switch (task?['priority']?.toString()) {
      'low' || 'high' || 'critical' => task!['priority'].toString(),
      _ => 'normal',
    };
    String status = switch (task?['status']?.toString()) {
      'in_progress' || 'done' || 'cancelled' => task!['status'].toString(),
      _ => 'pending',
    };
    DateTime? dueAt = _parse(task?['due_at'])?.toLocal();
    bool saving = false;

    final saved = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: Text(task == null ? 'Nova tarefa' : 'Editar tarefa'),
          content: SizedBox(
            width: 520,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextField(
                    controller: title,
                    decoration: const InputDecoration(
                      labelText: 'Tarefa',
                      prefixIcon: Icon(Icons.task_alt_outlined),
                    ),
                  ),
                  const SizedBox(height: 10),
                  TextField(
                    controller: description,
                    minLines: 2,
                    maxLines: 4,
                    decoration: const InputDecoration(
                      labelText: 'Descrição (opcional)',
                      prefixIcon: Icon(Icons.description_outlined),
                    ),
                  ),
                  const SizedBox(height: 10),
                  DropdownButtonFormField<String>(
                    initialValue: priority,
                    decoration: const InputDecoration(
                      labelText: 'Prioridade',
                      prefixIcon: Icon(Icons.priority_high_outlined),
                    ),
                    items: const [
                      DropdownMenuItem(value: 'low', child: Text('Baixa')),
                      DropdownMenuItem(value: 'normal', child: Text('Normal')),
                      DropdownMenuItem(value: 'high', child: Text('Alta')),
                      DropdownMenuItem(
                        value: 'critical',
                        child: Text('Crítica'),
                      ),
                    ],
                    onChanged: saving
                        ? null
                        : (value) {
                            if (value != null) {
                              setDialogState(() => priority = value);
                            }
                          },
                  ),
                  const SizedBox(height: 10),
                  DropdownButtonFormField<String>(
                    initialValue: status,
                    decoration: const InputDecoration(
                      labelText: 'Estado',
                      prefixIcon: Icon(Icons.flag_outlined),
                    ),
                    items: const [
                      DropdownMenuItem(
                        value: 'pending',
                        child: Text('Pendente'),
                      ),
                      DropdownMenuItem(
                        value: 'in_progress',
                        child: Text('Em curso'),
                      ),
                      DropdownMenuItem(value: 'done', child: Text('Concluída')),
                      DropdownMenuItem(
                        value: 'cancelled',
                        child: Text('Cancelada'),
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
                  const SizedBox(height: 10),
                  InkWell(
                    borderRadius: BorderRadius.circular(12),
                    onTap: saving
                        ? null
                        : () async {
                            final picked = await _pickDateTime(
                              dialogContext,
                              dueAt ?? DateTime.now(),
                              'Prazo da tarefa',
                            );
                            if (picked != null) {
                              setDialogState(() => dueAt = picked);
                            }
                          },
                    child: InputDecorator(
                      decoration: InputDecoration(
                        labelText: 'Prazo (opcional)',
                        prefixIcon: const Icon(Icons.event_outlined),
                        suffixIcon: dueAt == null
                            ? const Icon(Icons.edit_calendar_outlined)
                            : IconButton(
                                tooltip: 'Remover prazo',
                                onPressed: saving
                                    ? null
                                    : () => setDialogState(() => dueAt = null),
                                icon: const Icon(Icons.clear),
                              ),
                      ),
                      child: Text(
                        dueAt == null ? 'Sem prazo definido' : _dateTime(dueAt),
                      ),
                    ),
                  ),
                  const SizedBox(height: 10),
                  TextField(
                    controller: notes,
                    minLines: 2,
                    maxLines: 4,
                    decoration: const InputDecoration(
                      labelText: 'Notas (opcional)',
                      prefixIcon: Icon(Icons.notes_outlined),
                    ),
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
                      if (title.text.trim().isEmpty) {
                        _snack(dialogContext, 'Indica a tarefa.');
                        return;
                      }
                      setDialogState(() => saving = true);
                      try {
                        await widget.repository.saveTask(widget.eventId, {
                          'title': title.text.trim(),
                          'description': _nullText(description.text),
                          'priority': priority,
                          'status': status,
                          'due_at': dueAt?.toUtc().toIso8601String(),
                          'completed_at': status == 'done'
                              ? (task == null
                                    ? DateTime.now().toUtc().toIso8601String()
                                    : task['completed_at'] ??
                                          DateTime.now()
                                              .toUtc()
                                              .toIso8601String())
                              : null,
                          'notes': _nullText(notes.text),
                        }, id: task?['id']?.toString());
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

    title.dispose();
    description.dispose();
    notes.dispose();
    if (saved == true && mounted) {
      _snack(context, task == null ? 'Tarefa criada.' : 'Tarefa atualizada.');
      setState(_reload);
    }
  }

  Future<void> _deleteTask(Map<String, dynamic> task) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Eliminar tarefa'),
        content: Text(
          'Eliminar “${task['title']?.toString() ?? 'esta tarefa'}”? '
          'As atribuições associadas também serão eliminadas.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Eliminar'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    try {
      await widget.repository.deleteTask(
        eventId: widget.eventId,
        taskId: task['id'].toString(),
      );
      if (!mounted) return;
      _snack(context, 'Tarefa eliminada.');
      setState(_reload);
    } catch (error) {
      if (mounted) _snack(context, _friendly(error));
    }
  }

  Future<void> _assignTask(
    Map<String, dynamic> task,
    List<Map<String, dynamic>> taskAssignees,
    List<Map<String, dynamic>> volunteers,
  ) async {
    final assignedIds = taskAssignees
        .where((row) => row['task_id']?.toString() == task['id']?.toString())
        .map((row) => row['member_id']?.toString())
        .whereType<String>()
        .toSet();
    final volunteer = await _pickVolunteer(volunteers, assignedIds);
    if (volunteer == null) return;
    try {
      await widget.repository.assignTask(
        eventId: widget.eventId,
        taskId: task['id'].toString(),
        memberId: volunteer['member_id'].toString(),
      );
      if (!mounted) return;
      _snack(context, 'Voluntário atribuído à tarefa.');
      setState(_reload);
    } catch (error) {
      if (mounted) _snack(context, _friendly(error));
    }
  }

  Future<void> _removeTaskAssignee(Map<String, dynamic> assignment) async {
    try {
      await widget.repository.removeTaskAssignee(
        eventId: widget.eventId,
        assignmentId: assignment['id'].toString(),
      );
      if (!mounted) return;
      _snack(context, 'Atribuição removida.');
      setState(_reload);
    } catch (error) {
      if (mounted) _snack(context, _friendly(error));
    }
  }

  Future<void> _editShift([Map<String, dynamic>? shift]) async {
    final name = TextEditingController(text: shift?['name']?.toString() ?? '');
    final area = TextEditingController(text: shift?['area']?.toString() ?? '');
    final requiredPeople = TextEditingController(
      text: '${shift?['required_people'] ?? 1}',
    );
    final notes = TextEditingController(
      text: shift?['notes']?.toString() ?? '',
    );
    DateTime startsAt =
        _parse(shift?['starts_at'])?.toLocal() ?? DateTime.now();
    DateTime endsAt =
        _parse(shift?['ends_at'])?.toLocal() ??
        startsAt.add(const Duration(hours: 2));
    String status = switch (shift?['status']?.toString()) {
      'active' || 'completed' || 'cancelled' => shift!['status'].toString(),
      _ => 'planned',
    };
    bool saving = false;

    final saved = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: Text(shift == null ? 'Novo turno' : 'Editar turno'),
          content: SizedBox(
            width: 520,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextField(
                    controller: name,
                    decoration: const InputDecoration(
                      labelText: 'Nome do turno',
                      prefixIcon: Icon(Icons.schedule_outlined),
                    ),
                  ),
                  const SizedBox(height: 10),
                  TextField(
                    controller: area,
                    decoration: const InputDecoration(
                      labelText: 'Área (opcional)',
                      prefixIcon: Icon(Icons.place_outlined),
                    ),
                  ),
                  const SizedBox(height: 10),
                  InkWell(
                    borderRadius: BorderRadius.circular(12),
                    onTap: saving
                        ? null
                        : () async {
                            final picked = await _pickDateTime(
                              dialogContext,
                              startsAt,
                              'Início do turno',
                            );
                            if (picked != null) {
                              setDialogState(() => startsAt = picked);
                            }
                          },
                    child: InputDecorator(
                      decoration: const InputDecoration(
                        labelText: 'Início',
                        prefixIcon: Icon(Icons.login_outlined),
                        suffixIcon: Icon(Icons.edit_calendar_outlined),
                      ),
                      child: Text(_dateTime(startsAt)),
                    ),
                  ),
                  const SizedBox(height: 10),
                  InkWell(
                    borderRadius: BorderRadius.circular(12),
                    onTap: saving
                        ? null
                        : () async {
                            final picked = await _pickDateTime(
                              dialogContext,
                              endsAt,
                              'Fim do turno',
                            );
                            if (picked != null) {
                              setDialogState(() => endsAt = picked);
                            }
                          },
                    child: InputDecorator(
                      decoration: const InputDecoration(
                        labelText: 'Fim',
                        prefixIcon: Icon(Icons.logout_outlined),
                        suffixIcon: Icon(Icons.edit_calendar_outlined),
                      ),
                      child: Text(_dateTime(endsAt)),
                    ),
                  ),
                  const SizedBox(height: 10),
                  TextField(
                    controller: requiredPeople,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(
                      labelText: 'Pessoas necessárias',
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
                      DropdownMenuItem(
                        value: 'planned',
                        child: Text('Planeado'),
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
                  const SizedBox(height: 10),
                  TextField(
                    controller: notes,
                    minLines: 2,
                    maxLines: 4,
                    decoration: const InputDecoration(
                      labelText: 'Notas (opcional)',
                      prefixIcon: Icon(Icons.notes_outlined),
                    ),
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
                        _snack(dialogContext, 'Indica o nome do turno.');
                        return;
                      }
                      if (!endsAt.isAfter(startsAt)) {
                        _snack(
                          dialogContext,
                          'O fim do turno tem de ser posterior ao início.',
                        );
                        return;
                      }
                      final people = int.tryParse(requiredPeople.text.trim());
                      if (people == null || people <= 0) {
                        _snack(
                          dialogContext,
                          'Indica um número de pessoas superior a zero.',
                        );
                        return;
                      }
                      setDialogState(() => saving = true);
                      try {
                        await widget.repository.saveShift(widget.eventId, {
                          'name': name.text.trim(),
                          'area': _nullText(area.text),
                          'starts_at': startsAt.toUtc().toIso8601String(),
                          'ends_at': endsAt.toUtc().toIso8601String(),
                          'required_people': people,
                          'status': status,
                          'notes': _nullText(notes.text),
                        }, id: shift?['id']?.toString());
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
    area.dispose();
    requiredPeople.dispose();
    notes.dispose();
    if (saved == true && mounted) {
      _snack(context, shift == null ? 'Turno criado.' : 'Turno atualizado.');
      setState(_reload);
    }
  }

  Future<void> _deleteShift(Map<String, dynamic> shift) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Eliminar turno'),
        content: Text(
          'Eliminar “${shift['name']?.toString() ?? 'este turno'}”? '
          'As atribuições associadas também serão eliminadas.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Eliminar'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    try {
      await widget.repository.deleteShift(
        eventId: widget.eventId,
        shiftId: shift['id'].toString(),
      );
      if (!mounted) return;
      _snack(context, 'Turno eliminado.');
      setState(_reload);
    } catch (error) {
      if (mounted) _snack(context, _friendly(error));
    }
  }

  Future<void> _assignShift(
    Map<String, dynamic> shift,
    List<Map<String, dynamic>> shiftMembers,
    List<Map<String, dynamic>> volunteers,
  ) async {
    final assignedIds = shiftMembers
        .where((row) => row['shift_id']?.toString() == shift['id']?.toString())
        .map((row) => row['member_id']?.toString())
        .whereType<String>()
        .toSet();
    final volunteer = await _pickVolunteer(volunteers, assignedIds);
    if (volunteer == null) return;
    try {
      await widget.repository.assignShift(
        eventId: widget.eventId,
        shiftId: shift['id'].toString(),
        memberId: volunteer['member_id'].toString(),
      );
      if (!mounted) return;
      _snack(context, 'Voluntário atribuído ao turno.');
      setState(_reload);
    } catch (error) {
      if (mounted) _snack(context, _friendly(error));
    }
  }

  Future<void> _removeShiftMember(Map<String, dynamic> assignment) async {
    try {
      await widget.repository.removeShiftMember(
        eventId: widget.eventId,
        assignmentId: assignment['id'].toString(),
      );
      if (!mounted) return;
      _snack(context, 'Atribuição removida do turno.');
      setState(_reload);
    } catch (error) {
      if (mounted) _snack(context, _friendly(error));
    }
  }

  Future<void> _setShiftMemberStatus(
    Map<String, dynamic> assignment,
    String status,
  ) async {
    try {
      await widget.repository.setShiftMemberStatus(
        assignment['id'].toString(),
        status,
      );
      if (!mounted) return;
      _snack(context, 'Estado da presença atualizado.');
      setState(_reload);
    } catch (error) {
      if (mounted) _snack(context, _friendly(error));
    }
  }

  Future<void> _editProgram(
    List<Map<String, dynamic>> current,
    List<Map<String, dynamic>> members, [
    Map<String, dynamic>? item,
  ]) async {
    final title = TextEditingController(text: item?['title']?.toString() ?? '');
    final location = TextEditingController(
      text: item?['location']?.toString() ?? '',
    );
    final notes = TextEditingController(text: item?['notes']?.toString() ?? '');
    String itemType = switch (item?['item_type']?.toString()) {
      'briefing' ||
      'ride' ||
      'meal' ||
      'music' ||
      'other' => item!['item_type'].toString(),
      _ => 'activity',
    };
    String responsibleMemberId =
        item?['responsible_member_id']?.toString() ?? '';
    DateTime? startsAt = _parse(item?['starts_at'])?.toLocal();
    DateTime? endsAt = _parse(item?['ends_at'])?.toLocal();
    bool saving = false;

    var nextSequence = 1;
    for (final row in current) {
      final sequence = int.tryParse('${row['sequence_no'] ?? 0}') ?? 0;
      if (sequence >= nextSequence) nextSequence = sequence + 1;
    }

    final saved = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: Text(
            item == null
                ? 'Novo ponto do programa'
                : 'Editar ponto do programa',
          ),
          content: SizedBox(
            width: 540,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextField(
                    controller: title,
                    decoration: const InputDecoration(
                      labelText: 'Título',
                      prefixIcon: Icon(Icons.view_timeline_outlined),
                    ),
                  ),
                  const SizedBox(height: 10),
                  DropdownButtonFormField<String>(
                    initialValue: itemType,
                    decoration: const InputDecoration(
                      labelText: 'Tipo',
                      prefixIcon: Icon(Icons.category_outlined),
                    ),
                    items: const [
                      DropdownMenuItem(
                        value: 'activity',
                        child: Text('Atividade'),
                      ),
                      DropdownMenuItem(
                        value: 'briefing',
                        child: Text('Briefing'),
                      ),
                      DropdownMenuItem(
                        value: 'ride',
                        child: Text('Passeio / deslocação'),
                      ),
                      DropdownMenuItem(value: 'meal', child: Text('Refeição')),
                      DropdownMenuItem(
                        value: 'music',
                        child: Text('Música / concerto'),
                      ),
                      DropdownMenuItem(value: 'other', child: Text('Outro')),
                    ],
                    onChanged: saving
                        ? null
                        : (value) {
                            if (value != null) {
                              setDialogState(() => itemType = value);
                            }
                          },
                  ),
                  const SizedBox(height: 10),
                  InkWell(
                    borderRadius: BorderRadius.circular(12),
                    onTap: saving
                        ? null
                        : () async {
                            final picked = await _pickDateTime(
                              dialogContext,
                              startsAt ?? DateTime.now(),
                              'Início do ponto do programa',
                            );
                            if (picked != null) {
                              setDialogState(() => startsAt = picked);
                            }
                          },
                    child: InputDecorator(
                      decoration: InputDecoration(
                        labelText: 'Início (opcional)',
                        prefixIcon: const Icon(Icons.play_circle_outline),
                        suffixIcon: startsAt == null
                            ? const Icon(Icons.edit_calendar_outlined)
                            : IconButton(
                                tooltip: 'Remover início',
                                onPressed: saving
                                    ? null
                                    : () =>
                                          setDialogState(() => startsAt = null),
                                icon: const Icon(Icons.clear),
                              ),
                      ),
                      child: Text(
                        startsAt == null
                            ? 'Hora por definir'
                            : _dateTime(startsAt),
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
                                startsAt?.add(const Duration(hours: 1)) ??
                                DateTime.now();
                            final picked = await _pickDateTime(
                              dialogContext,
                              initial,
                              'Fim do ponto do programa',
                            );
                            if (picked != null) {
                              setDialogState(() => endsAt = picked);
                            }
                          },
                    child: InputDecorator(
                      decoration: InputDecoration(
                        labelText: 'Fim (opcional)',
                        prefixIcon: const Icon(Icons.stop_circle_outlined),
                        suffixIcon: endsAt == null
                            ? const Icon(Icons.edit_calendar_outlined)
                            : IconButton(
                                tooltip: 'Remover fim',
                                onPressed: saving
                                    ? null
                                    : () => setDialogState(() => endsAt = null),
                                icon: const Icon(Icons.clear),
                              ),
                      ),
                      child: Text(
                        endsAt == null ? 'Hora por definir' : _dateTime(endsAt),
                      ),
                    ),
                  ),
                  const SizedBox(height: 10),
                  TextField(
                    controller: location,
                    decoration: const InputDecoration(
                      labelText: 'Local (opcional)',
                      prefixIcon: Icon(Icons.location_on_outlined),
                    ),
                  ),
                  const SizedBox(height: 10),
                  DropdownButtonFormField<String>(
                    initialValue:
                        members.any(
                          (member) =>
                              member['id']?.toString() == responsibleMemberId,
                        )
                        ? responsibleMemberId
                        : '',
                    decoration: const InputDecoration(
                      labelText: 'Responsável (opcional)',
                      prefixIcon: Icon(Icons.person_outline),
                    ),
                    items: [
                      const DropdownMenuItem(
                        value: '',
                        child: Text('Sem responsável'),
                      ),
                      ...members.map(
                        (member) => DropdownMenuItem<String>(
                          value: member['id'].toString(),
                          child: Text(
                            _memberName(member['id'].toString(), members),
                          ),
                        ),
                      ),
                    ],
                    onChanged: saving
                        ? null
                        : (value) => setDialogState(
                            () => responsibleMemberId = value ?? '',
                          ),
                  ),
                  const SizedBox(height: 10),
                  TextField(
                    controller: notes,
                    minLines: 2,
                    maxLines: 4,
                    decoration: const InputDecoration(
                      labelText: 'Notas (opcional)',
                      prefixIcon: Icon(Icons.notes_outlined),
                    ),
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
                      if (title.text.trim().isEmpty) {
                        _snack(
                          dialogContext,
                          'Indica o título do ponto do programa.',
                        );
                        return;
                      }
                      if (startsAt != null &&
                          endsAt != null &&
                          endsAt!.isBefore(startsAt!)) {
                        _snack(
                          dialogContext,
                          'O fim não pode ser anterior ao início.',
                        );
                        return;
                      }
                      setDialogState(() => saving = true);
                      try {
                        await widget.repository.saveProgramItem(
                          widget.eventId,
                          {
                            'sequence_no': item?['sequence_no'] ?? nextSequence,
                            'title': title.text.trim(),
                            'item_type': itemType,
                            'starts_at': startsAt?.toUtc().toIso8601String(),
                            'ends_at': endsAt?.toUtc().toIso8601String(),
                            'location': _nullText(location.text),
                            'responsible_member_id': responsibleMemberId.isEmpty
                                ? null
                                : responsibleMemberId,
                            'notes': _nullText(notes.text),
                          },
                          id: item?['id']?.toString(),
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

    title.dispose();
    location.dispose();
    notes.dispose();
    if (saved == true && mounted) {
      _snack(
        context,
        item == null
            ? 'Ponto do programa criado.'
            : 'Ponto do programa atualizado.',
      );
      setState(_reload);
    }
  }

  Future<void> _deleteProgramItem(Map<String, dynamic> item) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Eliminar ponto do programa'),
        content: Text(
          'Eliminar “${item['title']?.toString() ?? 'este ponto'}”? Esta ação não pode ser anulada.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Eliminar'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    try {
      await widget.repository.deleteProgramItem(
        eventId: widget.eventId,
        itemId: item['id'].toString(),
      );
      if (!mounted) return;
      _snack(context, 'Ponto do programa eliminado.');
      setState(_reload);
    } catch (error) {
      if (mounted) _snack(context, _friendly(error));
    }
  }

  Future<void> _reorderProgram(
    List<Map<String, dynamic>> current,
    int oldIndex,
    int newIndex,
  ) async {
    if (_reorderingProgram || oldIndex == newIndex) return;
    final reordered = List<Map<String, dynamic>>.from(current);
    final moved = reordered.removeAt(oldIndex);
    reordered.insert(newIndex, moved);
    for (var index = 0; index < reordered.length; index++) {
      reordered[index]['sequence_no'] = index + 1;
    }
    setState(() {
      _reorderingProgram = true;
      current
        ..clear()
        ..addAll(reordered);
    });
    try {
      await widget.repository.reorderProgramItems(
        eventId: widget.eventId,
        itemIds: reordered.map((row) => row['id'].toString()).toList(),
      );
      await _refresh();
      if (mounted) _snack(context, 'Ordem do programa atualizada.');
    } catch (error) {
      try {
        await _refresh();
      } catch (_) {
        // Mantém a mensagem do erro original.
      }
      if (mounted) _snack(context, _friendly(error));
    } finally {
      if (mounted) setState(() => _reorderingProgram = false);
    }
  }

  String _programTypeLabel(Object? value) => switch (value?.toString()) {
    'briefing' => 'Briefing',
    'ride' => 'Passeio / deslocação',
    'meal' => 'Refeição',
    'music' => 'Música / concerto',
    'other' => 'Outro',
    _ => 'Atividade',
  };

  Widget _programSection(
    List<Map<String, dynamic>> program,
    List<Map<String, dynamic>> members,
    bool canManage,
  ) {
    return Card(
      child: ExpansionTile(
        leading: const Icon(Icons.view_timeline_outlined),
        title: const Text('Programa'),
        subtitle: Text(
          '${program.length} ponto${program.length == 1 ? '' : 's'}',
        ),
        children: [
          if (program.isEmpty)
            const ListTile(title: Text('Sem pontos no programa.'))
          else
            ReorderableListView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              buildDefaultDragHandles: false,
              itemCount: program.length,
              onReorderItem: canManage
                  ? (oldIndex, newIndex) =>
                        _reorderProgram(program, oldIndex, newIndex)
                  : (_, __) {},
              itemBuilder: (context, index) {
                final item = program[index];
                final startsAt = _parse(item['starts_at'])?.toLocal();
                final endsAt = _parse(item['ends_at'])?.toLocal();
                final locationText = item['location']?.toString().trim() ?? '';
                final responsibleId = item['responsible_member_id']?.toString();
                final notesText = item['notes']?.toString().trim() ?? '';
                final timeText = startsAt == null
                    ? 'Hora por definir'
                    : endsAt == null
                    ? _dateTime(startsAt)
                    : '${_dateTime(startsAt)} → ${_dateTime(endsAt)}';
                final details = <String>[
                  '${_programTypeLabel(item['item_type'])} • $timeText',
                  if (locationText.isNotEmpty) locationText,
                  if (responsibleId != null && responsibleId.isNotEmpty)
                    'Responsável: ${_memberName(responsibleId, members)}',
                  if (notesText.isNotEmpty) notesText,
                ];
                return ListTile(
                  key: ValueKey('program-${item['id']?.toString() ?? index}'),
                  leading: CircleAvatar(
                    child: Text('${item['sequence_no'] ?? index + 1}'),
                  ),
                  title: Text(item['title']?.toString() ?? 'Ponto do programa'),
                  subtitle: Text(details.join('\n')),
                  trailing: canManage
                      ? Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            IconButton(
                              tooltip: 'Editar ponto',
                              onPressed: _reorderingProgram
                                  ? null
                                  : () => _editProgram(program, members, item),
                              icon: const Icon(Icons.edit_outlined),
                            ),
                            IconButton(
                              tooltip: 'Eliminar ponto',
                              onPressed: _reorderingProgram
                                  ? null
                                  : () => _deleteProgramItem(item),
                              icon: const Icon(Icons.delete_outline),
                            ),
                            Tooltip(
                              message: 'Arrastar para reordenar',
                              child: ReorderableDragStartListener(
                                index: index,
                                enabled: !_reorderingProgram,
                                child: const Padding(
                                  padding: EdgeInsets.all(12),
                                  child: Icon(Icons.drag_handle),
                                ),
                              ),
                            ),
                          ],
                        )
                      : null,
                );
              },
            ),
          if (canManage)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
              child: Align(
                alignment: Alignment.centerLeft,
                child: FilledButton.tonalIcon(
                  onPressed: _reorderingProgram
                      ? null
                      : () => _editProgram(program, members),
                  icon: const Icon(Icons.add),
                  label: const Text('Adicionar ponto'),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Future<void> _editIncident(
    List<Map<String, dynamic>> members, [
    Map<String, dynamic>? incident,
  ]) async {
    final title = TextEditingController(
      text: incident?['title']?.toString() ?? '',
    );
    final description = TextEditingController(
      text: incident?['description']?.toString() ?? '',
    );
    final location = TextEditingController(
      text: incident?['location']?.toString() ?? '',
    );
    final resolution = TextEditingController(
      text: incident?['resolution']?.toString() ?? '',
    );
    DateTime occurredAt =
        _parse(incident?['occurred_at'])?.toLocal() ?? DateTime.now();
    String severity = switch (incident?['severity']?.toString()) {
      'medium' || 'high' || 'critical' => incident!['severity'].toString(),
      _ => 'low',
    };
    String status = switch (incident?['status']?.toString()) {
      'monitoring' || 'resolved' || 'closed' => incident!['status'].toString(),
      _ => 'open',
    };
    String assignedMemberId = incident?['assigned_member_id']?.toString() ?? '';
    bool saving = false;

    final saved = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: Text(
            incident == null ? 'Registar incidente' : 'Editar incidente',
          ),
          content: SizedBox(
            width: 540,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextField(
                    controller: title,
                    decoration: const InputDecoration(
                      labelText: 'Título',
                      prefixIcon: Icon(Icons.report_problem_outlined),
                    ),
                  ),
                  const SizedBox(height: 10),
                  TextField(
                    controller: description,
                    minLines: 2,
                    maxLines: 4,
                    decoration: const InputDecoration(
                      labelText: 'Descrição (opcional)',
                      prefixIcon: Icon(Icons.description_outlined),
                    ),
                  ),
                  const SizedBox(height: 10),
                  InkWell(
                    borderRadius: BorderRadius.circular(12),
                    onTap: saving
                        ? null
                        : () async {
                            final picked = await _pickDateTime(
                              dialogContext,
                              occurredAt,
                              'Data e hora do incidente',
                            );
                            if (picked != null) {
                              setDialogState(() => occurredAt = picked);
                            }
                          },
                    child: InputDecorator(
                      decoration: const InputDecoration(
                        labelText: 'Data e hora',
                        prefixIcon: Icon(Icons.access_time_outlined),
                        suffixIcon: Icon(Icons.edit_calendar_outlined),
                      ),
                      child: Text(_dateTime(occurredAt)),
                    ),
                  ),
                  const SizedBox(height: 10),
                  TextField(
                    controller: location,
                    decoration: const InputDecoration(
                      labelText: 'Local (opcional)',
                      prefixIcon: Icon(Icons.location_on_outlined),
                    ),
                  ),
                  const SizedBox(height: 10),
                  DropdownButtonFormField<String>(
                    initialValue: severity,
                    decoration: const InputDecoration(
                      labelText: 'Gravidade',
                      prefixIcon: Icon(Icons.priority_high_outlined),
                    ),
                    items: const [
                      DropdownMenuItem(value: 'low', child: Text('Baixa')),
                      DropdownMenuItem(value: 'medium', child: Text('Média')),
                      DropdownMenuItem(value: 'high', child: Text('Alta')),
                      DropdownMenuItem(
                        value: 'critical',
                        child: Text('Crítica'),
                      ),
                    ],
                    onChanged: saving
                        ? null
                        : (value) {
                            if (value != null) {
                              setDialogState(() => severity = value);
                            }
                          },
                  ),
                  const SizedBox(height: 10),
                  DropdownButtonFormField<String>(
                    initialValue: status,
                    decoration: const InputDecoration(
                      labelText: 'Estado',
                      prefixIcon: Icon(Icons.flag_outlined),
                    ),
                    items: const [
                      DropdownMenuItem(value: 'open', child: Text('Aberto')),
                      DropdownMenuItem(
                        value: 'monitoring',
                        child: Text('Em acompanhamento'),
                      ),
                      DropdownMenuItem(
                        value: 'resolved',
                        child: Text('Resolvido'),
                      ),
                      DropdownMenuItem(value: 'closed', child: Text('Fechado')),
                    ],
                    onChanged: saving
                        ? null
                        : (value) {
                            if (value != null) {
                              setDialogState(() => status = value);
                            }
                          },
                  ),
                  const SizedBox(height: 10),
                  DropdownButtonFormField<String>(
                    initialValue:
                        members.any(
                          (member) =>
                              member['id']?.toString() == assignedMemberId,
                        )
                        ? assignedMemberId
                        : '',
                    decoration: const InputDecoration(
                      labelText: 'Responsável (opcional)',
                      prefixIcon: Icon(Icons.person_outline),
                    ),
                    items: [
                      const DropdownMenuItem(
                        value: '',
                        child: Text('Sem responsável'),
                      ),
                      ...members.map(
                        (member) => DropdownMenuItem<String>(
                          value: member['id'].toString(),
                          child: Text(
                            _memberName(member['id'].toString(), members),
                          ),
                        ),
                      ),
                    ],
                    onChanged: saving
                        ? null
                        : (value) => setDialogState(
                            () => assignedMemberId = value ?? '',
                          ),
                  ),
                  const SizedBox(height: 10),
                  TextField(
                    controller: resolution,
                    minLines: 2,
                    maxLines: 4,
                    decoration: const InputDecoration(
                      labelText: 'Resolução / seguimento',
                      prefixIcon: Icon(Icons.fact_check_outlined),
                    ),
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
                      if (title.text.trim().isEmpty) {
                        _snack(dialogContext, 'Indica o título do incidente.');
                        return;
                      }
                      final resolved =
                          status == 'resolved' || status == 'closed';
                      if (resolved && resolution.text.trim().isEmpty) {
                        _snack(
                          dialogContext,
                          'Indica a resolução antes de concluir o incidente.',
                        );
                        return;
                      }
                      setDialogState(() => saving = true);
                      try {
                        await widget.repository.saveIncident(widget.eventId, {
                          'occurred_at': occurredAt.toUtc().toIso8601String(),
                          'title': title.text.trim(),
                          'description': _nullText(description.text),
                          'severity': severity,
                          'status': status,
                          'location': _nullText(location.text),
                          'assigned_member_id': assignedMemberId.isEmpty
                              ? null
                              : assignedMemberId,
                          'resolution': _nullText(resolution.text),
                          'resolved_at': resolved
                              ? (incident?['resolved_at'] ??
                                    DateTime.now().toUtc().toIso8601String())
                              : null,
                        }, id: incident?['id']?.toString());
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

    title.dispose();
    description.dispose();
    location.dispose();
    resolution.dispose();
    if (saved == true && mounted) {
      _snack(
        context,
        incident == null ? 'Incidente registado.' : 'Incidente atualizado.',
      );
      setState(_reload);
    }
  }

  Future<void> _deleteIncident(Map<String, dynamic> incident) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Eliminar incidente'),
        content: Text(
          'Eliminar “${incident['title']?.toString() ?? 'este incidente'}”? Esta ação não pode ser anulada.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Eliminar'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    try {
      await widget.repository.deleteIncident(
        eventId: widget.eventId,
        incidentId: incident['id'].toString(),
      );
      if (!mounted) return;
      _snack(context, 'Incidente eliminado.');
      setState(_reload);
    } catch (error) {
      if (mounted) _snack(context, _friendly(error));
    }
  }

  String _incidentSeverityLabel(Object? value) => switch (value?.toString()) {
    'medium' => 'Média',
    'high' => 'Alta',
    'critical' => 'Crítica',
    _ => 'Baixa',
  };

  String _incidentStatusLabel(Object? value) => switch (value?.toString()) {
    'monitoring' => 'Em acompanhamento',
    'resolved' => 'Resolvido',
    'closed' => 'Fechado',
    _ => 'Aberto',
  };

  Widget _incidentSection(
    List<Map<String, dynamic>> incidents,
    List<Map<String, dynamic>> members,
    bool canManage,
  ) {
    return Card(
      child: ExpansionTile(
        leading: const Icon(Icons.report_problem_outlined),
        title: const Text('Incidentes'),
        subtitle: Text(
          '${incidents.where((row) => row['status'] != 'resolved' && row['status'] != 'closed').length} aberto(s) • ${incidents.length} total',
        ),
        children: [
          if (incidents.isEmpty)
            const ListTile(title: Text('Sem incidentes registados.'))
          else
            ...incidents.map((incident) {
              final occurredAt = _parse(incident['occurred_at'])?.toLocal();
              final locationText =
                  incident['location']?.toString().trim() ?? '';
              final descriptionText =
                  incident['description']?.toString().trim() ?? '';
              final resolutionText =
                  incident['resolution']?.toString().trim() ?? '';
              final assignedId = incident['assigned_member_id']?.toString();
              final details = <String>[
                '${_incidentSeverityLabel(incident['severity'])} • ${_incidentStatusLabel(incident['status'])} • ${_dateTime(occurredAt)}',
                if (locationText.isNotEmpty) locationText,
                if (assignedId != null && assignedId.isNotEmpty)
                  'Responsável: ${_memberName(assignedId, members)}',
                if (descriptionText.isNotEmpty) descriptionText,
                if (resolutionText.isNotEmpty) 'Resolução: $resolutionText',
              ];
              return ListTile(
                leading: const CircleAvatar(
                  child: Icon(Icons.warning_amber_outlined),
                ),
                title: Text(incident['title']?.toString() ?? 'Incidente'),
                subtitle: Text(details.join('\n')),
                trailing: canManage
                    ? Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          IconButton(
                            tooltip: 'Editar incidente',
                            onPressed: () => _editIncident(members, incident),
                            icon: const Icon(Icons.edit_outlined),
                          ),
                          IconButton(
                            tooltip: 'Eliminar incidente',
                            onPressed: () => _deleteIncident(incident),
                            icon: const Icon(Icons.delete_outline),
                          ),
                        ],
                      )
                    : null,
              );
            }),
          if (canManage)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
              child: Align(
                alignment: Alignment.centerLeft,
                child: FilledButton.tonalIcon(
                  onPressed: () => _editIncident(members),
                  icon: const Icon(Icons.add),
                  label: const Text('Registar incidente'),
                ),
              ),
            ),
        ],
      ),
    );
  }

  String _taskStatusLabel(Object? value) => switch (value?.toString()) {
    'in_progress' => 'Em curso',
    'done' => 'Concluída',
    'cancelled' => 'Cancelada',
    _ => 'Pendente',
  };

  String _priorityLabel(Object? value) => switch (value?.toString()) {
    'low' => 'Baixa',
    'high' => 'Alta',
    'critical' => 'Crítica',
    _ => 'Normal',
  };

  String _shiftStatusLabel(Object? value) => switch (value?.toString()) {
    'active' => 'Em curso',
    'completed' => 'Concluído',
    'cancelled' => 'Cancelado',
    _ => 'Planeado',
  };

  String _assignmentStatusLabel(Object? value) => switch (value?.toString()) {
    'confirmed' => 'Confirmado',
    'present' => 'Presente',
    'absent' => 'Ausente',
    'cancelled' => 'Cancelado',
    _ => 'Atribuído',
  };

  Widget _volunteerSummary(List<Map<String, dynamic>> volunteers) {
    return Card(
      child: ExpansionTile(
        leading: const Icon(Icons.volunteer_activism_outlined),
        title: const Text('Equipa de voluntariado'),
        subtitle: Text(
          volunteers.isEmpty
              ? 'Sem voluntários definidos'
              : '${volunteers.length} voluntário${volunteers.length == 1 ? '' : 's'} disponível${volunteers.length == 1 ? '' : 'eis'} para tarefas e turnos',
        ),
        children: [
          if (volunteers.isEmpty)
            const ListTile(
              title: Text(
                'Adiciona voluntários em Participantes e acompanhantes.',
              ),
            )
          else
            ...volunteers.map(
              (row) => ListTile(
                leading: const CircleAvatar(child: Icon(Icons.person_outline)),
                title: Text(row['member_name']?.toString() ?? 'Membro'),
                subtitle: Text(
                  row['function_name']?.toString() ?? 'Apoio geral',
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _taskCard(
    Map<String, dynamic> task,
    List<Map<String, dynamic>> taskAssignees,
    List<Map<String, dynamic>> volunteers,
    List<Map<String, dynamic>> members,
    bool canManage,
  ) {
    final assignments = taskAssignees
        .where((row) => row['task_id']?.toString() == task['id']?.toString())
        .toList();
    final dueAt = _parse(task['due_at'])?.toLocal();
    return Card(
      child: ExpansionTile(
        leading: const Icon(Icons.task_alt_outlined),
        title: Text(task['title']?.toString() ?? 'Tarefa'),
        subtitle: Text(
          '${_taskStatusLabel(task['status'])} • ${_priorityLabel(task['priority'])}'
          '${dueAt == null ? '' : ' • prazo ${_dateTime(dueAt)}'}'
          ' • ${assignments.length} atribuído${assignments.length == 1 ? '' : 's'}',
        ),
        children: [
          if (task['description']?.toString().trim().isNotEmpty == true)
            ListTile(
              leading: const Icon(Icons.description_outlined),
              title: Text(task['description'].toString()),
            ),
          if (task['notes']?.toString().trim().isNotEmpty == true)
            ListTile(
              leading: const Icon(Icons.notes_outlined),
              title: Text(task['notes'].toString()),
            ),
          if (assignments.isEmpty)
            const ListTile(
              leading: Icon(Icons.person_off_outlined),
              title: Text('Sem voluntários atribuídos.'),
            )
          else
            ...assignments.map((assignment) {
              final completed = assignment['completed_at'] != null;
              final acknowledged = assignment['acknowledged_at'] != null;
              final state = completed
                  ? 'Concluído'
                  : (acknowledged ? 'Visto' : 'Atribuído');
              return ListTile(
                leading: const CircleAvatar(child: Icon(Icons.person_outline)),
                title: Text(
                  _memberName(assignment['member_id']?.toString(), members),
                ),
                subtitle: Text(state),
                trailing: canManage
                    ? IconButton(
                        tooltip: 'Remover atribuição',
                        onPressed: () => _removeTaskAssignee(assignment),
                        icon: const Icon(Icons.person_remove_outlined),
                      )
                    : null,
              );
            }),
          if (canManage)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
              child: Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  FilledButton.tonalIcon(
                    onPressed: () =>
                        _assignTask(task, taskAssignees, volunteers),
                    icon: const Icon(Icons.person_add_alt_outlined),
                    label: const Text('Atribuir voluntário'),
                  ),
                  OutlinedButton.icon(
                    onPressed: () => _editTask(task),
                    icon: const Icon(Icons.edit_outlined),
                    label: const Text('Editar'),
                  ),
                  TextButton.icon(
                    onPressed: () => _deleteTask(task),
                    icon: const Icon(Icons.delete_outline),
                    label: const Text('Eliminar'),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  Widget _shiftCard(
    Map<String, dynamic> shift,
    List<Map<String, dynamic>> shiftMembers,
    List<Map<String, dynamic>> volunteers,
    List<Map<String, dynamic>> members,
    bool canManage,
  ) {
    final assignments = shiftMembers
        .where((row) => row['shift_id']?.toString() == shift['id']?.toString())
        .toList();
    final startsAt = _parse(shift['starts_at'])?.toLocal();
    final endsAt = _parse(shift['ends_at'])?.toLocal();
    final required = int.tryParse('${shift['required_people'] ?? 1}') ?? 1;
    return Card(
      child: ExpansionTile(
        leading: const Icon(Icons.schedule_outlined),
        title: Text(shift['name']?.toString() ?? 'Turno'),
        subtitle: Text(
          '${shift['area']?.toString().trim().isNotEmpty == true ? shift['area'] : 'Área por definir'} • '
          '${_shiftStatusLabel(shift['status'])} • '
          '${assignments.length}/$required pessoa${required == 1 ? '' : 's'}',
        ),
        children: [
          ListTile(
            leading: const Icon(Icons.access_time_outlined),
            title: Text('${_dateTime(startsAt)} → ${_dateTime(endsAt)}'),
          ),
          if (shift['notes']?.toString().trim().isNotEmpty == true)
            ListTile(
              leading: const Icon(Icons.notes_outlined),
              title: Text(shift['notes'].toString()),
            ),
          if (assignments.isEmpty)
            const ListTile(
              leading: Icon(Icons.person_off_outlined),
              title: Text('Sem voluntários atribuídos.'),
            )
          else
            ...assignments.map(
              (assignment) => ListTile(
                leading: const CircleAvatar(child: Icon(Icons.person_outline)),
                title: Text(
                  _memberName(assignment['member_id']?.toString(), members),
                ),
                subtitle: Text(_assignmentStatusLabel(assignment['status'])),
                trailing: canManage
                    ? Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          PopupMenuButton<String>(
                            tooltip: 'Estado da presença',
                            onSelected: (value) =>
                                _setShiftMemberStatus(assignment, value),
                            itemBuilder: (context) => const [
                              PopupMenuItem(
                                value: 'assigned',
                                child: Text('Atribuído'),
                              ),
                              PopupMenuItem(
                                value: 'confirmed',
                                child: Text('Confirmado'),
                              ),
                              PopupMenuItem(
                                value: 'present',
                                child: Text('Presente'),
                              ),
                              PopupMenuItem(
                                value: 'absent',
                                child: Text('Ausente'),
                              ),
                              PopupMenuItem(
                                value: 'cancelled',
                                child: Text('Cancelado'),
                              ),
                            ],
                          ),
                          IconButton(
                            tooltip: 'Remover do turno',
                            onPressed: () => _removeShiftMember(assignment),
                            icon: const Icon(Icons.person_remove_outlined),
                          ),
                        ],
                      )
                    : null,
              ),
            ),
          if (canManage)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
              child: Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  FilledButton.tonalIcon(
                    onPressed: () =>
                        _assignShift(shift, shiftMembers, volunteers),
                    icon: const Icon(Icons.person_add_alt_outlined),
                    label: const Text('Atribuir voluntário'),
                  ),
                  OutlinedButton.icon(
                    onPressed: () => _editShift(shift),
                    icon: const Icon(Icons.edit_outlined),
                    label: const Text('Editar'),
                  ),
                  TextButton.icon(
                    onPressed: () => _deleteShift(shift),
                    icon: const Icon(Icons.delete_outline),
                    label: const Text('Eliminar'),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Operação do evento')),
      body: FutureBuilder<List<dynamic>>(
        future: _future,
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return Center(child: Text(_friendly(snapshot.error!)));
          }
          if (!snapshot.hasData) {
            return const Center(child: CircularProgressIndicator());
          }
          final tasks = List<Map<String, dynamic>>.from(
            snapshot.data![0] as List,
          );
          final taskAssignees = List<Map<String, dynamic>>.from(
            snapshot.data![1] as List,
          );
          final shifts = List<Map<String, dynamic>>.from(
            snapshot.data![2] as List,
          );
          final shiftMembers = List<Map<String, dynamic>>.from(
            snapshot.data![3] as List,
          );
          final program = List<Map<String, dynamic>>.from(
            snapshot.data![4] as List,
          );
          final incidents = List<Map<String, dynamic>>.from(
            snapshot.data![5] as List,
          );
          final volunteers = List<Map<String, dynamic>>.from(
            snapshot.data![6] as List,
          );
          final members = List<Map<String, dynamic>>.from(
            snapshot.data![7] as List,
          );
          final canManage = widget.repository.canManageOperations;

          return RefreshIndicator(
            onRefresh: _refresh,
            child: ListView(
              padding: const EdgeInsets.all(12),
              children: [
                _volunteerSummary(volunteers),
                const SizedBox(height: 4),
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        'Tarefas (${tasks.length})',
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                    ),
                    if (canManage)
                      IconButton(
                        tooltip: 'Nova tarefa',
                        onPressed: () => _editTask(),
                        icon: const Icon(Icons.add_task_outlined),
                      ),
                  ],
                ),
                if (tasks.isEmpty)
                  const Card(
                    child: ListTile(title: Text('Sem tarefas definidas.')),
                  )
                else
                  ...tasks.map(
                    (task) => _taskCard(
                      task,
                      taskAssignees,
                      volunteers,
                      members,
                      canManage,
                    ),
                  ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        'Turnos / Escalas (${shifts.length})',
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                    ),
                    if (canManage)
                      IconButton(
                        tooltip: 'Novo turno',
                        onPressed: () => _editShift(),
                        icon: const Icon(Icons.add_alarm_outlined),
                      ),
                  ],
                ),
                if (shifts.isEmpty)
                  const Card(
                    child: ListTile(title: Text('Sem turnos definidos.')),
                  )
                else
                  ...shifts.map(
                    (shift) => _shiftCard(
                      shift,
                      shiftMembers,
                      volunteers,
                      members,
                      canManage,
                    ),
                  ),
                const SizedBox(height: 8),
                _programSection(program, members, canManage),
                _incidentSection(incidents, members, canManage),
              ],
            ),
          );
        },
      ),
    );
  }
}

class _HubTile extends StatelessWidget {
  const _HubTile({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: ListTile(
        leading: CircleAvatar(child: Icon(icon)),
        title: Text(title),
        subtitle: Text(subtitle),
        trailing: const Icon(Icons.chevron_right),
        onTap: onTap,
      ),
    );
  }
}

class _EntitySection extends StatelessWidget {
  const _EntitySection({
    required this.title,
    required this.icon,
    required this.rows,
    required this.canAdd,
    required this.onAdd,
  });

  final String title;
  final IconData icon;
  final List<Map<String, dynamic>> rows;
  final bool canAdd;
  final VoidCallback onAdd;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: ExpansionTile(
        leading: Icon(icon),
        title: Text(title),
        subtitle: Text('${rows.length} registo(s)'),
        children: [
          if (rows.isEmpty)
            const ListTile(title: Text('Sem registos.'))
          else
            ...rows.map(
              (row) => ListTile(
                title: Text(row['name']?.toString() ?? 'Registo'),
                subtitle: Text(row['status']?.toString() ?? ''),
              ),
            ),
          if (canAdd)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
              child: Align(
                alignment: Alignment.centerLeft,
                child: FilledButton.tonalIcon(
                  onPressed: onAdd,
                  icon: const Icon(Icons.add),
                  label: const Text('Adicionar'),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _SimpleFutureList extends StatelessWidget {
  const _SimpleFutureList({
    required this.future,
    required this.emptyText,
    required this.title,
    required this.subtitle,
  });

  final Future<List<Map<String, dynamic>>> future;
  final String emptyText;
  final String Function(Map<String, dynamic>) title;
  final String Function(Map<String, dynamic>) subtitle;

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<List<Map<String, dynamic>>>(
      future: future,
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return Center(child: Text(_friendly(snapshot.error!)));
        }
        if (!snapshot.hasData) {
          return const Center(child: CircularProgressIndicator());
        }
        final rows = snapshot.data!;
        return ListView(
          padding: const EdgeInsets.fromLTRB(12, 12, 12, 96),
          children: rows.isEmpty
              ? [Card(child: ListTile(title: Text(emptyText)))]
              : rows
                    .map(
                      (row) => Card(
                        child: ListTile(
                          title: Text(title(row)),
                          subtitle: Text(subtitle(row)),
                        ),
                      ),
                    )
                    .toList(),
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

DateTime? _parse(Object? value) {
  if (value is DateTime) return value;
  return DateTime.tryParse(value?.toString() ?? '');
}

String _date(Object? value) {
  final date = _parse(value);
  if (date == null) return 'Data por definir';
  return '${date.day.toString().padLeft(2, '0')}/${date.month.toString().padLeft(2, '0')}/${date.year}';
}

String _dateTime(DateTime? value) {
  if (value == null) return 'Por definir';
  return '${_date(value)} ${value.hour.toString().padLeft(2, '0')}:${value.minute.toString().padLeft(2, '0')}';
}

String _dateTimeValue(Object? value, {String empty = 'Por definir'}) {
  final date = _parse(value)?.toLocal();
  if (date == null) return empty;
  return '${date.day.toString().padLeft(2, '0')}/'
      '${date.month.toString().padLeft(2, '0')}/${date.year} • '
      '${date.hour.toString().padLeft(2, '0')}:'
      '${date.minute.toString().padLeft(2, '0')}';
}

String _capacityLabel(Object? value) {
  final capacity = value is num
      ? value.toInt()
      : int.tryParse(value?.toString() ?? '');
  if (capacity == null || capacity <= 0) return 'Por definir';
  return '$capacity ${capacity == 1 ? 'pessoa' : 'pessoas'}';
}

String _moneyValue(Object? value) {
  final amount = value is num
      ? value.toDouble()
      : double.tryParse(value?.toString() ?? '') ?? 0;
  return '${amount.toStringAsFixed(2).replaceAll('.', ',')} €';
}

String? _nullText(String value) {
  final text = value.trim();
  return text.isEmpty ? null : text;
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
