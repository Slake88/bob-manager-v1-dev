/// Direct dinner result. All stock costs come from immutable sale-line snapshots.
class WeeklyDinnerFinance {
  const WeeklyDinnerFinance(this.data);
  final Map<String, dynamic> data;
  bool get closed => data['financial_status'] == 'closed';
  bool get hasUnclassifiedRevenue => number('excluded_revenue') > 0;
  bool get hasCosts => (data['missing_cost_count'] as num? ?? 0) == 0;
  bool get empty =>
      data['financial_status'] == 'none' &&
      number('total_revenue') == 0 &&
      number('food_cost') == 0 &&
      number('other_costs') == 0 &&
      rows('sales').isEmpty;
  double number(String key) => dinnerNumber(data[key]);
  List<Map<String, dynamic>> rows(String key) => (data[key] as List? ?? [])
      .map((row) => Map<String, dynamic>.from(row as Map))
      .toList();

  static WeeklyDinnerFinance calculate({
    required List<Map<String, dynamic>> lines,
    required List<Map<String, dynamic>> expenses,
    Map<String, dynamic> settings = const {},
  }) {
    double mealQuantity = 0,
        mealRevenue = 0,
        barRevenue = 0,
        barCost = 0,
        excluded = 0;
    var missing = 0, excludedLines = 0;
    for (final line in lines) {
      switch (line['component_override'] ?? line['dinner_component_snapshot']) {
        case 'meal':
          mealQuantity += dinnerNumber(line['quantity']);
          mealRevenue += dinnerNumber(line['line_total']);
        case 'bar':
          barRevenue += dinnerNumber(line['line_total']);
          if (line['cost_total_snapshot'] == null) {
            missing++;
          } else {
            barCost += dinnerNumber(line['cost_total_snapshot']);
          }
        case 'excluded':
          excludedLines++;
          excluded += dinnerNumber(line['line_total']);
        default:
          missing++;
      }
    }
    double foodLinked = 0, otherLinked = 0;
    for (final expense in expenses) {
      if (expense['reversed'] == true) continue;
      if (expense['cost_kind'] == 'food') {
        foodLinked += dinnerNumber(expense['amount']);
      } else {
        otherLinked += dinnerNumber(expense['amount']);
      }
    }
    // Live meal amounts only come from BAR lines; old manual settings are audit data.
    final quantity = mealQuantity;
    final revenue = mealRevenue;
    final food = foodLinked + dinnerNumber(settings['food_cost_manual']);
    final other = otherLinked + dinnerNumber(settings['other_cost_manual']);
    final totalRevenue = dinnerMoney(revenue + barRevenue);
    final totalCost = dinnerMoney(food + barCost + other);
    final result = dinnerMoney(totalRevenue - totalCost);
    return WeeklyDinnerFinance({
      ...settings,
      'meal_quantity': quantity,
      'meal_revenue': revenue,
      'food_cost': food,
      'meal_profit': dinnerMoney(revenue - food),
      'bar_meal_quantity': mealQuantity,
      'bar_meal_revenue': mealRevenue,
      'beverage_revenue': barRevenue,
      'beverage_cost': missing == 0 ? barCost : null,
      'beverage_profit':
          missing == 0 ? dinnerMoney(barRevenue - barCost) : null,
      'other_costs': other,
      'food_cost_linked': foodLinked,
      'other_cost_linked': otherLinked,
      'total_revenue': totalRevenue,
      'total_cost': missing == 0 ? totalCost : null,
      'result': missing == 0 ? result : null,
      'margin_percent': missing != 0
          ? null
          : totalRevenue > 0
              ? result / totalRevenue * 100
              : 0,
      'missing_cost_count': missing,
      'excluded_revenue': excluded,
      'excluded_line_count': excludedLines,
      'classification_lines': lines
          .where((line) =>
              line['dinner_component_snapshot'] == 'excluded' &&
              dinnerNumber(line['line_total']) > 0)
          .map((line) => <String, dynamic>{
                'sale_item_id': line['id'],
                'sale_id': line['sale_id'],
                'description': line['description'],
                'quantity': line['quantity'],
                'unit_price': line['unit_price'],
                'line_total': line['line_total'],
                'original_component': line['dinner_component_snapshot'],
                'component_override': line['component_override'],
                'effective_component': line['component_override'] ??
                    line['dinner_component_snapshot'],
              })
          .toList(),
      'expense_links': expenses,
    });
  }

  static Map<String, dynamic> annual(List<Map<String, dynamic>> rows) {
    final closed = rows.where((row) => row['financial_status'] == 'closed');
    double revenue = 0, cost = 0, result = 0;
    for (final row in closed) {
      final summary = Map<String, dynamic>.from(row['summary'] as Map);
      revenue += dinnerNumber(summary['total_revenue']);
      cost += dinnerNumber(summary['total_cost']);
      result += dinnerNumber(summary['result']);
    }
    return {
      'rows': rows,
      'closed_count': closed.length,
      'total_revenue': dinnerMoney(revenue),
      'total_cost': dinnerMoney(cost),
      'result': dinnerMoney(result),
      'margin_percent': revenue > 0 ? result / revenue * 100 : 0
    };
  }
}

double dinnerNumber(Object? value) => value is num
    ? value.toDouble()
    : double.tryParse(value?.toString() ?? '') ?? 0;
double dinnerMoney(num value) => (value * 100).round() / 100;
