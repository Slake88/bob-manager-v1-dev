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

  Future<List<Map<String,dynamic>>> movements({int limit=500}) async {
    _require(AppPermission.viewInventory);
    final response = await _client.from('stock_movements').select('id,kind,quantity,unit_cost,notes,created_at,products(name,category,inventory_area),product_variants(name,sku),events(name),profiles(full_name)').eq('club_id',_clubId).order('created_at',ascending:false).limit(limit);
    return List<Map<String,dynamic>>.from(response);
  }

  Future<List<Map<String,dynamic>>> locations() async {
    _require(AppPermission.viewInventory);
    final response = await _client.from('inventory_locations').select('id,name,active').eq('club_id',_clubId).eq('active',true).order('name');
    return List<Map<String,dynamic>>.from(response);
  }

  Future<List<Map<String,dynamic>>> events() async {
    _require(AppPermission.viewInventory);
    final response = await _client.from('events').select('id,name,starts_at').eq('club_id',_clubId).order('starts_at',ascending:false).limit(100);
    return List<Map<String,dynamic>>.from(response);
  }

  Future<List<Map<String,dynamic>>> countSessions() async {
    _require(AppPermission.viewInventory);
    final response = await _client.from('inventory_count_sessions').select('id,name,status,started_at,completed_at,notes,inventory_locations(name),events(name)').eq('club_id',_clubId).order('started_at',ascending:false).limit(100);
    return List<Map<String,dynamic>>.from(response);
  }

  Future<String> startCount({required String name,String? locationId,String? eventId,String notes=''}) async {
    _require(AppPermission.performInventoryCount);
    final result = await _client.rpc('inventory_count_start_v1',params:{'target_club':_clubId,'p_name':name,'p_location':locationId,'p_event':eventId,'p_notes':notes});
    return result.toString();
  }

  Future<List<Map<String,dynamic>>> countItems(String sessionId) async {
    _require(AppPermission.viewInventory);
    final response = await _client.from('inventory_count_items').select('id,product_id,variant_id,theoretical_qty,counted_qty,difference,unit_cost,notes,recounted,products(name,category,inventory_area,unit),product_variants(name,sku)').eq('session_id',sessionId).order('product_id');
    return List<Map<String,dynamic>>.from(response);
  }

  Future<void> setCount({required String itemId,required double counted,String notes='',bool recounted=false}) async {
    _require(AppPermission.performInventoryCount);
    await _client.rpc('inventory_count_set_qty_v1',params:{'target_club':_clubId,'p_item':itemId,'p_counted':counted,'p_notes':notes,'p_recounted':recounted});
  }

  Future<Map<String,dynamic>> finalize(String sessionId) async {
    _require(AppPermission.performInventoryCount);
    final result = await _client.rpc('inventory_count_finalize_v1',params:{'target_club':_clubId,'p_session':sessionId});
    return Map<String,dynamic>.from(result as Map);
  }
}
