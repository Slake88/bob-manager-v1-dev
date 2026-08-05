import 'dart:math';

import 'package:supabase_flutter/supabase_flutter.dart';

import '../core/app_config.dart';
import '../core/app_session.dart';

class DataService {
  DataService._();

  static final DataService instance = DataService._();

  final Map<String, List<Map<String, dynamic>>> _demoStore =
      _createInitialDemoStore();

  Future<List<Map<String, dynamic>>> list(
    String table, {
    String order = 'created_at',
    int limit = 250,
  }) async {
    if (AppConfig.demoMode) {
      return _demoStore[table]
              ?.map((row) => Map<String, dynamic>.from(row))
              .toList() ??
          <Map<String, dynamic>>[];
    }

    final response = await Supabase.instance.client
        .from(table)
        .select()
        .eq('club_id', AppSession.instance.clubId)
        .limit(limit);

    return List<Map<String, dynamic>>.from(response);
  }

  Future<Map<String, dynamic>?> getById(String table, String id) async {
    if (AppConfig.demoMode) {
      final rows = _demoStore[table] ?? const <Map<String, dynamic>>[];
      for (final row in rows) {
        if (row['id']?.toString() == id) {
          return Map<String, dynamic>.from(row);
        }
      }
      return null;
    }

    final response = await Supabase.instance.client
        .from(table)
        .select()
        .eq('id', id)
        .eq('club_id', AppSession.instance.clubId)
        .maybeSingle();

    return response == null ? null : Map<String, dynamic>.from(response);
  }

  Future<Map<String, dynamic>> insert(
    String table,
    Map<String, dynamic> values,
  ) async {
    if (AppConfig.demoMode) {
      final row = <String, dynamic>{
        ...values,
        'id': values['id'] ?? _demoId(table),
        'created_at': values['created_at'] ?? DateTime.now().toIso8601String(),
      };
      _demoStore.putIfAbsent(table, () => <Map<String, dynamic>>[]).add(row);
      return Map<String, dynamic>.from(row);
    }

    final response = await Supabase.instance.client
        .from(table)
        .insert({...values, 'club_id': AppSession.instance.clubId})
        .select()
        .single();

    return Map<String, dynamic>.from(response);
  }

  Future<Map<String, dynamic>> update(
    String table,
    String id,
    Map<String, dynamic> values,
  ) async {
    if (AppConfig.demoMode) {
      final rows = _demoStore[table] ?? <Map<String, dynamic>>[];
      final index = rows.indexWhere((row) => row['id']?.toString() == id);
      if (index < 0) throw StateError('Registo não encontrado.');
      rows[index] = <String, dynamic>{
        ...rows[index],
        ...values,
        'updated_at': DateTime.now().toIso8601String(),
      };
      return Map<String, dynamic>.from(rows[index]);
    }

    final response = await Supabase.instance.client
        .from(table)
        .update({...values, 'updated_at': DateTime.now().toIso8601String()})
        .eq('id', id)
        .eq('club_id', AppSession.instance.clubId)
        .select()
        .single();

    return Map<String, dynamic>.from(response);
  }

  Future<void> delete(String table, String id) async {
    if (AppConfig.demoMode) {
      _demoStore[table]?.removeWhere((row) => row['id']?.toString() == id);
      return;
    }

    await Supabase.instance.client
        .from(table)
        .delete()
        .eq('id', id)
        .eq('club_id', AppSession.instance.clubId);
  }

  Future<Map<String, dynamic>> dashboard() async {
    if (AppConfig.demoMode) {
      final members = _demoStore['members'] ?? const <Map<String, dynamic>>[];
      final prospects = members
          .where((member) => member['status']?.toString() == 'prospect')
          .length;
      final transactions =
          _demoStore['financial_transactions'] ?? const <Map<String, dynamic>>[];
      final totalBalance = transactions.fold<double>(0, (total, transaction) {
        final amount = _asDouble(transaction['amount']);
        return transaction['kind'] == 'expense' ? total - amount : total + amount;
      });
      final feeOutstanding =
          (_demoStore['fee_obligations'] ?? const <Map<String, dynamic>>[])
              .fold<double>(0, (total, row) => total + _asDouble(row['balance']));
      final openEvents = (_demoStore['events'] ?? const <Map<String, dynamic>>[])
          .where((event) => !['completed', 'cancelled', 'archived']
              .contains(event['status']?.toString()))
          .length;
      final lowStock = (_demoStore['products'] ?? const <Map<String, dynamic>>[])
          .where((product) =>
              _asDouble(product['current_stock']) <=
              _asDouble(product['minimum_stock']))
          .length;

      return <String, dynamic>{
        'members': members.length,
        'prospects': prospects,
        'total_balance': totalBalance,
        'fee_outstanding': feeOutstanding,
        'open_events': openEvents,
        'low_stock': lowStock,
      };
    }

    final response = await Supabase.instance.client.rpc(
      'dashboard_summary',
      params: {'target_club': AppSession.instance.clubId},
    );
    return Map<String, dynamic>.from(response);
  }

  static double _asDouble(dynamic value) {
    if (value is num) return value.toDouble();
    return double.tryParse(value?.toString() ?? '') ?? 0;
  }

  String _demoId(String table) {
    final random = Random();
    return '${table.substring(0, min(table.length, 4))}-${DateTime.now().microsecondsSinceEpoch}-${random.nextInt(999)}';
  }

  static Map<String, List<Map<String, dynamic>>> _createInitialDemoStore() {
    return <String, List<Map<String, dynamic>>>{
      'members': <Map<String, dynamic>>[
        {
          'id': 'm1',
          'member_number': 1,
          'full_name': 'Israel Sousa',
          'nickname': 'Slake',
          'status': 'full_color',
          'primary_role': 'Presidente',
          'additional_roles': 'Administrador',
          'email': 'israel@example.pt',
          'phone': '910 000 001',
          'birth_date': '1977-03-12',
          'prospect_joined_at': '2020-01-15',
          'full_colors_at': '2020-10-20',
          'emergency_name': 'Contacto Israel',
          'emergency_relation': 'Família',
          'emergency_phone': '910 100 001',
          'blood_type': 'A+',
          'allergies': 'Sem alergias registadas',
          'medical_notes': '',
          'motorcycle_brand': 'Harley-Davidson',
          'motorcycle_model': 'Road Glide Limited',
          'motorcycle_year': 2026,
          'motorcycle_registration': 'AA-00-AA',
        },
        {
          'id': 'm2',
          'member_number': 2,
          'full_name': 'Fernando Martins',
          'nickname': 'Mineiro',
          'status': 'full_color',
          'primary_role': 'Road Captain',
          'phone': '910 000 002',
          'birth_date': '1980-05-22',
          'prospect_joined_at': '2021-02-10',
          'full_colors_at': '2021-11-06',
          'emergency_name': 'Ana Martins',
          'emergency_relation': 'Esposa',
          'emergency_phone': '910 100 002',
          'blood_type': 'O+',
          'motorcycle_brand': 'Harley-Davidson',
          'motorcycle_model': 'Street Glide',
          'motorcycle_year': 2022,
          'motorcycle_registration': 'BB-00-BB',
        },
        {
          'id': 'm3',
          'member_number': 3,
          'full_name': 'Carlos Pereira',
          'nickname': 'Lobo',
          'status': 'prospect',
          'primary_role': 'Prospect',
          'phone': '910 000 003',
          'birth_date': '1985-09-11',
          'prospect_joined_at': '2026-04-05',
          'emergency_name': 'Maria Pereira',
          'emergency_relation': 'Irmã',
          'emergency_phone': '910 100 003',
          'motorcycle_brand': 'Harley-Davidson',
          'motorcycle_model': 'Fat Bob',
          'motorcycle_year': 2020,
          'motorcycle_registration': 'CC-00-CC',
        },
      ],
      'financial_transactions': <Map<String, dynamic>>[
        {
          'id': 'tx1',
          'transaction_date': '2026-08-01',
          'kind': 'income',
          'description': 'Quotas de agosto',
          'amount': 75.0,
          'account_name': 'Banco CGD',
          'fund_name': 'Quotas',
          'cost_center_name': 'Quotas',
          'payment_method': 'Transferência bancária',
        },
        {
          'id': 'tx2',
          'transaction_date': '2026-08-02',
          'kind': 'expense',
          'description': 'Material do Club House',
          'amount': 38.5,
          'account_name': 'Caixa',
          'fund_name': 'Reserva',
          'cost_center_name': 'Club House',
          'payment_method': 'Dinheiro',
        },
      ],
      'fee_obligations': <Map<String, dynamic>>[
        {
          'id': 'f1',
          'member_name': 'Israel Sousa',
          'period_label': 'Agosto 2026',
          'due_date': '2026-08-10',
          'amount': 25.0,
          'paid_amount': 25.0,
          'credit_amount': 0.0,
          'balance': 0.0,
          'status': 'paid',
          'payment_method': 'Transferência bancária',
        },
        {
          'id': 'f2',
          'member_name': 'Fernando Martins',
          'period_label': 'Agosto 2026',
          'due_date': '2026-08-10',
          'amount': 25.0,
          'paid_amount': 10.0,
          'credit_amount': 0.0,
          'balance': 15.0,
          'status': 'partial',
          'payment_method': 'MB Way',
        },
        {
          'id': 'f3',
          'member_name': 'Carlos Pereira',
          'period_label': 'Agosto 2026',
          'due_date': '2026-08-10',
          'amount': 25.0,
          'paid_amount': 0.0,
          'credit_amount': 0.0,
          'balance': 25.0,
          'status': 'pending',
        },
      ],
      'lottery_participants': <Map<String, dynamic>>[
        {
          'id': 'lp1',
          'member_name': 'Israel Sousa',
          'billing_frequency': 'weekly',
          'participant_amount': 5.0,
          'numbers': '4, 12, 23, 37, 48',
          'stars': '3, 9',
          'paid_amount': 20.0,
          'balance': 0.0,
          'active': true,
        },
        {
          'id': 'lp2',
          'member_name': 'Fernando Martins',
          'billing_frequency': 'monthly',
          'participant_amount': 20.0,
          'numbers': '5, 16, 28, 34, 45',
          'stars': '2, 11',
          'paid_amount': 10.0,
          'balance': 10.0,
          'active': true,
        },
      ],
      'events': <Map<String, dynamic>>[
        {
          'id': 'e1',
          'name': 'Rock & Ride In Poceirão',
          'event_type': 'rock_ride',
          'status': 'planning',
          'starts_at': '2027-06-20T14:00:00',
          'ends_at': '2027-06-21T02:00:00',
          'location': 'Parque Mário Bento, Poceirão',
          'expected_attendance': 1800,
          'budget': 9600.0,
          'free_entry': true,
        },
        {
          'id': 'e2',
          'name': 'Passeio à Serra da Arrábida',
          'event_type': 'ride',
          'status': 'approved',
          'starts_at': '2026-09-13T09:00:00',
          'ends_at': '2026-09-13T17:00:00',
          'location': 'Club House',
          'expected_attendance': 25,
          'free_entry': true,
        },
      ],
      'products': <Map<String, dynamic>>[
        {
          'id': 'p1',
          'name': 'T-shirt Blue On Black',
          'sku': 'BOB-TS-XL',
          'category': 'Merchandising',
          'variant': 'Preto / XL',
          'location': 'Club House',
          'unit': 'unidade',
          'current_stock': 8.0,
          'reserved_stock': 2.0,
          'minimum_stock': 3.0,
          'cost': 9.5,
          'sale_price': 18.0,
          'active': true,
        },
        {
          'id': 'p2',
          'name': 'Cerveja',
          'sku': 'BAR-CERV',
          'category': 'Bebidas',
          'variant': 'Copo 0,25 L',
          'location': 'Club House',
          'unit': 'copo',
          'current_stock': 90.0,
          'reserved_stock': 0.0,
          'minimum_stock': 100.0,
          'cost': 0.63,
          'sale_price': 1.5,
          'active': true,
        },
      ],
      'documents': <Map<String, dynamic>>[
        {
          'id': 'd1',
          'name': 'Regulamento interno',
          'category': 'Regulamentos',
          'description': 'Versão aprovada pela direção.',
          'document_date': '2026-01-15',
          'version': '1.0',
          'status': 'approved',
          'sensitive': false,
          'tags': 'regulamento, clube',
        },
        {
          'id': 'd2',
          'name': 'Seguro do Club House',
          'category': 'Seguros',
          'document_date': '2026-02-01',
          'expires_at': '2027-02-01',
          'version': '2026',
          'status': 'approved',
          'sensitive': true,
          'tags': 'seguro, validade',
        },
      ],
      'announcements': <Map<String, dynamic>>[
        {
          'id': 'c1',
          'title': 'Próximo passeio',
          'body': 'Confirma a tua presença no passeio à Serra da Arrábida.',
          'priority': 'important',
          'audience': 'Todos os membros',
          'published_at': '2026-08-05T12:00:00',
          'requires_acknowledgement': true,
        },
        {
          'id': 'c2',
          'title': 'Reunião mensal',
          'body': 'Reunião no Club House na primeira sexta-feira do mês.',
          'priority': 'normal',
          'audience': 'Full Colors e Prospects',
          'published_at': '2026-08-01T18:00:00',
          'requires_acknowledgement': false,
        },
      ],
    };
  }
}
