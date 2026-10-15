import 'dart:math' as math;

double feeNumber(Object? value) {
  if (value is num) return value.toDouble();
  return double.tryParse(value?.toString().replaceAll(',', '.') ?? '') ?? 0;
}

double feeObligationTotal(Map<String, dynamic> row) {
  return math.max(
    0,
    feeNumber(row['amount']) +
        feeNumber(row['adjustment_amount']) -
        feeNumber(row['exempt_amount']),
  );
}

double feeObligationOutstanding(Map<String, dynamic> row) {
  return math.max(0, feeObligationTotal(row) - feeNumber(row['paid_amount']));
}

bool feeObligationOverdue(
  Map<String, dynamic> row, {
  DateTime? today,
}) {
  if (feeObligationOutstanding(row) <= 0) return false;
  if (row['status'] == 'cancelled' || row['status'] == 'exempt') return false;
  final due = DateTime.tryParse(row['due_date']?.toString() ?? '');
  if (due == null) return false;
  final now = today ?? DateTime.now();
  final day = DateTime(now.year, now.month, now.day);
  return due.isBefore(day);
}

class FeeAllocationPreview {
  const FeeAllocationPreview({
    required this.paymentAmount,
    required this.allocations,
    required this.allocated,
    required this.excessCredit,
    this.existingCredit = 0,
  });

  final double paymentAmount;
  final List<Map<String, dynamic>> allocations;
  final double allocated;
  final double excessCredit;
  final double existingCredit;

  factory FeeAllocationPreview.fromMap(Map<String, dynamic> map) {
    return FeeAllocationPreview(
      paymentAmount: feeNumber(map['payment_amount']),
      allocations: List<Map<String, dynamic>>.from(
        (map['allocations'] as List?) ?? const [],
      ),
      allocated: feeNumber(map['allocated']),
      excessCredit: feeNumber(map['excess_credit']),
      existingCredit: feeNumber(map['existing_credit']),
    );
  }
}

FeeAllocationPreview previewFeeAllocation(
  Iterable<Map<String, dynamic>> obligations,
  double paymentAmount,
) {
  if (paymentAmount <= 0) {
    return const FeeAllocationPreview(
      paymentAmount: 0,
      allocations: [],
      allocated: 0,
      excessCredit: 0,
    );
  }

  final rows = obligations
      .where((row) => feeObligationOutstanding(row) > 0)
      .toList(growable: false)
    ..sort(_compareFeeObligations);

  var remaining = paymentAmount;
  final allocations = <Map<String, dynamic>>[];
  for (final row in rows) {
    if (remaining <= 0) break;
    final outstanding = feeObligationOutstanding(row);
    final applied = math.min(remaining, outstanding);
    allocations.add(<String, dynamic>{
      'obligation_id': row['id'],
      'reference_year': row['reference_year'],
      'reference_month': row['reference_month'],
      'obligation_type': row['obligation_type'],
      'due_date': row['due_date'],
      'amount': applied,
      'outstanding_before': outstanding,
    });
    remaining -= applied;
  }

  return FeeAllocationPreview(
    paymentAmount: paymentAmount,
    allocations: allocations,
    allocated: paymentAmount - remaining,
    excessCredit: math.max(0, remaining),
  );
}

int _compareFeeObligations(
  Map<String, dynamic> a,
  Map<String, dynamic> b,
) {
  final dueA = DateTime.tryParse(a['due_date']?.toString() ?? '');
  final dueB = DateTime.tryParse(b['due_date']?.toString() ?? '');
  if (dueA != null && dueB != null) {
    final compared = dueA.compareTo(dueB);
    if (compared != 0) return compared;
  } else if (dueA != null) {
    return -1;
  } else if (dueB != null) {
    return 1;
  }

  final yearA = int.tryParse(a['reference_year']?.toString() ?? '') ?? 9999;
  final yearB = int.tryParse(b['reference_year']?.toString() ?? '') ?? 9999;
  if (yearA != yearB) return yearA.compareTo(yearB);
  final monthA = int.tryParse(a['reference_month']?.toString() ?? '') ?? 0;
  final monthB = int.tryParse(b['reference_month']?.toString() ?? '') ?? 0;
  return monthA.compareTo(monthB);
}
