from pathlib import Path


def replace_once(text: str, old: str, new: str, label: str) -> str:
    count = text.count(old)
    if count != 1:
        raise SystemExit(f"{label}: expected 1 match, found {count}")
    return text.replace(old, new, 1)

repo_path = Path('apps/mobile/lib/repositories/events_advanced_repository.dart')
screen_path = Path('apps/mobile/lib/screens/events_module_screen.dart')
readme_path = Path('README.md')

repo = repo_path.read_text(encoding='utf-8')
old_repo = r'''  Future<Map<String, dynamic>> saveProgramItem(
    String eventId,
    Map<String, dynamic> values, {
    String? id,
  }) async {
    _require(AppPermission.manageEventOperations);
    return _saveEventRow('event_program', eventId, values, id: id);
  }

  Future<Map<String, dynamic>> saveIncident(
    String eventId,
    Map<String, dynamic> values, {
    String? id,
  }) async {
    if (!canManageOperations &&
        !AppSession.instance.can(AppPermission.viewEvents)) {
      throw StateError('Sem permissão para registar incidentes.');
    }
    return _saveEventRow('event_incidents', eventId, values, id: id);
  }
'''
new_repo = r'''  Future<Map<String, dynamic>> saveProgramItem(
    String eventId,
    Map<String, dynamic> values, {
    String? id,
  }) async {
    _require(AppPermission.manageEventOperations);
    return _saveEventRow('event_program', eventId, values, id: id);
  }

  Future<void> deleteProgramItem({
    required String eventId,
    required String itemId,
  }) async {
    _require(AppPermission.manageEventOperations);
    await _deleteEventRow('event_program', eventId, itemId);
  }

  Future<void> reorderProgramItems({
    required String eventId,
    required List<String> itemIds,
  }) async {
    _require(AppPermission.manageEventOperations);
    final normalized = itemIds.map((id) => id.trim()).toList();
    if (normalized.any((id) => id.isEmpty)) {
      throw ArgumentError('Não foi possível identificar todos os pontos do programa.');
    }
    if (normalized.toSet().length != normalized.length) {
      throw ArgumentError('A ordem do programa contém registos repetidos.');
    }
    if (isDemo || normalized.isEmpty) return;
    try {
      await _supabase.rpc(
        'reorder_event_program_v1',
        params: {'p_event': eventId, 'p_item_ids': normalized},
      );
    } on PostgrestException catch (error) {
      if (error.code == 'P0001' || error.code == '42501') {
        throw StateError(error.message);
      }
      rethrow;
    }
  }

  Future<Map<String, dynamic>> saveIncident(
    String eventId,
    Map<String, dynamic> values, {
    String? id,
  }) async {
    if (!canManageOperations &&
        !AppSession.instance.can(AppPermission.viewEvents)) {
      throw StateError('Sem permissão para registar incidentes.');
    }
    return _saveEventRow('event_incidents', eventId, values, id: id);
  }

  Future<void> deleteIncident({
    required String eventId,
    required String incidentId,
  }) async {
    _require(AppPermission.manageEventOperations);
    await _deleteEventRow('event_incidents', eventId, incidentId);
  }
'''
repo = replace_once(repo, old_repo, new_repo, 'repository program/incidents methods')
repo_path.write_text(repo, encoding='utf-8')

screen = screen_path.read_text(encoding='utf-8')
old_state = r'''class _EventOperationsPageState extends State<_EventOperationsPage> {
  final MemberRepository _members = MemberRepository();
  final EventsRepository _events = EventsRepository();
  late Future<List<dynamic>> _future;
'''
new_state = r'''class _EventOperationsPageState extends State<_EventOperationsPage> {
  final MemberRepository _members = MemberRepository();
  final EventsRepository _events = EventsRepository();
  late Future<List<dynamic>> _future;
  bool _reorderingProgram = false;
'''
screen = replace_once(screen, old_state, new_state, 'operations state')

old_methods = r'''  Future<void> _addProgram(int sequence) async {
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
'''
new_methods = r'''  Future<void> _editProgram(
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
      'briefing' || 'ride' || 'meal' || 'music' || 'other' =>
        item!['item_type'].toString(),
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
          title: Text(item == null ? 'Novo ponto do programa' : 'Editar ponto do programa'),
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
                      DropdownMenuItem(value: 'activity', child: Text('Atividade')),
                      DropdownMenuItem(value: 'briefing', child: Text('Briefing')),
                      DropdownMenuItem(value: 'ride', child: Text('Passeio / deslocação')),
                      DropdownMenuItem(value: 'meal', child: Text('Refeição')),
                      DropdownMenuItem(value: 'music', child: Text('Música / concerto')),
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
                                    : () => setDialogState(() => startsAt = null),
                                icon: const Icon(Icons.clear),
                              ),
                      ),
                      child: Text(startsAt == null ? 'Hora por definir' : _dateTime(startsAt)),
                    ),
                  ),
                  const SizedBox(height: 10),
                  InkWell(
                    borderRadius: BorderRadius.circular(12),
                    onTap: saving
                        ? null
                        : () async {
                            final initial =
                                endsAt ?? startsAt?.add(const Duration(hours: 1)) ?? DateTime.now();
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
                      child: Text(endsAt == null ? 'Hora por definir' : _dateTime(endsAt)),
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
                    initialValue: members.any(
                      (member) => member['id']?.toString() == responsibleMemberId,
                    )
                        ? responsibleMemberId
                        : '',
                    decoration: const InputDecoration(
                      labelText: 'Responsável (opcional)',
                      prefixIcon: Icon(Icons.person_outline),
                    ),
                    items: [
                      const DropdownMenuItem(value: '', child: Text('Sem responsável')),
                      ...members.map(
                        (member) => DropdownMenuItem<String>(
                          value: member['id'].toString(),
                          child: Text(_memberName(member['id'].toString(), members)),
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
              onPressed: saving ? null : () => Navigator.pop(dialogContext, false),
              child: const Text('Cancelar'),
            ),
            FilledButton.icon(
              onPressed: saving
                  ? null
                  : () async {
                      if (title.text.trim().isEmpty) {
                        _snack(dialogContext, 'Indica o título do ponto do programa.');
                        return;
                      }
                      if (startsAt != null && endsAt != null && endsAt!.isBefore(startsAt!)) {
                        _snack(dialogContext, 'O fim não pode ser anterior ao início.');
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
        item == null ? 'Ponto do programa criado.' : 'Ponto do programa atualizado.',
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
        subtitle: Text('${program.length} ponto${program.length == 1 ? '' : 's'}'),
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
                  ? (oldIndex, newIndex) => _reorderProgram(program, oldIndex, newIndex)
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
                  leading: CircleAvatar(child: Text('${item['sequence_no'] ?? index + 1}')),
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
    final title = TextEditingController(text: incident?['title']?.toString() ?? '');
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
          title: Text(incident == null ? 'Registar incidente' : 'Editar incidente'),
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
                      DropdownMenuItem(value: 'critical', child: Text('Crítica')),
                    ],
                    onChanged: saving
                        ? null
                        : (value) {
                            if (value != null) setDialogState(() => severity = value);
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
                      DropdownMenuItem(value: 'monitoring', child: Text('Em acompanhamento')),
                      DropdownMenuItem(value: 'resolved', child: Text('Resolvido')),
                      DropdownMenuItem(value: 'closed', child: Text('Fechado')),
                    ],
                    onChanged: saving
                        ? null
                        : (value) {
                            if (value != null) setDialogState(() => status = value);
                          },
                  ),
                  const SizedBox(height: 10),
                  DropdownButtonFormField<String>(
                    initialValue: members.any(
                      (member) => member['id']?.toString() == assignedMemberId,
                    )
                        ? assignedMemberId
                        : '',
                    decoration: const InputDecoration(
                      labelText: 'Responsável (opcional)',
                      prefixIcon: Icon(Icons.person_outline),
                    ),
                    items: [
                      const DropdownMenuItem(value: '', child: Text('Sem responsável')),
                      ...members.map(
                        (member) => DropdownMenuItem<String>(
                          value: member['id'].toString(),
                          child: Text(_memberName(member['id'].toString(), members)),
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
              onPressed: saving ? null : () => Navigator.pop(dialogContext, false),
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
                      final resolved = status == 'resolved' || status == 'closed';
                      if (resolved && resolution.text.trim().isEmpty) {
                        _snack(dialogContext, 'Indica a resolução antes de concluir o incidente.');
                        return;
                      }
                      setDialogState(() => saving = true);
                      try {
                        await widget.repository.saveIncident(
                          widget.eventId,
                          {
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
                          },
                          id: incident?['id']?.toString(),
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
    location.dispose();
    resolution.dispose();
    if (saved == true && mounted) {
      _snack(context, incident == null ? 'Incidente registado.' : 'Incidente atualizado.');
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
              final locationText = incident['location']?.toString().trim() ?? '';
              final descriptionText = incident['description']?.toString().trim() ?? '';
              final resolutionText = incident['resolution']?.toString().trim() ?? '';
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
                leading: const CircleAvatar(child: Icon(Icons.warning_amber_outlined)),
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
'''
screen = replace_once(screen, old_methods, new_methods, 'program and incident methods')

old_build = r'''                _OperationSection(
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
'''
new_build = r'''                _programSection(program, members, canManage),
                _incidentSection(incidents, members, canManage),
'''
screen = replace_once(screen, old_build, new_build, 'operations build sections')
screen_path.write_text(screen, encoding='utf-8')

readme = readme_path.read_text(encoding='utf-8')
paragraph = "\n\nO Programa do evento permite criar e editar pontos com tipo, início, fim, local, responsável e notas, eliminar registos e reordená-los por arrastar, com persistência atómica da sequência. A gestão de Incidentes permite registar data/hora, título, descrição, local, gravidade, estado, responsável e resolução, mantendo `resolved_at` coerente ao resolver ou reabrir um incidente e disponibilizando edição e eliminação aos gestores de operações.\n"
if paragraph.strip() not in readme:
    readme = readme.rstrip() + paragraph
readme_path.write_text(readme, encoding='utf-8')
