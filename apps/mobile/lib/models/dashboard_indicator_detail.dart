enum DashboardIndicator {
  members('Membros ativos'),
  prospects('Prospects'),
  totalBalance('Saldo total'),
  feeOutstanding('Quotas pendentes'),
  openEvents('Eventos abertos'),
  lowStock('Stock baixo'),
  expiringDocuments('Documentos a expirar'),
  pendingApprovals('Aprovações pendentes');

  const DashboardIndicator(this.title);
  final String title;

  String get key => switch (this) {
        totalBalance => 'total_balance',
        feeOutstanding => 'fee_outstanding',
        openEvents => 'open_events',
        lowStock => 'low_stock',
        expiringDocuments => 'expiring_documents',
        pendingApprovals => 'pending_approvals',
        _ => name,
      };

  bool get monetary => this == totalBalance || this == feeOutstanding;
}

/// complete means the entire contributing set is authorized, not that every
/// page has been loaded. An unauthorized response never contains partial rows.
class DashboardIndicatorDetail {
  const DashboardIndicatorDetail({
    required this.indicator,
    required this.authorized,
    required this.complete,
    this.rows = const [],
    this.totalRows,
    this.monetaryTotal,
    this.nextCursor,
  });

  final DashboardIndicator indicator;
  final bool authorized;
  final bool complete;
  final List<Map<String, dynamic>> rows;
  final int? totalRows;
  final num? monetaryTotal;
  final Map<String, dynamic>? nextCursor;

  bool get canDisplay => authorized && complete;
  Object? get aggregate =>
      canDisplay ? (indicator.monetary ? monetaryTotal : totalRows) : null;

  factory DashboardIndicatorDetail.fromMap(
    DashboardIndicator indicator,
    Map<String, dynamic> map,
  ) {
    if (map['indicator'] != indicator.key) {
      throw const FormatException('Indicador inesperado na resposta.');
    }
    final allowed = map['authorized'] == true && map['complete'] == true;
    return DashboardIndicatorDetail(
      indicator: indicator,
      authorized: allowed,
      complete: allowed,
      rows: allowed
          ? List<Map<String, dynamic>>.from(map['rows'] as List? ?? const [])
          : const [],
      totalRows: allowed ? (map['total_rows'] as num?)?.toInt() : null,
      monetaryTotal: allowed ? map['monetary_total'] as num? : null,
      nextCursor: allowed && map['next_cursor'] != null
          ? Map<String, dynamic>.from(map['next_cursor'] as Map)
          : null,
    );
  }
}
