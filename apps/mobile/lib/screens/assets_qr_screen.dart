import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

import '../core/app_session.dart';
import '../core/permissions.dart';
import '../repositories/assets_operations_repository.dart';
import '../repositories/assets_qr_repository.dart';
import '../widgets/asset_identity_panel.dart';

class AssetsQrScreen extends StatefulWidget {
  const AssetsQrScreen({super.key});

  @override
  State<AssetsQrScreen> createState() => _AssetsQrScreenState();
}

class _AssetsQrScreenState extends State<AssetsQrScreen> {
  final AssetsQrRepository _qr = AssetsQrRepository();
  final AssetsOperationsRepository _operations = AssetsOperationsRepository();
  final TextEditingController _manual = TextEditingController();
  final MobileScannerController _scanner = MobileScannerController(
    formats: const [BarcodeFormat.qrCode],
  );

  bool _scanning = false;
  bool _loading = false;
  bool _scanLocked = false;
  Map<String, dynamic>? _asset;
  Map<String, dynamic>? _loan;
  List<Map<String, dynamic>> _timeline = const [];

  bool get _canManage => AppSession.instance.can(AppPermission.manageAssets);

  @override
  void dispose() {
    _manual.dispose();
    _scanner.dispose();
    super.dispose();
  }

  void _error(Object error) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(error.toString())),
    );
  }

  Future<void> _lookup(String value) async {
    if (_loading) return;
    final clean = value.trim();
    if (clean.isEmpty) return;
    setState(() {
      _loading = true;
      _scanning = false;
    });
    try {
      final asset = await _qr.findByQr(clean);
      if (asset == null) {
        if (!mounted) return;
        setState(() {
          _asset = null;
          _loan = null;
          _timeline = const [];
        });
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('QR não encontrado no património deste clube.')),
        );
        return;
      }
      final assetId = asset['id'].toString();
      final values = await Future.wait<dynamic>([
        _qr.activeLoan(assetId),
        _qr.timeline(assetId),
      ]);
      if (!mounted) return;
      setState(() {
        _asset = asset;
        _loan = values[0] as Map<String, dynamic>?;
        _timeline = List<Map<String, dynamic>>.from(values[1] as List);
        _manual.text = asset['qr_code']?.toString() ?? clean;
      });
    } catch (error) {
      _error(error);
    } finally {
      if (mounted) setState(() => _loading = false);
      _scanLocked = false;
    }
  }

  Future<void> _reloadCurrent() async {
    final code = _asset?['qr_code']?.toString() ?? _manual.text;
    if (code.isNotEmpty) await _lookup(code);
  }

  void _onDetect(BarcodeCapture capture) {
    if (_scanLocked || capture.barcodes.isEmpty) return;
    final value = capture.barcodes.first.rawValue;
    if (value == null || value.trim().isEmpty) return;
    _scanLocked = true;
    _lookup(value);
  }

  Future<void> _loanAsset() async {
    final asset = _asset;
    if (asset == null) return;
    try {
      final values = await Future.wait<dynamic>([_qr.members(), _qr.events()]);
      if (!mounted) return;
      final input = await showDialog<_QrLoanInput>(
        context: context,
        builder: (_) => _QrLoanDialog(
          members: List<Map<String, dynamic>>.from(values[0] as List),
          events: List<Map<String, dynamic>>.from(values[1] as List),
        ),
      );
      if (input == null) return;
      await _operations.loan(
        assetId: asset['id'].toString(),
        borrowerType: input.type,
        memberId: input.memberId,
        eventId: input.eventId,
        externalName: input.externalName,
        expectedReturn: input.expectedReturn,
        notes: input.notes,
      );
      await _reloadCurrent();
    } catch (error) {
      _error(error);
    }
  }

  Future<void> _returnAsset() async {
    final loan = _loan;
    if (loan == null) return;
    final input = await showDialog<_QrReturnInput>(
      context: context,
      builder: (_) => const _QrReturnDialog(),
    );
    if (input == null) return;
    try {
      await _operations.returnLoan(
        loanId: loan['id'].toString(),
        condition: input.condition,
        notes: input.notes,
      );
      await _reloadCurrent();
    } catch (error) {
      _error(error);
    }
  }

  Future<void> _intervention(String type) async {
    final asset = _asset;
    if (asset == null) return;
    try {
      final accounts = await _qr.accounts();
      if (!mounted) return;
      final input = await showDialog<_QrMaintenanceInput>(
        context: context,
        builder: (_) => _QrMaintenanceDialog(type: type, accounts: accounts),
      );
      if (input == null) return;
      await _operations.maintenance(
        assetId: asset['id'].toString(),
        type: type,
        date: input.date,
        description: input.description,
        cost: input.cost,
        supplier: input.supplier,
        nextDue: input.nextDue,
        accountId: input.accountId,
        paymentMethod: input.paymentMethod,
        postFinancial: input.postFinancial,
      );
      await _reloadCurrent();
    } catch (error) {
      _error(error);
    }
  }

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 96),
      children: [
        Text(
          'QR Património',
          style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w900),
        ),
        const SizedBox(height: 4),
        const Text('Lê a etiqueta QR para abrir o equipamento e executar ações rápidas.'),
        const SizedBox(height: 16),
        Wrap(
          spacing: 10,
          runSpacing: 10,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            FilledButton.icon(
              onPressed: () => setState(() {
                _scanLocked = false;
                _scanning = !_scanning;
              }),
              icon: Icon(_scanning ? Icons.close : Icons.qr_code_scanner),
              label: Text(_scanning ? 'Fechar câmara' : 'Ler QR'),
            ),
            SizedBox(
              width: 260,
              child: TextField(
                controller: _manual,
                textCapitalization: TextCapitalization.characters,
                decoration: InputDecoration(
                  labelText: 'Código QR manual',
                  hintText: 'QR-0001 ou BOB:ASSET:QR-0001',
                  border: const OutlineInputBorder(),
                  suffixIcon: IconButton(
                    tooltip: 'Procurar',
                    onPressed: _loading ? null : () => _lookup(_manual.text),
                    icon: const Icon(Icons.search),
                  ),
                ),
                onSubmitted: _lookup,
              ),
            ),
          ],
        ),
        if (_scanning) ...[
          const SizedBox(height: 12),
          Card(
            clipBehavior: Clip.antiAlias,
            child: SizedBox(
              height: 330,
              child: Stack(
                fit: StackFit.expand,
                children: [
                  MobileScanner(controller: _scanner, onDetect: _onDetect),
                  IgnorePointer(
                    child: Center(
                      child: Container(
                        width: 220,
                        height: 220,
                        decoration: BoxDecoration(
                          border: Border.all(color: Colors.white, width: 3),
                          borderRadius: BorderRadius.circular(20),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
        if (_loading) ...[
          const SizedBox(height: 20),
          const Center(child: CircularProgressIndicator()),
        ],
        if (!_loading && _asset != null) ...[
          const SizedBox(height: 16),
          _assetCard(context),
          const SizedBox(height: 12),
          _actionsCard(context),
          const SizedBox(height: 12),
          _historyCard(context),
        ],
      ],
    );
  }

  Widget _assetCard(BuildContext context) {
    final asset = _asset!;
    final location = asset['inventory_locations'];
    final member = asset['members'];
    final qr = asset['qr_code']?.toString() ?? '';
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: LayoutBuilder(
          builder: (context, constraints) {
            final compact = constraints.maxWidth < 650;
            final info = Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(asset['name']?.toString() ?? 'Bem', style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w900)),
                  Text('${asset['asset_number'] ?? ''} · ${asset['category'] ?? 'Outros'}'),
                  const SizedBox(height: 10),
                  Wrap(spacing: 8, runSpacing: 8, children: [
                    Chip(label: Text(_conditionLabel(asset['condition']?.toString()))),
                    if (location is Map) Chip(avatar: const Icon(Icons.place_outlined, size: 18), label: Text(location['name']?.toString() ?? '')),
                    if (member is Map) Chip(avatar: const Icon(Icons.person_outline, size: 18), label: Text(_memberName(member))),
                    if (_loan != null) const Chip(avatar: Icon(Icons.swap_horiz, size: 18), label: Text('Emprestado')),
                  ]),
                  if ((asset['brand']?.toString() ?? '').isNotEmpty || (asset['model']?.toString() ?? '').isNotEmpty) ...[
                    const SizedBox(height: 8),
                    Text('${asset['brand'] ?? ''} ${asset['model'] ?? ''}'.trim()),
                  ],
                  if ((asset['serial_number']?.toString() ?? '').isNotEmpty) Text('Série: ${asset['serial_number']}'),
                ],
              ),
            );
            final qrWidget = AssetIdentityPanel(
              assetNumber: asset['asset_number']?.toString() ?? '',
              qrCode: qr,
              name: asset['name']?.toString() ?? 'Bem',
              category: asset['category']?.toString() ?? 'Outros',
              condition: asset['condition']?.toString() ?? 'good',
              compact: compact,
            );
            if (compact) {
              return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [info, const SizedBox(height: 12), Center(child: qrWidget)]);
            }
            return Row(crossAxisAlignment: CrossAxisAlignment.start, children: [info, const SizedBox(width: 20), qrWidget]);
          },
        ),
      ),
    );
  }

  Widget _actionsCard(BuildContext context) {
    final loan = _loan;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Ações rápidas', style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800)),
            if (loan != null) ...[
              const SizedBox(height: 6),
              Text('Emprestado a: ${_loanDestination(loan)}${loan['expected_return_at'] != null ? ' · até ${_date(loan['expected_return_at'])}' : ''}'),
            ],
            const SizedBox(height: 12),
            Wrap(spacing: 10, runSpacing: 10, children: [
              if (_canManage && loan == null)
                FilledButton.icon(onPressed: _loanAsset, icon: const Icon(Icons.output), label: const Text('Emprestar')),
              if (_canManage && loan != null)
                FilledButton.icon(onPressed: _returnAsset, icon: const Icon(Icons.assignment_return), label: const Text('Devolver')),
              if (_canManage)
                OutlinedButton.icon(onPressed: () => _intervention('maintenance'), icon: const Icon(Icons.build_outlined), label: const Text('Manutenção')),
              if (_canManage)
                OutlinedButton.icon(onPressed: () => _intervention('inspection'), icon: const Icon(Icons.fact_check_outlined), label: const Text('Inspeção')),
              OutlinedButton.icon(onPressed: _reloadCurrent, icon: const Icon(Icons.refresh), label: const Text('Atualizar')),
            ]),
          ],
        ),
      ),
    );
  }

  Widget _historyCard(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Histórico do bem', style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800)),
            const SizedBox(height: 8),
            if (_timeline.isEmpty)
              const Text('Ainda não existem movimentos no histórico.')
            else
              for (final event in _timeline)
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: const CircleAvatar(child: Icon(Icons.history, size: 18)),
                  title: Text(event['title']?.toString() ?? 'Movimento'),
                  subtitle: Text([
                    if ((event['description']?.toString() ?? '').isNotEmpty) event['description'].toString(),
                    _dateTime(event['created_at']),
                  ].join('\n')),
                ),
          ],
        ),
      ),
    );
  }
}

class _QrLoanDialog extends StatefulWidget {
  const _QrLoanDialog({required this.members, required this.events});
  final List<Map<String, dynamic>> members;
  final List<Map<String, dynamic>> events;

  @override
  State<_QrLoanDialog> createState() => _QrLoanDialogState();
}

class _QrLoanDialogState extends State<_QrLoanDialog> {
  String type = 'member';
  String? memberId;
  String? eventId;
  DateTime? expectedReturn;
  final external = TextEditingController();
  final notes = TextEditingController();

  @override
  void dispose() {
    external.dispose();
    notes.dispose();
    super.dispose();
  }

  bool get valid => switch (type) {
        'member' => memberId != null,
        'event' => eventId != null,
        'external' => external.text.trim().isNotEmpty,
        _ => false,
      };

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Emprestar equipamento'),
      content: SizedBox(
        width: 520,
        child: SingleChildScrollView(
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            DropdownButtonFormField<String>(
              initialValue: type,
              decoration: const InputDecoration(labelText: 'Destino', border: OutlineInputBorder()),
              items: const [
                DropdownMenuItem(value: 'member', child: Text('Membro')),
                DropdownMenuItem(value: 'external', child: Text('Externo')),
                DropdownMenuItem(value: 'event', child: Text('Evento')),
              ],
              onChanged: (v) => setState(() => type = v ?? type),
            ),
            const SizedBox(height: 12),
            if (type == 'member')
              _drop('Membro', memberId, widget.members, (e) => _memberName(e), (v) => setState(() => memberId = v)),
            if (type == 'event')
              _drop('Evento', eventId, widget.events, (e) => e['name']?.toString() ?? '', (v) => setState(() => eventId = v)),
            if (type == 'external')
              TextField(controller: external, onChanged: (_) => setState(() {}), decoration: const InputDecoration(labelText: 'Nome / entidade', border: OutlineInputBorder())),
            const SizedBox(height: 12),
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.event),
              title: Text(expectedReturn == null ? 'Data prevista de devolução' : 'Devolução: ${DateFormat('dd/MM/yyyy').format(expectedReturn!)}'),
              trailing: IconButton(
                icon: const Icon(Icons.calendar_month),
                onPressed: () async {
                  final d = await showDatePicker(context: context, initialDate: DateTime.now(), firstDate: DateTime.now(), lastDate: DateTime.now().add(const Duration(days: 3650)));
                  if (d != null) setState(() => expectedReturn = d);
                },
              ),
            ),
            TextField(controller: notes, maxLines: 2, decoration: const InputDecoration(labelText: 'Notas', border: OutlineInputBorder())),
          ]),
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancelar')),
        FilledButton(
          onPressed: valid ? () => Navigator.pop(context, _QrLoanInput(type, memberId, eventId, external.text, expectedReturn, notes.text)) : null,
          child: const Text('Registar'),
        ),
      ],
    );
  }
}

class _QrReturnDialog extends StatefulWidget {
  const _QrReturnDialog();
  @override
  State<_QrReturnDialog> createState() => _QrReturnDialogState();
}

class _QrReturnDialogState extends State<_QrReturnDialog> {
  String condition = 'good';
  final notes = TextEditingController();

  @override
  void dispose() {
    notes.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
        title: const Text('Devolver equipamento'),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          DropdownButtonFormField<String>(
            initialValue: condition,
            decoration: const InputDecoration(labelText: 'Estado na devolução', border: OutlineInputBorder()),
            items: const [
              DropdownMenuItem(value: 'excellent', child: Text('Excelente')),
              DropdownMenuItem(value: 'good', child: Text('Bom')),
              DropdownMenuItem(value: 'regular', child: Text('Regular')),
              DropdownMenuItem(value: 'maintenance', child: Text('Necessita manutenção')),
              DropdownMenuItem(value: 'damaged', child: Text('Avariado')),
            ],
            onChanged: (v) => setState(() => condition = v ?? condition),
          ),
          const SizedBox(height: 12),
          TextField(controller: notes, maxLines: 2, decoration: const InputDecoration(labelText: 'Notas', border: OutlineInputBorder())),
        ]),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancelar')),
          FilledButton(onPressed: () => Navigator.pop(context, _QrReturnInput(condition, notes.text)), child: const Text('Confirmar')),
        ],
      );
}

class _QrMaintenanceDialog extends StatefulWidget {
  const _QrMaintenanceDialog({required this.type, required this.accounts});
  final String type;
  final List<Map<String, dynamic>> accounts;

  @override
  State<_QrMaintenanceDialog> createState() => _QrMaintenanceDialogState();
}

class _QrMaintenanceDialogState extends State<_QrMaintenanceDialog> {
  DateTime date = DateTime.now();
  DateTime? nextDue;
  final description = TextEditingController();
  final cost = TextEditingController(text: '0');
  final supplier = TextEditingController();
  String? accountId;
  String paymentMethod = 'Dinheiro';
  bool postFinancial = false;

  @override
  void initState() {
    super.initState();
    final caixa = widget.accounts.where((e) => e['name']?.toString().toLowerCase() == 'caixa');
    if (caixa.isNotEmpty) {
      accountId = caixa.first['id'].toString();
    } else if (widget.accounts.isNotEmpty) {
      accountId = widget.accounts.first['id'].toString();
    }
  }

  @override
  void dispose() {
    description.dispose();
    cost.dispose();
    supplier.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final inspection = widget.type == 'inspection';
    return AlertDialog(
      title: Text(inspection ? 'Registar inspeção' : 'Registar manutenção'),
      content: SizedBox(
        width: 520,
        child: SingleChildScrollView(
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            TextField(controller: description, maxLines: 2, decoration: InputDecoration(labelText: inspection ? 'Resultado / observações' : 'Descrição', border: const OutlineInputBorder())),
            const SizedBox(height: 12),
            TextField(controller: supplier, decoration: const InputDecoration(labelText: 'Fornecedor / oficina', border: OutlineInputBorder())),
            const SizedBox(height: 12),
            TextField(controller: cost, keyboardType: const TextInputType.numberWithOptions(decimal: true), decoration: const InputDecoration(labelText: 'Custo (€)', border: OutlineInputBorder())),
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.event),
              title: Text('Data: ${DateFormat('dd/MM/yyyy').format(date)}'),
              trailing: IconButton(
                icon: const Icon(Icons.calendar_month),
                onPressed: () async {
                  final d = await showDatePicker(context: context, initialDate: date, firstDate: DateTime(2020), lastDate: DateTime.now().add(const Duration(days: 3650)));
                  if (d != null) setState(() => date = d);
                },
              ),
            ),
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.update),
              title: Text(nextDue == null ? 'Próxima intervenção (opcional)' : 'Próxima: ${DateFormat('dd/MM/yyyy').format(nextDue!)}'),
              trailing: IconButton(
                icon: const Icon(Icons.calendar_month),
                onPressed: () async {
                  final d = await showDatePicker(context: context, initialDate: date.add(const Duration(days: 180)), firstDate: date, lastDate: DateTime.now().add(const Duration(days: 3650)));
                  if (d != null) setState(() => nextDue = d);
                },
              ),
            ),
            SwitchListTile(contentPadding: EdgeInsets.zero, value: postFinancial, onChanged: (v) => setState(() => postFinancial = v), title: const Text('Registar despesa na Tesouraria')),
            if (postFinancial && widget.accounts.isNotEmpty) ...[
              const SizedBox(height: 8),
              _drop('Conta / fundo', accountId, widget.accounts, (e) => e['name']?.toString() ?? '', (v) => setState(() => accountId = v)),
              const SizedBox(height: 12),
              DropdownButtonFormField<String>(
                initialValue: paymentMethod,
                decoration: const InputDecoration(labelText: 'Pagamento', border: OutlineInputBorder()),
                items: const ['Dinheiro', 'MB Way', 'Transferência bancária'].map((v) => DropdownMenuItem(value: v, child: Text(v))).toList(),
                onChanged: (v) => setState(() => paymentMethod = v ?? paymentMethod),
              ),
            ],
          ]),
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancelar')),
        FilledButton(
          onPressed: () => Navigator.pop(
            context,
            _QrMaintenanceInput(
              date,
              description.text,
              _parse(cost.text),
              supplier.text,
              nextDue,
              accountId,
              paymentMethod,
              postFinancial,
            ),
          ),
          child: const Text('Registar'),
        ),
      ],
    );
  }
}

Widget _drop(
  String label,
  String? value,
  List<Map<String, dynamic>> rows,
  String Function(Map<String, dynamic>) labelFor,
  ValueChanged<String?> onChanged,
) =>
    DropdownButtonFormField<String>(
      initialValue: value,
      isExpanded: true,
      decoration: InputDecoration(labelText: label, border: const OutlineInputBorder()),
      items: rows.map((e) => DropdownMenuItem(value: e['id'].toString(), child: Text(labelFor(e), overflow: TextOverflow.ellipsis))).toList(),
      onChanged: onChanged,
    );

class _QrLoanInput {
  const _QrLoanInput(this.type, this.memberId, this.eventId, this.externalName, this.expectedReturn, this.notes);
  final String type;
  final String? memberId;
  final String? eventId;
  final String externalName;
  final DateTime? expectedReturn;
  final String notes;
}

class _QrReturnInput {
  const _QrReturnInput(this.condition, this.notes);
  final String condition;
  final String notes;
}

class _QrMaintenanceInput {
  const _QrMaintenanceInput(this.date, this.description, this.cost, this.supplier, this.nextDue, this.accountId, this.paymentMethod, this.postFinancial);
  final DateTime date;
  final String description;
  final double cost;
  final String supplier;
  final DateTime? nextDue;
  final String? accountId;
  final String paymentMethod;
  final bool postFinancial;
}

String _memberName(Map<dynamic, dynamic> row) {
  final full = row['full_name']?.toString() ?? '';
  final nick = row['nickname']?.toString() ?? '';
  return nick.isEmpty ? full : '$full ($nick)';
}

String _loanDestination(Map<String, dynamic> loan) {
  final member = loan['members'];
  final event = loan['events'];
  if (member is Map) return _memberName(member);
  if (event is Map) return event['name']?.toString() ?? 'Evento';
  return loan['external_name']?.toString() ?? 'Externo';
}

String _conditionLabel(String? value) => switch (value) {
      'excellent' => 'Excelente',
      'good' => 'Bom',
      'regular' => 'Regular',
      'maintenance' => 'Necessita manutenção',
      'damaged' => 'Avariado',
      'retired' => 'Abatido',
      _ => 'Bom',
    };

String _date(Object? value) {
  final d = DateTime.tryParse(value?.toString() ?? '');
  return d == null ? '—' : DateFormat('dd/MM/yyyy').format(d);
}

String _dateTime(Object? value) {
  final d = DateTime.tryParse(value?.toString() ?? '');
  return d == null ? '—' : DateFormat('dd/MM/yyyy HH:mm').format(d.toLocal());
}

double _parse(String value) => double.tryParse(value.replaceAll(',', '.')) ?? 0;
