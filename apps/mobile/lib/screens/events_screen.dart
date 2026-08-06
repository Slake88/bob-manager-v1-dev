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
  late Future<List<Map<String, dynamic>>> _future;

  AppRole get _role => AppRole.fromValue(AppSession.instance.role);
  bool get _canManage =>
      PermissionPolicy.allows(_role, AppPermission.manageEvents);

  @override
  void initState() {
    super.initState();
    _reload();
  }

  void _reload() => _future = _events.listEvents();

  Future<void> _refresh() async {
    setState(_reload);
    await _future;
  }

  Future<void> _openEvent([Map<String, dynamic>? event]) async {
    final name = TextEditingController(text: event?['name']?.toString() ?? '');
    final location =
        TextEditingController(text: event?['location']?.toString() ?? '');
    final budget = TextEditingController(text: event?['budget']?.toString() ?? '');
    final startsAt =
        TextEditingController(text: event?['starts_at']?.toString() ?? '');
    String status = event?['status']?.toString() ?? 'planning';

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
                    decoration: const InputDecoration(labelText: 'Nome'),
                  ),
                  TextField(
                    controller: location,
                    decoration: const InputDecoration(labelText: 'Local'),
                  ),
                  TextField(
                    controller: startsAt,
                    decoration: const InputDecoration(
                      labelText: 'Início (AAAA-MM-DDTHH:MM)',
                    ),
                  ),
                  TextField(
                    controller: budget,
                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: true,
                    ),
                    decoration: const InputDecoration(labelText: 'Orçamento'),
                  ),
                  DropdownButtonFormField<String>(
                    initialValue: status,
                    decoration: const InputDecoration(labelText: 'Estado'),
                    items: const [
                      'proposed',
                      'approved',
                      'planning',
                      'published',
                      'open',
                      'ongoing',
                      'completed',
                      'cancelled',
                    ]
                        .map((value) => DropdownMenuItem(
                              value: value,
                              child: Text(value),
                            ))
                        .toList(),
                    onChanged: (value) {
                      if (value != null) setDialogState(() => status = value);
                    },
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
                await _events.saveEvent(
                  {
                    'name': name.text.trim(),
                    'location': location.text.trim(),
                    'starts_at': startsAt.text.trim(),
                    'budget': double.tryParse(
                          budget.text.trim().replaceAll(',', '.'),
                        ) ??
                        0,
                    'status': status,
                    'event_type': event?['event_type'] ?? 'other',
                  },
                  eventId: event?['id']?.toString(),
                );
                if (dialogContext.mounted) Navigator.pop(dialogContext, true);
              },
              child: const Text('Guardar'),
            ),
          ],
        ),
      ),
    );

    name.dispose();
    location.dispose();
    budget.dispose();
    startsAt.dispose();
    if (saved == true && mounted) setState(_reload);
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
            return Center(child: Text('Erro: ${snapshot.error}'));
          }
          if (!snapshot.hasData) {
            return const Center(child: CircularProgressIndicator());
          }
          final events = snapshot.data!;
          return RefreshIndicator(
            onRefresh: _refresh,
            child: ListView(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 96),
              children: [
                Text('Eventos', style: Theme.of(context).textTheme.headlineSmall),
                const SizedBox(height: 12),
                if (events.isEmpty)
                  const Card(
                    child: ListTile(
                      leading: Icon(Icons.event_busy_outlined),
                      title: Text('Sem eventos registados.'),
                    ),
                  )
                else
                  ...events.map(
                    (event) => Card(
                      child: ListTile(
                        leading: const CircleAvatar(
                          child: Icon(Icons.event_outlined),
                        ),
                        title: Text(event['name']?.toString() ?? 'Evento'),
                        subtitle: Text([
                          event['starts_at'],
                          event['location'],
                          event['status'],
                        ]
                            .where((value) =>
                                value != null && value.toString().isNotEmpty)
                            .join(' • ')),
                        trailing: _canManage
                            ? IconButton(
                                tooltip: 'Editar',
                                onPressed: () => _openEvent(event),
                                icon: const Icon(Icons.edit_outlined),
                              )
                            : const Icon(Icons.chevron_right),
                        onTap: () => _openDetails(event),
                      ),
                    ),
                  ),
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
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              DropdownButtonFormField<String>(
                initialValue: memberId,
                decoration: const InputDecoration(labelText: 'Membro'),
                items: members
                    .map((member) => DropdownMenuItem<String>(
                          value: member['id'].toString(),
                          child: Text(member['full_name'].toString()),
                        ))
                    .toList(),
                onChanged: (value) {
                  if (value != null) setDialogState(() => memberId = value);
                },
              ),
              TextField(
                controller: extra,
                decoration: InputDecoration(
                  labelText: volunteer ? 'Função' : 'Acompanhante (opcional)',
                ),
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
                final member = members.firstWhere(
                  (row) => row['id'].toString() == memberId,
                );
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
                if (dialogContext.mounted) Navigator.pop(dialogContext, true);
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
            return Center(child: Text('Erro: ${snapshot.error}'));
          }
          if (!snapshot.hasData) {
            return const Center(child: CircularProgressIndicator());
          }
          final data = snapshot.data!;
          final budget = _money(widget.event['budget']);
          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              Card(
                child: ListTile(
                  title: Text(widget.event['location']?.toString() ?? 'Sem local'),
                  subtitle: Text(widget.event['starts_at']?.toString() ?? ''),
                  trailing: Text(widget.event['status']?.toString() ?? ''),
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
                    .map((row) => ListTile(
                          leading: const Icon(Icons.person_outline),
                          title: Text(row['member_name']?.toString() ?? 'Membro'),
                          subtitle: row['companion_name'] == null
                              ? null
                              : Text('Acompanhante: ${row['companion_name']}'),
                        ))
                    .toList(),
                action: _canManage
                    ? IconButton(
                        onPressed: () => _addPerson(volunteer: false),
                        icon: const Icon(Icons.person_add_alt_1_outlined),
                      )
                    : null,
              ),
              _section(
                'Voluntariado (${data.volunteers.length})',
                data.volunteers
                    .map((row) => ListTile(
                          leading: const Icon(Icons.volunteer_activism_outlined),
                          title: Text(row['member_name']?.toString() ?? 'Membro'),
                          subtitle: Text(
                            row['function_name']?.toString() ?? 'Apoio geral',
                          ),
                        ))
                    .toList(),
                action: _canManage
                    ? IconButton(
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
                    child: Text(title, style: Theme.of(context).textTheme.titleMedium),
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

String _money(Object? value) {
  final amount = value is num
      ? value.toDouble()
      : double.tryParse(value?.toString() ?? '') ?? 0;
  return '${amount.toStringAsFixed(2)} €';
}
