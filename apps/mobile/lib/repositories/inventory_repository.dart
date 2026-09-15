import 'package:supabase_flutter/supabase_flutter.dart';

import '../core/app_config.dart';
import '../core/app_role.dart';
import '../core/app_session.dart';
import '../core/permissions.dart';
import '../services/data_service.dart';

class InventoryRepository {
  InventoryRepository({DataService? dataService})
      : _dataService = dataService ?? DataService.instance;

  final DataService _dataService;

  AppRole get currentRole => AppRole.fromValue(AppSession.instance.role);
  SupabaseClient get _client => Supabase.instance.client;

  Future<List<Map<String, dynamic>>> listProducts() async {
    _require(AppPermission.viewInventory);
    if (AppConfig.demoMode) {
      final rows = await _dataService.list('products');
      rows.sort((a, b) => (a['name']?.toString() ?? '')
          .compareTo(b['name']?.toString() ?? ''));
      return rows;
    }

    final response = await _client
        .from('products')
        .select()
        .eq('club_id', AppSession.instance.clubId)
        .order('name');
    return List<Map<String, dynamic>>.from(response);
  }

  Future<Map<String, dynamic>> summary() async {
    final products = await listProducts();
    var stockValue = 0.0;
    var saleValue = 0.0;
    var lowStock = 0;
    var availableUnits = 0.0;

    for (final product in products) {
      final current = _asDouble(product['current_stock']);
      final reserved = _asDouble(product['reserved_stock']);
      final minimum = _asDouble(product['minimum_stock']);
      final available = current - reserved;
      stockValue += current * _asDouble(product['cost']);
      saleValue += current * _asDouble(product['sale_price']);
      availableUnits += available;
      if (current <= minimum) lowStock++;
    }

    return {
      'products': products,
      'product_count': products.length,
      'available_units': availableUnits,
      'stock_value': stockValue,
      'sale_value': saleValue,
      'low_stock': lowStock,
    };
  }

  Future<Map<String, dynamic>> saveProduct(
    Map<String, dynamic> values, {
    String? productId,
  }) async {
    _require(AppPermission.manageInventory);
    final normalized = <String, dynamic>{
      'name': values['name'],
      'sku': values['sku'],
      'category': values['category'],
      'unit': values['unit'] ?? 'unit',
      'current_stock': _asDouble(values['current_stock']),
      'reserved_stock': _asDouble(values['reserved_stock']),
      'minimum_stock': _asDouble(values['minimum_stock']),
      'cost': _asDouble(values['cost']),
      'sale_price': _asDouble(values['sale_price']),
      'active': values['active'] ?? true,
    };

    if (AppConfig.demoMode) {
      if (productId == null) {
        return _dataService.insert('products', normalized);
      }
      return _dataService.update('products', productId, normalized);
    }

    if (productId == null) {
      final response = await _client
          .from('products')
          .insert({...normalized, 'club_id': AppSession.instance.clubId})
          .select()
          .single();
      return Map<String, dynamic>.from(response);
    }

    final response = await _client
        .from('products')
        .update(normalized)
        .eq('id', productId)
        .eq('club_id', AppSession.instance.clubId)
        .select()
        .single();
    return Map<String, dynamic>.from(response);
  }

  Future<void> adjustStock({
    required String productId,
    required double quantity,
    required String reason,
  }) async {
    _require(AppPermission.manageInventory);
    if (quantity == 0) throw ArgumentError('A quantidade não pode ser zero.');

    if (AppConfig.demoMode) {
      final product = await _product(productId);
      final current = _asDouble(product['current_stock']);
      final reserved = _asDouble(product['reserved_stock']);
      final updated = current + quantity;
      if (updated < reserved || updated < 0) {
        throw StateError('O stock não pode ficar abaixo do stock reservado.');
      }
      await _dataService.update('products', productId, {
        'current_stock': updated,
      });
      await _movement(
        product: product,
        type: quantity > 0 ? 'entry' : 'adjustment',
        quantity: quantity,
        unitPrice: _asDouble(product['cost']),
        description: reason.trim().isEmpty ? 'Ajuste de stock' : reason.trim(),
      );
      return;
    }

    await _inventoryOperation(
      productId: productId,
      operation: quantity > 0 ? 'adjustment_in' : 'adjustment_out',
      quantity: quantity.abs(),
      description: reason,
    );
  }

  Future<void> reserveStock({
    required String productId,
    required double quantity,
    required String description,
  }) async {
    _require(AppPermission.manageInventory);
    if (quantity <= 0) throw ArgumentError('A quantidade deve ser positiva.');

    if (AppConfig.demoMode) {
      final product = await _product(productId);
      final current = _asDouble(product['current_stock']);
      final reserved = _asDouble(product['reserved_stock']);
      if (current - reserved < quantity) {
        throw StateError('Stock disponível insuficiente para a reserva.');
      }
      await _dataService.update('products', productId, {
        'reserved_stock': reserved + quantity,
      });
      await _movement(
        product: product,
        type: 'reservation',
        quantity: quantity,
        unitPrice: 0,
        description: description.trim().isEmpty
            ? 'Reserva de stock'
            : description.trim(),
      );
      return;
    }

    await _inventoryOperation(
      productId: productId,
      operation: 'reserve',
      quantity: quantity,
      unitPrice: 0,
      description: description,
    );
  }

  Future<void> recordSale({
    required String productId,
    required double quantity,
    double? unitPrice,
    String paymentMethod = 'Dinheiro',
    String description = '',
  }) async {
    _require(AppPermission.sellInventory);
    if (quantity <= 0) throw ArgumentError('A quantidade deve ser positiva.');

    if (AppConfig.demoMode) {
      final product = await _product(productId);
      final current = _asDouble(product['current_stock']);
      final reserved = _asDouble(product['reserved_stock']);
      if (current - reserved < quantity) {
        throw StateError('Stock disponível insuficiente para a venda.');
      }
      final price = unitPrice ?? _asDouble(product['sale_price']);
      if (price < 0) throw ArgumentError('O preço não pode ser negativo.');
      final total = quantity * price;
      await _dataService.update('products', productId, {
        'current_stock': current - quantity,
      });
      await _movement(
        product: product,
        type: 'sale',
        quantity: -quantity,
        unitPrice: price,
        description: description.trim().isEmpty
            ? 'Venda ${product['name']}'
            : description.trim(),
      );
      await _dataService.insert('financial_transactions', {
        'transaction_date': DateTime.now().toIso8601String().split('T').first,
        'kind': 'income',
        'status': 'confirmed',
        'description': description.trim().isEmpty
            ? 'Venda ${product['name']}'
            : description.trim(),
        'amount': total,
        'account_id': 'acc-clubhouse',
        'account_name': 'Club House',
        'cost_center_name': 'Club House',
        'payment_method': paymentMethod,
        'product_id': productId,
        'created_by': AppSession.instance.profileId,
      });
      return;
    }

    await _inventoryOperation(
      productId: productId,
      operation: 'sale',
      quantity: quantity,
      unitPrice: unitPrice,
      description: description,
      paymentMethod: paymentMethod,
    );
  }

  Future<List<Map<String, dynamic>>> listMovements({int limit = 100}) async {
    _require(AppPermission.viewInventory);
    if (AppConfig.demoMode) {
      final rows = await _dataService.list('inventory_movements');
      rows.sort((a, b) => (b['movement_date']?.toString() ?? '')
          .compareTo(a['movement_date']?.toString() ?? ''));
      return rows.take(limit).toList();
    }

    final response = await _client
        .from('stock_movements')
        .select('id,product_id,kind,quantity,unit_cost,notes,created_at,products(name)')
        .eq('club_id', AppSession.instance.clubId)
        .order('created_at', ascending: false)
        .limit(limit);
    return List<Map<String, dynamic>>.from(response).map((row) {
      final product = row['products'];
      return <String, dynamic>{
        ...row,
        'product_name': product is Map ? product['name'] : null,
        'movement_type': row['kind'],
        'movement_date': row['created_at'],
        'unit_price': row['unit_cost'],
        'description': row['notes'],
      };
    }).toList();
  }

  Future<Map<String, dynamic>> _product(String productId) async {
    if (AppConfig.demoMode) {
      final product = await _dataService.getById('products', productId);
      if (product == null) throw StateError('Artigo não encontrado.');
      return product;
    }

    final response = await _client
        .from('products')
        .select()
        .eq('id', productId)
        .eq('club_id', AppSession.instance.clubId)
        .maybeSingle();
    if (response == null) throw StateError('Artigo não encontrado.');
    return Map<String, dynamic>.from(response);
  }

  Future<void> _inventoryOperation({
    required String productId,
    required String operation,
    required double quantity,
    double? unitPrice,
    String description = '',
    String? paymentMethod,
  }) async {
    await _client.rpc('inventory_operation_v1', params: {
      'target_club': AppSession.instance.clubId,
      'p_product': productId,
      'p_operation': operation,
      'p_quantity': quantity,
      'p_unit_price': unitPrice,
      'p_description': description.trim(),
      'p_payment_method': paymentMethod,
    });
  }

  Future<void> _movement({
    required Map<String, dynamic> product,
    required String type,
    required double quantity,
    required double unitPrice,
    required String description,
  }) async {
    await _dataService.insert('inventory_movements', {
      'movement_date': DateTime.now().toIso8601String(),
      'product_id': product['id'],
      'product_name': product['name'],
      'movement_type': type,
      'quantity': quantity,
      'unit_price': unitPrice,
      'total': quantity.abs() * unitPrice,
      'description': description,
      'created_by': AppSession.instance.profileId,
    });
  }

  void _require(AppPermission permission) {
    if (!PermissionPolicy.allows(currentRole, permission)) {
      throw StateError('Sem permissão para executar esta operação.');
    }
  }
}

double _asDouble(Object? value) {
  if (value is num) return value.toDouble();
  return double.tryParse(value?.toString().replaceAll(',', '.') ?? '') ?? 0;
}
