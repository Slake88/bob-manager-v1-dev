import 'package:supabase_flutter/supabase_flutter.dart';

import '../core/app_config.dart';
import '../core/app_role.dart';
import '../core/app_session.dart';
import '../core/permissions.dart';

class PollsRepository {
  PollsRepository({SupabaseClient? client}) : _client = client;

  final SupabaseClient? _client;
  SupabaseClient get _supabase => _client ?? Supabase.instance.client;

  bool get isDemo => AppConfig.demoMode;
  bool get canView => AppSession.instance.can(AppPermission.viewCommunication);
  bool get canManage => AppSession.instance.can(AppPermission.manageCommunication);
  bool get isEligible =>
      canView &&
      AppSession.instance.currentRole != AppRole.prospect &&
      AppSession.instance.currentRole != AppRole.unknown;

  final List<Map<String, dynamic>> _demoPolls = [];
  final List<Map<String, dynamic>> _demoOptions = [];
  final List<Map<String, dynamic>> _demoVotes = [];

  String get _profileId => isDemo
      ? AppSession.instance.profileId
      : (_supabase.auth.currentUser?.id ?? AppSession.instance.profileId);

  Future<List<Map<String, dynamic>>> listPolls() async {
    _requireView();
    if (isDemo) {
      if (!canManage && !isEligible) return const [];
      final rows = _demoPolls
          .where((row) {
            if (canManage) return true;
            return row['status'] == 'published' || row['status'] == 'closed';
          })
          .map(Map<String, dynamic>.from)
          .toList()
        ..sort((a, b) => (b['created_at']?.toString() ?? '')
            .compareTo(a['created_at']?.toString() ?? ''));
      return rows;
    }
    final response = await _supabase
        .from('polls')
        .select()
        .eq('club_id', AppSession.instance.clubId)
        .order('created_at', ascending: false);
    return List<Map<String, dynamic>>.from(response);
  }

  Future<List<Map<String, dynamic>>> options(String pollId) async {
    _requireView();
    if (isDemo) {
      return _demoOptions
          .where((row) => row['poll_id'] == pollId)
          .map(Map<String, dynamic>.from)
          .toList()
        ..sort((a, b) => (a['sort_order'] as int).compareTo(b['sort_order'] as int));
    }
    final response = await _supabase
        .from('poll_options')
        .select()
        .eq('club_id', AppSession.instance.clubId)
        .eq('poll_id', pollId)
        .order('sort_order')
        .order('id');
    return List<Map<String, dynamic>>.from(response);
  }

  Future<List<Map<String, dynamic>>> ownVotes(String pollId) async {
    _requireView();
    if (isDemo) {
      return _demoVotes
          .where((row) => row['poll_id'] == pollId && row['profile_id'] == _profileId)
          .map(Map<String, dynamic>.from)
          .toList();
    }
    final response = await _supabase
        .from('poll_votes')
        .select('id,poll_id,option_id,profile_id,created_at')
        .eq('club_id', AppSession.instance.clubId)
        .eq('poll_id', pollId)
        .eq('profile_id', _profileId);
    return List<Map<String, dynamic>>.from(response);
  }

  Future<List<Map<String, dynamic>>> results(String pollId) async {
    _requireView();
    if (isDemo) {
      final poll = _demoPolls.firstWhere((row) => row['id'] == pollId);
      if (!pollResultsVisible(poll, canManage: canManage)) return const [];
      final counts = <String, int>{};
      for (final vote in _demoVotes.where((row) => row['poll_id'] == pollId)) {
        final optionId = vote['option_id'].toString();
        counts[optionId] = (counts[optionId] ?? 0) + 1;
      }
      return counts.entries
          .map((entry) => {
                'poll_id': pollId,
                'option_id': entry.key,
                'vote_count': entry.value,
              })
          .toList();
    }
    final response = await _supabase
        .from('poll_result_counts')
        .select('poll_id,option_id,vote_count,updated_at')
        .eq('club_id', AppSession.instance.clubId)
        .eq('poll_id', pollId);
    return List<Map<String, dynamic>>.from(response);
  }

  Future<String> saveDraft({
    String? pollId,
    required String title,
    String description = '',
    required String pollType,
    required bool anonymous,
    required bool multipleChoice,
    required bool showResultsBeforeClose,
    required DateTime startsAt,
    DateTime? endsAt,
    required List<String> optionLabels,
  }) async {
    _requireManage();
    final cleanTitle = title.trim();
    final cleanOptions = optionLabels
        .map((value) => value.trim())
        .where((value) => value.isNotEmpty)
        .toList();
    if (cleanTitle.length < 3) {
      throw ArgumentError('Indica um título com pelo menos 3 caracteres.');
    }
    if (pollType != 'vote' && pollType != 'survey') {
      throw ArgumentError('Tipo inválido.');
    }
    if (cleanOptions.length < 2) {
      throw ArgumentError('São necessárias pelo menos duas opções.');
    }
    if (cleanOptions.map((value) => value.toLowerCase()).toSet().length !=
        cleanOptions.length) {
      throw ArgumentError('As opções não podem estar repetidas.');
    }
    if (endsAt != null && !endsAt.isAfter(startsAt)) {
      throw ArgumentError('O fecho tem de ser posterior à abertura.');
    }

    if (isDemo) {
      return _saveDemoDraft(
        pollId: pollId,
        title: cleanTitle,
        description: description,
        pollType: pollType,
        anonymous: anonymous,
        multipleChoice: multipleChoice,
        showResultsBeforeClose: showResultsBeforeClose,
        startsAt: startsAt,
        endsAt: endsAt,
        options: cleanOptions,
      );
    }

    final clubId = AppSession.instance.clubId;
    final values = <String, dynamic>{
      'club_id': clubId,
      'title': cleanTitle,
      'description': _nullable(description),
      'poll_type': pollType,
      'anonymous': anonymous,
      'multiple_choice': multipleChoice,
      'show_results_before_close': showResultsBeforeClose,
      'starts_at': startsAt.toUtc().toIso8601String(),
      'ends_at': endsAt?.toUtc().toIso8601String(),
    };
    late final String id;
    if (pollId == null) {
      final row = await _supabase
          .from('polls')
          .insert({...values, 'status': 'draft', 'created_by': _profileId})
          .select('id')
          .single();
      id = row['id'].toString();
    } else {
      id = pollId;
      await _supabase
          .from('polls')
          .update(values)
          .eq('club_id', clubId)
          .eq('id', id)
          .eq('status', 'draft');
      await _supabase
          .from('poll_options')
          .delete()
          .eq('club_id', clubId)
          .eq('poll_id', id);
    }
    await _supabase.from('poll_options').insert([
      for (var index = 0; index < cleanOptions.length; index++)
        {
          'club_id': clubId,
          'poll_id': id,
          'label': cleanOptions[index],
          'sort_order': index,
        },
    ]);
    return id;
  }

  String _saveDemoDraft({
    required String? pollId,
    required String title,
    required String description,
    required String pollType,
    required bool anonymous,
    required bool multipleChoice,
    required bool showResultsBeforeClose,
    required DateTime startsAt,
    required DateTime? endsAt,
    required List<String> options,
  }) {
    final id = pollId ?? 'demo-poll-${DateTime.now().microsecondsSinceEpoch}';
    final now = DateTime.now().toUtc().toIso8601String();
    final values = <String, dynamic>{
      'title': title,
      'description': _nullable(description),
      'poll_type': pollType,
      'anonymous': anonymous,
      'multiple_choice': multipleChoice,
      'show_results_before_close': showResultsBeforeClose,
      'starts_at': startsAt.toUtc().toIso8601String(),
      'ends_at': endsAt?.toUtc().toIso8601String(),
      'updated_at': now,
    };
    if (pollId == null) {
      _demoPolls.insert(0, {
        'id': id,
        'club_id': AppSession.instance.clubId,
        ...values,
        'status': 'draft',
        'created_by': _profileId,
        'created_at': now,
      });
    } else {
      final index = _demoPolls.indexWhere((row) => row['id'] == id);
      if (index < 0 || _demoPolls[index]['status'] != 'draft') {
        throw StateError('Só é possível editar votações em rascunho.');
      }
      _demoPolls[index] = {..._demoPolls[index], ...values};
      _demoOptions.removeWhere((row) => row['poll_id'] == id);
    }
    for (var index = 0; index < options.length; index++) {
      _demoOptions.add({
        'id': 'demo-option-$id-$index',
        'club_id': AppSession.instance.clubId,
        'poll_id': id,
        'label': options[index],
        'sort_order': index,
        'created_at': now,
      });
    }
    return id;
  }

  Future<void> setStatus(String pollId, String status) async {
    _requireManage();
    if (!const {'published', 'closed', 'cancelled'}.contains(status)) {
      throw ArgumentError('Estado inválido.');
    }
    if (isDemo) {
      final index = _demoPolls.indexWhere((row) => row['id'] == pollId);
      if (index < 0) throw StateError('Votação não encontrada.');
      final current = _demoPolls[index]['status']?.toString();
      final valid =
          (current == 'draft' && (status == 'published' || status == 'cancelled')) ||
              (current == 'published' &&
                  (status == 'closed' || status == 'cancelled'));
      if (!valid) throw StateError('Transição de estado inválida.');
      if (status == 'published' &&
          _demoOptions.where((row) => row['poll_id'] == pollId).length < 2) {
        throw StateError('São necessárias pelo menos duas opções para publicar.');
      }
      _demoPolls[index] = {
        ..._demoPolls[index],
        'status': status,
        'updated_at': DateTime.now().toUtc().toIso8601String(),
      };
      return;
    }
    await _supabase
        .from('polls')
        .update({'status': status})
        .eq('club_id', AppSession.instance.clubId)
        .eq('id', pollId);
  }

  Future<void> castVote(String pollId, Iterable<String> optionIds) async {
    _requireVote();
    final selected = optionIds.toSet().toList();
    if (selected.isEmpty) throw ArgumentError('Seleciona pelo menos uma opção.');
    final poll = (await listPolls()).firstWhere(
      (row) => row['id'] == pollId,
      orElse: () => throw StateError('Votação não encontrada.'),
    );
    if (!pollIsOpen(poll)) throw StateError('A votação não está aberta.');
    if (poll['multiple_choice'] != true && selected.length != 1) {
      throw ArgumentError('Esta votação permite apenas uma opção.');
    }
    final valid = (await options(pollId)).map((row) => row['id'].toString()).toSet();
    if (!selected.every(valid.contains)) throw ArgumentError('Opção inválida.');
    if ((await ownVotes(pollId)).isNotEmpty) {
      throw StateError('O teu voto já foi submetido e não pode ser alterado.');
    }

    if (isDemo) {
      final now = DateTime.now().toUtc().toIso8601String();
      for (final optionId in selected) {
        _demoVotes.add({
          'id': 'demo-vote-${DateTime.now().microsecondsSinceEpoch}-$optionId',
          'club_id': AppSession.instance.clubId,
          'poll_id': pollId,
          'option_id': optionId,
          'profile_id': _profileId,
          'created_at': now,
        });
      }
      return;
    }
    await _supabase.from('poll_votes').insert([
      for (final optionId in selected)
        {
          'club_id': AppSession.instance.clubId,
          'poll_id': pollId,
          'option_id': optionId,
          'profile_id': _profileId,
        },
    ]);
  }

  void _requireView() {
    if (!canView) throw StateError('Sem permissão para consultar Comunicação.');
  }

  void _requireManage() {
    if (!canManage) {
      throw StateError('Sem permissão para gerir votações e inquéritos.');
    }
  }

  void _requireVote() {
    if (!isEligible) throw StateError('O teu perfil não é elegível para votar.');
  }
}

bool pollIsOpen(Map<String, dynamic> poll, {DateTime? now}) {
  final instant = (now ?? DateTime.now()).toUtc();
  if (poll['status']?.toString() != 'published') return false;
  final starts = _date(poll['starts_at']);
  final ends = _date(poll['ends_at']);
  if (starts != null && instant.isBefore(starts)) return false;
  if (ends != null && !instant.isBefore(ends)) return false;
  return true;
}

String pollEffectiveStatus(Map<String, dynamic> poll, {DateTime? now}) {
  final status = poll['status']?.toString() ?? 'draft';
  if (status != 'published') return status;
  final instant = (now ?? DateTime.now()).toUtc();
  final starts = _date(poll['starts_at']);
  final ends = _date(poll['ends_at']);
  if (starts != null && instant.isBefore(starts)) return 'scheduled';
  if (ends != null && !instant.isBefore(ends)) return 'closed';
  return 'published';
}

bool pollResultsVisible(
  Map<String, dynamic> poll, {
  required bool canManage,
  DateTime? now,
}) {
  final status = poll['status']?.toString();
  if (status == 'closed') return true;
  if (status != 'published') return false;
  if (poll['show_results_before_close'] == true) return true;
  final ends = _date(poll['ends_at']);
  return ends != null && !(now ?? DateTime.now()).toUtc().isBefore(ends);
}

String pollStatusLabel(Object? value) => switch (value?.toString()) {
      'draft' => 'Rascunho',
      'scheduled' => 'Agendada',
      'published' => 'Aberta',
      'closed' => 'Encerrada',
      'cancelled' => 'Cancelada',
      _ => 'Desconhecido',
    };

String pollTypeLabel(Object? value) =>
    value?.toString() == 'survey' ? 'Inquérito' : 'Votação';

String pollDateLabel(Object? value) {
  final date = value is DateTime ? value : _date(value);
  if (date == null) return '—';
  final local = date.toLocal();
  String two(int n) => n.toString().padLeft(2, '0');
  return '${two(local.day)}/${two(local.month)}/${local.year} '
      '${two(local.hour)}:${two(local.minute)}';
}

DateTime? _date(Object? value) {
  if (value == null) return null;
  if (value is DateTime) return value.toUtc();
  return DateTime.tryParse(value.toString())?.toUtc();
}

String? _nullable(String value) => value.trim().isEmpty ? null : value.trim();
