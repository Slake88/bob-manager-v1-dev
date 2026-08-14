import 'package:flutter/material.dart';

import '../core/app_session.dart';
import '../repositories/events_advanced_repository.dart';
import '../repositories/events_repository.dart';
import '../repositories/member_repository.dart';
import 'events_screen.dart';

class EventsModuleScreen extends StatefulWidget {
  const EventsModuleScreen({super.key});

  @override
  State<EventsModuleScreen> createState() => _EventsModuleScreenState();
}

class _EventsModuleScreenState extends State<EventsModuleScreen> {
  int _index = 0;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: IndexedStack(
        index: _index,
        children: const [EventsScreen(), EventsAdvancedHomeScreen()],
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _index,
        onDestinationSelected: (value) => setState(() => _index = value),
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
  const EventsAdvancedHomeScreen({super.key});

  @override
  State<EventsAdvancedHomeScreen> createState() =>
      _EventsAdvancedHomeScreenState();
}

class _EventsAdvancedHomeScreenState extends State<EventsAdvancedHomeScreen> {
  final EventsAdvancedRepository _advanced = EventsAdvancedRepository();
  final EventsRepository _events = EventsRepository();
  late Future<List<dynamic>> _future;

  @override
  void initState() {
    super.initState();
    _reload();
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
    await Navigator.of(context).push<void>(
      MaterialPageRoute(
        builder: (_) => EventAdvancedScreen(
          event: event,
          repository: _advanced,
        ),
      ),
    );
    if (mounted) setState(_reload);
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
        final proposals =
            List<Map<String, dynamic>>.from(snapshot.data![0] as List);
        final events =
            List<Map<String, dynamic>>.from(snapshot.data![1] as List);
        final pending =
            proposals.where((row) => row['status'] == 'submitted').length;

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
              if (events.isEmpty)
                const Card(
                  child: ListTile(
                    leading: Icon(Icons.event_busy_outlined),
                    title: Text('Ainda não existem eventos.'),
                  ),
                )
              else
                ...events.map(
                  (event) => Card(
                    child: ListTile(
                      leading: CircleAvatar(
                        child: Icon(_eventIcon(event['event_kind'])),
                      ),
                      title: Text(event['name']?.toString() ?? 'Evento'),
                      subtitle: Text(
                        '${eventKindLabel(event['event_kind'])} • ${_date(event['starts_at'])}\n${event['location']?.toString().trim().isNotEmpty == true ? event['location'] : 'Local por definir'}',
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
  const EventProposalsScreen({
    super.key,
    required this.repository,
  });

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
                      DropdownMenuItem(
                        value: 'general',
                        child: Text('Evento'),
                      ),
                      DropdownMenuItem(
                        value: 'ride',
                        child: Text('Passeio'),
                      ),
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
                              firstDate: DateTime.now()
                                  .subtract(const Duration(days: 365)),
                              lastDate: DateTime.now()
                                  .add(const Duration(days: 3650)),
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
                    decoration:
                        const InputDecoration(labelText: 'Descrição / notas'),
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
                  final mine = row['proposed_by']?.toString() ==
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
                                  style:
                                      Theme.of(context).textTheme.titleMedium,
                                ),
                              ),
                              Chip(
                                label: Text(
                                  proposalStatusLabel(row['status']),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 4),
                          Text(
                            '${eventKindLabel(row['event_kind'])} • ${_date(row['starts_at'])}',
                          ),
                          if (row['location']
                                  ?.toString()
                                  .trim()
                                  .isNotEmpty ==
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
                                    _snack(context, _friendly(error));
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
  late Future<Map<String, dynamic>> _future;

  String get _eventId => widget.event['id'].toString();

  @override
  void initState() {
    super.initState();
    _reload();
  }

  void _reload() => _future = widget.repository.overview(_eventId);

  Future<void> _open(Widget screen) async {
    await Navigator.of(context).push<void>(
      MaterialPageRoute(builder: (_) => screen),
    );
    if (mounted) setState(_reload);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.event['name']?.toString() ?? 'Evento'),
      ),
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
                      Text(
                        eventKindLabel(widget.event['event_kind']),
                        style: Theme.of(context).textTheme.titleLarge,
                      ),
                      const SizedBox(height: 6),
                      Text(
                        '${_date(widget.event['starts_at'])} • ${widget.event['location'] ?? 'Local por definir'}',
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 8),
              _HubTile(
                icon: Icons.people_alt_outlined,
                title: 'Acompanhantes',
                subtitle: '${data['guests']} registado(s)',
                onTap: () => _open(
                  _GuestsPage(
                    eventId: _eventId,
                    repository: widget.repository,
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
            ],
          );
        },
      ),
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
                  decoration:
                      const InputDecoration(labelText: 'Membro anfitrião'),
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

  Future<void> _add() async {
    final name = TextEditingController(text: 'Roadbook principal');
    final start = TextEditingController();
    final end = TextEditingController();
    final distance = TextEditingController();
    final saved = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Novo roadbook'),
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
                  keyboardType:
                      const TextInputType.numberWithOptions(decimal: true),
                  decoration:
                      const InputDecoration(labelText: 'Distância (km)'),
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
                  'distance_km':
                      double.tryParse(distance.text.replaceAll(',', '.')),
                });
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
    if (saved == true && mounted) setState(_reload);
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
                      child: ListTile(
                        title: Text('Sem roadbook configurado.'),
                      ),
                    ),
                  ]
                : rows
                    .map(
                      (row) => Card(
                        child: ListTile(
                          leading: const Icon(Icons.route_outlined),
                          title:
                              Text(row['name']?.toString() ?? 'Roadbook'),
                          subtitle: Text(
                            '${row['start_location'] ?? 'Partida'} → ${row['end_location'] ?? 'Destino'}${row['distance_km'] == null ? '' : ' • ${row['distance_km']} km'}',
                          ),
                          trailing: const Icon(Icons.chevron_right),
                          onTap: () async {
                            await Navigator.of(context).push<void>(
                              MaterialPageRoute(
                                builder: (_) => _RouteStopsPage(
                                  eventId: widget.eventId,
                                  route: row,
                                  repository: widget.repository,
                                ),
                              ),
                            );
                            if (mounted) setState(_reload);
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
              onPressed: _add,
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

  @override
  void initState() {
    super.initState();
    _reload();
  }

  void _reload() =>
      _future = widget.repository.listRouteStops(widget.route['id'].toString());

  Future<void> _add(List<Map<String, dynamic>> current) async {
    final name = TextEditingController();
    final location = TextEditingController();
    final saved = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Nova paragem'),
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
                  routeId: widget.route['id'].toString(),
                  values: {
                    'sequence_no': current.length + 1,
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
    if (saved == true && mounted) setState(_reload);
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
          return ListView(
            padding: const EdgeInsets.fromLTRB(12, 12, 12, 96),
            children: [
              if (rows.isEmpty)
                const Card(child: ListTile(title: Text('Sem paragens.')))
              else
                ...rows.map(
                  (row) => Card(
                    child: ListTile(
                      leading: CircleAvatar(
                        child: Text('${row['sequence_no'] ?? ''}'),
                      ),
                      title: Text(row['name']?.toString() ?? 'Paragem'),
                      subtitle:
                          Text(row['location']?.toString() ?? 'Local por definir'),
                    ),
                  ),
                ),
              if (widget.repository.canManageRoadbook)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: FilledButton.icon(
                    onPressed: () => _add(rows),
                    icon: const Icon(Icons.add_location_alt_outlined),
                    label: const Text('Adicionar paragem'),
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
                    : emergency?.toString() ??
                        'Sem contacto de emergência';
                return Card(
                  child: ListTile(
                    leading:
                        const CircleAvatar(child: Icon(Icons.person_outline)),
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
        title: Text(
          switch (type) {
            'band' => 'Nova banda',
            'exhibitor' => 'Novo expositor',
            _ => 'Novo patrocinador',
          },
        ),
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
                labelText:
                    type == 'exhibitor' ? 'Categoria' : 'Valor acordado (€)',
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
    final unit =
        TextEditingController(text: '${current?['unit_price'] ?? 1.5}');
    final five =
        TextEditingController(text: '${current?['five_card_price'] ?? 7}');
    final ten =
        TextEditingController(text: '${current?['ten_card_price'] ?? 13}');
    final saved = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Configuração de Octanas'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: unit,
              keyboardType:
                  const TextInputType.numberWithOptions(decimal: true),
              decoration: const InputDecoration(labelText: '1 Octana (€)'),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: five,
              keyboardType:
                  const TextInputType.numberWithOptions(decimal: true),
              decoration:
                  const InputDecoration(labelText: 'Cartão 5 Octanas (€)'),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: ten,
              keyboardType:
                  const TextInputType.numberWithOptions(decimal: true),
              decoration:
                  const InputDecoration(labelText: 'Cartão 10 + 1 (€)'),
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
                await widget.repository.saveOctaneConfig(
                  widget.eventId,
                  {
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
                  },
                  id: current?['id']?.toString(),
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
          final bands =
              List<Map<String, dynamic>>.from(snapshot.data![0] as List);
          final exhibitors =
              List<Map<String, dynamic>>.from(snapshot.data![1] as List);
          final sponsors =
              List<Map<String, dynamic>>.from(snapshot.data![2] as List);
          final octanes = snapshot.data![3] as Map<String, dynamic>?;
          final canWrite = widget.repository.canManageRockRide ||
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
  const _EventOperationsPage({
    required this.eventId,
    required this.repository,
  });

  final String eventId;
  final EventsAdvancedRepository repository;

  @override
  State<_EventOperationsPage> createState() => _EventOperationsPageState();
}

class _EventOperationsPageState extends State<_EventOperationsPage> {
  final MemberRepository _members = MemberRepository();
  late Future<List<dynamic>> _future;

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
    ]);
  }

  Future<void> _addTask() async {
    final title = TextEditingController();
    final saved = await _textDialog(
      context,
      title: 'Nova tarefa',
      label: 'Tarefa',
      controller: title,
      onSave: () => widget.repository.saveTask(widget.eventId, {
        'title': title.text.trim(),
        'priority': 'normal',
        'status': 'pending',
      }),
    );
    title.dispose();
    if (saved && mounted) setState(_reload);
  }

  Future<void> _assignTask(Map<String, dynamic> task) async {
    final member = await _pickMember(context, _members);
    if (member == null) return;
    try {
      await widget.repository.assignTask(
        eventId: widget.eventId,
        taskId: task['id'].toString(),
        memberId: member['id'].toString(),
      );
      if (mounted) setState(_reload);
    } catch (error) {
      if (mounted) _snack(context, _friendly(error));
    }
  }

  Future<void> _addShift() async {
    final name = TextEditingController();
    final area = TextEditingController();
    final saved = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Novo turno'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: name,
              decoration: const InputDecoration(labelText: 'Nome do turno'),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: area,
              decoration: const InputDecoration(labelText: 'Área'),
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
              final now = DateTime.now();
              try {
                await widget.repository.saveShift(widget.eventId, {
                  'name': name.text.trim(),
                  'area': _nullText(area.text),
                  'starts_at': now.toIso8601String(),
                  'ends_at':
                      now.add(const Duration(hours: 2)).toIso8601String(),
                  'required_people': 1,
                  'status': 'planned',
                });
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
    area.dispose();
    if (saved == true && mounted) setState(_reload);
  }

  Future<void> _assignShift(Map<String, dynamic> shift) async {
    final member = await _pickMember(context, _members);
    if (member == null) return;
    try {
      await widget.repository.assignShift(
        eventId: widget.eventId,
        shiftId: shift['id'].toString(),
        memberId: member['id'].toString(),
      );
      if (mounted) setState(_reload);
    } catch (error) {
      if (mounted) _snack(context, _friendly(error));
    }
  }

  Future<void> _addProgram(int sequence) async {
    final title = TextEditingController();
    final saved = await _textDialog(
      context,
      title: 'Novo ponto do programa',
      label: 'Título',
      controller: title,
      onSave: () => widget.repository.saveProgramItem(widget.eventId, {
        'sequence_no': sequence,
        'title': title.text.trim(),
        'item_type': 'activity',
      }),
    );
    title.dispose();
    if (saved && mounted) setState(_reload);
  }

  Future<void> _addIncident() async {
    final title = TextEditingController();
    final saved = await _textDialog(
      context,
      title: 'Registar incidente',
      label: 'Descrição curta',
      controller: title,
      onSave: () => widget.repository.saveIncident(widget.eventId, {
        'title': title.text.trim(),
        'severity': 'low',
        'status': 'open',
      }),
    );
    title.dispose();
    if (saved && mounted) setState(_reload);
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
          final tasks =
              List<Map<String, dynamic>>.from(snapshot.data![0] as List);
          final taskAssignees =
              List<Map<String, dynamic>>.from(snapshot.data![1] as List);
          final shifts =
              List<Map<String, dynamic>>.from(snapshot.data![2] as List);
          final shiftMembers =
              List<Map<String, dynamic>>.from(snapshot.data![3] as List);
          final program =
              List<Map<String, dynamic>>.from(snapshot.data![4] as List);
          final incidents =
              List<Map<String, dynamic>>.from(snapshot.data![5] as List);
          final canManage = widget.repository.canManageOperations;
          return ListView(
            padding: const EdgeInsets.all(12),
            children: [
              _OperationSection(
                title: 'Tarefas',
                icon: Icons.task_alt_outlined,
                rows: tasks,
                subtitle: (row) {
                  final assigned = taskAssignees
                      .where((a) => a['task_id'] == row['id'])
                      .length;
                  return '${row['status'] ?? 'pending'} • ${row['priority'] ?? 'normal'} • $assigned atribuído(s)';
                },
                canAdd: canManage,
                onAdd: _addTask,
                onRowAction: canManage ? _assignTask : null,
                actionLabel: 'Atribuir',
              ),
              _OperationSection(
                title: 'Turnos / Escalas',
                icon: Icons.schedule_outlined,
                rows: shifts,
                subtitle: (row) {
                  final assigned = shiftMembers
                      .where((a) => a['shift_id'] == row['id'])
                      .length;
                  return '${row['area'] ?? 'Área'} • $assigned/${row['required_people'] ?? 1} pessoa(s)';
                },
                canAdd: canManage,
                onAdd: _addShift,
                onRowAction: canManage ? _assignShift : null,
                actionLabel: 'Atribuir',
              ),
              _OperationSection(
                title: 'Programa',
                icon: Icons.view_timeline_outlined,
                rows: program,
                subtitle: (row) => row['starts_at'] == null
                    ? 'Hora por definir'
                    : _dateTime(_parse(row['starts_at'])),
                canAdd: canManage,
                onAdd: () => _addProgram(program.length + 1),
              ),
              _OperationSection(
                title: 'Incidentes',
                icon: Icons.report_problem_outlined,
                rows: incidents,
                subtitle: (row) =>
                    '${row['severity'] ?? 'low'} • ${row['status'] ?? 'open'}',
                canAdd: canManage,
                onAdd: _addIncident,
              ),
            ],
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

class _OperationSection extends StatelessWidget {
  const _OperationSection({
    required this.title,
    required this.icon,
    required this.rows,
    required this.subtitle,
    required this.canAdd,
    required this.onAdd,
    this.onRowAction,
    this.actionLabel,
  });

  final String title;
  final IconData icon;
  final List<Map<String, dynamic>> rows;
  final String Function(Map<String, dynamic>) subtitle;
  final bool canAdd;
  final VoidCallback onAdd;
  final Future<void> Function(Map<String, dynamic>)? onRowAction;
  final String? actionLabel;

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
                title: Text(
                  row['title']?.toString() ??
                      row['name']?.toString() ??
                      'Registo',
                ),
                subtitle: Text(subtitle(row)),
                trailing: onRowAction == null
                    ? null
                    : TextButton(
                        onPressed: () => onRowAction!(row),
                        child: Text(actionLabel ?? 'Abrir'),
                      ),
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

Future<Map<String, dynamic>?> _pickMember(
  BuildContext context,
  MemberRepository repository,
) async {
  final members = await repository.listMembers();
  if (!context.mounted) return null;
  return showDialog<Map<String, dynamic>>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      title: const Text('Selecionar membro'),
      content: SizedBox(
        width: 480,
        height: 420,
        child: ListView.builder(
          itemCount: members.length,
          itemBuilder: (context, index) {
            final member = members[index];
            return ListTile(
              title: Text(
                member['nickname']?.toString().trim().isNotEmpty == true
                    ? member['nickname'].toString()
                    : member['full_name']?.toString() ?? 'Membro',
              ),
              subtitle: Text(member['member_number']?.toString() ?? ''),
              onTap: () => Navigator.pop(dialogContext, member),
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

Future<bool> _textDialog(
  BuildContext context, {
  required String title,
  required String label,
  required TextEditingController controller,
  required Future<dynamic> Function() onSave,
}) async {
  final result = await showDialog<bool>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      title: Text(title),
      content: TextField(
        controller: controller,
        decoration: InputDecoration(labelText: label),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(dialogContext, false),
          child: const Text('Cancelar'),
        ),
        FilledButton(
          onPressed: () async {
            if (controller.text.trim().isEmpty) return;
            try {
              await onSave();
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
  return result == true;
}

IconData _eventIcon(Object? kind) => switch (kind?.toString()) {
      'ride' => Icons.two_wheeler_outlined,
      'rock_ride_in' => Icons.music_note_outlined,
      _ => Icons.event_outlined,
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
