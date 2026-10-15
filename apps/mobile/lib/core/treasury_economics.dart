double treasuryNumber(Object? value) => value is num
    ? value.toDouble()
    : double.tryParse(value?.toString() ?? '') ?? 0;

double treasuryOutstanding(Map<String, dynamic> row) {
  final value = treasuryNumber(row['amount']) - treasuryNumber(row['settled_amount']);
  return value > 0 ? value : 0;
}

bool treasuryObligationOverdue(
  Map<String, dynamic> row, {
  DateTime? today,
}) {
  if (row['status'] == 'paid' || row['status'] == 'cancelled') return false;
  final due = DateTime.tryParse(row['due_date']?.toString() ?? '');
  if (due == null) return false;
  final now = today ?? DateTime.now();
  final day = DateTime(now.year, now.month, now.day);
  return due.isBefore(day);
}

List<Map<String, dynamic>> effectiveTreasuryRows(
  Iterable<Map<String, dynamic>> rows,
) {
  final materialized = rows.toList(growable: false);
  final reversedIds = materialized
      .map((row) => row['reversal_of']?.toString())
      .whereType<String>()
      .where((id) => id.isNotEmpty)
      .toSet();

  return materialized.where((row) {
    final id = row['id']?.toString();
    if (row['reversal_of'] != null) return false;
    if (id != null && reversedIds.contains(id)) return false;
    return true;
  }).toList();
}
