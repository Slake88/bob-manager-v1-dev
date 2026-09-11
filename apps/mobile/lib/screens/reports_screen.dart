import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../core/app_session.dart';
import '../core/reporting.dart';
import '../repositories/reports_repository.dart';
import '../services/report_export_service.dart';
import 'treasury_reports_screen.dart';

class ReportsScreen extends StatelessWidget {
  const ReportsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final reports = ReportCatalog.visible(AppSession.instance.can);

    if (reports.isEmpty) {
      return const Center(
        child: Text('Não existem relatórios disponíveis para o teu perfil.'),
      );
    }

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 96),
      children: [
        Text(
          'Centro de Relatórios',
          style: Theme.of(context).textTheme.headlineSmall,
        ),
        const SizedBox(height: 4),
        const Text(
          'Consulta, filtra e exporta apenas os módulos a que tens acesso.',
        ),
        const SizedBox(height: 16),
        ...reports.map(
          (report) => Card(
            child: ListTile(
              leading: CircleAvatar(child: Icon(report.icon)),
              title: Text(report.title),
              subtitle: Text(report.description),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => _open(context, report),
            ),
          ),
        ),
      ],
    );
  }

  void _open(BuildContext context, ReportDefinition report) {
    if (report.kind == ReportKind.treasury) {
      Navigator.of(context).push(
        MaterialPageRoute(builder: (_) => const TreasuryReportsScreen()),
      );
      return;
    }
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => ReportDetailScreen(definition: report),
      ),
    );
  }
}

class ReportDetailScreen extends StatefulWidget {
  const ReportDetailScreen({
    super.key,
    required this.definition,
  });

  final ReportDefinition definition;

  @override
  State<ReportDetailScreen> createState() => _ReportDetailScreenState();
}

class _ReportDetailScreenState extends State<ReportDetailScreen> {
  final ReportsRepository _repository = ReportsRepository();
  final TextEditingController _search = TextEditingController();
  late ReportFilters _filters;
  late Future<ReportData> _future;

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    _filters = widget.definition.hasDateFilter
        ? ReportFilters(
            from: DateTime(now.year, 1, 1),
            to: DateTime(now.year, 12, 31),
          )
        : const ReportFilters();
    _future = _load();
  }

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  Future<ReportData> _load() {
    return _repository.load(widget.definition, filters: _filters);
  }

  Future<void> _refresh() async {
    setState(() => _future = _load());
    await _future;
  }

  void _apply() {
    setState(() {
      _filters = _filters.copyWith(query: _search.text.trim());
      _future = _load();
    });
  }

  void _clear() {
    _search.clear();
    setState(() {
      _filters = const ReportFilters();
      _future = _load();
    });
  }

  Future<void> _pickFrom() async {
    final now = DateTime.now();
    final value = await showDatePicker(
      context: context,
      initialDate: _filters.from ?? DateTime(now.year, 1, 1),
      firstDate: DateTime(2000),
      lastDate: DateTime(2100),
    );
    if (value == null) return;
    setState(() {
      var to = _filters.to;
      if (to != null && to.isBefore(value)) to = value;
      _filters = ReportFilters(
        query: _search.text.trim(),
        from: value,
        to: to,
        option: _filters.option,
      );
      _future = _load();
    });
  }

  Future<void> _pickTo() async {
    final now = DateTime.now();
    final value = await showDatePicker(
      context: context,
      initialDate: _filters.to ?? DateTime(now.year, 12, 31),
      firstDate: DateTime(2000),
      lastDate: DateTime(2100),
    );
    if (value == null) return;
    setState(() {
      var from = _filters.from;
      if (from != null && from.isAfter(value)) from = value;
      _filters = ReportFilters(
        query: _search.text.trim(),
        from: from,
        to: value,
        option: _filters.option,
      );
      _future = _load();
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(widget.definition.title)),
      body: FutureBuilder<ReportData>(
        future: _future,
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return _error(snapshot.error);
          }
          if (!snapshot.hasData) {
            return const Center(child: CircularProgressIndicator());
          }

          final data = snapshot.data!;
          return Column(
            children: [
              _filtersCard(),
              _metrics(data),
              _exports(data),
              Expanded(
                child: RefreshIndicator(
                  onRefresh: _refresh,
                  child: data.rows.isEmpty
                      ? ListView(
                          physics: const AlwaysScrollableScrollPhysics(),
                          padding: const EdgeInsets.all(24),
                          children: const [
                            SizedBox(height: 80),
                            Icon(Icons.search_off_outlined, size: 48),
                            SizedBox(height: 12),
                            Center(
                              child: Text(
                                'Sem registos para os filtros selecionados.',
                              ),
                            ),
                          ],
                        )
                      : ListView.builder(
                          physics: const AlwaysScrollableScrollPhysics(),
                          padding: const EdgeInsets.fromLTRB(12, 4, 12, 96),
                          itemCount: data.rows.length,
                          itemBuilder: (context, index) =>
                              _rowCard(data, data.rows[index]),
                        ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _filtersCard() {
    final definition = widget.definition;
    return Card(
      margin: const EdgeInsets.fromLTRB(12, 12, 12, 6),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Filtros',
              style: Theme.of(context)
                  .textTheme
                  .titleMedium
                  ?.copyWith(fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: _search,
              textInputAction: TextInputAction.search,
              onSubmitted: (_) => _apply(),
              decoration: InputDecoration(
                labelText: 'Pesquisar',
                prefixIcon: const Icon(Icons.search),
                suffixIcon: IconButton(
                  tooltip: 'Aplicar pesquisa',
                  onPressed: _apply,
                  icon: const Icon(Icons.arrow_forward),
                ),
              ),
            ),
            if (definition.hasDateFilter || definition.hasOptionFilter) ...[
              const SizedBox(height: 10),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  if (definition.hasDateFilter) ...[
                    OutlinedButton.icon(
                      onPressed: _pickFrom,
                      icon: const Icon(Icons.calendar_today_outlined),
                      label: Text(
                        _filters.from == null
                            ? 'Data inicial'
                            : 'De ${_date(_filters.from!)}',
                      ),
                    ),
                    OutlinedButton.icon(
                      onPressed: _pickTo,
                      icon: const Icon(Icons.event_outlined),
                      label: Text(
                        _filters.to == null
                            ? 'Data final'
                            : 'Até ${_date(_filters.to!)}',
                      ),
                    ),
                  ],
                  if (definition.hasOptionFilter)
                    SizedBox(
                      width: 220,
                      child: DropdownButtonFormField<String?>(
                        key: ValueKey(_filters.option),
                        initialValue: _filters.option,
                        decoration: InputDecoration(
                          labelText: definition.filterLabel,
                        ),
                        items: [
                          const DropdownMenuItem<String?>(
                            value: null,
                            child: Text('Todos'),
                          ),
                          ...definition.filterOptions.map(
                            (option) => DropdownMenuItem<String?>(
                              value: option.value,
                              child: Text(option.label),
                            ),
                          ),
                        ],
                        onChanged: (value) {
                          setState(() {
                            _filters = ReportFilters(
                              query: _search.text.trim(),
                              from: _filters.from,
                              to: _filters.to,
                              option: value,
                            );
                            _future = _load();
                          });
                        },
                      ),
                    ),
                  TextButton.icon(
                    onPressed: _clear,
                    icon: const Icon(Icons.filter_alt_off_outlined),
                    label: const Text('Limpar filtros'),
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _metrics(ReportData data) {
    if (data.metrics.isEmpty) return const SizedBox.shrink();
    return SizedBox(
      height: 82,
      child: ListView.separated(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
        scrollDirection: Axis.horizontal,
        itemCount: data.metrics.length,
        separatorBuilder: (context, index) => const SizedBox(width: 8),
        itemBuilder: (context, index) {
          final entry = data.metrics.entries.elementAt(index);
          return SizedBox(
            width: 150,
            child: Card(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      entry.key,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                    const SizedBox(height: 2),
                    Text(
                      entry.value,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context)
                          .textTheme
                          .titleMedium
                          ?.copyWith(fontWeight: FontWeight.w900),
                    ),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _exports(ReportData data) {
    return Card(
      margin: const EdgeInsets.fromLTRB(12, 2, 12, 6),
      child: Padding(
        padding: const EdgeInsets.all(10),
        child: Row(
          children: [
            Expanded(
              child: Text(
                '${data.rows.length} registos',
                style: const TextStyle(fontWeight: FontWeight.w700),
              ),
            ),
            IconButton(
              tooltip: 'Exportar PDF',
              onPressed: () => _runExport(
                () => ReportExportService.exportPdf(context, data),
              ),
              icon: const Icon(Icons.picture_as_pdf_outlined),
            ),
            IconButton(
              tooltip: 'Exportar Excel',
              onPressed: () => _runExport(
                () => ReportExportService.exportExcel(context, data),
              ),
              icon: const Icon(Icons.table_view_outlined),
            ),
            IconButton(
              tooltip: 'Exportar CSV',
              onPressed: () => _runExport(
                () => ReportExportService.exportCsv(context, data),
              ),
              icon: const Icon(Icons.text_snippet_outlined),
            ),
          ],
        ),
      ),
    );
  }

  Widget _rowCard(ReportData data, Map<String, dynamic> row) {
    final columns = data.columns;
    final titleColumn = columns.first;
    final title = ReportExportService.formatValue(
      row[titleColumn.key],
      titleColumn.type,
    );

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              title.isEmpty ? '—' : title,
              style: Theme.of(context)
                  .textTheme
                  .titleMedium
                  ?.copyWith(fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 8),
            ...columns.skip(1).map((column) {
              final value = ReportExportService.formatValue(
                row[column.key],
                column.type,
              );
              if (value.isEmpty) return const SizedBox.shrink();
              return Padding(
                padding: const EdgeInsets.only(bottom: 4),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    SizedBox(
                      width: 118,
                      child: Text(
                        column.label,
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    ),
                    Expanded(child: Text(value)),
                  ],
                ),
              );
            }),
          ],
        ),
      ),
    );
  }

  Widget _error(Object? error) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.error_outline, size: 44),
            const SizedBox(height: 12),
            Text('Erro ao carregar relatório: $error'),
            const SizedBox(height: 12),
            FilledButton.icon(
              onPressed: _refresh,
              icon: const Icon(Icons.refresh),
              label: const Text('Tentar novamente'),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _runExport(Future<void> Function() action) async {
    try {
      await action();
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Não foi possível exportar: $error')),
      );
    }
  }
}

String _date(DateTime value) => DateFormat('dd/MM/yyyy').format(value);
