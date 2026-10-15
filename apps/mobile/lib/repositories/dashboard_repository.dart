import 'dart:math' as math;

import 'package:supabase_flutter/supabase_flutter.dart';

import '../core/app_config.dart';
import '../core/app_session.dart';
import '../core/permissions.dart';
import '../models/dashboard_indicator_detail.dart';
import '../services/data_service.dart';
import '../services/rc1_data_extensions.dart';

class DashboardRepository {
  DashboardRepository({
    DataService? dataService,
    SupabaseClient? client,
    Future<List<Map<String, dynamic>>> Function(String)? demoLoader,
    DateTime Function()? now,
  })  : _dataService = dataService ?? DataService.instance,
        _clientOverride = client,
        _demoLoader = demoLoader,
        _now = now ?? DateTime.now;

  final DataService _dataService;
  final SupabaseClient? _clientOverride;
  final Future<List<Map<String, dynamic>>> Function(String)? _demoLoader;
  final DateTime Function() _now;
  SupabaseClient get _client => _clientOverride ?? Supabase.instance.client;
  bool get _isDemo => _clientOverride == null && AppConfig.demoMode;

  Future<Map<String, dynamic>> summary() async {
    if (!_isDemo) {
      final response = await _client.rpc(
        'dashboard_summary_rc1',
        params: {'target_club': AppSession.instance.clubId},
      );
      return Map<String, dynamic>.from(response as Map);
    }
    return _demoSummary();
  }

  Future<Map<String, dynamic>> reportsSummary() => summary();

  Future<DashboardIndicatorDetail> indicatorDetails(
    DashboardIndicator indicator, {
    int limit = 50,
    Map<String, dynamic>? cursor,
  }) async {
    if (limit < 1 || limit > 100) {
      throw ArgumentError.value(limit, 'limit', 'Deve estar entre 1 e 100.');
    }
    if (!_isDemo) {
      final response = await _client.rpc(
        'dashboard_indicator_details_v1',
        params: {
          'target_club': AppSession.instance.clubId,
          'p_indicator': indicator.key,
          'p_limit': limit,
          'p_cursor': cursor,
        },
      );
      return DashboardIndicatorDetail.fromMap(
        indicator,
        Map<String, dynamic>.from(response as Map),
      );
    }

    if (cursor != null) _validateDemoCursor(indicator, cursor);
    // Do not load financial data even in demo until permission is checked.
    if (!_demoPermission(indicator)) return _denied(indicator);
    final rows = await _demoIndicatorRows(indicator);
    if (rows.any((row) => !_demoRowVisible(indicator, row))) {
      return _denied(indicator);
    }
    final ordered = [...rows]..sort((a, b) => _compareDemoCursors(
        _demoCursor(indicator, a), _demoCursor(indicator, b)));
    final remaining = ordered
        .where((row) =>
            cursor == null ||
            _compareDemoCursors(_demoCursor(indicator, row), cursor) > 0)
        .toList();
    final displayed = remaining.take(limit).toList();
    final page = displayed.map(_publicRow).toList();
    return DashboardIndicatorDetail(
      indicator: indicator,
      authorized: true,
      complete: true,
      rows: page,
      totalRows: rows.length,
      monetaryTotal: indicator.monetary ? _sum(rows) : null,
      nextCursor: remaining.length > limit
          ? _demoCursor(indicator, displayed.last)
          : null,
    );
  }

  // Shared SQL ordering keys; unused keys stay explicitly null. The cursor
  // carries context, never permission, and is compared with NULLS LAST.
  Map<String, dynamic> _demoCursor(
    DashboardIndicator indicator,
    Map<String, dynamic> row,
  ) =>
      {
        'v': 1,
        'club_id': AppSession.instance.clubId,
        'indicator': indicator.key,
        'number': switch (indicator) {
          DashboardIndicator.members ||
          DashboardIndicator.prospects =>
            row['member_number'],
          _ => null,
        },
        'date': switch (indicator) {
          DashboardIndicator.feeOutstanding => _dateKey(row['due_date']),
          DashboardIndicator.expiringDocuments => _dateKey(row['expires_at']),
          _ => null,
        },
        'time': switch (indicator) {
          DashboardIndicator.openEvents => row['starts_at'],
          DashboardIndicator.pendingApprovals => row['_created_at'],
          _ => null,
        },
        'text': switch (indicator) {
          DashboardIndicator.members ||
          DashboardIndicator.prospects =>
            row['full_name'],
          DashboardIndicator.feeOutstanding => row['member_name'],
          DashboardIndicator.pendingApprovals => null,
          _ => row['name'],
        },
        'id': row['id'],
      };

  void _validateDemoCursor(
    DashboardIndicator indicator,
    Map<String, dynamic> cursor,
  ) {
    const keys = {
      'v',
      'club_id',
      'indicator',
      'number',
      'date',
      'time',
      'text',
      'id'
    };
    final number = cursor['number'];
    final date = cursor['date'];
    final time = cursor['time'];
    final text = cursor['text'];
    if (cursor.length != keys.length ||
        !keys.every(cursor.containsKey) ||
        cursor['v'] != 1 ||
        cursor['club_id'] != AppSession.instance.clubId ||
        cursor['indicator'] != indicator.key ||
        cursor['id'] is! String ||
        (cursor['id'] as String).isEmpty ||
        (number != null &&
            (number is! int || number < -2147483648 || number > 2147483647)) ||
        (date != null && (date is! String || !_validDateKey(date))) ||
        (time != null &&
            (time is! String || DateTime.tryParse(time) == null)) ||
        (text != null && text is! String) ||
        (number != null &&
            !{DashboardIndicator.members, DashboardIndicator.prospects}
                .contains(indicator)) ||
        (date != null &&
            !{
              DashboardIndicator.feeOutstanding,
              DashboardIndicator.expiringDocuments
            }.contains(indicator)) ||
        (time != null &&
            !{
              DashboardIndicator.openEvents,
              DashboardIndicator.pendingApprovals
            }.contains(indicator)) ||
        (text != null && indicator == DashboardIndicator.pendingApprovals)) {
      throw const FormatException('Cursor inválido para este indicador.');
    }
  }

  DashboardIndicatorDetail _denied(DashboardIndicator indicator) =>
      DashboardIndicatorDetail(
        indicator: indicator,
        authorized: false,
        complete: false,
      );

  bool _can(AppPermission permission) => AppSession.instance.can(permission);

  bool _demoPermission(DashboardIndicator indicator) => switch (indicator) {
        DashboardIndicator.members ||
        DashboardIndicator.prospects =>
          _can(AppPermission.viewMembers),
        DashboardIndicator.totalBalance => _can(AppPermission.viewTreasury),
        DashboardIndicator.feeOutstanding =>
          _can(AppPermission.viewTreasury) && _can(AppPermission.manageFees),
        DashboardIndicator.openEvents => _can(AppPermission.viewEvents),
        DashboardIndicator.lowStock =>
          _can(AppPermission.viewInventory) || _can(AppPermission.viewBar),
        DashboardIndicator.expiringDocuments =>
          _can(AppPermission.viewDocuments) ||
              _can(AppPermission.manageDocuments) ||
              _can(AppPermission.viewSensitiveDocuments),
        DashboardIndicator.pendingApprovals =>
          _can(AppPermission.approveExpenseRequests),
      };

  bool _demoRowVisible(
    DashboardIndicator indicator,
    Map<String, dynamic> row,
  ) {
    if (indicator == DashboardIndicator.lowStock) {
      return _can(row['_inventory_area'] == 'bar'
          ? AppPermission.viewBar
          : AppPermission.viewInventory);
    }
    if (indicator == DashboardIndicator.expiringDocuments) {
      final scope = row['_scope'] ?? 'club';
      if (scope == 'personal') {
        return row['_owner'] == AppSession.instance.profileId ||
            _can(AppPermission.manageDocuments);
      }
      if (scope == 'leadership') {
        return _can(AppPermission.viewSensitiveDocuments);
      }
      return {'club', 'event_gallery', 'annual_book'}.contains(scope) &&
          _can(AppPermission.viewDocuments) &&
          (row['_sensitive'] != true ||
              _can(AppPermission.viewSensitiveDocuments));
    }
    return true;
  }

  Future<List<Map<String, dynamic>>> _list(String table) async {
    final rows = await (_demoLoader?.call(table) ?? _dataService.list(table));
    return rows
        .where((row) =>
            row['club_id'] == null ||
            row['club_id'] == AppSession.instance.clubId)
        .map(Map<String, dynamic>.from)
        .toList();
  }

  DateTime get _today {
    final now = _now();
    return DateTime(now.year, now.month, now.day);
  }

  // The same selectors produce the demo summary and its drill-down rows.
  Future<List<Map<String, dynamic>>> _demoIndicatorRows(
    DashboardIndicator indicator,
  ) async {
    switch (indicator) {
      case DashboardIndicator.members:
      case DashboardIndicator.prospects:
        final rows = await _list('members');
        return rows
            .where((row) {
              final status = row['status']?.toString();
              return indicator == DashboardIndicator.prospects
                  ? status == 'prospect'
                  : status != null &&
                      !{'prospect', 'former', 'deceased'}.contains(status);
            })
            .map((row) => {
                  'id': row['id'],
                  'member_number': row['member_number'],
                  'full_name': row['full_name'],
                  'nickname': row['nickname'],
                })
            .toList();
      case DashboardIndicator.totalBalance:
        final List<Map<String, dynamic>> accounts;
        if (_demoLoader == null) {
          final treasury = await _dataService.treasurySummary();
          accounts =
              List<Map<String, dynamic>>.from(treasury['accounts'] as List);
        } else {
          accounts = await _list('financial_accounts');
          final transactions = await _list('financial_transactions');
          for (final account in accounts) {
            var balance = _number(account['opening_balance']);
            for (final transaction in transactions) {
              final amount = _number(transaction['amount']);
              if (transaction['account_id'] == account['id']) {
                if (transaction['kind'] == 'income') balance += amount;
                if (transaction['kind'] == 'expense' ||
                    transaction['kind'] == 'transfer') {
                  balance -= amount;
                }
              }
              if (transaction['kind'] == 'transfer' &&
                  transaction['destination_account_id'] == account['id']) {
                balance += amount;
              }
            }
            account['balance'] = balance;
          }
        }
        return accounts
            .where((row) => row['active'] == true)
            .map((row) => {
                  'id': row['id'],
                  'name': row['name'],
                  'balance': _number(row['balance']),
                  '_value': _number(row['balance']),
                })
            .toList();
      case DashboardIndicator.feeOutstanding:
        final rows = await _list('fee_obligations');
        final members = await _list('members');
        return rows
            .where((row) => _pending(row) > 0)
            .map((row) => {
                  'id': row['id'],
                  'member_name': _memberName(members, row['member_id']) ??
                      row['member_name'],
                  'outstanding': _pending(row),
                  'due_date': row['due_date'],
                  '_value': _pending(row),
                })
            .toList();
      case DashboardIndicator.openEvents:
        final rows = await _list('events');
        return rows
            .where((row) =>
                row['status'] != null &&
                !{'completed', 'cancelled', 'archived'}.contains(row['status']))
            .map((row) => {
                  'id': row['id'],
                  'name': row['name'],
                  'starts_at': row['starts_at'],
                  'status': row['status'],
                })
            .toList();
      case DashboardIndicator.lowStock:
        final rows = await _list('products');
        return rows
            .where((row) =>
                row['active'] == true &&
                row['current_stock'] != null &&
                row['reserved_stock'] != null &&
                row['minimum_stock'] != null &&
                _number(row['current_stock']) -
                        _number(row['reserved_stock']) <=
                    _number(row['minimum_stock']))
            .map((row) => {
                  'id': row['id'],
                  'name': row['name'],
                  'current_stock': row['current_stock'],
                  'reserved_stock': row['reserved_stock'],
                  'available_stock': _number(row['current_stock']) -
                      _number(row['reserved_stock']),
                  'minimum_stock': row['minimum_stock'],
                  '_inventory_area': row['inventory_area'],
                })
            .toList();
      case DashboardIndicator.expiringDocuments:
        final rows = await _list('documents');
        final today = _today;
        final end = DateTime(today.year, today.month, today.day + 30);
        return rows
            .where((row) {
              final expiry =
                  DateTime.tryParse(row['expires_at']?.toString() ?? '');
              if (expiry == null) return false;
              final day = DateTime(expiry.year, expiry.month, expiry.day);
              return !day.isBefore(today) && !day.isAfter(end);
            })
            .map((row) => {
                  'id': row['id'],
                  'name': row['name'],
                  'expires_at': row['expires_at'],
                  '_scope': row['scope'],
                  '_owner': row['owner_profile_id'],
                  '_sensitive': row['sensitive'],
                })
            .toList();
      case DashboardIndicator.pendingApprovals:
        final rows = await _list('financial_requests');
        final profiles = await _list('profiles');
        final members = await _list('members');
        return rows
            .where((row) => {'pending_review', 'awaiting_validation'}
                .contains(row['status']))
            .map((row) {
          final profile = profiles.where((profile) =>
              row['requested_by'] != null &&
              profile['id'] == row['requested_by']);
          final member = members.where((member) =>
              row['requested_by'] != null &&
              member['profile_id'] == row['requested_by']);
          // A profile is authoritative when present, even if its name is blank.
          // Members are only a fallback for demo data without that profile.
          final name = _nonBlankName(profile.isNotEmpty
              ? profile.first['full_name']
              : member.isNotEmpty
                  ? member.first['full_name']
                  : null);
          return {
            'id': row['id'],
            'request_type': row['request_type'],
            'description': row['description'],
            'amount': row['amount'],
            'requested_by': row['requested_by'],
            'requester_name': name,
            'requester_name_missing': name == null,
            '_created_at': row['created_at'],
            'status': row['status'],
          };
        }).toList();
    }
  }

  Future<Map<String, dynamic>> _demoSummary() async {
    final financial = _can(AppPermission.viewTreasury);
    final result = <String, dynamic>{'can_view_financial': financial};
    final counts = <String, dynamic>{};
    for (final indicator in DashboardIndicator.values) {
      if ((indicator.monetary && !financial) ||
          (indicator == DashboardIndicator.pendingApprovals &&
              !_can(AppPermission.approveExpenseRequests))) {
        result[indicator.key] = indicator.monetary ? null : 0;
        counts[indicator.key] = indicator.monetary ? null : 0;
        continue;
      }
      final rows = await _demoIndicatorRows(indicator);
      result[indicator.key] = indicator.monetary ? _sum(rows) : rows.length;
      counts[indicator.key] = rows.length;
    }
    result['indicator_row_counts'] = counts;
    // This pre-existing non-monetary alert remains independent of the cards.
    final fees = await _list('fee_obligations');
    result['overdue_fees'] = fees.where((row) {
      final due = DateTime.tryParse(row['due_date']?.toString() ?? '');
      return _pending(row) > 0 && due != null && due.isBefore(_today);
    }).length;
    result['monthly_income'] = null;
    result['monthly_expense'] = null;
    if (financial) {
      final transactions = await _list('financial_transactions');
      final now = _now();
      for (final kind in ['income', 'expense']) {
        result['monthly_${kind == 'income' ? 'income' : 'expense'}'] =
            transactions.where((row) {
          final date =
              DateTime.tryParse(row['transaction_date']?.toString() ?? '');
          return row['kind'] == kind &&
              date?.year == now.year &&
              date?.month == now.month;
        }).fold<double>(0, (total, row) => total + _number(row['amount']));
      }
    }
    final announcements = await _list('announcements');
    result['unread_announcements'] = announcements
        .where((row) => row['requires_acknowledgement'] == true)
        .length;
    return result;
  }
}

double _number(Object? value) => value is num
    ? value.toDouble()
    : double.tryParse(value?.toString() ?? '') ?? 0;

double _pending(Map<String, dynamic> row) =>
    math.max(_number(row['amount']) - _number(row['paid_amount']), 0);

double _sum(List<Map<String, dynamic>> rows) =>
    rows.fold<double>(0, (total, row) => total + _number(row['_value']));

String? _memberName(List<Map<String, dynamic>> members, Object? id) {
  final matches = members.where((row) => id != null && row['id'] == id);
  return matches.isEmpty ? null : matches.first['full_name']?.toString();
}

Map<String, dynamic> _publicRow(Map<String, dynamic> row) =>
    Map.fromEntries(row.entries.where((entry) => !entry.key.startsWith('_')));

String? _nonBlankName(Object? value) {
  final name = value?.toString().trim();
  return name == null || name.isEmpty ? null : name;
}

String? _dateKey(Object? value) =>
    value?.toString().split('T').first.split(' ').first;

bool _validDateKey(String value) {
  final parsed = DateTime.tryParse(value);
  return parsed != null &&
      RegExp(r'^\d{4}-\d{2}-\d{2}$').hasMatch(value) &&
      parsed.toIso8601String().split('T').first == value;
}

int _compareDemoCursors(Map<String, dynamic> a, Map<String, dynamic> b) {
  for (final key in ['number', 'date', 'time', 'text', 'id']) {
    final left = a[key];
    final right = b[key];
    if (left == null && right == null) continue;
    if (left == null) return 1;
    if (right == null) return -1;
    final comparison = switch (key) {
      'number' => (left as num).compareTo(right as num),
      'date' || 'time' => DateTime.parse(left as String)
          .compareTo(DateTime.parse(right as String)),
      _ => (left as String).compareTo(right as String),
    };
    if (comparison != 0) return comparison;
  }
  return 0;
}
