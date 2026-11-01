import 'package:supabase_flutter/supabase_flutter.dart';

import '../core/module_definition.dart';
import '../core/module_order_policy.dart';

abstract interface class ModuleOrderStore {
  /// Returns null when this Auth user has no saved preference.
  Future<List<String>?> load();

  Future<void> save(List<String> order);

  Future<void> reset();
}

/// The user id is always taken from the active Auth session. Callers cannot
/// select or submit another user's id.
class SupabaseModuleOrderStore implements ModuleOrderStore {
  SupabaseModuleOrderStore({SupabaseClient? client})
      : _client = client ?? Supabase.instance.client;

  final SupabaseClient _client;

  static List<String> get canonicalCodes =>
      appModules.map((module) => module.code).toList(growable: false);

  String _requireUserId() {
    final userId = _client.auth.currentUser?.id;
    if (userId == null || userId.isEmpty) {
      throw StateError(
          'É necessária uma sessão autenticada para guardar o menu.');
    }
    return userId;
  }

  @override
  Future<List<String>?> load() async {
    final userId = _requireUserId();
    final row = await _client
        .from('user_module_preferences')
        .select('module_order')
        .eq('user_id', userId)
        .maybeSingle();
    if (row == null) return null;
    return normalizeModuleOrder(row['module_order'], canonicalCodes);
  }

  @override
  Future<void> save(List<String> order) async {
    final userId = _requireUserId();
    final normalized = normalizeModuleOrder(order, canonicalCodes);
    await _client.from('user_module_preferences').upsert(
      <String, Object?>{
        'user_id': userId,
        'module_order': normalized,
        'updated_at': DateTime.now().toUtc().toIso8601String(),
      },
      onConflict: 'user_id',
    );
  }

  @override
  Future<void> reset() async {
    final userId = _requireUserId();
    await _client
        .from('user_module_preferences')
        .delete()
        .eq('user_id', userId);
  }
}
