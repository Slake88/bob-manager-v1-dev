import 'package:supabase_flutter/supabase_flutter.dart';

import '../core/app_config.dart';
import '../core/app_session.dart';
import '../services/data_service.dart';
import '../services/rc1_data_extensions.dart';

class MemberRepository {
  MemberRepository({DataService? dataService, SupabaseClient? client})
      : _dataService = dataService ?? DataService.instance,
        _client = client;

  final DataService _dataService;
  final SupabaseClient? _client;

  SupabaseClient get _supabase => _client ?? Supabase.instance.client;

  Future<List<Map<String, dynamic>>> listMembers() async {
    final rows = AppConfig.demoMode
        ? await _dataService.list('members')
        : await _listMembersFromSupabase();

    rows.sort((a, b) {
      final aNumber = int.tryParse(a['member_number']?.toString() ?? '');
      final bNumber = int.tryParse(b['member_number']?.toString() ?? '');
      return (aNumber ?? 999999).compareTo(bNumber ?? 999999);
    });
    return rows;
  }

  Future<Map<String, dynamic>?> getMember(String memberId) async {
    if (AppConfig.demoMode) {
      return _dataService.getById('members', memberId);
    }

    final response = await _supabase
        .from('members')
        .select()
        .eq('id', memberId)
        .eq('club_id', AppSession.instance.clubId)
        .maybeSingle();
    if (response == null) return null;

    final member = _normaliseMember(Map<String, dynamic>.from(response));
    final motorcycles = await motorcyclesFor(memberId);
    return _withPrimaryMotorcycle(member, motorcycles);
  }

  Future<Map<String, dynamic>> saveMember(
    Map<String, dynamic> values, {
    String? memberId,
  }) async {
    if (AppConfig.demoMode) {
      if (memberId == null) {
        return _dataService.insert('members', values);
      }
      return _dataService.update('members', memberId, values);
    }

    final payload = _memberPayload(values);
    if (memberId == null) {
      final response = await _supabase
          .from('members')
          .insert({...payload, 'club_id': AppSession.instance.clubId})
          .select()
          .single();
      return _normaliseMember(Map<String, dynamic>.from(response));
    }

    final response = await _supabase
        .from('members')
        .update(payload)
        .eq('id', memberId)
        .eq('club_id', AppSession.instance.clubId)
        .select()
        .single();
    return _normaliseMember(Map<String, dynamic>.from(response));
  }

  Future<void> deleteMember(String memberId) async {
    if (AppConfig.demoMode) {
      await _dataService.delete('members', memberId);
      return;
    }

    await _supabase
        .from('members')
        .delete()
        .eq('id', memberId)
        .eq('club_id', AppSession.instance.clubId);
  }

  Future<List<Map<String, dynamic>>> motorcyclesFor(String memberId) async {
    if (AppConfig.demoMode) {
      return _dataService.listWhere(
        'motorcycles',
        field: 'member_id',
        value: memberId,
      );
    }

    final response = await _supabase
        .from('member_motorcycles')
        .select()
        .eq('club_id', AppSession.instance.clubId)
        .eq('member_id', memberId)
        .order('primary_motorcycle', ascending: false)
        .order('created_at');
    return List<Map<String, dynamic>>.from(response);
  }

  Future<List<Map<String, dynamic>>> related(
    String table,
    String memberId,
  ) async {
    if (AppConfig.demoMode) {
      return _dataService.listWhere(
        table,
        field: 'member_id',
        value: memberId,
      );
    }

    if (table == 'motorcycles' || table == 'member_motorcycles') {
      return motorcyclesFor(memberId);
    }

    // Estas áreas ainda não têm tabelas próprias no esquema real atual.
    // O módulo mantém os contadores a zero até às respetivas migrações.
    if (table == 'maintenance_records' ||
        table == 'member_patch_awards' ||
        table == 'member_timeline') {
      return <Map<String, dynamic>>[];
    }

    final response = await _supabase
        .from(table)
        .select()
        .eq('member_id', memberId)
        .limit(250);
    return List<Map<String, dynamic>>.from(response);
  }

  Future<List<Map<String, dynamic>>> _listMembersFromSupabase() async {
    final response = await _supabase
        .from('members')
        .select()
        .eq('club_id', AppSession.instance.clubId)
        .limit(500);
    final members = List<Map<String, dynamic>>.from(response)
        .map(_normaliseMember)
        .toList();

    final motorcyclesResponse = await _supabase
        .from('member_motorcycles')
        .select()
        .eq('club_id', AppSession.instance.clubId)
        .eq('primary_motorcycle', true);
    final motorcycles = List<Map<String, dynamic>>.from(motorcyclesResponse);
    final byMember = <String, Map<String, dynamic>>{
      for (final motorcycle in motorcycles)
        if (motorcycle['member_id'] != null)
          motorcycle['member_id'].toString(): motorcycle,
    };

    return members
        .map((member) => _withPrimaryMotorcycle(
              member,
              [if (byMember[member['id']?.toString()] != null)
                byMember[member['id']?.toString()]!],
            ))
        .toList();
  }

  Map<String, dynamic> _normaliseMember(Map<String, dynamic> row) {
    final emergency = row['emergency_contact'];
    final emergencyMap = emergency is Map
        ? Map<String, dynamic>.from(emergency)
        : const <String, dynamic>{};

    return <String, dynamic>{
      ...row,
      'primary_role': row['primary_role'] ?? '',
      'additional_roles': row['additional_roles'] ?? '',
      'emergency_name': emergencyMap['name'] ?? emergencyMap['contact_name'],
      'emergency_relation': emergencyMap['relation'],
      'emergency_phone': emergencyMap['phone'],
      'blood_type': emergencyMap['blood_type'],
      'allergies': emergencyMap['allergies'],
      'medical_notes': emergencyMap['medical_notes'],
    };
  }

  Map<String, dynamic> _withPrimaryMotorcycle(
    Map<String, dynamic> member,
    List<Map<String, dynamic>> motorcycles,
  ) {
    if (motorcycles.isEmpty) return member;
    final motorcycle = motorcycles.first;
    return <String, dynamic>{
      ...member,
      'motorcycle_brand': motorcycle['brand'],
      'motorcycle_model': motorcycle['model'],
      'motorcycle_year': motorcycle['year'],
      'motorcycle_registration': motorcycle['registration'],
    };
  }

  Map<String, dynamic> _memberPayload(Map<String, dynamic> values) {
    final emergency = <String, dynamic>{
      'name': values['emergency_name'],
      'relation': values['emergency_relation'],
      'phone': values['emergency_phone'],
      'blood_type': values['blood_type'],
      'allergies': values['allergies'],
      'medical_notes': values['medical_notes'],
    }..removeWhere((_, value) => value == null || value.toString().trim().isEmpty);

    const allowed = <String>{
      'profile_id',
      'member_number',
      'full_name',
      'nickname',
      'email',
      'phone',
      'birth_date',
      'tax_number',
      'address',
      'joined_at',
      'status',
      'notes',
      'photo_path',
      'prospect_joined_at',
      'full_colors_at',
      'motorcycle',
      'registration',
    };

    final payload = <String, dynamic>{
      for (final entry in values.entries)
        if (allowed.contains(entry.key)) entry.key: _emptyToNull(entry.value),
      if (emergency.isNotEmpty) 'emergency_contact': emergency,
    };
    payload.removeWhere((key, _) => key == 'profile_id' && values[key] == null);
    return payload;
  }

  Object? _emptyToNull(Object? value) {
    if (value is String && value.trim().isEmpty) return null;
    return value;
  }
}
