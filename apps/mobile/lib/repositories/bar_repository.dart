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
    _require(AppPermission.viewBar);
    final response = await _client
        .from('products')
        .select(
          'id,name,sku,category,description,supplier,unit,cost,sale_price,minimum_stock,current_stock,purchase_unit,consumption_unit,units_per_purchase,purchase_cost,active,'
          'bar_product_sale_options(id,name,stock_quantity,public_price,member_price,sort_order,active)',
        )
        .eq('club_id', _clubId)
        .eq('inventory_area', 'bar')
        .eq('active', true)
        .order('name');
    final rows = List<Map<String, dynamic>>.from(response);
    for (final row in rows) {
      final raw = row['bar_product_sale_options'];
      if (raw is List) {
        final options = raw
            .whereType<Map>()
            .map((value) => Map<String, dynamic>.from(value))
            .where((value) => value['active'] != false)
            .toList()
          ..sort((a, b) {
            final sortA = (a['sort_order'] as num?)?.toInt() ?? 0;
            final sortB = (b['sort_order'] as num?)?.toInt() ?? 0;
            final bySort = sortA.compareTo(sortB);
            if (bySort != 0) return bySort;
            return (a['name']?.toString() ?? '')
                .compareTo(b['name']?.toString() ?? '');
          });
        row['sale_options'] = options;
      } else {
        row['sale_options'] = <Map<String, dynamic>>[];
      }
    }
    return rows;
  }

  Future<List<Map<String, dynamic>>> events() async {
    _require(AppPermission.viewBar);
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
    _require(AppPermission.viewBar);
    final response = await _client
        .from('bar_operations')
        .select(
          'id,operation_type,purchase_units,consumption_quantity,unit_price,total_amount,payment_method,notes,created_at,created_by,event_id,sale_id,sale_option_name,customer_type,'
          'actor:profiles!bar_operations_created_by_fkey(full_name,email),'
          'products(name,consumption_unit),events(name),'
          'treasury_transactions(account_id,source_account:treasury_accounts!treasury_transactions_account_id_fkey(name))',
        )
        .eq('club_id', _clubId)
        .order('created_at', ascending: false)
        .limit(limit);
    final rows = List<Map<String, dynamic>>.from(response);
    for (final row in rows) {
      final actor = row['actor'];
      if (actor is Map) {
        final name = actor['full_name']?.toString().trim() ?? '';
        final email = actor['email']?.toString().trim() ?? '';
        row['actor_label'] = name.isNotEmpty ? name : email;
      }
    }
    return rows;
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
    double? salePrice,
    required double minimumStock,
    List<Map<String, dynamic>>? saleOptions,
  }) async {
    _require(AppPermission.manageBar);
    if (name.trim().isEmpty) throw ArgumentError('Indica o nome do artigo.');
    if (unitsPerPurchase <= 0) {
      throw ArgumentError(
        'A quantidade por embalagem de compra deve ser superior a zero.',
      );
    }
    final options = saleOptions == null || saleOptions.isEmpty
        ? <Map<String, dynamic>>[
            {
              'name': _defaultSaleOptionName(consumptionUnit),
              'stock_quantity': 1,
              'public_price': salePrice ?? 0,
              'member_price': salePrice ?? 0,
            },
          ]
        : saleOptions;
    for (final option in options) {
      if ((option['name']?.toString().trim() ?? '').isEmpty) {
        throw ArgumentError('Todas as formas de venda precisam de nome.');
      }
      if (_double(option['stock_quantity']) <= 0) {
        throw ArgumentError(
          'A quantidade de stock por forma de venda deve ser superior a zero.',
        );
      }
      if (_double(option['public_price']) < 0 ||
          _double(option['member_price']) < 0) {
        throw ArgumentError('Os preços não podem ser negativos.');
      }
    }

    final response = await _client.rpc(
      'save_bar_product_v3',
      params: {
        'target_club': _clubId,
        'p_product': id,
        'p_name': name.trim(),
        'p_sku': sku.trim(),
        'p_category': category.trim(),
        'p_description': description.trim(),
        'p_supplier': supplier.trim(),
        'p_purchase_unit': purchaseUnit.trim(),
        'p_consumption_unit': consumptionUnit.trim(),
        'p_units_per_purchase': unitsPerPurchase,
        'p_purchase_cost': purchaseCost,
        'p_minimum_stock': minimumStock,
        'p_sale_options': options,
      },
    );
    if (response is! Map || response['id'] == null) {
      throw StateError('Resposta inválida ao guardar o artigo do Bar.');
    }

    final productId = response['id'].toString();
    final saved = await _client
        .from('products')
        .select(
          'id,name,sku,category,description,supplier,unit,cost,sale_price,minimum_stock,current_stock,purchase_unit,consumption_unit,units_per_purchase,purchase_cost,active,'
          'bar_product_sale_options(id,name,stock_quantity,public_price,member_price,sort_order,active)',
        )
        .eq('club_id', _clubId)
        .eq('id', productId)
        .single();
    return Map<String, dynamic>.from(saved);
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
    if (!const [
      'sale',
      'offer',
      'internal',
      'waste',
      'adjustment_in',
      'adjustment_out',
    ].contains(operation)) {
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
    if (quantity <= 0) {
      throw ArgumentError('A quantidade deve ser superior a zero.');
    }
    if (accountId != null) _require(AppPermission.selectBarFinancialAccount);
    await _client.rpc(
      'bar_operation_v2',
      params: {
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
      },
    );
  }
}

String _defaultSaleOptionName(String consumptionUnit) {
  final value = consumptionUnit.trim();
  if (value.isEmpty ||
      value == '1' ||
      value.toLowerCase() == 'unidade' ||
      value.toLowerCase() == 'unit') {
    return 'Unidade';
  }
  return value;
}

double _double(Object? value) {
  if (value is num) return value.toDouble();
  return double.tryParse(value?.toString().replaceAll(',', '.') ?? '') ?? 0;
}
