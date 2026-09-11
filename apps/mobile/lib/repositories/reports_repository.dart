import '../core/app_config.dart';
import '../core/app_session.dart';
import '../core/reporting.dart';
import 'communication_repository.dart';
import 'document_repository.dart';
import 'events_repository.dart';
import 'fees_repository.dart';
import 'inventory_control_repository.dart';
import 'inventory_repository.dart';
import 'member_repository.dart';

class ReportsRepository {
  ReportsRepository({
    MemberRepository? members,
    FeesRepository? fees,
    EventsRepository? events,
    InventoryRepository? inventory,
    InventoryControlRepository? inventoryControl,
    DocumentRepository? documents,
    CommunicationRepository? communication,
  })  : _members = members ?? MemberRepository(),
        _fees = fees ?? FeesRepository(),
        _events = events ?? EventsRepository(),
        _inventory = inventory ?? InventoryRepository(),
        _inventoryControl = inventoryControl ?? InventoryControlRepository(),
        _documents = documents ?? DocumentRepository(),
        _communication = communication ?? CommunicationRepository();

  final MemberRepository _members;
  final FeesRepository _fees;
  final EventsRepository _events;
  final InventoryRepository _inventory;
  final InventoryControlRepository _inventoryControl;
  final DocumentRepository _documents;
  final CommunicationRepository _communication;

  Future<ReportData> load(
    ReportDefinition definition, {
    ReportFilters filters = const ReportFilters(),
  }) async {
    _require(definition);

    final raw = switch (definition.kind) {
      ReportKind.members => await _memberRows(),
      ReportKind.fees => await _feeRows(),
      ReportKind.events => await _eventRows(),
      ReportKind.inventoryStock => await _inventoryStockRows(),
      ReportKind.inventoryByLocation => await _inventoryLocationRows(),
      ReportKind.inventoryMovements => await _inventoryMovementRows(),
      ReportKind.documents => await _documentRows(),
      ReportKind.communication => await _communicationRows(),
      ReportKind.treasury => throw StateError(
          'Os relatórios de Tesouraria usam o módulo financeiro dedicado.',
        ),
    };

    final columns = _columns(definition.kind);
    final rows = _applyFilters(raw, definition, filters, columns);

    return ReportData(
      definition: definition,
      columns: columns,
      rows: rows,
      metrics: _metrics(definition.kind, rows),
      filtersDescription: _filtersDescription(definition, filters),
    );
  }

  Future<List<Map<String, dynamic>>> _memberRows() async {
    final rows = await _members.listMembers();
    return rows.map((row) {
      final motorcycle = [
        row['motorcycle_brand'],
        row['motorcycle_model'],
        row['motorcycle_year'],
      ].where((value) => value != null && value.toString().trim().isNotEmpty).join(' ');
      return <String, dynamic>{
        'member_number': row['member_number'],
        'full_name': row['full_name'],
        'nickname': row['nickname'],
        'status': row['status']?.toString() ?? '',
        'status_label': _memberStatusLabel(row['status']?.toString()),
        'joined_at': row['joined_at'],
        'prospect_joined_at': row['prospect_joined_at'],
        'full_colors_at': row['full_colors_at'],
        'primary_role': row['primary_role'],
        'motorcycle': motorcycle,
        'registration': row['motorcycle_registration'],
      };
    }).toList();
  }

  Future<List<Map<String, dynamic>>> _feeRows() async {
    final rows = await _fees.listObligations();
    return rows.map((row) {
      final amount = _num(row['amount']);
      final paid = _num(row['paid_amount']);
      final balance = _num(row['balance']);
      final status = row['status']?.toString() ?? '';
      return <String, dynamic>{
        'member_name': row['member_name'],
        'period_label': row['period_label'],
        'due_date': row['due_date'],
        'amount': amount,
        'paid_amount': paid,
        'balance': balance,
        'status': status,
        'status_label': _feeStatusLabel(status),
      };
    }).toList();
  }

  Future<List<Map<String, dynamic>>> _eventRows() async {
    final rows = await _events.listEvents();
    return rows.map((row) {
      final status = row['status']?.toString() ?? '';
      return <String, dynamic>{
        'name': row['name'],
        'starts_at': row['starts_at'],
        'ends_at': row['ends_at'],
        'location': row['location'],
        'status': status,
        'status_label': _eventStatusLabel(status),
        'capacity': row['capacity'],
      };
    }).toList();
  }

  Future<List<Map<String, dynamic>>> _inventoryStockRows() async {
    final rows = await _inventory.listProducts();
    return rows.map((row) {
      final current = _num(row['current_stock']);
      final reserved = _num(row['reserved_stock']);
      final minimum = _num(row['minimum_stock']);
      final active = row['active'] != false;
      final state = !active
          ? 'inactive'
          : current - reserved <= minimum
              ? 'low'
              : 'ok';
      return <String, dynamic>{
        'name': row['name'],
        'sku': row['sku'],
        'category': row['category'],
        'inventory_area': _inventoryAreaLabel(row['inventory_area']?.toString()),
        'unit': row['unit'],
        'current_stock': current,
        'reserved_stock': reserved,
        'available_stock': current - reserved,
        'minimum_stock': minimum,
        'stock_state': state,
        'stock_state_label': _stockStateLabel(state),
      };
    }).toList();
  }

  Future<List<Map<String, dynamic>>> _inventoryLocationRows() async {
    if (AppConfig.demoMode) {
      final products = await _inventory.listProducts();
      return products.map((row) {
        final current = _num(row['current_stock']);
        final reserved = _num(row['reserved_stock']);
        return <String, dynamic>{
          'location_name': 'Geral',
          'location_type': 'demo',
          'product_name': row['name'],
          'variant_name': '',
          'sku': row['sku'],
          'inventory_area': _inventoryAreaLabel(row['inventory_area']?.toString()),
          'unit': row['unit'],
          'quantity': current,
          'reserved_quantity': reserved,
          'available_quantity': current - reserved,
        };
      }).toList();
    }

    final rows = await _inventoryControl.stockByLocation();
    return rows.map((row) => <String, dynamic>{
          'location_name': row['location_name'],
          'location_type': row['location_type'],
          'product_name': row['product_name'],
          'variant_name': row['variant_name'],
          'sku': row['sku'],
          'inventory_area': _inventoryAreaLabel(row['inventory_area']?.toString()),
          'unit': row['unit'],
          'quantity': _num(row['quantity']),
          'reserved_quantity': _num(row['reserved_quantity']),
          'available_quantity': _num(row['available_quantity']),
        }).toList();
  }

  Future<List<Map<String, dynamic>>> _inventoryMovementRows() async {
    final rows = await _inventory.listMovements(limit: 1000);
    return rows.map((row) {
      final type = row['movement_type']?.toString() ?? row['kind']?.toString() ?? '';
      return <String, dynamic>{
        'movement_date': row['movement_date'] ?? row['created_at'],
        'product_name': row['product_name'],
        'movement_type': type,
        'movement_type_label': _movementLabel(type),
        'quantity': _num(row['quantity']),
        'description': row['description'] ?? row['notes'],
      };
    }).toList();
  }

  Future<List<Map<String, dynamic>>> _documentRows() async {
    final rows = await _documents.listDocuments();
    return rows.map((row) {
      final storedStatus = row['status']?.toString() ?? 'active';
      final effectiveStatus = DocumentRepository.isExpired(row)
          ? 'expired'
          : storedStatus;
      return <String, dynamic>{
        'name': row['name'],
        'category': row['category'],
        'document_date': row['document_date'],
        'version': row['version'],
        'status': effectiveStatus,
        'status_label': _documentStatusLabel(effectiveStatus),
        'expires_at': row['expires_at'],
        'sensitive': row['sensitive'] == true,
      };
    }).toList();
  }

  Future<List<Map<String, dynamic>>> _communicationRows() async {
    final rows = await _communication.listAnnouncements();
    return rows.map((row) {
      final priority = row['priority']?.toString() ?? 'normal';
      return <String, dynamic>{
        'title': row['title'],
        'priority': priority,
        'priority_label': _priorityLabel(priority),
        'audience': _audienceLabel(row['audience']?.toString()),
        'published_at': row['published_at'],
        'expires_at': row['expires_at'],
        'requires_acknowledgement': row['requires_acknowledgement'] == true,
        'acknowledged': row['acknowledged'] == true,
      };
    }).toList();
  }

  List<Map<String, dynamic>> _applyFilters(
    List<Map<String, dynamic>> rows,
    ReportDefinition definition,
    ReportFilters filters,
    List<ReportColumn> columns,
  ) {
    final query = _normalize(filters.query);
    final from = filters.from == null ? null : _dateOnly(filters.from!);
    final to = filters.to == null ? null : _dateOnly(filters.to!);

    final filtered = rows.where((row) {
      if (definition.filterField != null &&
          filters.option != null &&
          filters.option!.isNotEmpty &&
          row[definition.filterField]?.toString() != filters.option) {
        return false;
      }

      if (definition.dateField != null && (from != null || to != null)) {
        final date = DateTime.tryParse(
          row[definition.dateField]?.toString() ?? '',
        );
        if (date == null) return false;
        final value = _dateOnly(date);
        if (from != null && value.isBefore(from)) return false;
        if (to != null && value.isAfter(to)) return false;
      }

      if (query.isNotEmpty) {
        final haystack = columns
            .map((column) => row[column.key]?.toString() ?? '')
            .join(' ');
        if (!_normalize(haystack).contains(query)) return false;
      }
      return true;
    }).map(Map<String, dynamic>.from).toList();

    _sort(definition.kind, filtered);
    return filtered;
  }

  void _sort(ReportKind kind, List<Map<String, dynamic>> rows) {
    switch (kind) {
      case ReportKind.members:
        rows.sort((a, b) => _int(a['member_number']).compareTo(_int(b['member_number'])));
      case ReportKind.fees:
        rows.sort((a, b) => (b['due_date']?.toString() ?? '').compareTo(a['due_date']?.toString() ?? ''));
      case ReportKind.events:
        rows.sort((a, b) => (a['starts_at']?.toString() ?? '').compareTo(b['starts_at']?.toString() ?? ''));
      case ReportKind.inventoryStock:
        rows.sort((a, b) => (a['name']?.toString() ?? '').compareTo(b['name']?.toString() ?? ''));
      case ReportKind.inventoryByLocation:
        rows.sort((a, b) {
          final location = (a['location_name']?.toString() ?? '').compareTo(b['location_name']?.toString() ?? '');
          if (location != 0) return location;
          return (a['product_name']?.toString() ?? '').compareTo(b['product_name']?.toString() ?? '');
        });
      case ReportKind.inventoryMovements:
        rows.sort((a, b) => (b['movement_date']?.toString() ?? '').compareTo(a['movement_date']?.toString() ?? ''));
      case ReportKind.documents:
        rows.sort((a, b) => (b['document_date']?.toString() ?? '').compareTo(a['document_date']?.toString() ?? ''));
      case ReportKind.communication:
        rows.sort((a, b) => (b['published_at']?.toString() ?? '').compareTo(a['published_at']?.toString() ?? ''));
      case ReportKind.treasury:
        break;
    }
  }

  List<ReportColumn> _columns(ReportKind kind) => switch (kind) {
        ReportKind.members => const [
            ReportColumn('member_number', 'N.º', type: ReportValueType.number),
            ReportColumn('full_name', 'Nome'),
            ReportColumn('nickname', 'Alcunha'),
            ReportColumn('status_label', 'Estado'),
            ReportColumn('joined_at', 'Entrada', type: ReportValueType.date),
            ReportColumn('prospect_joined_at', 'Prospect', type: ReportValueType.date),
            ReportColumn('full_colors_at', 'Full Colors', type: ReportValueType.date),
            ReportColumn('primary_role', 'Cargo'),
            ReportColumn('motorcycle', 'Mota principal'),
            ReportColumn('registration', 'Matrícula'),
          ],
        ReportKind.fees => const [
            ReportColumn('member_name', 'Membro'),
            ReportColumn('period_label', 'Período'),
            ReportColumn('due_date', 'Vencimento', type: ReportValueType.date),
            ReportColumn('amount', 'Valor', type: ReportValueType.currency),
            ReportColumn('paid_amount', 'Pago', type: ReportValueType.currency),
            ReportColumn('balance', 'Pendente', type: ReportValueType.currency),
            ReportColumn('status_label', 'Estado'),
          ],
        ReportKind.events => const [
            ReportColumn('name', 'Evento'),
            ReportColumn('starts_at', 'Início', type: ReportValueType.dateTime),
            ReportColumn('ends_at', 'Fim', type: ReportValueType.dateTime),
            ReportColumn('location', 'Local'),
            ReportColumn('status_label', 'Estado'),
            ReportColumn('capacity', 'Capacidade', type: ReportValueType.number),
          ],
        ReportKind.inventoryStock => const [
            ReportColumn('name', 'Artigo'),
            ReportColumn('sku', 'SKU'),
            ReportColumn('category', 'Categoria'),
            ReportColumn('inventory_area', 'Área'),
            ReportColumn('unit', 'Unidade'),
            ReportColumn('current_stock', 'Atual', type: ReportValueType.number),
            ReportColumn('reserved_stock', 'Reservado', type: ReportValueType.number),
            ReportColumn('available_stock', 'Disponível', type: ReportValueType.number),
            ReportColumn('minimum_stock', 'Mínimo', type: ReportValueType.number),
            ReportColumn('stock_state_label', 'Estado'),
          ],
        ReportKind.inventoryByLocation => const [
            ReportColumn('location_name', 'Localização'),
            ReportColumn('product_name', 'Artigo'),
            ReportColumn('variant_name', 'Variante'),
            ReportColumn('sku', 'SKU'),
            ReportColumn('inventory_area', 'Área'),
            ReportColumn('unit', 'Unidade'),
            ReportColumn('quantity', 'Quantidade', type: ReportValueType.number),
            ReportColumn('reserved_quantity', 'Reservado', type: ReportValueType.number),
            ReportColumn('available_quantity', 'Disponível', type: ReportValueType.number),
          ],
        ReportKind.inventoryMovements => const [
            ReportColumn('movement_date', 'Data', type: ReportValueType.dateTime),
            ReportColumn('product_name', 'Artigo'),
            ReportColumn('movement_type_label', 'Tipo'),
            ReportColumn('quantity', 'Quantidade', type: ReportValueType.number),
            ReportColumn('description', 'Descrição'),
          ],
        ReportKind.documents => const [
            ReportColumn('name', 'Documento'),
            ReportColumn('category', 'Categoria'),
            ReportColumn('document_date', 'Data', type: ReportValueType.date),
            ReportColumn('version', 'Versão'),
            ReportColumn('status_label', 'Estado'),
            ReportColumn('expires_at', 'Validade', type: ReportValueType.date),
            ReportColumn('sensitive', 'Sensível', type: ReportValueType.boolean),
          ],
        ReportKind.communication => const [
            ReportColumn('title', 'Comunicado'),
            ReportColumn('priority_label', 'Prioridade'),
            ReportColumn('audience', 'Audiência'),
            ReportColumn('published_at', 'Publicação', type: ReportValueType.dateTime),
            ReportColumn('expires_at', 'Expiração', type: ReportValueType.dateTime),
            ReportColumn('requires_acknowledgement', 'Exige confirmação', type: ReportValueType.boolean),
            ReportColumn('acknowledged', 'Confirmado por mim', type: ReportValueType.boolean),
          ],
        ReportKind.treasury => const [],
      };

  Map<String, String> _metrics(
    ReportKind kind,
    List<Map<String, dynamic>> rows,
  ) {
    return switch (kind) {
      ReportKind.members => {
          'Registos': '${rows.length}',
          'Ativos': '${rows.where((row) => row['status'] == 'active').length}',
          'Prospects': '${rows.where((row) => row['status'] == 'prospect').length}',
        },
      ReportKind.fees => {
          'Obrigações': '${rows.length}',
          'Total': _money(rows.fold<double>(0, (sum, row) => sum + _num(row['amount']))),
          'Pago': _money(rows.fold<double>(0, (sum, row) => sum + _num(row['paid_amount']))),
          'Pendente': _money(rows.fold<double>(0, (sum, row) => sum + _num(row['balance']))),
        },
      ReportKind.events => {
          'Eventos': '${rows.length}',
          'Concluídos': '${rows.where((row) => row['status'] == 'completed').length}',
          'Em curso': '${rows.where((row) => row['status'] == 'active').length}',
        },
      ReportKind.inventoryStock => {
          'Artigos': '${rows.length}',
          'Stock baixo': '${rows.where((row) => row['stock_state'] == 'low').length}',
          'Disponível': _number(rows.fold<double>(0, (sum, row) => sum + _num(row['available_stock']))),
        },
      ReportKind.inventoryByLocation => {
          'Linhas': '${rows.length}',
          'Localizações': '${rows.map((row) => row['location_name']?.toString()).whereType<String>().toSet().length}',
          'Disponível': _number(rows.fold<double>(0, (sum, row) => sum + _num(row['available_quantity']))),
        },
      ReportKind.inventoryMovements => {
          'Movimentos': '${rows.length}',
          'Quantidade líquida': _number(rows.fold<double>(0, (sum, row) => sum + _num(row['quantity']))),
        },
      ReportKind.documents => {
          'Documentos': '${rows.length}',
          'Expirados': '${rows.where((row) => row['status'] == 'expired').length}',
          'A expirar': '${rows.where((row) => _expiresSoon(row['expires_at'])).length}',
        },
      ReportKind.communication => {
          'Comunicados': '${rows.length}',
          'Exigem confirmação': '${rows.where((row) => row['requires_acknowledgement'] == true).length}',
          'Confirmados por mim': '${rows.where((row) => row['acknowledged'] == true).length}',
        },
      ReportKind.treasury => const {},
    };
  }

  String _filtersDescription(
    ReportDefinition definition,
    ReportFilters filters,
  ) {
    final values = <String>[];
    if (filters.query.trim().isNotEmpty) {
      values.add('Pesquisa: ${filters.query.trim()}');
    }
    if (definition.hasDateFilter && filters.from != null && filters.to != null) {
      values.add('Período: ${_date(filters.from!)} a ${_date(filters.to!)}');
    }
    if (definition.hasOptionFilter && filters.option != null) {
      final option = definition.filterOptions
          .where((item) => item.value == filters.option)
          .map((item) => item.label)
          .firstOrNull;
      if (option != null) values.add('${definition.filterLabel}: $option');
    }
    return values.isEmpty ? 'Sem filtros adicionais' : values.join(' • ');
  }

  void _require(ReportDefinition definition) {
    if (!AppSession.instance.can(definition.permission)) {
      throw StateError('Sem permissão para consultar este relatório.');
    }
  }
}

String _memberStatusLabel(String? value) => switch (value) {
      'active' => 'Ativo',
      'prospect' => 'Prospect',
      'full_color' => 'Full Colors',
      'honorary' => 'Honorário',
      'suspended' => 'Suspenso',
      'former' => 'Ex-membro',
      'deceased' => 'Falecido',
      _ => value?.isNotEmpty == true ? value! : '—',
    };

String _feeStatusLabel(String value) => switch (value) {
      'paid' => 'Paga',
      'partial' => 'Parcial',
      'overdue' => 'Vencida',
      'pending' => 'Pendente',
      'exempt' => 'Isenta',
      'cancelled' => 'Cancelada',
      _ => value.isEmpty ? '—' : value,
    };

String _eventStatusLabel(String value) => switch (value) {
      'draft' => 'Rascunho',
      'published' => 'Publicado',
      'active' => 'Em curso',
      'completed' => 'Concluído',
      'cancelled' => 'Cancelado',
      _ => value.isEmpty ? '—' : value,
    };

String _documentStatusLabel(String value) => switch (value) {
      'active' => 'Ativo',
      'draft' => 'Rascunho',
      'archived' => 'Arquivado',
      'expired' => 'Expirado',
      _ => value.isEmpty ? '—' : value,
    };

String _stockStateLabel(String value) => switch (value) {
      'low' => 'Stock baixo',
      'ok' => 'Normal',
      'inactive' => 'Inativo',
      _ => value,
    };

String _movementLabel(String value) => switch (value) {
      'purchase' => 'Compra / Entrada',
      'sale' => 'Venda',
      'adjustment' => 'Ajuste',
      'loss' => 'Perda',
      'transfer' => 'Transferência',
      'event_consumption' => 'Consumo em evento',
      'return' => 'Devolução',
      'entry' => 'Entrada',
      'transfer_in' => 'Transferência entrada',
      'transfer_out' => 'Transferência saída',
      'adjustment_in' => 'Ajuste entrada',
      'adjustment_out' => 'Ajuste saída',
      'reservation' => 'Reserva',
      'release' => 'Libertação',
      _ => value.isEmpty ? 'Movimento' : value,
    };

String _priorityLabel(String value) => switch (value) {
      'informative' => 'Informativo',
      'important' => 'Importante',
      'urgent' => 'Urgente',
      'critical' => 'Crítico',
      _ => 'Normal',
    };

String _audienceLabel(String? value) => switch (value) {
      'members' => 'Membros',
      'prospects' => 'Prospects',
      'leadership' => 'Direção',
      'treasury' => 'Tesouraria',
      'events' => 'Eventos',
      _ => 'Todos',
    };

String _inventoryAreaLabel(String? value) => switch (value) {
      'bar' => 'Bar',
      'shop' => 'Loja',
      'assets' => 'Património',
      _ => value?.isNotEmpty == true ? value! : 'Geral',
    };

bool _expiresSoon(Object? value) {
  final date = DateTime.tryParse(value?.toString() ?? '');
  if (date == null) return false;
  final now = _dateOnly(DateTime.now());
  final target = _dateOnly(date);
  final days = target.difference(now).inDays;
  return days >= 0 && days <= 30;
}

String _normalize(String value) => value
    .trim()
    .toLowerCase()
    .replaceAll('á', 'a')
    .replaceAll('à', 'a')
    .replaceAll('ã', 'a')
    .replaceAll('â', 'a')
    .replaceAll('é', 'e')
    .replaceAll('ê', 'e')
    .replaceAll('í', 'i')
    .replaceAll('ó', 'o')
    .replaceAll('õ', 'o')
    .replaceAll('ô', 'o')
    .replaceAll('ú', 'u')
    .replaceAll('ç', 'c');

double _num(Object? value) => value is num
    ? value.toDouble()
    : double.tryParse(value?.toString().replaceAll(',', '.') ?? '') ?? 0;
int _int(Object? value) => value is num
    ? value.toInt()
    : int.tryParse(value?.toString() ?? '') ?? 999999;
DateTime _dateOnly(DateTime value) => DateTime(value.year, value.month, value.day);
String _date(DateTime value) =>
    '${value.day.toString().padLeft(2, '0')}/${value.month.toString().padLeft(2, '0')}/${value.year}';
String _money(double value) => '${value.toStringAsFixed(2).replaceAll('.', ',')} €';
String _number(double value) => value.toStringAsFixed(value % 1 == 0 ? 0 : 2).replaceAll('.', ',');

extension _FirstOrNull<T> on Iterable<T> {
  T? get firstOrNull => isEmpty ? null : first;
}
