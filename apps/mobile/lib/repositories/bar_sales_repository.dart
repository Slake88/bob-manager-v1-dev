import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../core/app_config.dart';
import '../core/app_session.dart';
import '../core/permissions.dart';
import 'financial_documents_repository.dart';
import 'weekly_dinner_finance_repository.dart';
import '../services/data_service.dart';
import '../models/weekly_dinner_finance.dart';

class BarSalesRepository {
  BarSalesRepository({SupabaseClient? client, DataService? dataService})
      : _clientOverride = client,
        _data = dataService ?? DataService.instance;
  final SupabaseClient? _clientOverride;
  final DataService _data;
  bool get _isDemo => _clientOverride == null && AppConfig.demoMode;
  SupabaseClient get _client => _clientOverride ?? Supabase.instance.client;
  Future<List<Map<String, dynamic>>> _demoList(String table) async =>
      (await _data.list(table)).where((r) => r['club_id'] == _clubId).toList();
  String get _clubId => AppSession.instance.clubId;

  bool get canManage => AppSession.instance.can(AppPermission.manageBar);
  bool get canSelectAccount =>
      AppSession.instance.can(AppPermission.selectBarFinancialAccount);

  void _requireView() {
    if (!AppSession.instance.can(AppPermission.viewBar)) {
      throw StateError('Sem permissão para ver o Bar.');
    }
  }

  void _requireManage() {
    if (!canManage) {
      throw StateError('Sem permissão para registar vendas no Bar.');
    }
  }

  Future<List<Map<String, dynamic>>> products() async {
    _requireView();
    if (_isDemo) {
      await WeeklyDinnerFinanceRepository.seedDemo();
      return (await _demoList('products'))
          .where((p) => p['inventory_area'] == 'bar' && p['active'] != false)
          .toList();
    }
    final response = await _client
        .from('products')
        .select(
          'id,name,category,consumption_unit,current_stock,minimum_stock,active,'
          'bar_product_sale_options(id,name,stock_quantity,public_price,member_price,sort_order,active)',
        )
        .eq('club_id', _clubId)
        .eq('inventory_area', 'bar')
        .eq('active', true)
        .order('name');
    final rows = List<Map<String, dynamic>>.from(response);
    for (final product in rows) {
      final raw = product['bar_product_sale_options'];
      final options = raw is List
          ? raw
              .whereType<Map>()
              .map((row) => Map<String, dynamic>.from(row))
              .where((row) => row['active'] != false)
              .toList()
          : <Map<String, dynamic>>[];
      options.sort((a, b) {
        final aSort = (a['sort_order'] as num?)?.toInt() ?? 0;
        final bSort = (b['sort_order'] as num?)?.toInt() ?? 0;
        final bySort = aSort.compareTo(bSort);
        if (bySort != 0) return bySort;
        return (a['name']?.toString() ?? '')
            .compareTo(b['name']?.toString() ?? '');
      });
      product['sale_options'] = options;
    }
    return rows;
  }

  Future<List<Map<String, dynamic>>> members() async {
    _requireView();
    if (_isDemo) return const [];
    final response = await _client
        .from('members')
        .select('id,member_number,full_name,nickname,status')
        .eq('club_id', _clubId)
        .inFilter('status', const ['active', 'full_color', 'honorary']).order(
            'full_name');
    return List<Map<String, dynamic>>.from(response);
  }

  Future<List<Map<String, dynamic>>> presets() async {
    _requireView();
    if (_isDemo) {
      await WeeklyDinnerFinanceRepository.seedDemo();
      return (await _demoList('bar_sale_presets'))
          .where((p) => p['active'] != false)
          .toList();
    }
    final response = await _client
        .from('bar_sale_presets')
        .select('id,name,unit_price,active,sort_order,counts_as_dinner_meal')
        .eq('club_id', _clubId)
        .eq('active', true)
        .order('sort_order')
        .order('name');
    return List<Map<String, dynamic>>.from(response);
  }

  Future<void> updatePresetPrice({
    required String presetId,
    required double price,
    bool? countsAsDinnerMeal,
  }) async {
    _requireManage();
    if (price < 0) throw ArgumentError('O preço não pode ser negativo.');
    if (_isDemo) {
      await _data.update('bar_sale_presets', presetId, {
        'unit_price': price,
        if (countsAsDinnerMeal != null)
          'counts_as_dinner_meal': countsAsDinnerMeal
      });
      return;
    }
    await _client
        .from('bar_sale_presets')
        .update({
          'unit_price': price,
          if (countsAsDinnerMeal != null)
            'counts_as_dinner_meal': countsAsDinnerMeal,
          'updated_by': _client.auth.currentUser?.id,
          'updated_at': DateTime.now().toUtc().toIso8601String(),
        })
        .eq('club_id', _clubId)
        .eq('id', presetId);
  }

  Future<void> savePreset(
      {String? id,
      required String name,
      required double price,
      required bool countsAsDinnerMeal}) async {
    _requireManage();
    if (name.trim().isEmpty || !price.isFinite || price < 0) {
      throw ArgumentError('Nome/preço inválido.');
    }
    final values = {
      'club_id': _clubId,
      'name': name.trim(),
      'unit_price': price,
      'active': true,
      'counts_as_dinner_meal': countsAsDinnerMeal,
      'updated_by': AppSession.instance.profileId
    };
    if (_isDemo) {
      if (id == null) {
        await _data.insert('bar_sale_presets', values);
      } else {
        if (!(await _demoList('bar_sale_presets')).any((r) => r['id'] == id)) {
          throw StateError('Preset inválido.');
        }
        await _data.update('bar_sale_presets', id, values);
      }
    } else if (id == null) {
      await _client.from('bar_sale_presets').insert(values);
    } else {
      await _client
          .from('bar_sale_presets')
          .update(values)
          .eq('club_id', _clubId)
          .eq('id', id);
    }
  }

  Future<List<Map<String, dynamic>>> events() async {
    _requireView();
    if (_isDemo) return _demoList('events');
    final response = await _client
        .from('events')
        .select('id,name,starts_at,status')
        .eq('club_id', _clubId)
        .order('starts_at', ascending: false)
        .limit(40);
    return List<Map<String, dynamic>>.from(response);
  }

  Future<List<Map<String, dynamic>>> treasuryAccounts() async {
    if (!canSelectAccount || _isDemo) return const [];
    final response = await _client
        .from('treasury_accounts')
        .select('id,name,account_type')
        .eq('club_id', _clubId)
        .eq('active', true)
        .order('name');
    return List<Map<String, dynamic>>.from(response);
  }

  Future<List<Map<String, dynamic>>> recentSales({int limit = 40}) async {
    _requireView();
    if (_isDemo) {
      return (await _demoList('bar_sales'))
          .where((s) => s['status'] == 'completed')
          .toList();
    }
    final response = await _client
        .from('bar_sales')
        .select(
          'id,source_mode,status,customer_label,customer_type,member_id,payment_method,total_amount,notes,created_at,completed_at,completed_by,event_id,weekly_dinner_id,'
          'events(name),member:members!bar_sales_member_id_fkey(id,full_name,nickname),'
          'completed_actor:profiles!bar_sales_completed_by_fkey(full_name,email),'
          'bar_sale_items(id,item_kind,description,quantity,unit_price,line_total,sale_option_name,stock_quantity_per_unit,price_tier,dinner_component_snapshot),'
          'bar_sale_attachments(id,original_file_name,mime_type,file_size,ocr_status,ocr_confidence)',
        )
        .eq('club_id', _clubId)
        .eq('status', 'completed')
        .order('completed_at', ascending: false)
        .limit(limit);
    return List<Map<String, dynamic>>.from(response);
  }

  Future<String> createDraft({
    String sourceMode = 'manual',
    String? customerLabel,
    String customerType = 'public',
    String? memberId,
    String? eventId,
    String? weeklyDinnerId,
    String? notes,
  }) async {
    _requireManage();
    if (_isDemo) {
      await _validateDemoDinner(weeklyDinnerId);
      return (await _data.insert('bar_sales', {
        'club_id': _clubId,
        'status': 'draft',
        'source_mode': sourceMode,
        'customer_label': customerLabel,
        'customer_type': customerType,
        'member_id': memberId,
        'event_id': eventId,
        'weekly_dinner_id': weeklyDinnerId,
        'notes': notes
      }))['id']
          .toString();
    }
    final response = await _client.rpc(
      'create_bar_sale_v3',
      params: {
        'target_club': _clubId,
        'p_customer_label': _emptyToNull(customerLabel),
        'p_customer_type': customerType,
        'p_member': memberId,
        'p_source_mode': sourceMode,
        'p_event': eventId,
        'p_weekly_dinner': weeklyDinnerId,
        'p_notes': _emptyToNull(notes),
      },
    );
    return response.toString();
  }

  Future<void> cancelDraft(String saleId) async {
    _requireManage();
    if (_isDemo) {
      await _data.update('bar_sales', saleId, {'status': 'cancelled'});
      return;
    }
    await _client
        .from('bar_sales')
        .update({
          'status': 'cancelled',
          'updated_by': _client.auth.currentUser?.id,
          'updated_at': DateTime.now().toUtc().toIso8601String(),
        })
        .eq('club_id', _clubId)
        .eq('id', saleId)
        .eq('status', 'draft');
  }

  Future<List<Map<String, dynamic>>> uploadConsumptionCards({
    required String saleId,
    required List<PlatformFile> files,
    required bool runOcr,
  }) async {
    _requireManage();
    if (_isDemo) {
      throw StateError('Os anexos do Bar não estão disponíveis em Demo.');
    }
    if (files.isEmpty) return const [];

    final uploaded = <Map<String, dynamic>>[];
    for (final file in files) {
      final Uint8List? bytes = file.bytes;
      if (bytes == null || bytes.isEmpty) {
        throw StateError(
          'Não foi possível ler ${file.name}. Seleciona novamente a fotografia.',
        );
      }
      if (bytes.length > FinancialDocumentsRepository.maxFileBytes) {
        throw StateError('${file.name} ultrapassa o limite de 20 MB.');
      }
      final mime = FinancialDocumentsRepository.mimeTypeForExtension(
        file.extension,
      );
      if (mime == null || !mime.startsWith('image/')) {
        throw StateError(
          '${file.name}: usa uma fotografia JPG, PNG ou WEBP para o cartão de consumo.',
        );
      }

      final safeName = _safeFileName(file.name);
      final timestamp = DateTime.now().microsecondsSinceEpoch;
      final path = '$_clubId/bar-sales/$saleId/${timestamp}_$safeName';

      await _client.storage
          .from(FinancialDocumentsRepository.bucketName)
          .uploadBinary(
            path,
            bytes,
            fileOptions: FileOptions(contentType: mime, upsert: false),
          );

      try {
        final row = Map<String, dynamic>.from(
          await _client
              .from('bar_sale_attachments')
              .insert({
                'club_id': _clubId,
                'sale_id': saleId,
                'storage_path': path,
                'original_file_name': file.name,
                'mime_type': mime,
                'file_size': bytes.length,
                'attachment_kind': 'consumption_card',
                'ocr_status': runOcr ? 'pending' : 'skipped',
                'created_by': _client.auth.currentUser?.id,
              })
              .select()
              .single(),
        );

        if (runOcr) {
          await _runOcr(row['id'].toString());
          final refreshed = Map<String, dynamic>.from(
            await _client
                .from('bar_sale_attachments')
                .select()
                .eq('club_id', _clubId)
                .eq('id', row['id'])
                .single(),
          );
          uploaded.add(refreshed);
        } else {
          uploaded.add(row);
        }
      } catch (_) {
        await _client.storage
            .from(FinancialDocumentsRepository.bucketName)
            .remove([path]);
        rethrow;
      }
    }
    return uploaded;
  }

  Future<void> _runOcr(String attachmentId) async {
    final response = await _client.functions.invoke(
      'bar-sale-ocr',
      body: {'attachment_id': attachmentId},
    );
    final data = response.data;
    if (data is Map && data['error'] != null) {
      throw StateError(data['error'].toString());
    }
  }

  Future<Map<String, dynamic>> completeSale({
    required String saleId,
    required List<Map<String, dynamic>> lines,
    required String paymentMethod,
    String customerType = 'public',
    String? memberId,
    String? accountId,
    String? customerLabel,
    String? eventId,
    String? weeklyDinnerId,
    String? notes,
  }) async {
    _requireManage();
    if (lines.isEmpty) throw ArgumentError('Adiciona artigos à venda.');
    if (accountId != null && !canSelectAccount) {
      throw StateError('Sem permissão para escolher a conta financeira.');
    }
    if (_isDemo) {
      return _completeDemo(saleId, lines, paymentMethod, customerType, memberId,
          accountId, customerLabel, eventId, weeklyDinnerId, notes);
    }
    final response = await _client.rpc(
      'complete_bar_sale_v3',
      params: {
        'target_club': _clubId,
        'p_sale': saleId,
        'p_lines': lines,
        'p_payment_method': paymentMethod,
        'p_account': accountId,
        'p_customer_label': _emptyToNull(customerLabel),
        'p_customer_type': customerType,
        'p_member': memberId,
        'p_event': eventId,
        'p_weekly_dinner': weeklyDinnerId,
        'p_notes': _emptyToNull(notes),
      },
    );
    if (response is Map) return Map<String, dynamic>.from(response);
    throw StateError('Resposta inválida ao concluir a venda.');
  }

  Future<List<Map<String, dynamic>>> dinners() async {
    _requireView();
    if (!_isDemo) {
      return List<Map<String, dynamic>>.from(await _client.rpc(
          'bar_weekly_dinner_choices_v1',
          params: {'target_club': _clubId}) as List);
    }
    await WeeklyDinnerFinanceRepository.seedDemo();
    final finances = await _demoList('weekly_dinner_finances');
    return (await _demoList('weekly_dinners'))
        .where((d) =>
            !['closed', 'cancelled'].contains(d['status']) &&
            !finances.any((f) =>
                f['dinner_id'] == d['id'] && f['financial_status'] == 'closed'))
        .toList();
  }

  Future<void> _validateDemoDinner(String? id) async {
    if (id != null && !(await dinners()).any((d) => d['id'] == id)) {
      throw StateError('Jantar inválido ou fechado.');
    }
  }

  Future<Map<String, dynamic>> _completeDemo(
      String saleId,
      List<Map<String, dynamic>> lines,
      String method,
      String customerType,
      String? member,
      String? account,
      String? customer,
      String? event,
      String? dinner,
      String? notes) async {
    await _validateDemoDinner(dinner);
    final sales = (await _demoList('bar_sales'))
        .where((s) => s['id'] == saleId && s['status'] == 'draft');
    if (sales.isEmpty) throw StateError('Rascunho inválido.');
    if (!['public', 'member'].contains(customerType) || method.trim().isEmpty) {
      throw ArgumentError('Cliente/pagamento inválido.');
    }
    if (customerType == 'member' &&
        member == null &&
        (customer?.trim() ?? '').isEmpty) {
      throw ArgumentError('Indica o membro/grupo.');
    }
    final finalEvent = event ?? sales.first['event_id'] as String?;
    if (finalEvent != null &&
        !(await _demoList('events')).any((e) => e['id'] == finalEvent)) {
      throw StateError('Evento inválido para este clube.');
    }
    final accounts = (await _demoList('financial_accounts'))
        .where((a) => a['active'] != false)
        .toList();
    if (account != null && !accounts.any((a) => a['id'] == account)) {
      throw StateError('Conta inválida para este clube.');
    }
    final accountId = account ??
        (accounts.isEmpty
            ? (await _data.insert('financial_accounts', {
                'club_id': _clubId,
                'name': 'Caixa BAR Demo',
                'active': true
              }))['id']
                .toString()
            : accounts.first['id'].toString());
    final products = await _demoList('products');
    final presets = await _demoList('bar_sale_presets');
    final remaining = <String, double>{};
    final items = <Map<String, dynamic>>[];
    double total = 0;
    for (final line in lines) {
      final kind = line['kind'] ?? 'stock';
      final quantity = dinnerNumber(line['quantity']);
      if (!quantity.isFinite || quantity <= 0) {
        throw ArgumentError('Quantidade inválida.');
      }
      double price;
      Map<String, dynamic> item;
      if (kind == 'stock') {
        final matches = products.where((p) =>
            p['id'] == line['product_id'] &&
            p['active'] != false &&
            p['inventory_area'] == 'bar');
        if (matches.isEmpty) throw StateError('Produto inválido.');
        final product = matches.first;
        final options = List<Map<String, dynamic>>.from(
            product['sale_options'] as List? ?? []);
        final selected = options.where(
            (o) => o['id'] == line['sale_option_id'] && o['active'] != false);
        if (selected.isEmpty) throw StateError('Forma de venda inválida.');
        final option = selected.first;
        final consumed = quantity * dinnerNumber(option['stock_quantity']);
        final productId = product['id'].toString();
        final stock =
            remaining[productId] ?? dinnerNumber(product['current_stock']);
        if (consumed <= 0 || stock < consumed) {
          throw StateError('Stock insuficiente.');
        }
        remaining[productId] = stock - consumed;
        price = dinnerNumber(
            option[customerType == 'member' ? 'member_price' : 'public_price']);
        final cost = product['cost'];
        item = {
          'product_id': productId,
          'sale_option_id': option['id'],
          'stock_quantity_per_unit': option['stock_quantity'],
          'description': '${product['name']} · ${option['name']}',
          'unit_cost_snapshot': cost,
          'cost_total_snapshot':
              cost == null ? null : dinnerMoney(consumed * dinnerNumber(cost)),
          'dinner_component_snapshot': 'bar'
        };
      } else if (kind == 'preset') {
        final matches = presets
            .where((p) => p['id'] == line['preset_id'] && p['active'] != false);
        if (matches.isEmpty) throw StateError('Preset inválido.');
        final preset = matches.first;
        price = dinnerNumber(preset['unit_price']);
        if (price <= 0) throw StateError('Define o preço do preset.');
        item = {
          'preset_id': preset['id'],
          'description': preset['name'],
          'dinner_component_snapshot':
              preset['counts_as_dinner_meal'] == true ? 'meal' : 'excluded'
        };
      } else if (kind == 'other') {
        price = dinnerNumber(line['unit_price']);
        if (price < 0 ||
            (line['description']?.toString().trim() ?? '').isEmpty) {
          throw ArgumentError('Item Outro inválido.');
        }
        item = {
          'description': line['description'],
          'dinner_component_snapshot': 'excluded'
        };
      } else {
        throw ArgumentError('Tipo de linha inválido.');
      }
      final amount = dinnerMoney(price * quantity);
      total += amount;
      items.add({
        'club_id': _clubId,
        'sale_id': saleId,
        'item_kind': kind,
        'quantity': quantity,
        'unit_price': price,
        'line_total': amount,
        ...item
      });
    }
    if (total <= 0) throw StateError('Total inválido.');
    // Mutate only after validating the entire cart, including accumulated stock.
    for (final entry in remaining.entries) {
      await _data.update('products', entry.key, {'current_stock': entry.value});
    }
    final tx = await _data.insert('financial_transactions', {
      'club_id': _clubId,
      'kind': 'income',
      'amount': total,
      'account_id': accountId,
      'event_id': finalEvent,
      'source_type': 'bar_sale',
      'source_id': saleId,
      'transaction_date': DateTime.now().toIso8601String()
    });
    for (final item in items) {
      await _data.insert('bar_sale_items', item);
      if (item['item_kind'] == 'stock') {
        await _data.insert('stock_movements', {
          'club_id': _clubId,
          'product_id': item['product_id'],
          'event_id': finalEvent,
          'kind': 'sale',
          'quantity': -dinnerNumber(item['quantity']) *
              dinnerNumber(item['stock_quantity_per_unit']),
          'unit_cost': item['unit_cost_snapshot']
        });
        await _data.insert('bar_operations', {
          'club_id': _clubId,
          'product_id': item['product_id'],
          'event_id': finalEvent,
          'operation_type': 'sale',
          'consumption_quantity': dinnerNumber(item['quantity']) *
              dinnerNumber(item['stock_quantity_per_unit']),
          'products': products.firstWhere((p) => p['id'] == item['product_id']),
          'sale_id': saleId,
          'unit_price': item['unit_price'],
          'total_amount': item['line_total'],
          'treasury_transaction_id': tx['id'],
          'notes': notes,
          'created_by': AppSession.instance.profileId,
        });
      }
    }
    await _data.update('bar_sales', saleId, {
      'status': 'completed',
      'weekly_dinner_id': dinner,
      'event_id': finalEvent,
      'total_amount': total,
      'customer_label': customer,
      'customer_type': customerType,
      'member_id': member,
      'treasury_transaction_id': tx['id'],
      'completed_at': DateTime.now().toUtc().toIso8601String(),
      'notes': notes
    });
    return {
      'sale_id': saleId,
      'total': total,
      'weekly_dinner_id': dinner,
      'transaction_id': tx['id']
    };
  }

  static List<Map<String, dynamic>> suggestions(
    Map<String, dynamic> attachment,
  ) {
    final raw = attachment['ocr_suggestions'];
    if (raw is! List) return const [];
    return raw
        .whereType<Map>()
        .map((row) => Map<String, dynamic>.from(row))
        .toList();
  }
}

String? _emptyToNull(String? value) {
  final text = value?.trim() ?? '';
  return text.isEmpty ? null : text;
}

String _safeFileName(String value) {
  final normalized = value
      .trim()
      .replaceAll(RegExp(r'[^A-Za-z0-9._-]+'), '_')
      .replaceAll(RegExp(r'_+'), '_');
  return normalized.isEmpty ? 'cartao.jpg' : normalized;
}
