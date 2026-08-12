import 'package:supabase_flutter/supabase_flutter.dart';

import '../core/app_session.dart';
import '../core/permissions.dart';

class InventoryControlRepository {
  SupabaseClient get _client => Supabase.instance.client;
  String get _clubId => AppSession.instance.clubId;

  void _require(AppPermission permission) {
    if (!AppSession.instance.can(permission)) {
      throw StateError('Sem permissão para executar esta operação.');
    }
  }

  Future<List<Map<String, dynamic>>> movements({int limit = 500}) async {
    _require(AppPermission.viewInventory);
    final response = await _client
        .from('stock_movements')
        .select(
          'id,kind,quantity,unit_cost,notes,created_at,'
          'products(name,category,inventory_area),'
          'product_variants(name,sku),events(name),profiles(full_name),'
          'from_location:inventory_locations!stock_movements_from_location_id_fkey(name),'
          'to_location:inventory_locations!stock_movements_to_location_id_fkey(name)',
        )
        .eq('club_id', _clubId)
        .order('created_at', ascending: false)
        .limit(limit);
    return List<Map<String, dynamic>>.from(response);
  }

  Future<List<Map<String, dynamic>>> locations() async {
    _require(AppPermission.viewInventory);
    final response = await _client
        .from('inventory_locations')
        .select('id,name,description,location_type,event_id,parent_id,active')
        .eq('club_id', _clubId)
        .eq('active', true)
        .order('name');
    return List<Map<String, dynamic>>.from(response);
  }

  Future<List<Map<String, dynamic>>> stockByLocation() async {
    _require(AppPermission.viewInventory);
    final response = await _client.rpc(
      'inventory_stock_by_location_v1',
      params: {'target_club': _clubId},
    );
    return List<Map<String, dynamic>>.from(response as List);
  }

  Future<Map<String, dynamic>> transferStock({
    required String productId,
    String? variantId,
    required String fromLocationId,
    required String toLocationId,
    required double quantity,
    String notes = '',
  }) async {
    _require(AppPermission.manageInventory);
    final result = await _client.rpc(
      'inventory_transfer_v1',
      params: {
        'target_club': _clubId,
        'p_product': productId,
        'p_variant': variantId,
        'p_from_location': fromLocationId,
        'p_to_location': toLocationId,
        'p_quantity': quantity,
        'p_notes': notes.trim(),
      },
    );
    return Map<String, dynamic>.from(result as Map);
  }

  Future<List<Map<String, dynamic>>> events() async {
    _require(AppPermission.viewInventory);
    final response = await _client
        .from('events')
        .select('id,name,starts_at')
        .eq('club_id', _clubId)
        .order('starts_at', ascending: false)
        .limit(100);
    return List<Map<String, dynamic>>.from(response);
  }

  Future<List<Map<String, dynamic>>> countSessions() async {
    _require(AppPermission.viewInventory);
    final response = await _client
        .from('inventory_count_sessions')
        .select(
          'id,name,status,started_at,completed_at,notes,'
          'inventory_locations(name,location_type),events(name)',
        )
        .eq('club_id', _clubId)
        .order('started_at', ascending: false)
        .limit(100);
    return List<Map<String, dynamic>>.from(response);
  }

  Future<String> startCount({
    required String name,
    String? locationId,
    String? eventId,
    String notes = '',
  }) async {
    _require(AppPermission.performInventoryCount);
    final result = await _client.rpc(
      'inventory_count_start_v1',
      params: {
        'target_club': _clubId,
        'p_name': name,
        'p_location': locationId,
        'p_event': eventId,
        'p_notes': notes,
      },
    );
    return result.toString();
  }

  Future<List<Map<String, dynamic>>> countItems(String sessionId) async {
    _require(AppPermission.viewInventory);
    final response = await _client
        .from('inventory_count_items')
        .select(
          'id,product_id,variant_id,theoretical_qty,counted_qty,difference,'
          'unit_cost,notes,recounted,products(name,category,inventory_area,unit),'
          'product_variants(name,sku)',
        )
        .eq('session_id', sessionId)
        .order('product_id');
    return List<Map<String, dynamic>>.from(response);
  }

  Future<void> setCount({
    required String itemId,
    required double counted,
    String notes = '',
    bool recounted = false,
  }) async {
    _require(AppPermission.performInventoryCount);
    await _client.rpc(
      'inventory_count_set_qty_v1',
      params: {
        'target_club': _clubId,
        'p_item': itemId,
        'p_counted': counted,
        'p_notes': notes,
        'p_recounted': recounted,
      },
    );
  }

  Future<Map<String, dynamic>> finalize(String sessionId) async {
    _require(AppPermission.performInventoryCount);
    final result = await _client.rpc(
      'inventory_count_finalize_v1',
      params: {'target_club': _clubId, 'p_session': sessionId},
    );
    return Map<String, dynamic>.from(result as Map);
  }
}
