import 'package:supabase_flutter/supabase_flutter.dart';

import '../core/app_config.dart';
import '../core/app_session.dart';
import '../services/data_service.dart';

class InventoryFoundationRepository {
  InventoryFoundationRepository({DataService? dataService})
      : _dataService = dataService ?? DataService.instance;

  final DataService _dataService;
  SupabaseClient get _client => Supabase.instance.client;

  Future<Map<String, dynamic>> summary() async {
    if (AppConfig.demoMode) {
      final products = (await _dataService.list('products'))
          .where((row) => row['inventory_area'] != 'bar')
          .toList();
      return {
        'shop_products': products.length,
        'assets': 0,
        'low_stock': products.where((row) {
          final current = _asDouble(row['current_stock']);
          final minimum = _asDouble(row['minimum_stock']);
          return current <= minimum;
        }).length,
        'reserved_units': products.fold<double>(
          0,
          (total, row) => total + _asDouble(row['reserved_stock']),
        ),
        'stock_value': products.fold<double>(
          0,
          (total, row) =>
              total + _asDouble(row['current_stock']) * _asDouble(row['cost']),
        ),
        'asset_value': 0.0,
      };
    }

    final clubId = AppSession.instance.clubId;
    final productRows = List<Map<String, dynamic>>.from(
      await _client
          .from('products')
          .select('inventory_area,current_stock,reserved_stock,minimum_stock,cost')
          .eq('club_id', clubId)
          .eq('active', true)
          .neq('inventory_area', 'bar'),
    );
    final assetRows = List<Map<String, dynamic>>.from(
      await _client
          .from('inventory_assets')
          .select('acquisition_value,condition')
          .eq('club_id', clubId)
          .eq('active', true),
    );

    var lowStock = 0;
    var reservedUnits = 0.0;
    var stockValue = 0.0;
    for (final row in productRows) {
      final current = _asDouble(row['current_stock']);
      final minimum = _asDouble(row['minimum_stock']);
      if (current <= minimum) lowStock++;
      reservedUnits += _asDouble(row['reserved_stock']);
      stockValue += current * _asDouble(row['cost']);
    }

    return {
      'shop_products': productRows.length,
      'assets': assetRows.length,
      'low_stock': lowStock,
      'reserved_units': reservedUnits,
      'stock_value': stockValue,
      'asset_value': assetRows.fold<double>(
        0,
        (total, row) => total + _asDouble(row['acquisition_value']),
      ),
    };
  }
}

double _asDouble(Object? value) {
  if (value is num) return value.toDouble();
  return double.tryParse(value?.toString().replaceAll(',', '.') ?? '') ?? 0;
}
