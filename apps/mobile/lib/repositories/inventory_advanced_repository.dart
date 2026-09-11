import 'package:supabase_flutter/supabase_flutter.dart';

import '../core/app_config.dart';
import '../core/app_session.dart';
import '../core/permissions.dart';

class InventoryAdvancedRepository {
  InventoryAdvancedRepository({SupabaseClient? client}) : _client = client;

  final SupabaseClient? _client;
  SupabaseClient get _supabase => _client ?? Supabase.instance.client;

  bool get isDemo => AppConfig.demoMode;
  bool get canView => AppSession.instance.can(AppPermission.viewInventory);
  bool get canManage => AppSession.instance.can(AppPermission.manageInventory);

  final List<Map<String, dynamic>> _demoReservations = <Map<String, dynamic>>[];
  final List<Map<String, dynamic>> _demoLots = <Map<String, dynamic>>[];
  final List<Map<String, dynamic>> _demoBreakages = <Map<String, dynamic>>[];

  Future<Map<String, dynamic>> summary() async {
    _requireView();
    if (isDemo) {
      final now = DateTime.now();
      final active = _demoReservations.where((row) => row['status'] == 'active').toList();
      return <String, dynamic>{
        'active_reservations': active.length,
        'reservations_expiring_soon': active.where((row) {
          final expiry = DateTime.tryParse(row['expires_at']?.toString() ?? '');
          return expiry != null && expiry.difference(now).inDays <= 3;
        }).length,
        'lots_expiring_30d': _demoLots.where((row) {
          final expiry = DateTime.tryParse(row['expires_at']?.toString() ?? '');
          return row['status'] == 'active' &&
              expiry != null &&
              expiry.difference(now).inDays <= 30;
        }).length,
        'expired_lots': _demoLots.where((row) => row['status'] == 'expired').length,
        'breakage_units_month': _demoBreakages.fold<double>(
          0,
          (total, row) => total + inventoryQuantity(row['quantity']),
        ),
        'can_manage': canManage,
      };
    }
    final response = await _supabase.rpc(
      'inventory_advanced_summary_v1',
      params: {'target_club': AppSession.instance.clubId},
    );
    return Map<String, dynamic>.from(response as Map);
  }

  Future<List<Map<String, dynamic>>> stockRows() async {
    _requireView();
    if (isDemo) {
      return <Map<String, dynamic>>[
        {
          'location_id': 'loc-main',
          'location_name': 'Armazém principal',
          'location_type': 'warehouse',
          'product_id': 'product-shirt',
          'product_name': 'T-shirt Blue On Black',
          'variant_id': 'variant-l',
          'variant_name': 'L',
          'sku': 'BOB-TS-L',
          'inventory_area': 'shop',
          'unit': 'un',
          'quantity': 24,
          'reserved_quantity': 2,
          'available_quantity': 22,
        },
        {
          'location_id': 'loc-main',
          'location_name': 'Armazém principal',
          'location_type': 'warehouse',
          'product_id': 'product-water',
          'product_name': 'Água 0,5 L',
          'variant_id': null,
          'variant_name': null,
          'sku': 'BAR-AGUA',
          'inventory_area': 'bar',
          'unit': 'un',
          'quantity': 80,
          'reserved_quantity': 0,
          'available_quantity': 80,
        },
      ];
    }
    final response = await _supabase.rpc(
      'inventory_stock_by_location_v1',
      params: {'target_club': AppSession.instance.clubId},
    );
    return List<Map<String, dynamic>>.from(response as List);
  }

  Future<List<Map<String, dynamic>>> catalogItems() async {
    _requireView();
    if (isDemo) {
      return <Map<String, dynamic>>[
        {
          'product_id': 'product-shirt',
          'product_name': 'T-shirt Blue On Black',
          'variant_id': 'variant-l',
          'variant_name': 'L',
          'sku': 'BOB-TS-L',
        },
        {
          'product_id': 'product-water',
          'product_name': 'Água 0,5 L',
          'variant_id': null,
          'variant_name': null,
          'sku': 'BAR-AGUA',
        },
      ];
    }
    final response = await _supabase
        .from('products')
        .select('id,name,sku,active,product_variants(id,name,sku,active)')
        .eq('club_id', AppSession.instance.clubId)
        .eq('active', true)
        .order('name');
    final flattened = <Map<String, dynamic>>[];
    for (final raw in response) {
      final product = Map<String, dynamic>.from(raw);
      final variants = (product['product_variants'] as List?) ?? const [];
      final activeVariants = variants
          .map((value) => Map<String, dynamic>.from(value as Map))
          .where((row) => row['active'] != false)
          .toList();
      if (activeVariants.isEmpty) {
        flattened.add({
          'product_id': product['id'],
          'product_name': product['name'],
          'variant_id': null,
          'variant_name': null,
          'sku': product['sku'],
        });
      } else {
        for (final variant in activeVariants) {
          flattened.add({
            'product_id': product['id'],
            'product_name': product['name'],
            'variant_id': variant['id'],
            'variant_name': variant['name'],
            'sku': variant['sku'] ?? product['sku'],
          });
        }
      }
    }
    return flattened;
  }

  Future<List<Map<String, dynamic>>> locations() async {
    _requireView();
    if (isDemo) {
      return <Map<String, dynamic>>[
        {'id': 'loc-main', 'name': 'Armazém principal', 'location_type': 'warehouse'},
        {'id': 'loc-club', 'name': 'Club House', 'location_type': 'clubhouse'},
      ];
    }
    final response = await _supabase
        .from('inventory_locations')
        .select('id,name,location_type')
        .eq('club_id', AppSession.instance.clubId)
        .eq('active', true)
        .order('name');
    return List<Map<String, dynamic>>.from(response);
  }

  Future<List<Map<String, dynamic>>> reservations() async {
    _requireView();
    if (isDemo) return _demoReservations.map(Map<String, dynamic>.from).toList();
    final response = await _supabase.rpc(
      'inventory_reservations_v1',
      params: {'target_club': AppSession.instance.clubId},
    );
    return List<Map<String, dynamic>>.from(response as List);
  }

  Future<String> createReservation({
    required String productId,
    String? variantId,
    required String locationId,
    required double quantity,
    String notes = '',
  }) async {
    _requireView();
    if (quantity <= 0) throw ArgumentError('A quantidade deve ser superior a zero.');
    if (isDemo) {
      final id = 'demo-reservation-${DateTime.now().microsecondsSinceEpoch}';
      final stock = (await stockRows()).firstWhere(
        (row) =>
            row['product_id'] == productId &&
            row['variant_id'] == variantId &&
            row['location_id'] == locationId,
      );
      if (inventoryQuantity(stock['available_quantity']) < quantity) {
        throw StateError('Stock disponível insuficiente para a reserva.');
      }
      final now = DateTime.now();
      _demoReservations.insert(0, {
        'id': id,
        'product_id': productId,
        'product_name': stock['product_name'],
        'variant_id': variantId,
        'variant_name': stock['variant_name'],
        'location_id': locationId,
        'location_name': stock['location_name'],
        'member_id': 'demo-member',
        'member_name': AppSession.instance.fullName,
        'quantity': quantity,
        'status': 'active',
        'reserved_at': now.toIso8601String(),
        'expires_at': now.add(const Duration(days: 30)).toIso8601String(),
        'days_remaining': 30,
        'notes': notes.trim(),
        'can_cancel': true,
      });
      return id;
    }
    final response = await _supabase.rpc(
      'inventory_reservation_create_v1',
      params: {
        'target_club': AppSession.instance.clubId,
        'p_product': productId,
        'p_variant': variantId,
        'p_location': locationId,
        'p_quantity': quantity,
        'p_member': null,
        'p_notes': _nullable(notes),
      },
    );
    return response.toString();
  }

  Future<void> closeReservation(
    String reservationId, {
    required String action,
    String reason = '',
  }) async {
    _requireView();
    if (action != 'cancel' && action != 'release') {
      throw ArgumentError('Ação de reserva inválida.');
    }
    if (action == 'release' && !canManage) {
      throw StateError('Sem permissão para libertar reservas.');
    }
    if (isDemo) {
      final index = _demoReservations.indexWhere((row) => row['id'] == reservationId);
      if (index < 0 || _demoReservations[index]['status'] != 'active') {
        throw StateError('Reserva não encontrada ou já encerrada.');
      }
      _demoReservations[index] = {
        ..._demoReservations[index],
        'status': action == 'cancel' ? 'cancelled' : 'released',
        'released_at': DateTime.now().toIso8601String(),
        'release_reason': reason.trim(),
      };
      return;
    }
    await _supabase.rpc(
      'inventory_reservation_close_v1',
      params: {
        'target_club': AppSession.instance.clubId,
        'p_reservation': reservationId,
        'p_action': action,
        'p_reason': _nullable(reason),
      },
    );
  }

  Future<List<Map<String, dynamic>>> lots() async {
    _requireManage();
    if (isDemo) return _demoLots.map(Map<String, dynamic>.from).toList();
    final response = await _supabase.rpc(
      'inventory_lots_v1',
      params: {'target_club': AppSession.instance.clubId},
    );
    return List<Map<String, dynamic>>.from(response as List);
  }

  Future<String> receiveLot({
    required String productId,
    String? variantId,
    required String locationId,
    required String lotCode,
    required double quantity,
    DateTime? receivedAt,
    DateTime? expiresAt,
    double? unitCost,
    String supplier = '',
    String notes = '',
  }) async {
    _requireManage();
    if (lotCode.trim().isEmpty) throw ArgumentError('Indica o código do lote.');
    if (quantity <= 0) throw ArgumentError('A quantidade deve ser superior a zero.');
    if (isDemo) {
      final catalog = (await catalogItems()).firstWhere(
        (row) => row['product_id'] == productId && row['variant_id'] == variantId,
      );
      final location = (await locations()).firstWhere((row) => row['id'] == locationId);
      final id = 'demo-lot-${DateTime.now().microsecondsSinceEpoch}';
      final expiry = expiresAt;
      _demoLots.insert(0, {
        'id': id,
        'product_id': productId,
        'product_name': catalog['product_name'],
        'variant_id': variantId,
        'variant_name': catalog['variant_name'],
        'location_id': locationId,
        'location_name': location['name'],
        'lot_code': lotCode.trim(),
        'received_at': inventoryDateValue(receivedAt ?? DateTime.now()),
        'expires_at': expiry == null ? null : inventoryDateValue(expiry),
        'initial_quantity': quantity,
        'quantity': quantity,
        'unit_cost': unitCost,
        'supplier': supplier.trim(),
        'status': expiry != null && expiry.isBefore(DateTime.now()) ? 'expired' : 'active',
        'days_to_expiry': expiry?.difference(DateTime.now()).inDays,
        'notes': notes.trim(),
      });
      return id;
    }
    final response = await _supabase.rpc(
      'inventory_lot_receive_v1',
      params: {
        'target_club': AppSession.instance.clubId,
        'p_product': productId,
        'p_variant': variantId,
        'p_location': locationId,
        'p_lot_code': lotCode.trim(),
        'p_quantity': quantity,
        'p_received_at': inventoryDateValue(receivedAt ?? DateTime.now()),
        'p_expires_at': expiresAt == null ? null : inventoryDateValue(expiresAt),
        'p_unit_cost': unitCost,
        'p_supplier': _nullable(supplier),
        'p_notes': _nullable(notes),
      },
    );
    return response.toString();
  }

  Future<List<Map<String, dynamic>>> breakages() async {
    _requireManage();
    if (isDemo) return _demoBreakages.map(Map<String, dynamic>.from).toList();
    final response = await _supabase
        .from('stock_breakages')
        .select(
          'id,quantity,reason,unit_cost,notes,created_at,product_id,variant_id,location_id,lot_id,'
          'products(name),product_variants(name),inventory_locations(name),stock_lots(lot_code)',
        )
        .eq('club_id', AppSession.instance.clubId)
        .order('created_at', ascending: false)
        .limit(300);
    return List<Map<String, dynamic>>.from(response);
  }

  Future<String> recordBreakage({
    required String productId,
    String? variantId,
    required String locationId,
    required double quantity,
    String reason = 'breakage',
    String? lotId,
    String notes = '',
  }) async {
    _requireManage();
    if (quantity <= 0) throw ArgumentError('A quantidade deve ser superior a zero.');
    if (isDemo) {
      final stock = (await stockRows()).firstWhere(
        (row) =>
            row['product_id'] == productId &&
            row['variant_id'] == variantId &&
            row['location_id'] == locationId,
      );
      if (inventoryQuantity(stock['quantity']) < quantity) {
        throw StateError('Stock físico insuficiente.');
      }
      final id = 'demo-breakage-${DateTime.now().microsecondsSinceEpoch}';
      _demoBreakages.insert(0, {
        'id': id,
        'product_id': productId,
        'product_name': stock['product_name'],
        'variant_id': variantId,
        'variant_name': stock['variant_name'],
        'location_id': locationId,
        'location_name': stock['location_name'],
        'lot_id': lotId,
        'quantity': quantity,
        'reason': reason,
        'unit_cost': 0,
        'notes': notes.trim(),
        'created_at': DateTime.now().toIso8601String(),
      });
      return id;
    }
    final response = await _supabase.rpc(
      'inventory_breakage_record_v1',
      params: {
        'target_club': AppSession.instance.clubId,
        'p_product': productId,
        'p_variant': variantId,
        'p_location': locationId,
        'p_quantity': quantity,
        'p_reason': reason,
        'p_lot': lotId,
        'p_notes': _nullable(notes),
      },
    );
    return response.toString();
  }

  void _requireView() {
    if (!canView) throw StateError('Sem permissão para consultar o inventário.');
  }

  void _requireManage() {
    if (!canManage) throw StateError('Sem permissão para gerir o inventário.');
  }

  String? _nullable(String value) {
    final normalized = value.trim();
    return normalized.isEmpty ? null : normalized;
  }
}

double inventoryQuantity(Object? value) {
  if (value is num) return value.toDouble();
  return double.tryParse(value?.toString() ?? '') ?? 0;
}

String inventoryDateValue(DateTime date) {
  final local = DateTime(date.year, date.month, date.day);
  return '${local.year.toString().padLeft(4, '0')}-'
      '${local.month.toString().padLeft(2, '0')}-'
      '${local.day.toString().padLeft(2, '0')}';
}

String inventoryDateLabel(Object? value) {
  final raw = value?.toString() ?? '';
  final date = DateTime.tryParse(raw);
  if (date == null) return raw.isEmpty ? '—' : raw;
  return '${date.day.toString().padLeft(2, '0')}/'
      '${date.month.toString().padLeft(2, '0')}/${date.year}';
}

String inventoryReservationStatusLabel(Object? value) => switch (value?.toString()) {
      'active' => 'Ativa',
      'released' => 'Libertada',
      'cancelled' => 'Cancelada',
      'expired' => 'Expirada',
      _ => value?.toString() ?? '—',
    };

String inventoryLotStatusLabel(Object? value) => switch (value?.toString()) {
      'active' => 'Ativo',
      'expired' => 'Expirado',
      'depleted' => 'Esgotado',
      'quarantined' => 'Quarentena',
      _ => value?.toString() ?? '—',
    };

String inventoryBreakageReasonLabel(Object? value) => switch (value?.toString()) {
      'breakage' => 'Quebra',
      'expiry' => 'Validade',
      'damage' => 'Dano',
      'loss' => 'Perda',
      'other' => 'Outro',
      _ => value?.toString() ?? '—',
    };

String inventoryItemLabel(Map<String, dynamic> row) {
  final product = row['product_name']?.toString() ?? 'Produto';
  final variant = row['variant_name']?.toString().trim() ?? '';
  return variant.isEmpty ? product : '$product · $variant';
}
