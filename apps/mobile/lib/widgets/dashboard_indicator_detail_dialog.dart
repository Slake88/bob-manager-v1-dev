import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../core/app_session.dart';
import '../models/dashboard_indicator_detail.dart';
import '../repositories/dashboard_repository.dart';
import '../repositories/member_repository.dart';
import '../screens/member_detail_screen.dart';

class DashboardIndicatorDetailDialog extends StatefulWidget {
  const DashboardIndicatorDetailDialog({
    super.key,
    required this.indicator,
    required this.repository,
    this.onAggregate,
    this.onOpenMember,
  });

  final DashboardIndicator indicator;
  final DashboardRepository repository;
  final ValueChanged<DashboardIndicatorDetail>? onAggregate;
  final Future<void> Function(String)? onOpenMember;

  static Future<void> show(
    BuildContext context, {
    required DashboardIndicator indicator,
    required DashboardRepository repository,
    ValueChanged<DashboardIndicatorDetail>? onAggregate,
  }) {
    final content = DashboardIndicatorDetailDialog(
      indicator: indicator,
      repository: repository,
      onAggregate: onAggregate,
    );
    if (MediaQuery.sizeOf(context).width >= 700) {
      return showDialog<void>(
        context: context,
        builder: (_) => Dialog(
          child: SizedBox(
            width: 680,
            height: MediaQuery.sizeOf(context).height * .8,
            child: content,
          ),
        ),
      );
    }
    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (_) => SizedBox(
        height: MediaQuery.sizeOf(context).height * .85,
        child: content,
      ),
    );
  }

  @override
  State<DashboardIndicatorDetailDialog> createState() =>
      _DashboardIndicatorDetailDialogState();
}

class _DashboardIndicatorDetailDialogState
    extends State<DashboardIndicatorDetailDialog> {
  final _rows = <String, Map<String, dynamic>>{};
  DashboardIndicatorDetail? _detail;
  bool _loading = true;
  String? _error;
  bool _openingMember = false;
  late final String _clubId;
  late final String _profileId;
  final _euro = NumberFormat.currency(locale: 'pt_PT', symbol: '€');

  @override
  void initState() {
    super.initState();
    _clubId = AppSession.instance.clubId;
    _profileId = AppSession.instance.profileId;
    _load(reset: true);
  }

  Future<void> _load({bool reset = false}) async {
    setState(() {
      _loading = true;
      _error = null;
      if (reset) {
        _rows.clear();
        _detail = null;
      }
    });
    try {
      final next = await widget.repository.indicatorDetails(
        widget.indicator,
        cursor: reset ? null : _detail?.nextCursor,
      );
      if (!mounted) return;
      if (_clubId != AppSession.instance.clubId ||
          _profileId != AppSession.instance.profileId) {
        _rows.clear();
        setState(() {
          _detail = DashboardIndicatorDetail(
            indicator: widget.indicator,
            authorized: false,
            complete: false,
          );
          _loading = false;
        });
        return;
      }
      final previous = _detail;
      if (!reset &&
          previous != null &&
          next.canDisplay &&
          (previous.totalRows != next.totalRows ||
              previous.monetaryTotal != next.monetaryTotal)) {
        // Never append a page from a changed aggregate to an older list.
        await _load(reset: true);
        return;
      }
      setState(() {
        _detail = next;
        _loading = false;
        if (!next.canDisplay) {
          _rows.clear();
        } else {
          for (final row in next.rows) {
            _rows[row['id'].toString()] = row;
          }
        }
      });
      if (next.canDisplay) widget.onAggregate?.call(next);
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _error = 'Não foi possível carregar o detalhe.';
        _loading = false;
      });
    }
  }

  Future<void> _openMember(String id) async {
    if (_openingMember) return;
    setState(() => _openingMember = true);
    try {
      if (widget.onOpenMember != null) {
        await widget.onOpenMember!(id);
      } else {
        final member = await MemberRepository().getMember(id);
        if (!mounted || member == null) return;
        await Navigator.of(context).push<void>(
          MaterialPageRoute(builder: (_) => MemberDetailScreen(member: member)),
        );
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Não foi possível abrir o membro.')),
        );
      }
    } finally {
      if (mounted) setState(() => _openingMember = false);
    }
  }

  String _date(Object? value) {
    final date = DateTime.tryParse(value?.toString() ?? '');
    return date == null ? 'Sem data' : DateFormat('dd/MM/yyyy').format(date);
  }

  String _stock(Object? value) =>
      NumberFormat('0.##', 'pt_PT').format(value is num ? value : 0);

  Widget _row(Map<String, dynamic> row) {
    String title;
    String subtitle;
    Widget? trailing;
    switch (widget.indicator) {
      case DashboardIndicator.members:
      case DashboardIndicator.prospects:
        title = row['full_name']?.toString() ?? 'Membro';
        subtitle = 'Nº ${row['member_number'] ?? '—'}';
        if ((row['nickname']?.toString() ?? '').isNotEmpty) {
          subtitle += ' · ${row['nickname']}';
        }
        trailing = IconButton(
          tooltip: 'Abrir membro',
          onPressed:
              _openingMember ? null : () => _openMember(row['id'].toString()),
          icon: const Icon(Icons.open_in_new),
        );
      case DashboardIndicator.totalBalance:
        title = row['name']?.toString() ?? 'Conta';
        subtitle = _euro.format(row['balance'] ?? 0);
      case DashboardIndicator.feeOutstanding:
        title = row['member_name']?.toString() ?? 'Membro';
        subtitle = '${_euro.format(row['outstanding'] ?? 0)} · '
            'Vencimento: ${_date(row['due_date'])}';
      case DashboardIndicator.openEvents:
        title = row['name']?.toString() ?? 'Evento';
        subtitle = '${_date(row['starts_at'])} · ${row['status'] ?? ''}';
      case DashboardIndicator.lowStock:
        title = row['name']?.toString() ?? 'Artigo';
        subtitle = 'Stock atual: ${_stock(row['current_stock'])} · '
            'Reservado: ${_stock(row['reserved_stock'])}\n'
            'Disponível: ${_stock(row['available_stock'])} · '
            'Mínimo: ${_stock(row['minimum_stock'])}';
      case DashboardIndicator.expiringDocuments:
        title = row['name']?.toString() ?? 'Documento';
        subtitle = 'Validade: ${_date(row['expires_at'])}';
      case DashboardIndicator.pendingApprovals:
        title = row['description']?.toString() ?? 'Pedido';
        final name = row['requester_name']?.toString().trim();
        final requester = row['requester_name_missing'] == true ||
                name == null ||
                name.isEmpty
            ? 'Nome não disponível'
            : name;
        subtitle = '${row['request_type'] ?? ''} · '
            '${row['status'] ?? ''}\nRequerente: $requester';
        if (row['amount'] != null) {
          subtitle += ' · ${_euro.format(row['amount'])}';
        }
    }
    return ListTile(
      title: Text(title),
      subtitle: Text(subtitle),
      trailing: trailing,
    );
  }

  @override
  Widget build(BuildContext context) {
    final detail = _detail;
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    widget.indicator.title,
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                ),
                IconButton(
                  tooltip: 'Atualizar detalhe',
                  onPressed: _loading ? null : () => _load(reset: true),
                  icon: const Icon(Icons.refresh),
                ),
                IconButton(
                  tooltip: 'Fechar',
                  onPressed: () => Navigator.of(context).pop(),
                  icon: const Icon(Icons.close),
                ),
              ],
            ),
            if (detail?.canDisplay == true) ...[
              Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  widget.indicator.monetary
                      ? 'Total: ${_euro.format(detail!.monetaryTotal ?? 0)}'
                      : 'Total: ${detail!.totalRows ?? 0}',
                ),
              ),
              Align(
                alignment: Alignment.centerLeft,
                child: Text('${_rows.length} de ${detail.totalRows} registos'),
              ),
            ],
            const SizedBox(height: 8),
            Expanded(
              child: _loading && detail == null
                  ? const Center(child: CircularProgressIndicator())
                  : detail != null && !detail.canDisplay
                      ? const Center(
                          child: Text(
                            'Não tem permissão para consultar o detalhe completo deste indicador.',
                            textAlign: TextAlign.center,
                          ),
                        )
                      : _error != null && detail == null
                          ? const SizedBox.shrink()
                          : _rows.isEmpty
                              ? const Center(
                                  child: Text(
                                    'Não existem registos para este indicador.',
                                    textAlign: TextAlign.center,
                                  ),
                                )
                              : ListView(
                                  children: _rows.values.map(_row).toList(),
                                ),
            ),
            if (_error != null) ...[
              Text(_error!, textAlign: TextAlign.center),
              TextButton(
                onPressed: () => _load(reset: detail == null),
                child: const Text('Repetir'),
              ),
            ],
            if (_loading && detail != null) const LinearProgressIndicator(),
            if (!_loading &&
                detail?.canDisplay == true &&
                detail?.nextCursor != null)
              TextButton(
                onPressed: _load,
                child: const Text('Carregar mais'),
              ),
          ],
        ),
      ),
    );
  }
}
