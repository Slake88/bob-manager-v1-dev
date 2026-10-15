import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../repositories/admin_repository.dart';
import '../widgets/audit_detail_content.dart';

class AuditModuleDefinition {
  const AuditModuleDefinition(this.label, this.entityTypes);

  final String label;
  final Set<String> entityTypes;
}

const auditModuleDefinitions = <AuditModuleDefinition>[
  AuditModuleDefinition('Membros', {
    'members',
    'member_emergency_data',
    'member_status_history',
    'club_positions',
    'member_positions',
    'member_patch_awards',
    'assigned_assets',
    'member_timeline',
  }),
  AuditModuleDefinition('Motas e manutenção', {
    'motorcycles',
    'member_motorcycles',
    'motorcycle_photos',
    'motorcycle_ownership_history',
    'maintenance_records',
    'maintenance_attachments',
    'motorcycle_documents',
  }),
  AuditModuleDefinition('Pedidos & Pagamentos', {
    'financial_requests',
    'financial_request_attachments',
  }),
  AuditModuleDefinition('Tesouraria', {
    'financial_accounts',
    'treasury_transactions',
    'treasury_accounts',
    'transaction',
    'financial_transaction_documents',
    'financial_ocr_jobs',
    'funds',
    'cost_centers',
    'financial_categories',
    'financial_transactions',
    'transaction_allocations',
    'suppliers',
    'payables',
    'receivables',
    'reimbursement_requests',
    'cash_sessions',
    'bank_reconciliations',
    'bank_reconciliation_items',
    'budgets',
    'budget_lines',
  }),
  AuditModuleDefinition('Quotas', {
    'fee_plans',
    'member_fee_assignments',
    'fee_obligations',
    'fee_payments',
    'fee_payment_allocations',
    'fee_credits',
    'fee_exemptions',
    'fee_adjustments',
    'fee_receipts',
    'reported_payments',
    'prospect_enrollment_fees',
  }),
  AuditModuleDefinition('Euromilhões', {
    'lottery_groups',
    'euromillions',
    'euromillions_draw_charges',
    'euromillions_fines',
    'euromillions_fine_payment',
    'euromillions_results',
    'euromillions_players',
    'euromillions_prizes',
    'lottery_participants',
    'participant_keys',
    'lottery_periods',
    'lottery_contributions',
    'lottery_draws',
    'lottery_bets',
    'lottery_bet_keys',
    'lottery_results',
    'lottery_matches',
    'lottery_prizes',
    'lottery_fund_uses',
    'euromillions_prize',
    'euromillions_draw_charge',
  }),
  AuditModuleDefinition('Eventos', {
    'events',
    'event_proposals',
    'event_route_stops',
    'event_volunteers',
    'event_participants',
    'event_guests',
    'event_tasks',
    'event_task_assignees',
    'event_shifts',
    'event_shift_members',
    'event_program',
    'event_routes',
    'event_bands',
    'event_exhibitors',
    'event_sponsors',
    'event_documents',
    'event_incidents',
    'event_octane_configs',
  }),
  AuditModuleDefinition('Agenda', {'agenda_items', 'agenda_item'}),
  AuditModuleDefinition('Responsável semanal', {
    'weekly_dinners',
    'weekly_officer_absences',
    'weekly_officer_rotation',
    'weekly_officer_swap_requests',
  }),
  AuditModuleDefinition('BAR', {
    'bar_sales',
    'bar_operations',
    'bar_sale_items',
    'bar_sale_attachments',
    'bar_sale_presets',
    'bar_product_sale_options',
  }),
  AuditModuleDefinition('Inventário', {
    'products',
    'inventory',
    'inventory_locations',
    'inventory_prices',
    'inventory_visibility',
    'inventory_count_sessions',
    'product',
    'stock_breakages',
    'product_variants',
    'stock_locations',
    'stock_lots',
    'stock_movements',
    'stock_reservations',
    'physical_inventories',
    'inventory_counts',
    'external_customers',
    'sales_orders',
    'sales_order_lines',
    'patch_delivery_requests',
  }),
  AuditModuleDefinition('Documentos', {
    'attachments',
    'documents',
    'document_versions',
    'document_links',
    'document_approvals',
    'document_access_log',
    'document_ocr',
    'annual_books',
    'annual_book_items',
  }),
  AuditModuleDefinition('Comunicação', {
    'announcements',
    'announcement',
    'announcement_acknowledgements',
    'announcement_recipients',
    'polls',
    'poll_options',
    'poll_votes',
  }),
  AuditModuleDefinition('Administração', {
    'clubs',
    'club_role_permissions',
    'user_access',
    'profiles',
    'club_memberships',
    'roles',
    'permissions',
    'role_permissions',
    'membership_roles',
    'user_permission_overrides',
    'permission_change_log',
    'club_settings',
    'imports',
    'import_rows',
    'exports',
    'scheduled_reports',
    'notification_preferences',
    'payment_methods',
    'number_sequences',
    'consumption_card_templates',
    'consumption_cards',
    'consumption_card_scans',
    'consumption_card_lines',
    'clubhouse_visitors',
    'club_export',
    'import',
  }),
];

final _allAuditedEntityTypes = auditModuleDefinitions
    .expand((module) => module.entityTypes)
    .toSet();

String auditModuleForEntityType(String? entityType) {
  for (final module in auditModuleDefinitions) {
    if (module.entityTypes.contains(entityType)) return module.label;
  }
  return 'Outros';
}

List<String>? auditEntityTypesForModule(String? label) {
  if (label == null || label.isEmpty) return null;
  if (label == 'Outros') {
    return _allAuditedEntityTypes.toList()..sort();
  }
  for (final module in auditModuleDefinitions) {
    if (module.label == label) return module.entityTypes.toList()..sort();
  }
  return null;
}

class AuditScreen extends StatefulWidget {
  const AuditScreen({super.key});

  @override
  State<AuditScreen> createState() => _AuditScreenState();
}

class _AuditScreenState extends State<AuditScreen> {
  static const _pageSize = 50;

  final AdminRepository _repository = AdminRepository();
  final _actorController = TextEditingController();
  final _searchController = TextEditingController();
  final _entityIdController = TextEditingController();
  final _actionController = TextEditingController();

  List<Map<String, dynamic>> _rows = [];
  AuditLogFilters _filters = const AuditLogFilters();
  AuditLogCursor? _cursor;
  DateTime? _dateFrom;
  DateTime? _dateTo;
  String? _selectedModule;
  bool _loading = true;
  bool _loadingMore = false;
  bool _hasMore = false;
  Object? _error;
  int _requestVersion = 0;

  @override
  void initState() {
    super.initState();
    _loadFirstPage();
  }

  @override
  void dispose() {
    _actorController.dispose();
    _searchController.dispose();
    _entityIdController.dispose();
    _actionController.dispose();
    super.dispose();
  }

  Future<void> _loadFirstPage({AuditLogFilters? filters}) async {
    final requestVersion = ++_requestVersion;
    setState(() {
      _filters = filters ?? _filters;
      _rows = [];
      _cursor = null;
      _hasMore = false;
      _loading = true;
      _loadingMore = false;
      _error = null;
    });
    try {
      final page = await _repository.listAuditLogPage(
        filters: _filters,
        limit: _pageSize,
      );
      if (!mounted || requestVersion != _requestVersion) return;
      setState(() {
        _rows = page.rows;
        _cursor = page.nextCursor;
        _hasMore = page.hasMore;
        _loading = false;
      });
    } catch (error) {
      if (!mounted || requestVersion != _requestVersion) return;
      setState(() {
        _loading = false;
        _error = error;
      });
    }
  }

  Future<void> _loadNextPage() async {
    final cursor = _cursor;
    if (_loadingMore || !_hasMore || cursor == null) return;
    final requestVersion = _requestVersion;
    setState(() => _loadingMore = true);
    try {
      final page = await _repository.listAuditLogPage(
        filters: _filters,
        cursor: cursor,
        limit: _pageSize,
      );
      if (!mounted || requestVersion != _requestVersion) return;
      setState(() {
        _rows.addAll(page.rows);
        _cursor = page.nextCursor;
        _hasMore = page.hasMore;
        _loadingMore = false;
      });
    } catch (error) {
      if (!mounted || requestVersion != _requestVersion) return;
      setState(() {
        _loadingMore = false;
        _error = error;
      });
    }
  }

  Future<void> _selectDate({required bool isStart}) async {
    final initialDate = isStart ? _dateFrom : _dateTo;
    final selected = await showDatePicker(
      context: context,
      initialDate: initialDate ?? DateTime.now(),
      firstDate: DateTime(2000),
      lastDate: DateTime(2100),
    );
    if (selected == null || !mounted) return;
    setState(() {
      if (isStart) {
        _dateFrom = selected;
      } else {
        _dateTo = selected;
      }
    });
  }

  void _applyFilters() {
    if (_dateFrom != null &&
        _dateTo != null &&
        _dateFrom!.isAfter(_dateTo!)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('A data inicial deve preceder a final.')),
      );
      return;
    }
    final moduleTypes = auditEntityTypesForModule(_selectedModule);
    _loadFirstPage(
      filters: AuditLogFilters(
        dateFrom: _dateFrom,
        dateTo: _dateTo,
        entityTypes: moduleTypes,
        excludeEntityTypes: _selectedModule == 'Outros',
        action: _actionController.text,
        actorQuery: _actorController.text,
        search: _searchController.text,
        entityId: _entityIdController.text,
      ),
    );
  }

  void _clearFilters() {
    _actorController.clear();
    _searchController.clear();
    _entityIdController.clear();
    _actionController.clear();
    setState(() {
      _dateFrom = null;
      _dateTo = null;
      _selectedModule = null;
    });
    _loadFirstPage(filters: const AuditLogFilters());
  }

  Future<void> _showDetail(Map<String, dynamic> row) async {
    await showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(
          '${auditActionLabel(row['action'])} · '
          '${auditEntityLabel(row['entity_type'])}',
        ),
        content: SizedBox(
          width: 720,
          child: SingleChildScrollView(
            child: AuditDetailContent(row: row),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Fechar'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Auditoria'),
        actions: [
          IconButton(
            tooltip: 'Limpar filtros',
            onPressed: _clearFilters,
            icon: const Icon(Icons.filter_alt_off_outlined),
          ),
        ],
      ),
      body: Column(
        children: [
          _buildFilterPanel(context),
          Expanded(child: _buildResults()),
        ],
      ),
    );
  }

  Widget _buildFilterPanel(BuildContext context) {
    return Card(
      margin: const EdgeInsets.fromLTRB(16, 12, 16, 8),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: LayoutBuilder(
          builder: (context, constraints) {
            final width = constraints.maxWidth < 560
                ? constraints.maxWidth
                : 250.0;
            return Wrap(
              spacing: 8,
              runSpacing: 8,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                SizedBox(
                  width: width,
                  child: DropdownButtonFormField<String?>(
                    initialValue: _selectedModule,
                    decoration: const InputDecoration(
                      labelText: 'Módulo',
                      border: OutlineInputBorder(),
                      isDense: true,
                    ),
                    items: [
                      const DropdownMenuItem<String?>(
                        value: null,
                        child: Text('Todos'),
                      ),
                      ...auditModuleDefinitions.map(
                        (module) => DropdownMenuItem<String?>(
                          value: module.label,
                          child: Text(module.label),
                        ),
                      ),
                      const DropdownMenuItem<String?>(
                        value: 'Outros',
                        child: Text('Outros'),
                      ),
                    ],
                    onChanged: (value) =>
                        setState(() => _selectedModule = value),
                  ),
                ),
                SizedBox(
                  width: width,
                  child: _dateButton(
                    label: 'Data inicial',
                    value: _dateFrom,
                    onPressed: () => _selectDate(isStart: true),
                  ),
                ),
                SizedBox(
                  width: width,
                  child: _dateButton(
                    label: 'Data final',
                    value: _dateTo,
                    onPressed: () => _selectDate(isStart: false),
                  ),
                ),
                _filterField(
                  width,
                  _actionController,
                  'Ação (valor exato)',
                ),
                _filterField(width, _actorController, 'Utilizador'),
                _filterField(width, _searchController, 'Pesquisa textual'),
                _filterField(width, _entityIdController, 'ID do registo'),
                FilledButton.icon(
                  onPressed: _applyFilters,
                  icon: const Icon(Icons.search),
                  label: const Text('Filtrar'),
                ),
                TextButton.icon(
                  onPressed: _clearFilters,
                  icon: const Icon(Icons.clear),
                  label: const Text('Limpar'),
                ),
              ],
            );
          },
        ),
      ),
    );
  }

  Widget _filterField(
    double width,
    TextEditingController controller,
    String label,
  ) {
    return SizedBox(
      width: width,
      child: TextField(
        controller: controller,
        textInputAction: TextInputAction.search,
        onSubmitted: (_) => _applyFilters(),
        decoration: InputDecoration(
          labelText: label,
          border: const OutlineInputBorder(),
          isDense: true,
        ),
      ),
    );
  }

  Widget _dateButton({
    required String label,
    required DateTime? value,
    required VoidCallback onPressed,
  }) {
    final dateLabel = value == null ? label : DateFormat('dd/MM/yyyy').format(value);
    return OutlinedButton.icon(
      onPressed: onPressed,
      icon: const Icon(Icons.calendar_today_outlined),
      label: Text(dateLabel, overflow: TextOverflow.ellipsis),
    );
  }

  Widget _buildResults() {
    if (_loading) return const Center(child: CircularProgressIndicator());
    if (_error != null && _rows.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('Erro ao carregar a Auditoria: $_error'),
            const SizedBox(height: 8),
            OutlinedButton.icon(
              onPressed: () => _loadFirstPage(),
              icon: const Icon(Icons.refresh),
              label: const Text('Tentar novamente'),
            ),
          ],
        ),
      );
    }
    if (_rows.isEmpty) {
      return const Center(child: Text('Não foram encontrados registos.'));
    }

    return RefreshIndicator(
      onRefresh: () => _loadFirstPage(),
      child: ListView.separated(
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
        itemCount: _rows.length + (_hasMore || _loadingMore ? 1 : 0),
        separatorBuilder: (_, __) => const Divider(height: 1),
        itemBuilder: (context, index) {
          if (index == _rows.length) {
            return Padding(
              padding: const EdgeInsets.symmetric(vertical: 12),
              child: Center(
                child: _loadingMore
                    ? const CircularProgressIndicator()
                    : OutlinedButton.icon(
                        onPressed: _loadNextPage,
                        icon: const Icon(Icons.expand_more),
                        label: const Text('Carregar mais'),
                      ),
              ),
            );
          }
          final row = _rows[index];
          final actor = auditActorLabel(row);
          final moment = auditMomentLabel(row['created_at']);
          final entityId = row['entity_id']?.toString() ?? '';
          return ListTile(
            leading: const CircleAvatar(
              child: Icon(Icons.history_outlined),
            ),
            title: Text(
              '${auditActionLabel(row['action'])} · '
              '${auditEntityLabel(row['entity_type'])}',
            ),
            subtitle: Text(
              '$actor · $moment${entityId.isEmpty ? '' : '\nID: $entityId'}',
            ),
            isThreeLine: entityId.isNotEmpty,
            trailing: const Icon(Icons.chevron_right),
            onTap: () => _showDetail(row),
          );
        },
      ),
    );
  }
}
