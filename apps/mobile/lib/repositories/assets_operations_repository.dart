import 'package:supabase_flutter/supabase_flutter.dart';

import '../core/app_session.dart';
import '../core/permissions.dart';

class AssetsOperationsRepository {
  SupabaseClient get _client => Supabase.instance.client;
  String get _clubId => AppSession.instance.clubId;

  void _require(AppPermission permission) {
    if (!AppSession.instance.can(permission)) {
      throw StateError('Sem permissão para executar esta operação.');
    }
  }

  Future<List<Map<String, dynamic>>> assets() async {
    _require(AppPermission.viewInventory);
    final response = await _client
        .from('inventory_assets')
        .select('id,asset_number,qr_code,name,category,condition,requires_inspection,next_inspection_at,inventory_locations(name)')
        .eq('club_id', _clubId)
        .eq('active', true)
        .neq('condition', 'retired')
        .order('asset_number');
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

  Future<List<Map<String, dynamic>>> activeLoans() async {
    _require(AppPermission.viewInventory);
    final response = await _client
        .from('asset_loans')
        .select('id,asset_id,borrower_type,external_name,loaned_at,expected_return_at,notes,inventory_assets(asset_number,name),members(full_name,nickname),events(name)')
        .eq('club_id', _clubId)
        .isFilter('returned_at', null)
        .order('loaned_at', ascending: false);
    return List<Map<String, dynamic>>.from(response);
  }

  Future<List<Map<String, dynamic>>> maintenanceHistory({int limit = 100}) async {
    _require(AppPermission.viewInventory);
    final response = await _client
        .from('asset_maintenance')
        .select('id,asset_id,maintenance_date,maintenance_type,description,cost,supplier,next_due_date,payment_method,inventory_assets(asset_number,name),treasury_accounts(name)')
        .eq('club_id', _clubId)
        .order('maintenance_date', ascending: false)
        .limit(limit);
    return List<Map<String, dynamic>>.from(response);
  }

  Future<List<Map<String, dynamic>>> kits() async {
    _require(AppPermission.viewInventory);
    final response = await _client
        .from('asset_kits')
        .select('id,name,description,active,asset_kit_items(asset_id,quantity,inventory_assets(asset_number,name,condition))')
        .eq('club_id', _clubId)
        .eq('active', true)
        .order('name');
    return List<Map<String, dynamic>>.from(response);
  }

  Future<void> loan({
    required String assetId,
    required String borrowerType,
    String? memberId,
    String? eventId,
    String? externalName,
    DateTime? expectedReturn,
    String notes = '',
  }) async {
    _require(AppPermission.manageAssets);
    await _client.rpc('asset_loan_v1', params: {
      'target_club': _clubId,
      'p_asset': assetId,
      'p_borrower_type': borrowerType,
      'p_member': memberId,
      'p_event': eventId,
      'p_external_name': externalName,
      'p_expected_return': expectedReturn?.toIso8601String(),
      'p_notes': notes,
    });
  }

  Future<void> returnLoan({
    required String loanId,
    required String condition,
    String notes = '',
  }) async {
    _require(AppPermission.manageAssets);
    await _client.rpc('asset_return_v1', params: {
      'target_club': _clubId,
      'p_loan': loanId,
      'p_condition': condition,
      'p_notes': notes,
    });
  }

  Future<void> maintenance({
    required String assetId,
    required String type,
    required DateTime date,
    required String description,
    required double cost,
    required String supplier,
    DateTime? nextDue,
    String? accountId,
    String paymentMethod = 'Dinheiro',
    bool postFinancial = false,
  }) async {
    _require(AppPermission.manageAssets);
    await _client.rpc('asset_maintenance_v1', params: {
      'target_club': _clubId,
      'p_asset': assetId,
      'p_type': type,
      'p_date': date.toIso8601String().split('T').first,
      'p_description': description,
      'p_cost': cost,
      'p_supplier': supplier,
      'p_next_due': nextDue?.toIso8601String().split('T').first,
      'p_account': accountId,
      'p_payment_method': paymentMethod,
      'p_post_financial': postFinancial,
    });
  }

  Future<void> saveKit({
    String? id,
    required String name,
    required String description,
    required List<String> assetIds,
  }) async {
    _require(AppPermission.manageAssets);
    final clean = name.trim();
    if (clean.isEmpty) throw ArgumentError('Indica o nome do Kit.');
    String kitId;
    if (id == null) {
      final response = await _client
          .from('asset_kits')
          .insert({
            'club_id': _clubId,
            'name': clean,
            'description': description.trim().isEmpty ? null : description.trim(),
            'active': true,
            'created_by': AppSession.instance.profileId,
          })
          .select('id')
          .single();
      kitId = response['id'].toString();
    } else {
      kitId = id;
      await _client
          .from('asset_kits')
          .update({
            'name': clean,
            'description': description.trim().isEmpty ? null : description.trim(),
          })
          .eq('id', id)
          .eq('club_id', _clubId);
      await _client.from('asset_kit_items').delete().eq('kit_id', id);
    }
    if (assetIds.isNotEmpty) {
      await _client.from('asset_kit_items').insert([
        for (final assetId in assetIds)
          {'kit_id': kitId, 'asset_id': assetId, 'quantity': 1},
      ]);
    }
  }
}
