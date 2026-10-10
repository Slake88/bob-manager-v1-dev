import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../core/app_session.dart';
import '../models/weekly_dinner_finance.dart';
import '../repositories/weekly_dinner_finance_repository.dart';

class WeeklyDinnerFinanceDialog extends StatefulWidget {
  const WeeklyDinnerFinanceDialog(
      {super.key, required this.dinner, required this.repository});
  final Map<String, dynamic> dinner;
  final WeeklyDinnerFinanceRepository repository;
  static Future<void> show(BuildContext context, Map<String, dynamic> dinner,
      WeeklyDinnerFinanceRepository repository) {
    final widget =
        WeeklyDinnerFinanceDialog(dinner: dinner, repository: repository);
    if (MediaQuery.sizeOf(context).width >= 700) {
      return showDialog<void>(
          context: context,
          builder: (context) => Dialog(
              child: SizedBox(
                  width: 720,
                  height: MediaQuery.sizeOf(context).height * .85,
                  child: widget)));
    }
    return showModalBottomSheet<void>(
        context: context,
        isScrollControlled: true,
        useSafeArea: true,
        builder: (context) => SizedBox(
            height: MediaQuery.sizeOf(context).height * .92, child: widget));
  }

  @override
  State<WeeklyDinnerFinanceDialog> createState() => _DinnerFinanceState();
}

class _DinnerFinanceState extends State<WeeklyDinnerFinanceDialog> {
  late Future<WeeklyDinnerFinance> _future;
  final _quantity = TextEditingController(),
      _revenue = TextEditingController(),
      _food = TextEditingController(),
      _other = TextEditingController(),
      _notes = TextEditingController();
  String _mode = 'automatic';
  bool _busy = false;
  late final String _club, _profile;
  final _money = NumberFormat.currency(locale: 'pt_PT', symbol: '€');
  String get id => widget.dinner['id'].toString();
  @override
  void initState() {
    super.initState();
    _club = AppSession.instance.clubId;
    _profile = AppSession.instance.profileId;
    _future = widget.repository.canRead
        ? _load()
        : Future.value(const WeeklyDinnerFinance({}));
  }

  @override
  void dispose() {
    for (final c in [_quantity, _revenue, _food, _other, _notes]) {
      c.dispose();
    }
    super.dispose();
  }

  bool get _sameSession =>
      _club == AppSession.instance.clubId &&
      _profile == AppSession.instance.profileId;
  Future<WeeklyDinnerFinance> _load() async {
    final detail = await widget.repository.detail(id);
    if (!_sameSession) {
      throw StateError('A sessão mudou. Abre novamente o jantar.');
    }
    _mode = detail.data['meal_mode']?.toString() ?? 'automatic';
    _quantity.text = '${detail.number('manual_meal_quantity')}';
    _revenue.text = '${detail.number('manual_meal_revenue')}';
    _food.text = '${detail.number('food_cost_manual')}';
    _other.text = '${detail.number('other_cost_manual')}';
    _notes.text = detail.data['notes']?.toString() ?? '';
    return detail;
  }

  double _value(TextEditingController controller) {
    final value = double.tryParse(controller.text.replaceAll(',', '.'));
    if (value == null || !value.isFinite || value < 0) {
      throw const FormatException('Indica valores não negativos.');
    }
    return value;
  }

  Future<void> _save() => widget.repository.save(id,
      mode: _mode,
      quantity: _value(_quantity),
      revenue: _value(_revenue),
      food: _value(_food),
      other: _value(_other),
      notes: _notes.text);
  Future<void> _act(Future<void> Function() action) async {
    setState(() => _busy = true);
    try {
      if (!_sameSession) throw StateError('A sessão mudou.');
      await action();
      if (mounted) {
        setState(() {
          _future = _load();
        });
      }
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('$error')));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Widget _amount(String label, Object? value) => ListTile(
      dense: true,
      title: Text(label),
      trailing: Text(value == null ? 'Não disponível' : _money.format(value)));
  Widget _input(String label, TextEditingController controller, bool enabled) =>
      Padding(
          padding: const EdgeInsets.symmetric(vertical: 6),
          child: TextField(
              controller: controller,
              enabled: enabled,
              keyboardType:
                  const TextInputType.numberWithOptions(decimal: true),
              onChanged: (_) => setState(() {}),
              decoration: InputDecoration(
                  labelText: label, border: const OutlineInputBorder())));
  Future<void> _choose(bool expense) async {
    try {
      final choices = await widget.repository.choices(id);
      if (!mounted || !_sameSession) return;
      final rows = (choices[expense ? 'expenses' : 'sales'] as List)
          .map((row) => Map<String, dynamic>.from(row as Map))
          .toList();
      var kind = 'food';
      final selected = await showDialog<Map<String, dynamic>>(
          context: context,
          builder: (context) => StatefulBuilder(
              builder: (context, setState) => AlertDialog(
                      title: Text(expense
                          ? 'Associar despesa'
                          : 'Associar venda existente'),
                      content: SizedBox(
                          width: 520,
                          height: 360,
                          child: Column(children: [
                            if (expense)
                              DropdownButton<String>(
                                  value: kind,
                                  items: const [
                                    DropdownMenuItem(
                                        value: 'food',
                                        child: Text('Comida/preparação')),
                                    DropdownMenuItem(
                                        value: 'other',
                                        child: Text('Outros custos'))
                                  ],
                                  onChanged: (v) => setState(() => kind = v!)),
                            if (!expense)
                              const Text(
                                  'Associação explícita; a data nunca associa vendas automaticamente.'),
                            Expanded(
                                child: rows.isEmpty
                                    ? const Center(
                                        child:
                                            Text('Sem registos disponíveis.'))
                                    : ListView(
                                        children: rows
                                            .map((row) => ListTile(
                                                title: Text(
                                                    '${row['description'] ?? row['customer_label'] ?? 'Venda'}'),
                                                subtitle: Text(
                                                    '${_dinnerDatePT(row['transaction_date'] ?? row['completed_at'], time: !expense)} · ${_money.format(row['amount'] ?? row['total_amount'] ?? 0)}'),
                                                onTap: () => Navigator.pop(
                                                    context, row)))
                                            .toList())),
                          ])),
                      actions: [
                        TextButton(
                            onPressed: () => Navigator.pop(context),
                            child: const Text('Cancelar'))
                      ])));
      if (selected == null) return;
      await _act(() async {
        if (expense) {
          await widget.repository
              .linkExpense(id, selected['id'].toString(), kind);
        } else {
          await widget.repository.assignSale(id, selected['id'].toString());
        }
      });
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('$error')));
      }
    }
  }

  Widget _classificationLine(Map<String, dynamic> line, bool edit,
      {bool undo = false}) {
    final itemId = line['sale_item_id'].toString();
    return ListTile(
      title: Text(
          '${line['description'] ?? 'Linha BAR'} · ${NumberFormat('0.###', 'pt_PT').format(dinnerNumber(line['quantity']))} × ${_money.format(line['unit_price'] ?? 0)} · ${_money.format(line['line_total'] ?? 0)}'),
      subtitle: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        if (undo)
          Text(line['component_override'] == 'meal'
              ? 'Classificada como refeição neste jantar'
              : 'Classificada como BAR neste jantar'),
        if (edit)
          TextButton(
            key: ValueKey('${undo ? 'undo' : 'classify'}-$itemId'),
            onPressed: () => _act(() => widget.repository
                .classifySaleItem(id, itemId, component: undo ? null : 'meal')),
            child: Text(
                undo ? 'Desfazer classificação' : 'Classificar como refeição'),
          ),
      ]),
    );
  }

  WeeklyDinnerFinance _preview(WeeklyDinnerFinance current) {
    if (current.closed) return current;
    try {
      final meal = _mode == 'manual'
          ? _value(_revenue)
          : current.number('bar_meal_revenue');
      final food = current.number('food_cost_linked') + _value(_food);
      final other = current.number('other_cost_linked') + _value(_other);
      final revenue = dinnerMoney(meal + current.number('beverage_revenue'));
      final cost = dinnerMoney(food + other + current.number('beverage_cost'));
      return WeeklyDinnerFinance({
        ...current.data,
        'meal_quantity': _mode == 'manual'
            ? _value(_quantity)
            : current.number('bar_meal_quantity'),
        'meal_revenue': meal,
        'food_cost': food,
        'meal_profit': dinnerMoney(meal - food),
        'other_costs': other,
        'total_revenue': revenue,
        'total_cost': current.hasCosts ? cost : null,
        'result': current.hasCosts ? dinnerMoney(revenue - cost) : null,
        'margin_percent': !current.hasCosts
            ? null
            : revenue > 0
                ? (revenue - cost) / revenue * 100
                : 0
      });
    } catch (_) {
      return current;
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.repository.canRead || !_sameSession) {
      return const Center(child: Text('Sem autorização financeira.'));
    }
    return Padding(
        padding: const EdgeInsets.all(16),
        child: Column(children: [
          Row(children: [
            Expanded(
                child: Text(
                    'Fecho financeiro · ${widget.dinner['dish'] ?? _dinnerDatePT(widget.dinner['dinner_date'])}',
                    style: Theme.of(context).textTheme.titleLarge)),
            IconButton(
                tooltip: 'Fechar',
                onPressed: () => Navigator.pop(context),
                icon: const Icon(Icons.close))
          ]),
          Expanded(
              child: FutureBuilder<WeeklyDinnerFinance>(
                  future: _future,
                  builder: (context, snapshot) {
                    if (snapshot.connectionState == ConnectionState.waiting) {
                      return const Center(child: CircularProgressIndicator());
                    }
                    if (snapshot.hasError) {
                      return Center(
                          child:
                              Column(mainAxisSize: MainAxisSize.min, children: [
                        const Text(
                            'Não foi possível carregar o fecho financeiro.'),
                        TextButton(
                            onPressed: () => setState(() {
                                  _future = _load();
                                }),
                            child: const Text('Repetir'))
                      ]));
                    }
                    final current = snapshot.data!;
                    final detail = _preview(current);
                    final edit = widget.repository.canManage &&
                        !current.closed &&
                        !_busy;
                    return ListView(children: [
                      Text(current.closed
                          ? 'Fechado · snapshot histórico'
                          : 'Por fechar · cálculo vivo'),
                      if (current.empty)
                        const Text(
                            'Sem fecho financeiro. Regista custos ou refeições manuais para este jantar.'),
                      if (current.closed)
                        Text(
                            'Fechado em ${_dinnerDatePT(current.data['closed_at'], time: true)} · Revisão ${current.data['revision']}'),
                      const Divider(),
                      const Text('Resumo automático BAR',
                          style: TextStyle(fontWeight: FontWeight.bold)),
                      Text(
                          '${current.number('bar_meal_quantity')} refeições BAR'),
                      _amount('Receita refeições BAR',
                          current.data['bar_meal_revenue']),
                      _amount('Receita bebidas / BAR',
                          current.data['beverage_revenue']),
                      _amount('Custo histórico do stock consumido',
                          current.data['beverage_cost']),
                      if (!current.hasCosts)
                        const Text(
                            'Falta custo ou classificação histórica. O resultado é desconhecido e o fecho está bloqueado.'),
                      if (current.hasUnclassifiedRevenue) ...[
                        _amount('Receita por classificar',
                            current.data['excluded_revenue']),
                        const Text(
                            'Existem vendas do BAR por classificar neste jantar. Classifica ou corrige essas vendas antes de fechar financeiramente.'),
                      ],
                      for (final line in current
                          .rows('classification_lines')
                          .where((line) =>
                              line['effective_component'] == 'excluded'))
                        _classificationLine(line, edit),
                      if (current
                          .rows('classification_lines')
                          .any((line) => line['component_override'] != null))
                        const Text('Classificações financeiras por linha',
                            style: TextStyle(fontWeight: FontWeight.bold)),
                      for (final line in current
                          .rows('classification_lines')
                          .where((line) => line['component_override'] != null))
                        _classificationLine(line, edit, undo: true),
                      const Divider(),
                      const Text('Ajustes de refeições',
                          style: TextStyle(fontWeight: FontWeight.bold)),
                      DropdownButtonFormField<String>(
                          isExpanded: true,
                          initialValue: _mode,
                          decoration: const InputDecoration(
                              labelText: 'Receita de refeições'),
                          items: const [
                            DropdownMenuItem(
                                value: 'automatic',
                                child: Text('Automático pelo BAR')),
                            DropdownMenuItem(
                                value: 'manual',
                                child: Text('Manual (substitui o automático)'))
                          ],
                          onChanged:
                              edit ? (v) => setState(() => _mode = v!) : null),
                      if (_mode == 'manual') ...[
                        _input('Quantidade de refeições', _quantity, edit),
                        _input('Receita das refeições', _revenue, edit)
                      ],
                      const Divider(),
                      const Text('Custos ligados à Tesouraria',
                          style: TextStyle(fontWeight: FontWeight.bold)),
                      _amount('Comida/preparação ligada',
                          current.data['food_cost_linked']),
                      _amount('Outros custos ligados',
                          current.data['other_cost_linked']),
                      for (final link in current.rows('expense_links'))
                        ListTile(
                            title: Text('${link['description']}'),
                            subtitle: Text(
                                '${link['cost_kind'] == 'food' ? 'Comida/preparação' : 'Outros custos'} · ${_money.format(link['amount'] ?? 0)}${link['reversed'] == true ? ' · Revertida (não conta)' : ''}'),
                            trailing: edit
                                ? IconButton(
                                    tooltip: 'Remover ligação',
                                    icon: const Icon(Icons.link_off),
                                    onPressed: () => _act(() =>
                                        widget.repository.linkExpense(
                                            id,
                                            link['transaction_id'].toString(),
                                            link['cost_kind'].toString(),
                                            remove: true)))
                                : null),
                      if (edit)
                        TextButton(
                            onPressed: () => _choose(true),
                            child:
                                const Text('Associar despesa da Tesouraria')),
                      const Text(
                          'Ajuste/manual: apenas valores adicionais não incluídos nas despesas ligadas.'),
                      _input('Comida/preparação — ajuste manual adicional',
                          _food, edit),
                      _input('Outros custos — ajuste manual adicional', _other,
                          edit),
                      TextField(
                          controller: _notes,
                          enabled: edit,
                          maxLines: 2,
                          decoration: const InputDecoration(
                              labelText: 'Justificação dos ajustes')),
                      const Divider(),
                      const Text('Vendas associadas',
                          style: TextStyle(fontWeight: FontWeight.bold)),
                      for (final sale in current.rows('sales'))
                        ListTile(
                            title: Text(
                                '${sale['customer_label'] ?? 'Venda BAR'}'),
                            subtitle: Text(
                                '${_money.format(sale['total_amount'] ?? 0)}${sale['completed_at'] == null ? '' : ' · ${_dinnerDatePT(sale['completed_at'], time: true)}'}'),
                            trailing: edit
                                ? IconButton(
                                    tooltip: 'Desassociar venda',
                                    icon: const Icon(Icons.link_off),
                                    onPressed: () => _act(() => widget
                                        .repository
                                        .assignSale(id, sale['id'].toString(),
                                            remove: true)))
                                : null),
                      if (edit)
                        TextButton(
                            onPressed: () => _choose(false),
                            child: const Text('Associar venda existente')),
                      const Divider(),
                      Text('Refeições: ${detail.number('meal_quantity')}'),
                      _amount('Receita refeições', detail.data['meal_revenue']),
                      _amount(
                          'Custo comida/preparação', detail.data['food_cost']),
                      _amount(
                          'Resultado refeições', detail.data['meal_profit']),
                      _amount('Resultado bebidas / BAR',
                          detail.data['beverage_profit']),
                      _amount(
                          'Outros custos diretos', detail.data['other_costs']),
                      _amount('Receita total', detail.data['total_revenue']),
                      _amount('Custo total', detail.data['total_cost']),
                      _amount('Resultado do jantar', detail.data['result']),
                      Text(detail.hasCosts
                          ? 'Margem: ${NumberFormat('0.0', 'pt_PT').format(detail.number('margin_percent'))}%'
                          : 'Margem não disponível'),
                      if (widget.repository.canManage)
                        Wrap(spacing: 8, children: [
                          if (!current.closed)
                            OutlinedButton(
                                onPressed: _busy ? null : () => _act(_save),
                                child: const Text('Guardar ajustes')),
                          FilledButton(
                              onPressed: _busy ||
                                      (!current.closed &&
                                          (!current.hasCosts ||
                                              current.hasUnclassifiedRevenue))
                                  ? null
                                  : () => _act(() async {
                                        if (!current.closed) await _save();
                                        await widget.repository
                                            .setClosed(id, !current.closed);
                                      }),
                              child: Text(current.closed
                                  ? 'Reabrir fecho financeiro'
                                  : 'Fechar financeiramente')),
                        ]),
                      if (current.rows('previous_snapshots').isNotEmpty)
                        ExpansionTile(
                            title:
                                const Text('Histórico de fechos preservados'),
                            children: current
                                .rows('previous_snapshots')
                                .map((r) => ListTile(
                                    title: Text(
                                        'Revisão ${r['revision']} · ${_dinnerDatePT(r['closed_at'], time: true)}'),
                                    subtitle: Text(
                                        'Resultado: ${_money.format((r['snapshot'] as Map)['result'] ?? 0)}')))
                                .toList()),
                      if (_busy) const LinearProgressIndicator(),
                    ]);
                  })),
        ]));
  }
}

class WeeklyDinnerFinancialHistory extends StatefulWidget {
  const WeeklyDinnerFinancialHistory(
      {super.key, required this.year, required this.repository});
  final int year;
  final WeeklyDinnerFinanceRepository repository;
  @override
  State<WeeklyDinnerFinancialHistory> createState() => _FinancialHistoryState();
}

class _FinancialHistoryState extends State<WeeklyDinnerFinancialHistory> {
  late Future<Map<String, dynamic>> _future;
  late String _club, _profile;
  void _reload() {
    _club = AppSession.instance.clubId;
    _profile = AppSession.instance.profileId;
    _future = widget.repository.canRead
        ? widget.repository.history(widget.year)
        : Future.value(<String, dynamic>{});
  }

  @override
  void initState() {
    super.initState();
    _reload();
  }

  @override
  void didUpdateWidget(covariant WeeklyDinnerFinancialHistory old) {
    super.didUpdateWidget(old);
    if (old.year != widget.year) {
      _reload();
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.repository.canRead ||
        _club != AppSession.instance.clubId ||
        _profile != AppSession.instance.profileId) {
      return const SizedBox.shrink();
    }
    return FutureBuilder<Map<String, dynamic>>(
        future: _future,
        builder: (context, snapshot) {
          if (!widget.repository.canRead ||
              _club != AppSession.instance.clubId ||
              _profile != AppSession.instance.profileId) {
            return const SizedBox.shrink();
          }
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.hasError) {
            return Center(
                child: TextButton(
                    onPressed: () => setState(() {
                          _future = widget.repository.history(widget.year);
                        }),
                    child:
                        const Text('Erro no histórico financeiro · Repetir')));
          }
          final data = snapshot.data!;
          final rows = List<Map<String, dynamic>>.from(data['rows'] as List);
          final money = NumberFormat.currency(locale: 'pt_PT', symbol: '€');
          return ListView(children: [
            ListTile(
                title: Text('Histórico financeiro ${widget.year}'),
                subtitle: Text(
                    '${data['closed_count']} jantares fechados · Receita ${money.format(data['total_revenue'])} · '
                    'Custo ${money.format(data['total_cost'])} · Resultado ${money.format(data['result'])}\n'
                    'Margem global: ${NumberFormat('0.0', 'pt_PT').format(data['margin_percent'])}%')),
            if (rows.isEmpty)
              const ListTile(title: Text('Sem jantares neste ano.')),
            for (final row in rows)
              ListTile(
                  title: Text(
                      '${_dinnerDatePT(row['dinner_date'])} · ${row['dish'] ?? 'Jantar'}'),
                  subtitle: Text(row['financial_status'] == 'closed'
                      ? 'Fechado · Receita ${money.format((row['summary'] as Map)['total_revenue'])} · Custo ${money.format((row['summary'] as Map)['total_cost'])}\n'
                          'Resultado ${money.format((row['summary'] as Map)['result'])} · Margem ${NumberFormat('0.0', 'pt_PT').format((row['summary'] as Map)['margin_percent'])}%'
                      : row['financial_status'] == 'none'
                          ? 'Sem fecho financeiro'
                          : 'Por fechar'),
                  onTap: () async {
                    await WeeklyDinnerFinanceDialog.show(
                        context, row, widget.repository);
                    if (mounted) {
                      setState(() {
                        _future = widget.repository.history(widget.year);
                      });
                    }
                  }),
          ]);
        });
  }
}

String _dinnerDatePT(Object? value, {bool time = false}) {
  final date = DateTime.tryParse(value?.toString() ?? '');
  if (date == null) return 'Data indisponível';
  return DateFormat(time ? 'dd/MM/yyyy HH:mm' : 'dd/MM/yyyy', 'pt_PT')
      .format(date.toLocal());
}
