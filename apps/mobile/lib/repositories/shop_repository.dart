import 'dart:typed_data';

import 'package:image_picker/image_picker.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../core/app_session.dart';
import '../core/permissions.dart';

class ShopRepository {
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
        .select('id,name,sku,category,description,supplier,cost,sale_price,minimum_stock,current_stock,reserved_stock,photo_path,institutional_delivery,active,product_variants(id,name,sku,attributes,current_stock,reserved_stock,minimum_stock,cost,sale_price,photo_path,active)')
        .eq('club_id', _clubId)
        .eq('inventory_area', 'shop')
        .eq('active', true)
        .order('name');
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

  Future<List<Map<String, dynamic>>> orders() async {
    _require(AppPermission.viewInventory);
    final response = await _client
        .from('shop_orders')
        .select('id,status,total_amount,paid_amount,notes,external_name,external_contact,created_at,member_id,members(full_name),shop_order_items(id,quantity,unit_price,product_id,variant_id,products(name),product_variants(name))')
        .eq('club_id', _clubId)
        .neq('status', 'cancelled')
        .order('created_at', ascending: false);
    return List<Map<String, dynamic>>.from(response);
  }

  Future<Map<String, dynamic>> saveProduct({
    String? id,
    required String name,
    required String sku,
    required String category,
    required String description,
    required String supplier,
    required double cost,
    required double salePrice,
    required double minimumStock,
    required bool institutionalDelivery,
  }) async {
    _require(AppPermission.manageMerchandising);
    final values = <String, dynamic>{
      'club_id': _clubId,
      'inventory_area': 'shop',
      'name': name.trim(),
      'sku': sku.trim().isEmpty ? null : sku.trim(),
      'category': category.trim().isEmpty ? 'Merchandising' : category.trim(),
      'description': description.trim().isEmpty ? null : description.trim(),
      'supplier': supplier.trim().isEmpty ? null : supplier.trim(),
      'unit': 'unit',
      'cost': cost,
      'sale_price': salePrice,
      'minimum_stock': minimumStock,
      'institutional_delivery': institutionalDelivery,
      'active': true,
    };
    if (id == null) {
      final response = await _client.from('products').insert(values).select().single();
      final product = Map<String, dynamic>.from(response);
      await _ensureDefaultVisibility(product['id'].toString(), salePrice);
      return product;
    }
    final response = await _client
        .from('products')
        .update(values..remove('club_id'))
        .eq('id', id)
        .eq('club_id', _clubId)
        .select()
        .single();
    return Map<String, dynamic>.from(response);
  }

  Future<void> _ensureDefaultVisibility(String productId, double salePrice) async {
    for (final audience in const ['public', 'prospect', 'full_color']) {
      await _client.from('inventory_visibility').upsert({
        'club_id': _clubId,
        'product_id': productId,
        'audience': audience,
        'allowed': true,
      }, onConflict: 'product_id,audience');
      await _client.from('inventory_prices').upsert({
        'club_id': _clubId,
        'product_id': productId,
        'audience': audience,
        'price': salePrice,
      }, onConflict: 'product_id,audience');
    }
  }

  Future<void> saveAudience({
    required String productId,
    required Map<String, bool> visibility,
    required Map<String, double> prices,
  }) async {
    _require(AppPermission.manageMerchandising);
    for (final audience in const ['public', 'prospect', 'full_color']) {
      await _client.from('inventory_visibility').upsert({
        'club_id': _clubId,
        'product_id': productId,
        'audience': audience,
        'allowed': visibility[audience] ?? false,
      }, onConflict: 'product_id,audience');
      await _client.from('inventory_prices').upsert({
        'club_id': _clubId,
        'product_id': productId,
        'audience': audience,
        'price': prices[audience] ?? 0,
      }, onConflict: 'product_id,audience');
    }
  }

  Future<Map<String, dynamic>> audience(String productId) async {
    _require(AppPermission.viewInventory);
    final visibility = await _client
        .from('inventory_visibility')
        .select('audience,allowed')
        .eq('product_id', productId);
    final prices = await _client
        .from('inventory_prices')
        .select('audience,price')
        .eq('product_id', productId);
    return {
      'visibility': {for (final row in visibility) row['audience'].toString(): row['allowed'] == true},
      'prices': {for (final row in prices) row['audience'].toString(): _double(row['price'])},
    };
  }

  Future<void> saveVariant({
    String? id,
    required String productId,
    required String name,
    required String sku,
    required double currentStock,
    required double minimumStock,
    required double cost,
    required double salePrice,
  }) async {
    _require(AppPermission.manageMerchandising);
    final values = <String, dynamic>{
      'product_id': productId,
      'name': name.trim(),
      'sku': sku.trim().isEmpty ? null : sku.trim(),
      'attributes': {'label': name.trim()},
      'current_stock': currentStock,
      'minimum_stock': minimumStock,
      'cost': cost,
      'sale_price': salePrice,
      'active': true,
    };
    if (id == null) {
      await _client.from('product_variants').insert(values);
    } else {
      await _client.from('product_variants').update(values).eq('id', id);
    }
  }

  Future<void> reserveVariant({
    required String productId,
    required String variantId,
    required double quantity,
    String notes = '',
  }) async {
    _require(AppPermission.manageMerchandising);
    await _client.rpc('reserve_shop_variant_v1', params: {
      'target_club': _clubId,
      'p_product': productId,
      'p_variant': variantId,
      'p_quantity': quantity,
      'p_notes': notes,
    });
  }

  Future<String> createOrder({
    required String productId,
    String? variantId,
    required double quantity,
    required double unitPrice,
    String? memberId,
    String externalName = '',
    String externalContact = '',
    String notes = '',
  }) async {
    _require(AppPermission.manageMerchandising);
    final result = await _client.rpc('create_shop_order_v1', params: {
      'target_club': _clubId,
      'p_product': productId,
      'p_variant': variantId,
      'p_quantity': quantity,
      'p_unit_price': unitPrice,
      'p_member': memberId,
      'p_external_name': externalName,
      'p_external_contact': externalContact,
      'p_notes': notes,
    });
    return result.toString();
  }

  Future<void> payOrder({
    required String orderId,
    required double amount,
    required String paymentMethod,
  }) async {
    await _client.rpc('record_shop_order_payment_v1', params: {
      'target_club': _clubId,
      'p_order': orderId,
      'p_amount': amount,
      'p_payment_method': paymentMethod,
    });
  }

  Future<void> updateOrderStatus(String orderId, String status) async {
    _require(AppPermission.manageMerchandising);
    await _client
        .from('shop_orders')
        .update({'status': status, 'updated_at': DateTime.now().toIso8601String()})
        .eq('id', orderId)
        .eq('club_id', _clubId);
  }

  Future<String> uploadProductImage({
    required String productId,
    required XFile file,
  }) async {
    _require(AppPermission.manageMerchandising);
    final Uint8List bytes = await file.readAsBytes();
    final extension = file.name.toLowerCase().endsWith('.png')
        ? 'png'
        : file.name.toLowerCase().endsWith('.webp')
            ? 'webp'
            : 'jpg';
    final path = '$_clubId/products/$productId/${DateTime.now().microsecondsSinceEpoch}.$extension';
    await _client.storage.from('inventory-media').uploadBinary(
          path,
          bytes,
          fileOptions: FileOptions(contentType: file.mimeType, upsert: false),
        );
    await _client
        .from('products')
        .update({'photo_path': path})
        .eq('id', productId)
        .eq('club_id', _clubId);
    await _client.from('product_images').insert({
      'club_id': _clubId,
      'product_id': productId,
      'storage_path': path,
      'is_primary': true,
      'created_by': AppSession.instance.profileId,
    });
    return path;
  }

  String? publicImageUrl(Object? path) {
    final value = path?.toString();
    if (value == null || value.isEmpty) return null;
    return _client.storage.from('inventory-media').getPublicUrl(value);
  }
}

double _double(Object? value) {
  if (value is num) return value.toDouble();
  return double.tryParse(value?.toString().replaceAll(',', '.') ?? '') ?? 0;
}
