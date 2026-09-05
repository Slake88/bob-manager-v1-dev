import 'package:flutter/material.dart';

import '../core/fees_economics.dart';
import '../repositories/fees_operational_repository.dart';

class FeesSettingsOperationalScreen extends StatefulWidget {
  const FeesSettingsOperationalScreen({super.key});

  @override
  State<FeesSettingsOperationalScreen> createState() => _FeesSettingsOperationalScreenState();
}

class _FeesSettingsOperationalScreenState extends State<FeesSettingsOperationalScreen> {
  final FeesOperationalRepository _repository = FeesOperationalRepository();
  final TextEditingController _dueDay = TextEditingController();
  final TextEditingController _monthly = TextEditingController();
  final TextEditingController _registration = TextEditingController();
  bool _loading = true;
  bool _saving = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _dueDay.dispose();
    _monthly.dispose();
    _registration.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final settings = await _repository.settings();
      _dueDay.text = settings['due_day']?.toString() ?? '8';
      _monthly.text = feeNumber(settings['monthly_amount']).toStringAsFixed(2);
      _registration.text = feeNumber(settings['registration_amount']).toStringAsFixed(2);
    } catch (error) {
      _error = error.toString();
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _save() async {
    final day = int.tryParse(_dueDay.text.trim());
    if (day == null || day < 1 || day > 28) {
      _message('O dia de vencimento deve estar entre 1 e 28.');
      return;
    }
    if (feeNumber(_monthly.text) < 0 || feeNumber(_registration.text) < 0) {
      _message('Os valores não podem ser negativos.');
      return;
    }
    if (_repository.isDemo) {
      _message('O modo Demo é apenas de leitura.');
      return;
    }
    setState(() => _saving = true);
    try {
      await _repository.updateSettings(
        dueDay: day,
        monthlyAmount: feeNumber(_monthly.text),
        registrationAmount: feeNumber(_registration.text),
      );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Configuração de quotas atualizada.')),
        );
        Navigator.pop(context);
      }
    } catch (error) {
      if (mounted) _message(_friendly(error));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Configuração de quotas')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? Center(child: Text('Erro: $_error'))
              : ListView(
                  padding: const EdgeInsets.fromLTRB(16, 16, 16, 96),
                  children: [
                    if (_repository.isDemo)
                      const Card(
                        child: ListTile(
                          leading: Icon(Icons.visibility_outlined),
                          title: Text('Modo Demo — apenas leitura'),
                        ),
                      ),
                    TextField(
                      controller: _dueDay,
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(
                        labelText: 'Dia de vencimento mensal',
                        helperText: 'Entre 1 e 28',
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: _monthly,
                      keyboardType: const TextInputType.numberWithOptions(decimal: true),
                      decoration: const InputDecoration(labelText: 'Mensalidade (€)'),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: _registration,
                      keyboardType: const TextInputType.numberWithOptions(decimal: true),
                      decoration: const InputDecoration(labelText: 'Inscrição (€)'),
                    ),
                    const SizedBox(height: 20),
                    FilledButton.icon(
                      onPressed: _saving || _repository.isDemo ? null : _save,
                      icon: const Icon(Icons.save_outlined),
                      label: const Text('Guardar configuração'),
                    ),
                    if (_saving) ...[
                      const SizedBox(height: 12),
                      const LinearProgressIndicator(),
                    ],
                  ],
                ),
    );
  }

  void _message(String value) => ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(value)));
}

String _friendly(Object error) => error.toString().replaceFirst('StateError: ', '').replaceFirst('Invalid argument(s): ', '');
