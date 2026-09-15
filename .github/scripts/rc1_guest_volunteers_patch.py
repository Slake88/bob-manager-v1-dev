from pathlib import Path
import re


def regex_one(text: str, pattern: str, replacement: str, label: str) -> str:
    updated, count = re.subn(pattern, replacement, text, count=1, flags=re.S)
    if count != 1:
        raise SystemExit(f"{label}: expected 1 match, found {count}")
    return updated


def replace_one(text: str, old: str, new: str, label: str) -> str:
    count = text.count(old)
    if count != 1:
        raise SystemExit(f"{label}: expected 1 match, found {count}")
    return text.replace(old, new, 1)


# EventsRepository: load and create member/guest volunteers.
repo_path = Path("apps/mobile/lib/repositories/events_repository.dart")
repo = repo_path.read_text()
repo = regex_one(
    repo,
    r"  Future<List<Map<String, dynamic>>> volunteers\(String eventId\) async \{.*?\n  \}\n\n  Future<Map<String, dynamic>> addVolunteer\(",
    """  Future<List<Map<String, dynamic>>> volunteers(String eventId) async {
    _require(AppPermission.viewEvents);
    if (AppConfig.demoMode) {
      return _dataService.listWhere(
        'event_volunteers',
        field: 'event_id',
        value: eventId,
      );
    }

    final response = await _client
        .from('event_volunteers')
        .select(
          'id,event_id,member_id,guest_id,function_name,status,created_at,'
          'members(full_name),'
          'event_registration_guests(guest_name,event_registrations(member_id,members(full_name)))',
        )
        .eq('event_id', eventId)
        .order('created_at');
    return List<Map<String, dynamic>>.from(response).map((row) {
      final member = row['members'];
      final guest = row['event_registration_guests'];
      final registration = guest is Map ? guest['event_registrations'] : null;
      final hostMember = registration is Map ? registration['members'] : null;
      final memberName = member is Map
          ? member['full_name']?.toString().trim()
          : null;
      final guestName = guest is Map
          ? guest['guest_name']?.toString().trim()
          : null;
      final hostMemberName = hostMember is Map
          ? hostMember['full_name']?.toString().trim()
          : null;
      final isGuest = row['guest_id'] != null;
      final displayName = isGuest
          ? (guestName?.isNotEmpty == true ? guestName! : 'Acompanhante')
          : (memberName?.isNotEmpty == true ? memberName! : 'Membro');
      return <String, dynamic>{
        ...row,
        'member_name': memberName,
        'guest_name': guestName,
        'host_member_name': hostMemberName,
        'display_name': displayName,
        'volunteer_kind': isGuest ? 'guest' : 'member',
      };
    }).toList();
  }

  Future<Map<String, dynamic>> addVolunteer(""",
    "volunteers reader",
)

guest_method = """  Future<Map<String, dynamic>> addGuestVolunteer({
    required String eventId,
    required String guestId,
    required String guestName,
    required String hostMemberName,
    required String functionName,
  }) async {
    _require(AppPermission.manageEventParticipants);
    final normalizedFunction = functionName.trim();
    if (normalizedFunction.isEmpty) {
      throw ArgumentError('Indica a função do voluntário.');
    }
    if (AppConfig.demoMode) {
      final existing = await _dataService.listWhere(
        'event_volunteers',
        field: 'event_id',
        value: eventId,
      );
      if (existing.any((row) => row['guest_id']?.toString() == guestId)) {
        throw StateError(
          'Este acompanhante já está registado como voluntário neste evento.',
        );
      }
      return _dataService.insert('event_volunteers', {
        'event_id': eventId,
        'member_id': null,
        'guest_id': guestId,
        'guest_name': guestName,
        'host_member_name': hostMemberName,
        'display_name': guestName,
        'volunteer_kind': 'guest',
        'function_name': normalizedFunction,
        'status': 'confirmed',
      });
    }

    try {
      final response = await _client
          .from('event_volunteers')
          .insert({
            'club_id': AppSession.instance.clubId,
            'event_id': eventId,
            'guest_id': guestId,
            'function_name': normalizedFunction,
            'status': 'confirmed',
          })
          .select()
          .single();
      return <String, dynamic>{
        ...Map<String, dynamic>.from(response),
        'guest_name': guestName,
        'host_member_name': hostMemberName,
        'display_name': guestName,
        'volunteer_kind': 'guest',
      };
    } on PostgrestException catch (error) {
      if (error.code == '23505' ||
          error.message.contains('event_volunteers_event_guest_unique')) {
        throw StateError(
          'Este acompanhante já está registado como voluntário neste evento.',
        );
      }
      rethrow;
    }
  }

"""
repo = replace_one(
    repo,
    "  Future<void> removeVolunteer(String volunteerId) async {",
    guest_method + "  Future<void> removeVolunteer(String volunteerId) async {",
    "guest volunteer writer",
)
repo_path.write_text(repo)

# Advanced repository: task/shift assignments can target either subject type.
advanced_path = Path("apps/mobile/lib/repositories/events_advanced_repository.dart")
advanced = advanced_path.read_text()
advanced = regex_one(
    advanced,
    r"  Future<Map<String, dynamic>> assignTask\(\{.*?\n  \}\n\n  Future<void> deleteTask\(",
    """  Future<Map<String, dynamic>> assignTask({
    required String eventId,
    required String taskId,
    String? memberId,
    String? guestId,
  }) async {
    _require(AppPermission.manageEventOperations);
    final normalizedMemberId = memberId?.trim() ?? '';
    final normalizedGuestId = guestId?.trim() ?? '';
    final hasMember = normalizedMemberId.isNotEmpty;
    final hasGuest = normalizedGuestId.isNotEmpty;
    if (hasMember == hasGuest) {
      throw ArgumentError('Seleciona exatamente um voluntário.');
    }
    try {
      return await _saveEventRow('event_task_assignees', eventId, {
        'task_id': taskId,
        'member_id': hasMember ? normalizedMemberId : null,
        'guest_id': hasGuest ? normalizedGuestId : null,
      });
    } on PostgrestException catch (error) {
      if (error.code == '23505') {
        throw StateError('Este voluntário já está atribuído a esta tarefa.');
      }
      if (error.code == 'P0001' || error.code == '23514') {
        throw StateError(error.message);
      }
      rethrow;
    }
  }

  Future<void> deleteTask(""",
    "assign task",
)
advanced = regex_one(
    advanced,
    r"  Future<Map<String, dynamic>> assignShift\(\{.*?\n  \}\n\n  Future<void> deleteShift\(",
    """  Future<Map<String, dynamic>> assignShift({
    required String eventId,
    required String shiftId,
    String? memberId,
    String? guestId,
  }) async {
    _require(AppPermission.manageEventOperations);
    final normalizedMemberId = memberId?.trim() ?? '';
    final normalizedGuestId = guestId?.trim() ?? '';
    final hasMember = normalizedMemberId.isNotEmpty;
    final hasGuest = normalizedGuestId.isNotEmpty;
    if (hasMember == hasGuest) {
      throw ArgumentError('Seleciona exatamente um voluntário.');
    }
    try {
      return await _saveEventRow('event_shift_members', eventId, {
        'shift_id': shiftId,
        'member_id': hasMember ? normalizedMemberId : null,
        'guest_id': hasGuest ? normalizedGuestId : null,
        'status': 'assigned',
      });
    } on PostgrestException catch (error) {
      if (error.code == '23505') {
        throw StateError('Este voluntário já está atribuído a este turno.');
      }
      if (error.code == 'P0001' || error.code == '23514') {
        throw StateError(error.message);
      }
      rethrow;
    }
  }

  Future<void> deleteShift(""",
    "assign shift",
)
advanced_path.write_text(advanced)

# Participant screen: choose members or companions as volunteers.
agenda_path = Path("apps/mobile/lib/screens/events_agenda_v2_screen.dart")
agenda = agenda_path.read_text()
agenda = regex_one(
    agenda,
    r"  Future<void> _addVolunteer\(\) async \{.*?\n  \}\n\n  Future<void> _removeVolunteer",
    """  Future<void> _addVolunteer(_EventDetailV2Data data) async {
    final members = await widget.memberRepository.listMembers();
    if (!mounted) return;

    final existingKeys = data.volunteers.map((row) {
      final guestId = row['guest_id']?.toString().trim() ?? '';
      if (guestId.isNotEmpty) return 'guest:$guestId';
      return 'member:${row['member_id']?.toString() ?? ''}';
    }).toSet();

    final candidates = <Map<String, dynamic>>[];
    for (final member in members) {
      final id = member['id']?.toString() ?? '';
      if (id.isEmpty || existingKeys.contains('member:$id')) continue;
      final name = member['full_name']?.toString().trim() ?? '';
      candidates.add({
        'key': 'member:$id',
        'kind': 'member',
        'id': id,
        'name': name.isEmpty ? 'Membro' : name,
        'label': 'Membro',
      });
    }
    for (final registration in data.participants) {
      final hostName =
          registration['member_name']?.toString().trim().isNotEmpty == true
          ? registration['member_name'].toString().trim()
          : 'participante';
      for (final companion in _companions(registration)) {
        final id = companion['id']?.toString() ?? '';
        if (id.isEmpty || existingKeys.contains('guest:$id')) continue;
        final name = companion['guest_name']?.toString().trim() ?? '';
        candidates.add({
          'key': 'guest:$id',
          'kind': 'guest',
          'id': id,
          'name': name.isEmpty ? 'Acompanhante' : name,
          'host_name': hostName,
          'label': 'Acompanhante de $hostName',
        });
      }
    }

    if (candidates.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Não existem membros ou acompanhantes disponíveis para adicionar.',
          ),
        ),
      );
      return;
    }

    String subjectKey = candidates.first['key'].toString();
    final function = TextEditingController();
    final saved = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('Adicionar voluntário'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                DropdownButtonFormField<String>(
                  initialValue: subjectKey,
                  decoration: const InputDecoration(labelText: 'Pessoa'),
                  items: candidates
                      .map(
                        (candidate) => DropdownMenuItem<String>(
                          value: candidate['key'].toString(),
                          child: Text(
                            '${candidate['name']} — ${candidate['label']}',
                          ),
                        ),
                      )
                      .toList(),
                  onChanged: (value) {
                    if (value != null) {
                      setDialogState(() => subjectKey = value);
                    }
                  },
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: function,
                  decoration: const InputDecoration(labelText: 'Função'),
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
                final candidate = candidates.firstWhere(
                  (row) => row['key']?.toString() == subjectKey,
                );
                final functionName = function.text.trim().isEmpty
                    ? 'Apoio geral'
                    : function.text.trim();
                try {
                  if (candidate['kind'] == 'guest') {
                    await widget.repository.addGuestVolunteer(
                      eventId: widget.event['id'].toString(),
                      guestId: candidate['id'].toString(),
                      guestName: candidate['name'].toString(),
                      hostMemberName:
                          candidate['host_name']?.toString() ?? 'participante',
                      functionName: functionName,
                    );
                  } else {
                    await widget.repository.addVolunteer(
                      eventId: widget.event['id'].toString(),
                      memberId: candidate['id'].toString(),
                      memberName: candidate['name'].toString(),
                      functionName: functionName,
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
    function.dispose();
    if (saved == true && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Voluntário adicionado ao evento.')),
      );
      setState(_reload);
    }
  }

  Future<void> _removeVolunteer""",
    "participant volunteer chooser",
)
agenda = replace_one(
    agenda,
    "                          onPressed: _addVolunteer,",
    "                          onPressed: () => _addVolunteer(data),",
    "volunteer add action",
)
agenda = replace_one(
    agenda,
    """                          title: Text(
                            row['member_name']?.toString() ?? 'Membro',
                          ),
                          subtitle: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                row['function_name']?.toString() ??
                                    'Apoio geral',
                              ),
""",
    """                          title: Text(
                            row['display_name']?.toString() ??
                                row['member_name']?.toString() ??
                                row['guest_name']?.toString() ??
                                'Voluntário',
                          ),
                          subtitle: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                row['guest_id'] != null
                                    ? 'Acompanhante de ${row['host_member_name']?.toString() ?? 'participante'} • ${row['function_name']?.toString() ?? 'Apoio geral'}'
                                    : row['function_name']?.toString() ??
                                        'Apoio geral',
                              ),
""",
    "volunteer display in participant screen",
)
agenda_path.write_text(agenda)

# Operations screen: task/shift assignments use stable member/guest subject keys.
module_path = Path("apps/mobile/lib/screens/events_module_screen.dart")
module = module_path.read_text()
module = regex_one(
    module,
    r"  Future<Map<String, dynamic>\?> _pickVolunteer\(.*?\n  \}\n\n  Future<DateTime\?> _pickDateTime",
    """  String _volunteerSubjectKey(Map<String, dynamic> row) {
    final guestId = row['guest_id']?.toString().trim() ?? '';
    if (guestId.isNotEmpty) return 'guest:$guestId';
    final memberId = row['member_id']?.toString().trim() ?? '';
    return 'member:$memberId';
  }

  String _volunteerDisplayName(Map<String, dynamic> row) {
    final displayName = row['display_name']?.toString().trim() ?? '';
    if (displayName.isNotEmpty) return displayName;
    final guestName = row['guest_name']?.toString().trim() ?? '';
    if (guestName.isNotEmpty) return guestName;
    final memberName = row['member_name']?.toString().trim() ?? '';
    if (memberName.isNotEmpty) return memberName;
    return row['guest_id'] != null ? 'Acompanhante' : 'Membro';
  }

  String _assignmentDisplayName(
    Map<String, dynamic> assignment,
    List<Map<String, dynamic>> volunteers,
    List<Map<String, dynamic>> members,
  ) {
    final key = _volunteerSubjectKey(assignment);
    for (final volunteer in volunteers) {
      if (_volunteerSubjectKey(volunteer) == key) {
        return _volunteerDisplayName(volunteer);
      }
    }
    final memberId = assignment['member_id']?.toString().trim() ?? '';
    if (memberId.isNotEmpty) return _memberName(memberId, members);
    return 'Acompanhante';
  }

  Future<Map<String, dynamic>?> _pickVolunteer(
    List<Map<String, dynamic>> volunteers,
    Set<String> excludedSubjectKeys,
  ) async {
    final available = volunteers
        .where((row) => !excludedSubjectKeys.contains(_volunteerSubjectKey(row)))
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
              final isGuest = volunteer['guest_id'] != null;
              final hostName =
                  volunteer['host_member_name']?.toString().trim() ?? '';
              return ListTile(
                leading: CircleAvatar(
                  child: Icon(
                    isGuest
                        ? Icons.group_outlined
                        : Icons.volunteer_activism_outlined,
                  ),
                ),
                title: Text(_volunteerDisplayName(volunteer)),
                subtitle: Text(
                  isGuest
                      ? 'Acompanhante${hostName.isEmpty ? '' : ' de $hostName'} • ${volunteer['function_name']?.toString() ?? 'Apoio geral'}'
                      : volunteer['function_name']?.toString() ?? 'Apoio geral',
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

  Future<DateTime?> _pickDateTime""",
    "volunteer picker",
)
module = regex_one(
    module,
    r"  Future<void> _assignTask\(.*?\n  \}\n\n  Future<void> _removeTaskAssignee",
    """  Future<void> _assignTask(
    Map<String, dynamic> task,
    List<Map<String, dynamic>> taskAssignees,
    List<Map<String, dynamic>> volunteers,
  ) async {
    final assignedKeys = taskAssignees
        .where((row) => row['task_id']?.toString() == task['id']?.toString())
        .map(_volunteerSubjectKey)
        .toSet();
    final volunteer = await _pickVolunteer(volunteers, assignedKeys);
    if (volunteer == null) return;
    try {
      await widget.repository.assignTask(
        eventId: widget.eventId,
        taskId: task['id'].toString(),
        memberId: volunteer['member_id']?.toString(),
        guestId: volunteer['guest_id']?.toString(),
      );
      if (!mounted) return;
      _snack(context, 'Voluntário atribuído à tarefa.');
      setState(_reload);
    } catch (error) {
      if (mounted) _snack(context, _friendly(error));
    }
  }

  Future<void> _removeTaskAssignee""",
    "task UI assignment",
)
module = regex_one(
    module,
    r"  Future<void> _assignShift\(.*?\n  \}\n\n  Future<void> _removeShiftMember",
    """  Future<void> _assignShift(
    Map<String, dynamic> shift,
    List<Map<String, dynamic>> shiftMembers,
    List<Map<String, dynamic>> volunteers,
  ) async {
    final assignedKeys = shiftMembers
        .where((row) => row['shift_id']?.toString() == shift['id']?.toString())
        .map(_volunteerSubjectKey)
        .toSet();
    final volunteer = await _pickVolunteer(volunteers, assignedKeys);
    if (volunteer == null) return;
    try {
      await widget.repository.assignShift(
        eventId: widget.eventId,
        shiftId: shift['id'].toString(),
        memberId: volunteer['member_id']?.toString(),
        guestId: volunteer['guest_id']?.toString(),
      );
      if (!mounted) return;
      _snack(context, 'Voluntário atribuído ao turno.');
      setState(_reload);
    } catch (error) {
      if (mounted) _snack(context, _friendly(error));
    }
  }

  Future<void> _removeShiftMember""",
    "shift UI assignment",
)
module = regex_one(
    module,
    r"  Widget _volunteerSummary\(List<Map<String, dynamic>> volunteers\) \{.*?\n  \}\n\n  Widget _taskCard",
    """  Widget _volunteerSummary(List<Map<String, dynamic>> volunteers) {
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
            ...volunteers.map((row) {
              final isGuest = row['guest_id'] != null;
              final hostName = row['host_member_name']?.toString().trim() ?? '';
              final functionName =
                  row['function_name']?.toString() ?? 'Apoio geral';
              return ListTile(
                leading: CircleAvatar(
                  child: Icon(
                    isGuest ? Icons.group_outlined : Icons.person_outline,
                  ),
                ),
                title: Text(_volunteerDisplayName(row)),
                subtitle: Text(
                  isGuest
                      ? 'Acompanhante${hostName.isEmpty ? '' : ' de $hostName'} • $functionName'
                      : functionName,
                ),
              );
            }),
        ],
      ),
    );
  }

  Widget _taskCard""",
    "volunteer summary",
)
old_assignment_title = """                title: Text(
                  _memberName(assignment['member_id']?.toString(), members),
                ),
"""
count = module.count(old_assignment_title)
if count != 2:
    raise SystemExit(f"assignment names: expected 2 matches, found {count}")
module = module.replace(
    old_assignment_title,
    """                title: Text(
                  _assignmentDisplayName(assignment, volunteers, members),
                ),
""",
)
module_path.write_text(module)
