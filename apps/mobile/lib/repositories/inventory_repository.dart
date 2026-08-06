import '../core/app_role.dart';
import '../core/app_session.dart';
import '../core/permissions.dart';
import '../services/data_service.dart';

class InventoryRepository {
  InventoryRepository({DataService? dataService})
      : _dataService = dataService ?? DataService.instance;

  final DataService _dataService;

  AppRole get currentRole => AppRole.fromValue(AppSession.instance.role);

  Future<List<Map<String, dynamic>>> listProducts() async {
    _require(AppPermission.viewInventory);
    final rows = await _dataService.list('products');
    rows.sort((a, b) => (a['name']?.toString() ?? '')
        .compareTo(b['name']?.toString() ?? ''));
    return rows;
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
  }) {
    _require(AppPermission.manageInventory);
    final normalized = <String, dynamic>{
      ...values,
      'current_stock': _asDouble(values['current_stock']),
      'reserved_stock': _asDouble(values['reserved_stock']),
      'minimum_stock': _asDouble(values['minimum_stock']),
      'cost': _asDouble(values['cost']),
      'sale_price': _asDouble(values['sale_price']),
      'active': values['active'] ?? true,
    };
    if (productId == null) {
      return _dataService.insert('products', normalized);
    }
    return _dataService.update('products', productId, normalized);
  }

  Future<void> adjustStock({
    required String productId,
    required double quantity,
    required String reason,
  }) async {
    _require(AppPermission.manageInventory);
    if (quantity == 0) throw ArgumentError('A quantidade não pode ser zero.');

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
  }

  Future<void> reserveStock({
    required String productId,
    required double quantity,
    required String description,
  }) async {
    _require(AppPermission.manageInventory);
    if (quantity <= 0) throw ArgumentError('A quantidade deve ser positiva.');

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
  }

  Future<Map<String, dynamic>> _product(String productId) async {
    final product = await _dataService.getById('products', productId);
    if (product == null) throw StateError('Artigo não encontrado.');
    return product;
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
