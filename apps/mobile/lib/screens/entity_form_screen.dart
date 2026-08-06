import 'package:flutter/material.dart';

import '../core/entity_definition.dart';
import '../services/data_service.dart';

typedef EntitySaveHandler = Future<void> Function(
  Map<String, dynamic> values,
  String? entityId,
);

class EntityFormScreen extends StatefulWidget {
  const EntityFormScreen({
    super.key,
    required this.definition,
    this.initialValues,
    this.onSave,
  });

  final EntityDefinition definition;
  final Map<String, dynamic>? initialValues;
  final EntitySaveHandler? onSave;

  bool get isEditing => initialValues?['id'] != null;

  @override
  State<EntityFormScreen> createState() => _EntityFormScreenState();
}

class _EntityFormScreenState extends State<EntityFormScreen> {
  final GlobalKey<FormState> _formKey = GlobalKey<FormState>();
  final Map<String, TextEditingController> _controllers = {};
  final Map<String, bool> _booleanValues = {};
  final Map<String, String?> _choiceValues = {};
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    for (final field in widget.definition.fields) {
      final value = widget.initialValues?[field.key];
      if (field.type == EntityFieldType.boolean) {
        _booleanValues[field.key] = value == true || value?.toString() == 'true';
      } else if (field.type == EntityFieldType.choice) {
        final text = value?.toString();
        _choiceValues[field.key] = field.choices.contains(text) ? text : null;
      } else {
        _controllers[field.key] = TextEditingController(
          text: value?.toString() ?? '',
        );
      }
    }
  }

  @override
  void dispose() {
    for (final controller in _controllers.values) {
      controller.dispose();
    }
    super.dispose();
  }

  Future<void> _pickDate(
    EntityFieldDefinition field,
    TextEditingController controller,
  ) async {
    final current = DateTime.tryParse(controller.text);
    final picked = await showDatePicker(
      context: context,
      firstDate: DateTime(1900),
      lastDate: DateTime(2100),
      initialDate: current ?? DateTime.now(),
    );
    if (picked == null) return;
    controller.text = picked.toIso8601String().split('T').first;
  }

  Future<void> _pickDateTime(
    EntityFieldDefinition field,
    TextEditingController controller,
  ) async {
    final current = DateTime.tryParse(controller.text) ?? DateTime.now();
    final date = await showDatePicker(
      context: context,
      firstDate: DateTime(2000),
      lastDate: DateTime(2100),
      initialDate: current,
    );
    if (date == null || !mounted) return;
    final time = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(current),
    );
    if (time == null) return;
    controller.text = DateTime(
      date.year,
      date.month,
      date.day,
      time.hour,
      time.minute,
    ).toIso8601String();
  }

  dynamic _valueFor(EntityFieldDefinition field) {
    if (field.type == EntityFieldType.boolean) {
      return _booleanValues[field.key] ?? false;
    }
    if (field.type == EntityFieldType.choice) {
      return _choiceValues[field.key];
    }

    final text = _controllers[field.key]?.text.trim() ?? '';
    if (text.isEmpty) return null;
    if (field.type == EntityFieldType.integer) return int.tryParse(text);
    if (field.type == EntityFieldType.decimal) {
      return double.tryParse(text.replaceAll(',', '.'));
    }
    return text;
  }

  Map<String, dynamic> _buildValues() {
    final values = <String, dynamic>{};
    for (final field in widget.definition.fields) {
      if (field.readOnly) continue;
      final value = _valueFor(field);
      if (value != null) values[field.key] = value;
    }

    if (widget.definition.table == 'fee_obligations') {
      final amount = (values['amount'] as num?)?.toDouble() ?? 0;
      final paid = (values['paid_amount'] as num?)?.toDouble() ?? 0;
      final credit = (values['credit_amount'] as num?)?.toDouble() ?? 0;
      values['balance'] = (amount - paid - credit).clamp(0, double.infinity);
      if (values['balance'] == 0 && amount > 0) {
        values['status'] = 'paid';
      } else if (paid > 0) {
        values['status'] = 'partial';
      }
    }

    return values;
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _saving = true);
    try {
      final values = _buildValues();
      final id = widget.initialValues?['id']?.toString();
      if (widget.onSave != null) {
        await widget.onSave!(values, id);
      } else if (widget.isEditing) {
        await DataService.instance.update(
          widget.definition.table,
          id!,
          values,
        );
      } else {
        await DataService.instance.insert(widget.definition.table, values);
      }
      if (!mounted) return;
      Navigator.of(context).pop(true);
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Não foi possível guardar: $error')),
      );
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Widget _buildField(EntityFieldDefinition field) {
    if (field.type == EntityFieldType.boolean) {
      return SwitchListTile(
        contentPadding: EdgeInsets.zero,
        title: Text(field.label),
        value: _booleanValues[field.key] ?? false,
        onChanged: field.readOnly
            ? null
            : (value) => setState(() => _booleanValues[field.key] = value),
      );
    }

    if (field.type == EntityFieldType.choice) {
      return DropdownButtonFormField<String>(
        initialValue: _choiceValues[field.key],
        decoration: InputDecoration(labelText: field.label),
        items: field.choices
            .map(
              (choice) => DropdownMenuItem<String>(
                value: choice,
                child: Text(choice),
              ),
            )
            .toList(),
        onChanged: field.readOnly
            ? null
            : (value) => setState(() => _choiceValues[field.key] = value),
        validator: field.required
            ? (value) => value == null ? 'Campo obrigatório.' : null
            : null,
      );
    }

    final controller = _controllers[field.key]!;
    final isDate = field.type == EntityFieldType.date;
    final isDateTime = field.type == EntityFieldType.dateTime;
    final isNumber = field.type == EntityFieldType.integer ||
        field.type == EntityFieldType.decimal;

    return TextFormField(
      controller: controller,
      readOnly: field.readOnly || isDate || isDateTime,
      maxLines: field.type == EntityFieldType.multiline ? 4 : 1,
      keyboardType: isNumber
          ? const TextInputType.numberWithOptions(decimal: true)
          : TextInputType.text,
      decoration: InputDecoration(
        labelText: field.label,
        suffixIcon: isDate || isDateTime
            ? IconButton(
                onPressed: field.readOnly
                    ? null
                    : () => isDate
                        ? _pickDate(field, controller)
                        : _pickDateTime(field, controller),
                icon: const Icon(Icons.calendar_month_outlined),
              )
            : null,
      ),
      validator: field.required
          ? (value) => value == null || value.trim().isEmpty
              ? 'Campo obrigatório.'
              : null
          : null,
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(
          widget.isEditing
              ? 'Editar ${widget.definition.singularTitle}'
              : 'Novo ${widget.definition.singularTitle}',
        ),
        actions: [
          TextButton.icon(
            onPressed: _saving ? null : _save,
            icon: _saving
                ? const SizedBox.square(
                    dimension: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.save_outlined),
            label: const Text('Guardar'),
          ),
        ],
      ),
      body: Form(
        key: _formKey,
        child: ListView.separated(
          padding: const EdgeInsets.all(16),
          itemCount: widget.definition.fields.length,
          separatorBuilder: (_, __) => const SizedBox(height: 12),
          itemBuilder: (context, index) =>
              _buildField(widget.definition.fields[index]),
        ),
      ),
    );
  }
}
