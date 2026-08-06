import '../core/app_role.dart';
import '../core/app_session.dart';
import '../core/permissions.dart';
import '../services/data_service.dart';
import '../services/rc1_data_extensions.dart';

class DashboardRepository {
  DashboardRepository({DataService? dataService})
      : _dataService = dataService ?? DataService.instance;

  final DataService _dataService;

  Future<Map<String, dynamic>> summary() async {
    final members = await _dataService.list('members');
    final fees = await _dataService.list('fee_obligations');
    final events = await _dataService.list('events');
    final products = await _dataService.list('products');
    final documents = await _dataService.list('documents');
    final announcements = await _dataService.list('announcements');
    final expenseRequests = await _dataService.list('expense_requests');
    final treasury = await _dataService.treasurySummary();

    final now = DateTime.now();
    final activeMembers = members.where((row) {
      final status = row['status']?.toString();
      return status != 'former' && status != 'deceased';
    }).length;
    final prospects = members
        .where((row) => row['status']?.toString() == 'prospect')
        .length;
    final overdueFees = fees.where((row) {
      final balance = _asDouble(row['balance']);
      final dueDate = DateTime.tryParse(row['due_date']?.toString() ?? '');
      return balance > 0 && dueDate != null && dueDate.isBefore(now);
    }).length;
    final outstandingFees = fees.fold<double>(
      0,
      (total, row) => total + _asDouble(row['balance']),
    );
    final openEvents = events.where((row) {
      final status = row['status']?.toString();
      return !{'completed', 'cancelled', 'archived'}.contains(status);
    }).length;
    final lowStock = products.where((row) {
      final current = _asDouble(row['current_stock']);
      final reserved = _asDouble(row['reserved_stock']);
      final minimum = _asDouble(row['minimum_stock']);
      return current - reserved <= minimum;
    }).length;
    final expiringDocuments = documents.where((row) {
      final expiresAt = DateTime.tryParse(row['expires_at']?.toString() ?? '');
      if (expiresAt == null) return false;
      return !expiresAt.isBefore(now) &&
          expiresAt.isBefore(now.add(const Duration(days: 31)));
    }).length;
    final unreadAnnouncements = announcements.where((row) {
      return row['requires_acknowledgement'] == true;
    }).length;
    final pendingApprovals = expenseRequests.where((row) {
      return {'submitted', 'review'}.contains(row['status']?.toString());
    }).length;

    return {
      'members': activeMembers,
      'prospects': prospects,
      'total_balance': _asDouble(treasury['total_balance']),
      'fee_outstanding': outstandingFees,
      'overdue_fees': overdueFees,
      'open_events': openEvents,
      'low_stock': lowStock,
      'expiring_documents': expiringDocuments,
      'unread_announcements': unreadAnnouncements,
      'pending_approvals': pendingApprovals,
      'monthly_income': _asDouble(treasury['monthly_income']),
      'monthly_expense': _asDouble(treasury['monthly_expense']),
    };
  }

  Future<Map<String, dynamic>> reportsSummary() async {
    final summaryData = await summary();
    final role = AppRole.fromValue(AppSession.instance.role);
    return {
      ...summaryData,
      'can_view_financial': PermissionPolicy.allows(
        role,
        AppPermission.viewFinancialReports,
      ),
    };
  }
}

double _asDouble(Object? value) {
  if (value is num) return value.toDouble();
  return double.tryParse(value?.toString() ?? '') ?? 0;
}
