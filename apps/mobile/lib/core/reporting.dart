import 'package:flutter/material.dart';

import 'permissions.dart';

enum ReportKind {
  members,
  fees,
  events,
  inventoryStock,
  inventoryByLocation,
  inventoryMovements,
  documents,
  communication,
  treasury,
}

enum ReportValueType { text, number, currency, date, dateTime, boolean }

class ReportFilterOption {
  const ReportFilterOption(this.value, this.label);

  final String value;
  final String label;
}

class ReportDefinition {
  const ReportDefinition({
    required this.kind,
    required this.title,
    required this.description,
    required this.icon,
    required this.permission,
    this.dateField,
    this.filterField,
    this.filterLabel,
    this.filterOptions = const [],
  });

  final ReportKind kind;
  final String title;
  final String description;
  final IconData icon;
  final AppPermission permission;
  final String? dateField;
  final String? filterField;
  final String? filterLabel;
  final List<ReportFilterOption> filterOptions;

  bool get hasDateFilter => dateField != null;
  bool get hasOptionFilter =>
      filterField != null && filterOptions.isNotEmpty;
}

class ReportColumn {
  const ReportColumn(
    this.key,
    this.label, {
    this.type = ReportValueType.text,
  });

  final String key;
  final String label;
  final ReportValueType type;
}

class ReportFilters {
  const ReportFilters({
    this.query = '',
    this.from,
    this.to,
    this.option,
  });

  final String query;
  final DateTime? from;
  final DateTime? to;
  final String? option;

  ReportFilters copyWith({
    String? query,
    DateTime? from,
    DateTime? to,
    String? option,
    bool clearOption = false,
  }) {
    return ReportFilters(
      query: query ?? this.query,
      from: from ?? this.from,
      to: to ?? this.to,
      option: clearOption ? null : option ?? this.option,
    );
  }
}

class ReportData {
  const ReportData({
    required this.definition,
    required this.columns,
    required this.rows,
    required this.metrics,
    required this.filtersDescription,
  });

  final ReportDefinition definition;
  final List<ReportColumn> columns;
  final List<Map<String, dynamic>> rows;
  final Map<String, String> metrics;
  final String filtersDescription;
}

class ReportCatalog {
  const ReportCatalog._();

  static const definitions = <ReportDefinition>[
    ReportDefinition(
      kind: ReportKind.members,
      title: 'Membros',
      description: 'Mapa de membros, estados, percurso e mota principal.',
      icon: Icons.groups_outlined,
      permission: AppPermission.viewMembers,
      filterField: 'status',
      filterLabel: 'Estado',
      filterOptions: [
        ReportFilterOption('active', 'Ativos'),
        ReportFilterOption('prospect', 'Prospects'),
        ReportFilterOption('full_color', 'Full Colors'),
        ReportFilterOption('honorary', 'Honorários'),
        ReportFilterOption('suspended', 'Suspensos'),
        ReportFilterOption('former', 'Ex-membros'),
        ReportFilterOption('deceased', 'Falecidos'),
      ],
    ),
    ReportDefinition(
      kind: ReportKind.fees,
      title: 'Quotas',
      description: 'Obrigações, pagamentos e valores pendentes por período.',
      icon: Icons.receipt_long_outlined,
      permission: AppPermission.viewFees,
      dateField: 'due_date',
      filterField: 'status',
      filterLabel: 'Estado',
      filterOptions: [
        ReportFilterOption('paid', 'Pagas'),
        ReportFilterOption('partial', 'Parciais'),
        ReportFilterOption('pending', 'Pendentes'),
        ReportFilterOption('overdue', 'Vencidas'),
        ReportFilterOption('exempt', 'Isentas'),
        ReportFilterOption('cancelled', 'Canceladas'),
      ],
    ),
    ReportDefinition(
      kind: ReportKind.events,
      title: 'Eventos',
      description: 'Agenda operacional de eventos, datas, locais e estados.',
      icon: Icons.event_outlined,
      permission: AppPermission.viewEvents,
      dateField: 'starts_at',
      filterField: 'status',
      filterLabel: 'Estado',
      filterOptions: [
        ReportFilterOption('draft', 'Rascunho'),
        ReportFilterOption('published', 'Publicado'),
        ReportFilterOption('active', 'Em curso'),
        ReportFilterOption('completed', 'Concluído'),
        ReportFilterOption('cancelled', 'Cancelado'),
      ],
    ),
    ReportDefinition(
      kind: ReportKind.inventoryStock,
      title: 'Inventário — Stock',
      description: 'Stock atual, reservado, disponível e níveis mínimos.',
      icon: Icons.inventory_2_outlined,
      permission: AppPermission.viewInventory,
      filterField: 'stock_state',
      filterLabel: 'Stock',
      filterOptions: [
        ReportFilterOption('low', 'Stock baixo'),
        ReportFilterOption('ok', 'Stock normal'),
        ReportFilterOption('inactive', 'Inativos'),
      ],
    ),
    ReportDefinition(
      kind: ReportKind.inventoryByLocation,
      title: 'Inventário — Por localização',
      description: 'Quantidades físicas e disponíveis em cada localização.',
      icon: Icons.warehouse_outlined,
      permission: AppPermission.viewInventory,
    ),
    ReportDefinition(
      kind: ReportKind.inventoryMovements,
      title: 'Inventário — Movimentos',
      description: 'Entradas, saídas, transferências e ajustes de stock.',
      icon: Icons.swap_horiz_outlined,
      permission: AppPermission.viewInventory,
      dateField: 'movement_date',
      filterField: 'movement_type',
      filterLabel: 'Tipo',
      filterOptions: [
        ReportFilterOption('purchase', 'Compra / Entrada'),
        ReportFilterOption('sale', 'Venda'),
        ReportFilterOption('adjustment', 'Ajuste'),
        ReportFilterOption('loss', 'Perda'),
        ReportFilterOption('transfer', 'Transferência'),
        ReportFilterOption('event_consumption', 'Consumo em evento'),
        ReportFilterOption('return', 'Devolução'),
        ReportFilterOption('entry', 'Entrada (Demo)'),
      ],
    ),
    ReportDefinition(
      kind: ReportKind.documents,
      title: 'Documentos',
      description: 'Mapa documental, categorias, estados e validades.',
      icon: Icons.folder_outlined,
      permission: AppPermission.viewDocuments,
      dateField: 'document_date',
      filterField: 'status',
      filterLabel: 'Estado',
      filterOptions: [
        ReportFilterOption('active', 'Ativos'),
        ReportFilterOption('draft', 'Rascunho'),
        ReportFilterOption('archived', 'Arquivados'),
        ReportFilterOption('expired', 'Expirados'),
      ],
    ),
    ReportDefinition(
      kind: ReportKind.communication,
      title: 'Comunicação',
      description: 'Comunicados visíveis, prioridade, audiência e confirmação.',
      icon: Icons.campaign_outlined,
      permission: AppPermission.viewCommunication,
      dateField: 'published_at',
      filterField: 'priority',
      filterLabel: 'Prioridade',
      filterOptions: [
        ReportFilterOption('informative', 'Informativo'),
        ReportFilterOption('normal', 'Normal'),
        ReportFilterOption('important', 'Importante'),
        ReportFilterOption('urgent', 'Urgente'),
        ReportFilterOption('critical', 'Crítico'),
      ],
    ),
    ReportDefinition(
      kind: ReportKind.treasury,
      title: 'Tesouraria',
      description: 'Extratos e relatórios financeiros já integrados.',
      icon: Icons.account_balance_wallet_outlined,
      permission: AppPermission.viewFinancialReports,
    ),
  ];

  static List<ReportDefinition> visible(
    bool Function(AppPermission permission) allows,
  ) {
    return definitions.where((item) => allows(item.permission)).toList();
  }

  static bool canOpenCenter(
    bool Function(AppPermission permission) allows,
  ) {
    return definitions.any((item) => allows(item.permission));
  }
}
