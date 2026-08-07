import 'package:supabase_flutter/supabase_flutter.dart';

import '../core/app_session.dart';
import '../core/permissions.dart';

class BarRepository {
  SupabaseClient get _client => Supabase.instance.client;
  String get _clubId => AppSession.instance.clubId;

  void _require(AppPermission permission) {
    if (!AppSession.instance.can(permission)) {
      throw StateError('Sem permissão para executar esta operação.');
    }
  }

  Future<List<Map<String, dynamic>>> products() async {
    _require(AppPermission.viewInventory);
    final response = await _client
        .from('products')
        .select('id,name,sku,category,description,supplier,unit,cost,sale_price,minimum_stock,current_stock,purchase_unit,consumption_unit,units_per_purchase,purchase_cost,active')
        .eq('club_id', _clubId)
        .eq('inventory_area', 'bar')
        .eq('active', true)
        .order('name');
    return List<Map<String, dynamic>>.from(response);
  }

  Future<List<Map<String, dynamic>>> events() async {
    _require(AppPermission.viewInventory);
    final response = await _client
        .from('events')
        .select('id,name,starts_at,status')
        .eq('club_id', _clubId)
        .order('starts_at', ascending: false)
        .limit(50);
    return List<Map<String, dynamic>>.from(response);
  }

  Future<List<Map<String, dynamic>>> treasuryAccounts() async {
    _require(AppPermission.selectBarFinancialAccount);
    final response = await _client
        .from('treasury_accounts')
        .select('id,name,account_type,icon,allows_negative')
        .eq('club_id', _clubId)
        .eq('active', true)
        .order('name');
    return List<Map<String, dynamic>>.from(response);
  }

  Future<List<Map<String, dynamic>>> operations({int limit = 100}) async {
    _require(AppPermission.viewInventory);
    final response = await _client
        .from('bar_operations')
        .select(
          'id,operation_type,purchase_units,consumption_quantity,unit_price,total_amount,payment_method,notes,created_at,event_id,products(name,consumption_unit),events(name),treasury_transactions(account_id,source_account:treasury_accounts!treasury_transactions_account_id_fkey(name))',
        )
        .eq('club_id', _clubId)
        .order('created_at', ascending: false)
        .limit(limit);
    return List<Map<String, dynamic>>.from(response);
  }

  Future<Map<String, dynamic>> saveProduct({
    String? id,
    required String name,
    required String sku,
    required String category,
    required String description,
    required String supplier,
    required String purchaseUnit,
    required String consumptionUnit,
    required double unitsPerPurchase,
    required double purchaseCost,
    required double salePrice,
    required double minimumStock,
  }) async {
    _require(AppPermission.manageBar);
    if (name.trim().isEmpty) throw ArgumentError('Indica o nome do artigo.');
    if (unitsPerPurchase <= 0) {
      throw ArgumentError('A quantidade por embalagem de compra deve ser superior a zero.');
    }
    final unitCost = purchaseCost / unitsPerPurchase;
    final values = <String, dynamic>{
      'inventory_area': 'bar',
      'name': name.trim(),
      'sku': sku.trim().isEmpty ? null : sku.trim(),
      'category': category.trim().isEmpty ? 'Bebidas' : category.trim(),
      'description': description.trim().isEmpty ? null : description.trim(),
      'supplier': supplier.trim().isEmpty ? null : supplier.trim(),
      'unit': consumptionUnit.trim().isEmpty ? 'unidade' : consumptionUnit.trim(),
      'purchase_unit': purchaseUnit.trim().isEmpty ? 'unidade' : purchaseUnit.trim(),
      'consumption_unit': consumptionUnit.trim().isEmpty ? 'unidade' : consumptionUnit.trim(),
      'units_per_purchase': unitsPerPurchase,
      'purchase_cost': purchaseCost,
      'cost': unitCost,
      'sale_price': salePrice,
      'minimum_stock': minimumStock,
      'active': true,
    };
    if (id == null) {
      final response = await _client
          .from('products')
          .insert({...values, 'club_id': _clubId, 'current_stock': 0, 'reserved_stock': 0})
          .select()
          .single();
      return Map<String, dynamic>.from(response);
    }
    final response = await _client
        .from('products')
        .update(values)
        .eq('id', id)
        .eq('club_id', _clubId)
        .select()
        .single();
    return Map<String, dynamic>.from(response);
  }

  Future<void> purchase({
    required Map<String, dynamic> product,
    required double purchaseUnits,
    required double costPerPurchaseUnit,
    String? eventId,
    String? accountId,
    String paymentMethod = 'Dinheiro',
    String notes = '',
    bool postFinancial = true,
  }) async {
    _require(AppPermission.manageBar);
    final conversion = _double(product['units_per_purchase']);
    if (purchaseUnits <= 0 || conversion <= 0) {
      throw ArgumentError('Quantidade/conversão inválida.');
    }
    await _operate(
      productId: product['id'].toString(),
      operation: 'purchase',
      quantity: purchaseUnits * conversion,
      purchaseUnits: purchaseUnits,
      unitPrice: costPerPurchaseUnit,
      eventId: eventId,
      accountId: accountId,
      paymentMethod: paymentMethod,
      notes: notes,
      postFinancial: postFinancial,
    );
  }

  Future<void> consume({
    required String productId,
    required String operation,
    required double quantity,
    String? eventId,
    String? accountId,
    double? unitPrice,
    String? paymentMethod,
    String notes = '',
    bool postFinancial = false,
  }) async {
    _require(AppPermission.manageBar);
    if (!const ['sale', 'offer', 'internal', 'waste', 'adjustment_in', 'adjustment_out'].contains(operation)) {
      throw ArgumentError('Operação de Bar inválida.');
    }
    await _operate(
      productId: productId,
      operation: operation,
      quantity: quantity,
      eventId: eventId,
      accountId: accountId,
      unitPrice: unitPrice,
      paymentMethod: paymentMethod,
      notes: notes,
      postFinancial: postFinancial,
    );
  }

  Future<void> _operate({
    required String productId,
    required String operation,
    required double quantity,
    String? eventId,
    String? accountId,
    double? purchaseUnits,
    double? unitPrice,
    String? paymentMethod,
    String notes = '',
    required bool postFinancial,
  }) async {
    if (quantity <= 0) throw ArgumentError('A quantidade deve ser superior a zero.');
    if (accountId != null) _require(AppPermission.selectBarFinancialAccount);
    await _client.rpc('bar_operation_v2', params: {
      'target_club': _clubId,
      'p_product': productId,
      'p_operation': operation,
      'p_quantity': quantity,
      'p_event': eventId,
      'p_purchase_units': purchaseUnits,
      'p_unit_price': unitPrice,
      'p_payment_method': paymentMethod,
      'p_notes': notes.trim(),
      'p_post_financial': postFinancial,
      'p_account': accountId,
    });
  }
}

double _double(Object? value) {
  if (value is num) return value.toDouble();
  return double.tryParse(value?.toString().replaceAll(',', '.') ?? '') ?? 0;
}
