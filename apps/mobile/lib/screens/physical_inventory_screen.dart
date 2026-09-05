import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../core/app_session.dart';
import '../core/permissions.dart';
import '../repositories/inventory_control_repository.dart';

class PhysicalInventoryScreen extends StatefulWidget {
  const PhysicalInventoryScreen({super.key});
  @override
  State<PhysicalInventoryScreen> createState() =>
      _PhysicalInventoryScreenState();
}

class _PhysicalInventoryScreenState extends State<PhysicalInventoryScreen> {
  final _repo = InventoryControlRepository();
  late Future<List<Map<String, dynamic>>> _future;
  bool get _canCount =>
      AppSession.instance.can(AppPermission.performInventoryCount);
  @override
  void initState() {
    super.initState();
    _reload();
  }

  void _reload() => _future = _repo.countSessions();
  Future<void> _refresh() async {
    setState(() {
      _reload();
    });
    await _future;
  }

  Future<void> _newCount() async {
    try {
      final data = await Future.wait([_repo.locations(), _repo.events()]);
      if (!mounted) return;
      final input = await showDialog<_StartInput>(
          context: context,
          builder: (_) => _StartDialog(locations: data[0], events: data[1]));
      if (input == null) return;
      final id = await _repo.startCount(
          name: input.name,
          locationId: input.locationId,
          eventId: input.eventId,
          notes: input.notes);
      if (!mounted) return;
      await Navigator.of(context).push(MaterialPageRoute(
          builder: (_) =>
              _CountSessionScreen(sessionId: id, name: input.name)));
      setState(() {
        _reload();
      });
    } catch (e) {
      _error(e);
    }
  }

  void _error(Object e) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(e.toString())));
  }

  @override
  Widget build(BuildContext context) =>
      FutureBuilder<List<Map<String, dynamic>>>(
          future: _future,
          builder: (context, s) {
            if (s.hasError) return Center(child: Text('Erro: ${s.error}'));
            if (!s.hasData) {
              return const Center(child: CircularProgressIndicator());
            }
            final rows = s.data!;
            return RefreshIndicator(
                onRefresh: _refresh,
                child: ListView(
                    padding: const EdgeInsets.fromLTRB(16, 16, 16, 96),
                    children: [
                      Row(children: [
                        Expanded(
                            child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                              Text('Inventário Físico',
                                  style: Theme.of(context)
                                      .textTheme
                                      .headlineSmall
                                      ?.copyWith(fontWeight: FontWeight.w900)),
                              const SizedBox(height: 4),
                              const Text(
                                  'Conta stock real, revê diferenças e aplica ajustes apenas após confirmação.')
                            ])),
                        if (_canCount)
                          FilledButton.icon(
                              onPressed: _newCount,
                              icon: const Icon(Icons.add),
                              label: const Text('Nova contagem'))
                      ]),
                      const SizedBox(height: 16),
                      if (rows.isEmpty)
                        const Card(
                            child: ListTile(
                                title: Text(
                                    'Ainda não existem sessões de inventário.')))
                      else
                        for (final r in rows) _sessionCard(r),
                    ]));
          });

  Widget _sessionCard(Map<String, dynamic> r) {
    final status = r['status']?.toString() ?? 'draft';
    final loc = r['inventory_locations'];
    final event = r['events'];
    return Card(
        child: ListTile(
            leading: CircleAvatar(
                child: Icon(status == 'completed'
                    ? Icons.check
                    : Icons.fact_check_outlined)),
            title: Text(r['name']?.toString() ?? 'Inventário'),
            subtitle: Text([
              _status(status),
              if (loc is Map) 'Local: ${loc['name']}',
              if (event is Map) 'Evento: ${event['name']}',
              'Início: ${_dateTime(r['started_at'])}'
            ].join(' · ')),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => Navigator.of(context)
                .push(MaterialPageRoute(
                    builder: (_) => _CountSessionScreen(
                        sessionId: r['id'].toString(),
                        name: r['name']?.toString() ?? 'Inventário',
                        readOnly: status == 'completed')))
                .then((_) => setState(() {
                      _reload();
                    }))));
  }
}

class _CountSessionScreen extends StatefulWidget {
  const _CountSessionScreen(
      {required this.sessionId, required this.name, this.readOnly = false});
  final String sessionId, name;
  final bool readOnly;
  @override
  State<_CountSessionScreen> createState() => _CountSessionScreenState();
}

class _CountSessionScreenState extends State<_CountSessionScreen> {
  final _repo = InventoryControlRepository();
  late Future<List<Map<String, dynamic>>> _future;
  final _search = TextEditingController();
  bool get _canEdit =>
      !widget.readOnly &&
      AppSession.instance.can(AppPermission.performInventoryCount);
  @override
  void initState() {
    super.initState();
    _reload();
  }

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  void _reload() => _future = _repo.countItems(widget.sessionId);
  Future<void> _refresh() async {
    setState(() {
      _reload();
    });
    await _future;
  }

  void _error(Object e) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(e.toString())));
  }

  Future<void> _edit(Map<String, dynamic> row) async {
    final input = await showDialog<_CountInput>(
        context: context, builder: (_) => _CountDialog(row: row));
    if (input == null) return;
    try {
      await _repo.setCount(
          itemId: row['id'].toString(),
          counted: input.qty,
          notes: input.notes,
          recounted: input.recounted);
      setState(() {
        _reload();
      });
    } catch (e) {
      _error(e);
    }
  }

  Future<void> _finalize(List<Map<String, dynamic>> rows) async {
    if (rows.any((r) => r['counted_qty'] == null)) {
      _error('Existem artigos por contar.');
      return;
    }
    final ok = await showDialog<bool>(
        context: context,
        builder: (c) => AlertDialog(
                title: const Text('Aplicar ajustes?'),
                content: const Text(
                    'Esta ação atualiza o stock real e cria movimentos de ajuste. Não deve ser feita antes de rever as diferenças.'),
                actions: [
                  TextButton(
                      onPressed: () => Navigator.pop(c, false),
                      child: const Text('Cancelar')),
                  FilledButton(
                      onPressed: () => Navigator.pop(c, true),
                      child: const Text('Aplicar ajustes'))
                ]));
    if (ok != true) return;
    try {
      final result = await _repo.finalize(widget.sessionId);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(
              'Inventário concluído · ${result['adjusted_items']} artigos ajustados.')));
      Navigator.pop(context);
    } catch (e) {
      _error(e);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
      appBar: AppBar(title: Text(widget.name)),
      body: FutureBuilder<List<Map<String, dynamic>>>(
          future: _future,
          builder: (context, s) {
            if (s.hasError) return Center(child: Text('Erro: ${s.error}'));
            if (!s.hasData) {
              return const Center(child: CircularProgressIndicator());
            }
            final all = s.data!;
            final q = _search.text.toLowerCase();
            final rows = all.where((r) {
              final p = r['products'];
              final v = r['product_variants'];
              return '${p is Map ? p['name'] : ''} ${v is Map ? v['name'] : ''}'
                  .toLowerCase()
                  .contains(q);
            }).toList();
            final counted = all.where((r) => r['counted_qty'] != null).length;
            final diffs = all
                .where((r) =>
                    _num(r['difference']) != 0 && r['counted_qty'] != null)
                .length;
            final value = all.fold<double>(0,
                (a, r) => a + (_num(r['difference']) * _num(r['unit_cost'])));
            return RefreshIndicator(
                onRefresh: _refresh,
                child: ListView(
                    padding: const EdgeInsets.fromLTRB(16, 16, 16, 96),
                    children: [
                      Wrap(spacing: 10, runSpacing: 10, children: [
                        _metric(context, 'Contados', '$counted/${all.length}',
                            Icons.checklist),
                        _metric(context, 'Diferenças', '$diffs',
                            Icons.compare_arrows),
                        _metric(
                            context,
                            'Impacto',
                            '${value.toStringAsFixed(2).replaceAll('.', ',')} €',
                            Icons.euro)
                      ]),
                      const SizedBox(height: 12),
                      TextField(
                          controller: _search,
                          onChanged: (_) => setState(() {}),
                          decoration: const InputDecoration(
                              prefixIcon: Icon(Icons.search),
                              labelText: 'Pesquisar artigo',
                              border: OutlineInputBorder())),
                      const SizedBox(height: 12),
                      if (_canEdit)
                        Align(
                            alignment: Alignment.centerRight,
                            child: FilledButton.icon(
                                onPressed: () => _finalize(all),
                                icon: const Icon(Icons.done_all),
                                label: const Text('Concluir inventário'))),
                      for (final r in rows) _item(r),
                    ]));
          }));

  Widget _item(Map<String, dynamic> r) {
    final p = r['products'];
    final v = r['product_variants'];
    final theoretical = _num(r['theoretical_qty']);
    final counted = r['counted_qty'] == null ? null : _num(r['counted_qty']);
    final diff = counted == null ? 0.0 : _num(r['difference']);
    final high = counted != null &&
        theoretical.abs() > 0 &&
        (diff.abs() / theoretical.abs()) >= .10;
    final name =
        '${p is Map ? p['name'] : 'Artigo'}${v is Map ? ' · ${v['name']}' : ''}';
    return Card(
        child: ListTile(
            onTap: _canEdit ? () => _edit(r) : null,
            leading: CircleAvatar(
                child: Icon(counted == null
                    ? Icons.help_outline
                    : diff == 0
                        ? Icons.check
                        : Icons.warning_amber)),
            title: Text(name),
            subtitle: Text([
              'Teórico: ${_qty(theoretical)}',
              'Contado: ${counted == null ? '—' : _qty(counted)}',
              'Diferença: ${counted == null ? '—' : '${diff > 0 ? '+' : ''}${_qty(diff)}'}',
              if (high) '⚠ Diferença elevada',
              if (r['recounted'] == true) 'Recontado',
              if ((r['notes']?.toString() ?? '').isNotEmpty)
                r['notes'].toString()
            ].join(' · ')),
            trailing: _canEdit ? const Icon(Icons.edit_outlined) : null));
  }
}

class _StartDialog extends StatefulWidget {
  const _StartDialog({required this.locations, required this.events});
  final List<Map<String, dynamic>> locations, events;
  @override
  State<_StartDialog> createState() => _StartDialogState();
}

class _StartDialogState extends State<_StartDialog> {
  final name = TextEditingController(
      text: 'Inventário ${DateFormat('MM/yyyy').format(DateTime.now())}');
  final notes = TextEditingController();
  String? locationId, eventId;
  @override
  void dispose() {
    name.dispose();
    notes.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
          title: const Text('Nova contagem'),
          content: SizedBox(
              width: 520,
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                TextField(
                    controller: name,
                    decoration: const InputDecoration(
                        labelText: 'Nome', border: OutlineInputBorder())),
                const SizedBox(height: 12),
                _drop(
                    'Local obrigatório',
                    locationId,
                    widget.locations,
                    (r) => r['name']?.toString() ?? '',
                    (v) => setState(() => locationId = v)),
                const SizedBox(height: 12),
                _drop(
                    'Evento (opcional)',
                    eventId,
                    widget.events,
                    (r) => r['name']?.toString() ?? '',
                    (v) => setState(() => eventId = v),
                    allowEmpty: true),
                const SizedBox(height: 12),
                TextField(
                    controller: notes,
                    maxLines: 2,
                    decoration: const InputDecoration(
                        labelText: 'Notas', border: OutlineInputBorder()))
              ])),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('Cancelar')),
            FilledButton(
                onPressed: locationId == null
                    ? null
                    : () => Navigator.pop(
                        context,
                        _StartInput(
                            name.text, locationId, eventId, notes.text)),
                child: const Text('Iniciar'))
          ]);
}

class _CountDialog extends StatefulWidget {
  const _CountDialog({required this.row});
  final Map<String, dynamic> row;
  @override
  State<_CountDialog> createState() => _CountDialogState();
}

class _CountDialogState extends State<_CountDialog> {
  late final TextEditingController qty, notes;
  bool recount = false;
  @override
  void initState() {
    super.initState();
    qty = TextEditingController(
        text: widget.row['counted_qty']?.toString() ?? '');
    notes = TextEditingController(text: widget.row['notes']?.toString() ?? '');
    recount = widget.row['recounted'] == true;
  }

  @override
  void dispose() {
    qty.dispose();
    notes.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
          title: const Text('Registar contagem'),
          content: Column(mainAxisSize: MainAxisSize.min, children: [
            Text('Stock teórico: ${_qty(_num(widget.row['theoretical_qty']))}'),
            const SizedBox(height: 12),
            TextField(
                controller: qty,
                autofocus: true,
                keyboardType:
                    const TextInputType.numberWithOptions(decimal: true),
                decoration: const InputDecoration(
                    labelText: 'Quantidade contada',
                    border: OutlineInputBorder())),
            const SizedBox(height: 12),
            TextField(
                controller: notes,
                maxLines: 2,
                decoration: const InputDecoration(
                    labelText: 'Notas / motivo', border: OutlineInputBorder())),
            CheckboxListTile(
                contentPadding: EdgeInsets.zero,
                value: recount,
                onChanged: (v) => setState(() => recount = v ?? false),
                title: const Text('Esta é uma recontagem'))
          ]),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('Cancelar')),
            FilledButton(
                onPressed: () => Navigator.pop(context,
                    _CountInput(_parse(qty.text), notes.text, recount)),
                child: const Text('Guardar'))
          ]);
}

Widget _metric(BuildContext c, String l, String v, IconData i) => SizedBox(
    width: 190,
    child: Card(
        child: ListTile(
            leading: CircleAvatar(child: Icon(i)),
            title: Text(l),
            subtitle: Text(v,
                style: Theme.of(c)
                    .textTheme
                    .titleLarge
                    ?.copyWith(fontWeight: FontWeight.w900)))));
Widget _drop(
        String label,
        String? value,
        List<Map<String, dynamic>> rows,
        String Function(Map<String, dynamic>) labelFor,
        ValueChanged<String?> onChanged,
        {bool allowEmpty = false}) =>
    DropdownButtonFormField<String>(
        initialValue: value,
        isExpanded: true,
        decoration: InputDecoration(
            labelText: label, border: const OutlineInputBorder()),
        items: [
          if (allowEmpty)
            const DropdownMenuItem<String>(value: null, child: Text('Nenhum')),
          ...rows.map((r) => DropdownMenuItem(
              value: r['id'].toString(),
              child: Text(labelFor(r), overflow: TextOverflow.ellipsis)))
        ],
        onChanged: onChanged);

class _StartInput {
  const _StartInput(this.name, this.locationId, this.eventId, this.notes);
  final String name, notes;
  final String? locationId, eventId;
}

class _CountInput {
  const _CountInput(this.qty, this.notes, this.recounted);
  final double qty;
  final String notes;
  final bool recounted;
}

double _num(Object? v) =>
    v is num ? v.toDouble() : double.tryParse(v?.toString() ?? '') ?? 0;
double _parse(String v) => double.tryParse(v.replaceAll(',', '.')) ?? 0;
String _qty(double v) => v == v.roundToDouble()
    ? v.toInt().toString()
    : v.toStringAsFixed(2).replaceAll('.', ',');
String _dateTime(Object? v) {
  final d = DateTime.tryParse(v?.toString() ?? '');
  return d == null ? '—' : DateFormat('dd/MM/yyyy HH:mm').format(d.toLocal());
}

String _status(String s) => switch (s) {
      'counting' => 'Em contagem',
      'review' => 'Em revisão',
      'completed' => 'Concluído',
      'cancelled' => 'Cancelado',
      _ => 'Rascunho'
    };
