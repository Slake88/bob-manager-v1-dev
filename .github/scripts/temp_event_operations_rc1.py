from pathlib import Path

repo_path = Path('apps/mobile/lib/repositories/events_advanced_repository.dart')
repo = repo_path.read_text()

old_assign_task = '''  Future<Map<String, dynamic>> assignTask({
    required String eventId,
    required String taskId,
    required String memberId,
  }) async {
    _require(AppPermission.manageEventOperations);
    return _saveEventRow(
      'event_task_assignees',
      eventId,
      {'task_id': taskId, 'member_id': memberId},
    );
  }
'''
new_assign_task = '''  Future<Map<String, dynamic>> assignTask({
    required String eventId,
    required String taskId,
    required String memberId,
  }) async {
    _require(AppPermission.manageEventOperations);
    try {
      return await _saveEventRow(
        'event_task_assignees',
        eventId,
        {'task_id': taskId, 'member_id': memberId},
      );
    } on PostgrestException catch (error) {
      if (error.code == '23505') {
        throw StateError('Este voluntário já está atribuído a esta tarefa.');
      }
      rethrow;
    }
  }

  Future<void> deleteTask({
    required String eventId,
    required String taskId,
  }) async {
    _require(AppPermission.manageEventOperations);
    await _deleteEventRow('event_tasks', eventId, taskId);
  }

  Future<void> removeTaskAssignee({
    required String eventId,
    required String assignmentId,
  }) async {
    _require(AppPermission.manageEventOperations);
    await _deleteEventRow('event_task_assignees', eventId, assignmentId);
  }
'''
if old_assign_task not in repo:
    raise SystemExit('assignTask block not found')
repo = repo.replace(old_assign_task, new_assign_task, 1)

old_assign_shift = '''  Future<Map<String, dynamic>> assignShift({
    required String eventId,
    required String shiftId,
    required String memberId,
  }) async {
    _require(AppPermission.manageEventOperations);
    return _saveEventRow(
      'event_shift_members',
      eventId,
      {'shift_id': shiftId, 'member_id': memberId, 'status': 'assigned'},
    );
  }
'''
new_assign_shift = '''  Future<Map<String, dynamic>> assignShift({
    required String eventId,
    required String shiftId,
    required String memberId,
  }) async {
    _require(AppPermission.manageEventOperations);
    try {
      return await _saveEventRow(
        'event_shift_members',
        eventId,
        {'shift_id': shiftId, 'member_id': memberId, 'status': 'assigned'},
      );
    } on PostgrestException catch (error) {
      if (error.code == '23505') {
        throw StateError('Este voluntário já está atribuído a este turno.');
      }
      rethrow;
    }
  }

  Future<void> deleteShift({
    required String eventId,
    required String shiftId,
  }) async {
    _require(AppPermission.manageEventOperations);
    await _deleteEventRow('event_shifts', eventId, shiftId);
  }

  Future<void> removeShiftMember({
    required String eventId,
    required String assignmentId,
  }) async {
    _require(AppPermission.manageEventOperations);
    await _deleteEventRow('event_shift_members', eventId, assignmentId);
  }
'''
if old_assign_shift not in repo:
    raise SystemExit('assignShift block not found')
repo = repo.replace(old_assign_shift, new_assign_shift, 1)

save_marker = '''  List<Map<String, dynamic>> _demoRows(String table, String eventId) {
'''
if save_marker not in repo:
    raise SystemExit('repository helper marker not found')
delete_helper = '''  Future<void> _deleteEventRow(
    String table,
    String eventId,
    String id,
  ) async {
    if (isDemo) return;
    final response = await _supabase
        .from(table)
        .delete()
        .eq('id', id)
        .eq('event_id', eventId)
        .eq('club_id', AppSession.instance.clubId)
        .select('id');
    if (response.isEmpty) {
      throw StateError('Registo não encontrado ou sem permissão para eliminar.');
    }
  }

'''
repo = repo.replace(save_marker, delete_helper + save_marker, 1)
repo_path.write_text(repo)

screen_path = Path('apps/mobile/lib/screens/events_module_screen.dart')
screen = screen_path.read_text()
start = screen.find('class _EventOperationsPage extends StatefulWidget {')
end = screen.find('class _HubTile extends StatelessWidget {', start)
if start < 0 or end < 0:
    raise SystemExit('operations class bounds not found')

new_operations = r'''class _EventOperationsPage extends StatefulWidget {
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

  String _memberName(
    String? memberId,
    List<Map<String, dynamic>> members,
  ) {
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
                title: Text(
                  volunteer['member_name']?.toString() ?? 'Membro',
                ),
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
                      DropdownMenuItem(value: 'critical', child: Text('Crítica')),
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
                      DropdownMenuItem(value: 'pending', child: Text('Pendente')),
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
              onPressed:
                  saving ? null : () => Navigator.pop(dialogContext, false),
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
                        await widget.repository.saveTask(
                          widget.eventId,
                          {
                            'title': title.text.trim(),
                            'description': _nullText(description.text),
                            'priority': priority,
                            'status': status,
                            'due_at': dueAt?.toUtc().toIso8601String(),
                            'completed_at': status == 'done'
                                ? task?['completed_at'] ??
                                    DateTime.now().toUtc().toIso8601String()
                                : null,
                            'notes': _nullText(notes.text),
                          },
                          id: task?['id']?.toString(),
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
    final notes = TextEditingController(text: shift?['notes']?.toString() ?? '');
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
                      DropdownMenuItem(value: 'planned', child: Text('Planeado')),
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
              onPressed:
                  saving ? null : () => Navigator.pop(dialogContext, false),
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
                        await widget.repository.saveShift(
                          widget.eventId,
                          {
                            'name': name.text.trim(),
                            'area': _nullText(area.text),
                            'starts_at': startsAt.toUtc().toIso8601String(),
                            'ends_at': endsAt.toUtc().toIso8601String(),
                            'required_people': people,
                            'status': status,
                            'notes': _nullText(notes.text),
                          },
                          id: shift?['id']?.toString(),
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
              title: Text('Adiciona voluntários em Participantes e acompanhantes.'),
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
            ...assignments.map(
              (assignment) {
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
              },
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
            title: Text(
              '${_dateTime(startsAt)} → ${_dateTime(endsAt)}',
            ),
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
                subtitle: Text(
                  _assignmentStatusLabel(assignment['status']),
                ),
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
                _OperationSection(
                  title: 'Programa',
                  icon: Icons.view_timeline_outlined,
                  rows: program,
                  subtitle: (row) => row['starts_at'] == null
                      ? 'Hora por definir'
                      : _dateTime(_parse(row['starts_at'])?.toLocal()),
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
            ),
          );
        },
      ),
    );
  }
}

'''
screen = screen[:start] + new_operations + screen[end:]
screen_path.write_text(screen)
