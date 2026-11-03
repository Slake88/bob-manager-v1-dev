import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

String? suggestedDinnerForToday(
    List<Map<String, dynamic>> dinners, DateTime today) {
  final date = DateFormat('yyyy-MM-dd').format(today);
  final matches = dinners
      .where((d) =>
          d['dinner_date'] == date &&
          !['closed', 'cancelled'].contains(d['status']))
      .toList();
  return matches.length == 1 ? matches.single['id'].toString() : null;
}

class DinnerAssociationField extends StatelessWidget {
  const DinnerAssociationField(
      {super.key,
      required this.dinners,
      required this.value,
      required this.onChanged});
  final List<Map<String, dynamic>> dinners;
  final String? value;
  final ValueChanged<String?>? onChanged;
  @override
  Widget build(BuildContext context) => DropdownButtonFormField<String>(
      key: ValueKey('dinner-$value'),
      initialValue: value,
      isExpanded: true,
      decoration: const InputDecoration(
          labelText: 'Jantar associado', border: OutlineInputBorder()),
      items: [
        const DropdownMenuItem<String>(
            value: null, child: Text('Sem jantar associado')),
        ...dinners.map((d) => DropdownMenuItem(
            value: d['id'].toString(),
            child: Text(
                '${DateFormat('dd/MM/yyyy').format(DateTime.parse(d['dinner_date'].toString()))} · ${d['dish'] ?? 'Jantar'}',
                overflow: TextOverflow.ellipsis)))
      ],
      onChanged: onChanged);
}
