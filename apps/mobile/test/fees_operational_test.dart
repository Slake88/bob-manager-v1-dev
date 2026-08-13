import 'package:bob_manager_mobile/core/fees_economics.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  Map<String, dynamic> fee({
    required String id,
    required int month,
    double amount = 25,
    double paid = 0,
    double exempt = 0,
    double adjustment = 0,
    String due = '2026-01-08',
  }) {
    return <String, dynamic>{
      'id': id,
      'reference_year': 2026,
      'reference_month': month,
      'obligation_type': 'monthly',
      'amount': amount,
      'paid_amount': paid,
      'exempt_amount': exempt,
      'adjustment_amount': adjustment,
      'due_date': due,
      'status': paid >= amount ? 'paid' : 'pending',
    };
  }

  test('saldo considera isenções e ajustes', () {
    final row = fee(
      id: 'jan',
      month: 1,
      amount: 25,
      paid: 5,
      exempt: 3,
      adjustment: 2,
    );
    expect(feeObligationTotal(row), 24);
    expect(feeObligationOutstanding(row), 19);
  });

  test('pagamento parcial fica numa única quota', () {
    final preview = previewFeeAllocation([
      fee(id: 'jan', month: 1),
      fee(id: 'fev', month: 2, due: '2026-02-08'),
    ], 10);
    expect(preview.allocations, hasLength(1));
    expect(preview.allocations.first['obligation_id'], 'jan');
    expect(preview.allocations.first['amount'], 10);
    expect(preview.excessCredit, 0);
  });

  test('um pagamento é distribuído por vários meses', () {
    final preview = previewFeeAllocation([
      fee(id: 'jan', month: 1),
      fee(id: 'fev', month: 2, due: '2026-02-08'),
      fee(id: 'mar', month: 3, due: '2026-03-08'),
    ], 60);
    expect(preview.allocations, hasLength(3));
    expect(preview.allocations[0]['amount'], 25);
    expect(preview.allocations[1]['amount'], 25);
    expect(preview.allocations[2]['amount'], 10);
    expect(preview.allocated, 60);
  });

  test('dívida mais antiga recebe primeiro', () {
    final preview = previewFeeAllocation([
      fee(id: 'mar', month: 3, due: '2026-03-08'),
      fee(id: 'jan', month: 1, due: '2026-01-08'),
      fee(id: 'fev', month: 2, due: '2026-02-08'),
    ], 25);
    expect(preview.allocations.single['obligation_id'], 'jan');
  });

  test('excesso do pagamento transforma-se em crédito', () {
    final preview = previewFeeAllocation([
      fee(id: 'jan', month: 1),
      fee(id: 'fev', month: 2, due: '2026-02-08'),
    ], 75);
    expect(preview.allocated, 50);
    expect(preview.excessCredit, 25);
  });

  test('quota paga ou isenta não é considerada vencida', () {
    final paid = fee(id: 'jan', month: 1, paid: 25);
    final exempt = fee(id: 'fev', month: 2, exempt: 25, due: '2026-02-08')
      ..['status'] = 'exempt';
    final today = DateTime(2026, 8, 13);
    expect(feeObligationOverdue(paid, today: today), isFalse);
    expect(feeObligationOverdue(exempt, today: today), isFalse);
  });
}
