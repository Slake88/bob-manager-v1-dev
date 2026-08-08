import 'package:supabase_flutter/supabase_flutter.dart';

import '../core/app_session.dart';
import '../core/permissions.dart';

class AssetsQrRepository {
  SupabaseClient get _client => Supabase.instance.client;
  String get _clubId => AppSession.instance.clubId;

  void _require(AppPermission permission) {
    if (!AppSession.instance.can(permission)) {
      throw StateError('Sem permissão para executar esta operação.');
    }
  }

  Future<Map<String, dynamic>?> findByQr(String rawCode) async {
    _require(AppPermission.viewInventory);
    final code = _normalise(rawCode);
    if (code.isEmpty) return null;
    final response = await _client
        .from('inventory_assets')
        .select('id,asset_number,qr_code,name,category,description,brand,model,serial_number,condition,location_id,responsible_member_id,photo_path,requires_inspection,next_inspection_at,current_value,inventory_locations(name),members(full_name,nickname)')
        .eq('club_id', _clubId)
        .eq('qr_code', code)
        .eq('active', true)
        .maybeSingle();
    return response == null ? null : Map<String, dynamic>.from(response);
  }

  Future<Map<String, dynamic>?> activeLoan(String assetId) async {
    _require(AppPermission.viewInventory);
    final response = await _client
        .from('asset_loans')
        .select('id,asset_id,borrower_type,external_name,loaned_at,expected_return_at,notes,members(full_name,nickname),events(name)')
        .eq('club_id', _clubId)
        .eq('asset_id', assetId)
        .isFilter('returned_at', null)
        .order('loaned_at', ascending: false)
        .limit(1)
        .maybeSingle();
    return response == null ? null : Map<String, dynamic>.from(response);
  }

  Future<List<Map<String, dynamic>>> timeline(String assetId) async {
    _require(AppPermission.viewInventory);
    final response = await _client
        .from('asset_events')
        .select('id,event_type,title,description,metadata,created_at')
        .eq('club_id', _clubId)
        .eq('asset_id', assetId)
        .order('created_at', ascending: false)
        .limit(100);
    return List<Map<String, dynamic>>.from(response);
  }

  Future<List<Map<String, dynamic>>> members() async {
    _require(AppPermission.viewInventory);
    final response = await _client
        .from('members')
        .select('id,full_name,nickname,status')
        .eq('club_id', _clubId)
        .order('full_name');
    return List<Map<String, dynamic>>.from(response);
  }

  Future<List<Map<String, dynamic>>> events() async {
    _require(AppPermission.viewInventory);
    final response = await _client
        .from('events')
        .select('id,name,starts_at,status')
        .eq('club_id', _clubId)
        .order('starts_at', ascending: false)
        .limit(100);
    return List<Map<String, dynamic>>.from(response);
  }

  Future<List<Map<String, dynamic>>> accounts() async {
    _require(AppPermission.manageAssets);
    final response = await _client
        .from('treasury_accounts')
        .select('id,name,active')
        .eq('club_id', _clubId)
        .eq('active', true)
        .order('name');
    return List<Map<String, dynamic>>.from(response);
  }

  String _normalise(String value) {
    var clean = value.trim();
    if (clean.startsWith('BOB-ASSET:')) clean = clean.substring(10).trim();
    return clean.toUpperCase();
  }
}
