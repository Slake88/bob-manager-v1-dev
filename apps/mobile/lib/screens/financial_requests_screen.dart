import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';

import '../core/app_session.dart';
import '../repositories/financial_requests_repository.dart';

class FinancialRequestsScreen extends StatefulWidget {
  const FinancialRequestsScreen({super.key});

  @override
  State<FinancialRequestsScreen> createState() =>
      _FinancialRequestsScreenState();
}

class _FinancialRequestsScreenState extends State<FinancialRequestsScreen> {
  final FinancialRequestsRepository _repository = FinancialRequestsRepository();
  final NumberFormat _euro =
      NumberFormat.currency(locale: 'pt_PT', symbol: '€');
  late Future<List<Map<String, dynamic>>> _future;
  String _filter = 'open';

  bool get _manager => _repository.canManage;

  @override
  void initState() {
    super.initState();
    _reload();
  }

  void _reload() {
    _future = _repository.listRequests();
  }

  Future<void> _refresh() async {
    setState(_reload);
    await _future;
  }

  Future<List<PlatformFile>> _pickFiles() async {
    final result = await FilePicker.platform.pickFiles(
      allowMultiple: true,
      withData: true,
      type: FileType.custom,
      allowedExtensions: const ['jpg', 'jpeg', 'png', 'webp', 'pdf'],
    );
    return result?.files ?? const <PlatformFile>[];
  }

  Future<void> _newReimbursement() async {
    try {
      final members = _manager
          ? await _repository.eligibleMembers()
          : const <Map<String, dynamic>>[];
      if (!mounted) return;

      final draft = await showDialog<_ReimbursementDraft>(
        context: context,
        builder: (_) => _ReimbursementDialog(
          manager: _manager,
          members: members,
        ),
      );
      if (draft == null) return;

      final files = await _pickFiles();
      if (files.isEmpty) {
        _message('Seleciona pelo menos um talão ou recibo.');
        return;
      }

      final requestId = await _repository.createReimbursementDraft(
        memberId: draft.memberId,
        amount: draft.amount,
        description: draft.description,
      );
      await _repository.uploadAttachments(
        requestId: requestId,
        kind: 'receipt',
        files: files,
      );
      await _repository.submitReimbursement(requestId);
      if (!mounted) return;
      _message('Pedido de reembolso submetido.');
      await _refresh();
    } catch (error) {
      if (mounted) _message(_errorText(error), error: true);
    }
  }

  Future<void> _newCharge() async {
    try {
      final members = await _repository.eligibleMembers();
      if (!mounted) return;
      final draft = await showDialog<_ChargeDraft>(
        context: context,
        builder: (_) => _ChargeDialog(members: members),
      );
      if (draft == null) return;

      final result = await _repository.createCharges(
        memberIds: draft.memberIds,
        category: draft.category,
        amount: draft.amount,
        description: draft.description,
        dueDate: draft.dueDate,
      );
      if (!mounted) return;
      _message('${result['count'] ?? draft.memberIds.length} cobrança(s) criada(s).');
      await _refresh();
    } catch (error) {
      if (mounted) _message(_errorText(error), error: true);
    }
  }

  Future<void> _addAndSubmitReimbursement(
    Map<String, dynamic> row,
  ) async {
    try {
      final files = await _pickFiles();
      if (files.isEmpty) return;
      final id = row['id'].toString();
      await _repository.uploadAttachments(
        requestId: id,
        kind: 'receipt',
        files: files,
      );
      await _repository.submitReimbursement(id);
      if (!mounted) return;
      Navigator.of(context).pop();
      _message('Pedido reenviado para análise.');
      await _refresh();
    } catch (error) {
      if (mounted) _message(_errorText(error), error: true);
    }
  }

  Future<void> _addChargeProof(Map<String, dynamic> row) async {
    try {
      final files = await _pickFiles();
      if (files.isEmpty) return;
      final id = row['id'].toString();
      await _repository.uploadAttachments(
        requestId: id,
        kind: 'member_payment_proof',
        files: files,
      );
      await _repository.submitChargeProof(id);
      if (!mounted) return;
      Navigator.of(context).pop();
      _message('Comprovativo enviado para validação.');
      await _refresh();
    } catch (error) {
      if (mounted) _message(_errorText(error), error: true);
    }
  }

  Future<void> _addClubPaymentProof(Map<String, dynamic> row) async {
    try {
      final files = await _pickFiles();
      if (files.isEmpty) return;
      await _repository.uploadAttachments(
        requestId: row['id'].toString(),
        kind: 'club_payment_proof',
        files: files,
      );
      if (!mounted) return;
      Navigator.of(context).pop();
      _message('Comprovativo de pagamento anexado.');
      await _refresh();
    } catch (error) {
      if (mounted) _message(_errorText(error), error: true);
    }
  }

  Future<void> _reviewReimbursement(
    Map<String, dynamic> row,
    String action,
  ) async {
    String? note;
    if (action != 'approve') {
      note = await _askNote(
        action == 'reject'
            ? 'Motivo da rejeição'
            : 'Informação em falta',
      );
      if (note == null) return;
    }

    try {
      await _repository.reviewReimbursement(
        requestId: row['id'].toString(),
        action: action,
        note: note,
      );
      if (!mounted) return;
      Navigator.of(context).pop();
      _message(switch (action) {
        'approve' => 'Pedido aprovado.',
        'reject' => 'Pedido rejeitado.',
        _ => 'Pedido devolvido para informação adicional.',
      });
      await _refresh();
    } catch (error) {
      if (mounted) _message(_errorText(error), error: true);
    }
  }

  Future<void> _payReimbursement(Map<String, dynamic> row) async {
    try {
      final accounts = await _repository.accounts();
      if (!mounted) return;
      final payment = await showDialog<_PaymentDraft>(
        context: context,
        builder: (_) => _PaymentDialog(
          accounts: accounts,
          title: 'Liquidar reembolso',
        ),
      );
      if (payment == null) return;

      await _repository.payReimbursement(
        requestId: row['id'].toString(),
        accountId: payment.accountId,
        paymentMethod: payment.method,
        note: payment.note,
      );
      if (!mounted) return;
      Navigator.of(context).pop();
      _message('Reembolso liquidado e lançado na Tesouraria.');
      await _refresh();
    } catch (error) {
      if (mounted) _message(_errorText(error), error: true);
    }
  }

  Future<void> _approveCharge(Map<String, dynamic> row) async {
    try {
      final accounts = await _repository.accounts();
      if (!mounted) return;
      final payment = await showDialog<_PaymentDraft>(
        context: context,
        builder: (_) => _PaymentDialog(
          accounts: accounts,
          title: 'Validar pagamento',
        ),
      );
      if (payment == null) return;

      await _repository.reviewChargePayment(
        requestId: row['id'].toString(),
        action: 'approve',
        accountId: payment.accountId,
        paymentMethod: payment.method,
        note: payment.note,
      );
      if (!mounted) return;
      Navigator.of(context).pop();
      _message('Pagamento validado e lançado na Tesouraria.');
      await _refresh();
    } catch (error) {
      if (mounted) _message(_errorText(error), error: true);
    }
  }

  Future<void> _cashCharge(Map<String, dynamic> row) async {
    try {
      final accounts = await _repository.accounts();
      if (!mounted) return;
      final accountId = await showDialog<String>(
        context: context,
        builder: (_) => _AccountDialog(
          accounts: accounts,
          title: 'Receber em numerário',
        ),
      );
      if (accountId == null) return;

      await _repository.reviewChargePayment(
        requestId: row['id'].toString(),
        action: 'approve',
        accountId: accountId,
        paymentMethod: 'cash',
      );
      if (!mounted) return;
      Navigator.of(context).pop();
      _message('Cobrança recebida em numerário.');
      await _refresh();
    } catch (error) {
      if (mounted) _message(_errorText(error), error: true);
    }
  }

  Future<void> _rejectChargeProof(Map<String, dynamic> row) async {
    final note = await _askNote('Motivo da rejeição do comprovativo');
    if (note == null) return;
    try {
      await _repository.reviewChargePayment(
        requestId: row['id'].toString(),
        action: 'reject',
        note: note,
      );
      if (!mounted) return;
      Navigator.of(context).pop();
      _message('Comprovativo rejeitado.');
      await _refresh();
    } catch (error) {
      if (mounted) _message(_errorText(error), error: true);
    }
  }

  Future<void> _openAttachment(Map<String, dynamic> attachment) async {
    try {
      final url = await _repository.signedAttachmentUrl(attachment);
      final uri = Uri.parse(url);
      if (!await launchUrl(uri, mode: LaunchMode.externalApplication)) {
        throw StateError('Não foi possível abrir o ficheiro.');
      }
    } catch (error) {
      if (mounted) _message(_errorText(error), error: true);
    }
  }

  Future<String?> _askNote(String title) async {
    final controller = TextEditingController();
    final result = await showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(title),
        content: TextField(
          controller: controller,
          minLines: 2,
          maxLines: 5,
          autofocus: true,
          decoration: const InputDecoration(labelText: 'Observação'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () {
              final value = controller.text.trim();
              if (value.isNotEmpty) Navigator.pop(dialogContext, value);
            },
            child: const Text('Confirmar'),
          ),
        ],
      ),
    );
    controller.dispose();
    return result;
  }

  bool _isOwner(Map<String, dynamic> row) {
    final member = row['member'];
    return member is Map &&
        member['profile_id']?.toString() == AppSession.instance.profileId;
  }

  List<Map<String, dynamic>> _filtered(List<Map<String, dynamic>> rows) {
    return switch (_filter) {
      'open' => rows
          .where((row) => !FinancialRequestsRepository.isTerminalStatus(
                row['status']?.toString(),
              ))
          .toList(),
      'reimbursement' => rows
          .where((row) => row['request_type']?.toString() == 'reimbursement')
          .toList(),
      'charge' => rows
          .where((row) => row['request_type']?.toString() == 'charge')
          .toList(),
      'closed' => rows
          .where((row) => FinancialRequestsRepository.isTerminalStatus(
                row['status']?.toString(),
              ))
          .toList(),
      _ => rows,
    };
  }

  void _message(String text, {bool error = false}) {
    final scheme = Theme.of(context).colorScheme;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(text),
        backgroundColor: error ? scheme.error : null,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<List<Map<String, dynamic>>>(
      future: _future,
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return Center(child: Text('Erro: ${_errorText(snapshot.error!)}'));
        }
        if (!snapshot.hasData) {
          return const Center(child: CircularProgressIndicator());
        }

        final allRows = snapshot.data!;
        final rows = _filtered(allRows);
        final pendingManager = allRows.where((row) {
          final status = row['status']?.toString();
          return status == 'pending_review' || status == 'awaiting_validation';
        }).length;
        final awaitingPayment = allRows.where(
          (row) => row['status']?.toString() == 'awaiting_payment',
        ).length;

        return RefreshIndicator(
          onRefresh: _refresh,
          child: ListView(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 100),
            children: [
              Wrap(
                spacing: 12,
                runSpacing: 12,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  SizedBox(
                    width: 330,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Pedidos & Pagamentos',
                          style:
                              Theme.of(context).textTheme.headlineSmall?.copyWith(
                                    fontWeight: FontWeight.w900,
                                  ),
                        ),
                        const SizedBox(height: 4),
                        const Text(
                          'Reembolsos, cobranças, comprovativos e liquidações num único local.',
                        ),
                      ],
                    ),
                  ),
                  FilledButton.icon(
                    onPressed: _newReimbursement,
                    icon: const Icon(Icons.receipt_long_outlined),
                    label: const Text('Novo reembolso'),
                  ),
                  if (_manager)
                    FilledButton.tonalIcon(
                      onPressed: _newCharge,
                      icon: const Icon(Icons.request_quote_outlined),
                      label: const Text('Nova cobrança'),
                    ),
                ],
              ),
              const SizedBox(height: 14),
              Wrap(
                spacing: 10,
                runSpacing: 10,
                children: [
                  _SummaryCard(
                    icon: Icons.pending_actions_outlined,
                    label: _manager ? 'Para validar' : 'Em aberto',
                    value: _manager
                        ? '$pendingManager'
                        : '${allRows.where((row) => !FinancialRequestsRepository.isTerminalStatus(row['status']?.toString())).length}',
                  ),
                  _SummaryCard(
                    icon: Icons.payments_outlined,
                    label: 'Aguarda pagamento',
                    value: '$awaitingPayment',
                  ),
                  _SummaryCard(
                    icon: Icons.task_alt_outlined,
                    label: 'Liquidados',
                    value:
                        '${allRows.where((row) => row['status'] == 'paid').length}',
                  ),
                ],
              ),
              const SizedBox(height: 14),
              Wrap(
                spacing: 8,
                children: [
                  _filterChip('open', 'Em aberto'),
                  _filterChip('all', 'Tudo'),
                  _filterChip('reimbursement', 'Reembolsos'),
                  _filterChip('charge', 'Cobranças'),
                  _filterChip('closed', 'Encerrados'),
                ],
              ),
              const SizedBox(height: 10),
              if (rows.isEmpty)
                const Card(
                  child: ListTile(
                    leading: Icon(Icons.inbox_outlined),
                    title: Text('Não existem processos neste filtro.'),
                  ),
                )
              else
                ...rows.map(
                  (row) => _RequestCard(
                    row: row,
                    euro: _euro,
                    onTap: () => _openRequest(row),
                  ),
                ),
            ],
          ),
        );
      },
    );
  }

  Widget _filterChip(String value, String label) {
    return FilterChip(
      selected: _filter == value,
      label: Text(label),
      onSelected: (_) => setState(() => _filter = value),
    );
  }

  Future<void> _openRequest(Map<String, dynamic> row) async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (sheetContext) => _RequestDetailSheet(
        row: row,
        manager: _manager,
        owner: _isOwner(row),
        euro: _euro,
        onOpenAttachment: _openAttachment,
        onAddReimbursementInfo: () => _addAndSubmitReimbursement(row),
        onApproveReimbursement: () => _reviewReimbursement(row, 'approve'),
        onRequestInfo: () => _reviewReimbursement(row, 'request_info'),
        onRejectReimbursement: () => _reviewReimbursement(row, 'reject'),
        onAddClubProof: () => _addClubPaymentProof(row),
        onPayReimbursement: () => _payReimbursement(row),
        onAddChargeProof: () => _addChargeProof(row),
        onApproveCharge: () => _approveCharge(row),
        onRejectChargeProof: () => _rejectChargeProof(row),
        onCashCharge: () => _cashCharge(row),
      ),
    );
  }
}

class _RequestCard extends StatelessWidget {
  const _RequestCard({
    required this.row,
    required this.euro,
    required this.onTap,
  });

  final Map<String, dynamic> row;
  final NumberFormat euro;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final member = row['member'];
    final name = member is Map
        ? (member['nickname']?.toString().trim().isNotEmpty == true
            ? member['nickname'].toString()
            : member['full_name']?.toString() ?? 'Membro')
        : 'Membro';
    final status = row['status']?.toString();
    final type = row['request_type']?.toString();
    final amount = _asDouble(row['amount']);
    final due = _formatDate(row['due_date']);

    return Card(
      child: ListTile(
        onTap: onTap,
        leading: CircleAvatar(
          child: Icon(
            type == 'reimbursement'
                ? Icons.receipt_long_outlined
                : Icons.request_quote_outlined,
          ),
        ),
        title: Text(
          '${FinancialRequestsRepository.categoryLabel(row['category']?.toString())} · ${euro.format(amount)}',
          style: const TextStyle(fontWeight: FontWeight.w800),
        ),
        subtitle: Text([
          name,
          row['description']?.toString(),
          if (due.isNotEmpty) 'Vencimento: $due',
        ].where((value) => value != null && value.isNotEmpty).join('\n')),
        isThreeLine: true,
        trailing: Chip(
          label: Text(FinancialRequestsRepository.statusLabel(status)),
        ),
      ),
    );
  }
}

class _RequestDetailSheet extends StatelessWidget {
  const _RequestDetailSheet({
    required this.row,
    required this.manager,
    required this.owner,
    required this.euro,
    required this.onOpenAttachment,
    required this.onAddReimbursementInfo,
    required this.onApproveReimbursement,
    required this.onRequestInfo,
    required this.onRejectReimbursement,
    required this.onAddClubProof,
    required this.onPayReimbursement,
    required this.onAddChargeProof,
    required this.onApproveCharge,
    required this.onRejectChargeProof,
    required this.onCashCharge,
  });

  final Map<String, dynamic> row;
  final bool manager;
  final bool owner;
  final NumberFormat euro;
  final Future<void> Function(Map<String, dynamic>) onOpenAttachment;
  final VoidCallback onAddReimbursementInfo;
  final VoidCallback onApproveReimbursement;
  final VoidCallback onRequestInfo;
  final VoidCallback onRejectReimbursement;
  final VoidCallback onAddClubProof;
  final VoidCallback onPayReimbursement;
  final VoidCallback onAddChargeProof;
  final VoidCallback onApproveCharge;
  final VoidCallback onRejectChargeProof;
  final VoidCallback onCashCharge;

  @override
  Widget build(BuildContext context) {
    final status = row['status']?.toString() ?? '';
    final type = row['request_type']?.toString() ?? '';
    final attachments = _attachments(row);
    final member = row['member'];
    final memberName = member is Map
        ? (member['nickname']?.toString().trim().isNotEmpty == true
            ? member['nickname'].toString()
            : member['full_name']?.toString() ?? 'Membro')
        : 'Membro';

    return SafeArea(
      child: SingleChildScrollView(
        padding: EdgeInsets.fromLTRB(
          20,
          0,
          20,
          24 + MediaQuery.of(context).viewInsets.bottom,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              FinancialRequestsRepository.categoryLabel(
                row['category']?.toString(),
              ),
              style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                    fontWeight: FontWeight.w900,
                  ),
            ),
            const SizedBox(height: 4),
            Text(
              '${euro.format(_asDouble(row['amount']))} · $memberName',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 10),
            Chip(
              label: Text(FinancialRequestsRepository.statusLabel(status)),
            ),
            const SizedBox(height: 10),
            Text(row['description']?.toString() ?? ''),
            if ((row['review_note']?.toString() ?? '').isNotEmpty) ...[
              const SizedBox(height: 12),
              Card(
                child: ListTile(
                  leading: const Icon(Icons.info_outline),
                  title: const Text('Observação'),
                  subtitle: Text(row['review_note'].toString()),
                ),
              ),
            ],
            const SizedBox(height: 16),
            Text(
              'Anexos',
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w800,
                  ),
            ),
            const SizedBox(height: 6),
            if (attachments.isEmpty)
              const Text('Sem anexos.')
            else
              ...attachments.map(
                (attachment) => ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: Icon(
                    attachment['mime_type'] == 'application/pdf'
                        ? Icons.picture_as_pdf_outlined
                        : Icons.image_outlined,
                  ),
                  title: Text(
                    attachment['original_file_name']?.toString() ?? 'Ficheiro',
                  ),
                  subtitle: Text(
                    _attachmentKindLabel(attachment['kind']?.toString()),
                  ),
                  trailing: const Icon(Icons.open_in_new),
                  onTap: () => onOpenAttachment(attachment),
                ),
              ),
            const SizedBox(height: 18),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                if (type == 'reimbursement' &&
                    owner &&
                    (status == 'draft' || status == 'needs_info'))
                  FilledButton.icon(
                    onPressed: onAddReimbursementInfo,
                    icon: const Icon(Icons.upload_file_outlined),
                    label: Text(
                      status == 'needs_info'
                          ? 'Adicionar e reenviar'
                          : 'Adicionar e submeter',
                    ),
                  ),
                if (type == 'reimbursement' &&
                    manager &&
                    status == 'pending_review') ...[
                  FilledButton.icon(
                    onPressed: onApproveReimbursement,
                    icon: const Icon(Icons.check),
                    label: const Text('Aprovar'),
                  ),
                  OutlinedButton.icon(
                    onPressed: onRequestInfo,
                    icon: const Icon(Icons.help_outline),
                    label: const Text('Pedir informação'),
                  ),
                  OutlinedButton.icon(
                    onPressed: onRejectReimbursement,
                    icon: const Icon(Icons.close),
                    label: const Text('Rejeitar'),
                  ),
                ],
                if (type == 'reimbursement' &&
                    manager &&
                    status == 'approved') ...[
                  OutlinedButton.icon(
                    onPressed: onAddClubProof,
                    icon: const Icon(Icons.attach_file),
                    label: const Text('Anexar comprovativo'),
                  ),
                  FilledButton.icon(
                    onPressed: onPayReimbursement,
                    icon: const Icon(Icons.payments_outlined),
                    label: const Text('Liquidar'),
                  ),
                ],
                if (type == 'charge' &&
                    owner &&
                    status == 'awaiting_payment')
                  FilledButton.icon(
                    onPressed: onAddChargeProof,
                    icon: const Icon(Icons.upload_file_outlined),
                    label: const Text('Enviar comprovativo'),
                  ),
                if (type == 'charge' &&
                    manager &&
                    status == 'awaiting_payment')
                  OutlinedButton.icon(
                    onPressed: onCashCharge,
                    icon: const Icon(Icons.money_outlined),
                    label: const Text('Receber numerário'),
                  ),
                if (type == 'charge' &&
                    manager &&
                    status == 'awaiting_validation') ...[
                  FilledButton.icon(
                    onPressed: onApproveCharge,
                    icon: const Icon(Icons.verified_outlined),
                    label: const Text('Validar pagamento'),
                  ),
                  OutlinedButton.icon(
                    onPressed: onRejectChargeProof,
                    icon: const Icon(Icons.close),
                    label: const Text('Rejeitar comprovativo'),
                  ),
                ],
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _SummaryCard extends StatelessWidget {
  const _SummaryCard({
    required this.icon,
    required this.label,
    required this.value,
  });

  final IconData icon;
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 190,
      child: Card(
        child: ListTile(
          leading: Icon(icon),
          title: Text(label),
          subtitle: Text(
            value,
            style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                  fontWeight: FontWeight.w900,
                ),
          ),
        ),
      ),
    );
  }
}

class _ReimbursementDraft {
  const _ReimbursementDraft({
    required this.memberId,
    required this.amount,
    required this.description,
  });

  final String? memberId;
  final double amount;
  final String description;
}

class _ReimbursementDialog extends StatefulWidget {
  const _ReimbursementDialog({
    required this.manager,
    required this.members,
  });

  final bool manager;
  final List<Map<String, dynamic>> members;

  @override
  State<_ReimbursementDialog> createState() => _ReimbursementDialogState();
}

class _ReimbursementDialogState extends State<_ReimbursementDialog> {
  final _amount = TextEditingController();
  final _description = TextEditingController();
  String? _memberId;

  @override
  void dispose() {
    _amount.dispose();
    _description.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Novo pedido de reembolso'),
      content: SizedBox(
        width: 480,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (widget.manager)
              DropdownButtonFormField<String>(
                initialValue: _memberId,
                decoration: const InputDecoration(labelText: 'Membro'),
                items: widget.members
                    .map(
                      (member) => DropdownMenuItem(
                        value: member['id'].toString(),
                        child: Text(_memberLabel(member)),
                      ),
                    )
                    .toList(),
                onChanged: (value) => setState(() => _memberId = value),
              ),
            if (widget.manager) const SizedBox(height: 10),
            TextField(
              controller: _amount,
              keyboardType:
                  const TextInputType.numberWithOptions(decimal: true),
              decoration: const InputDecoration(labelText: 'Valor (€)'),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: _description,
              minLines: 2,
              maxLines: 4,
              decoration: const InputDecoration(
                labelText: 'Descrição da despesa',
              ),
            ),
            const SizedBox(height: 10),
            const Align(
              alignment: Alignment.centerLeft,
              child: Text(
                'Depois de confirmar vais selecionar um ou vários talões/recibos.',
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancelar'),
        ),
        FilledButton(
          onPressed: () {
            final amount =
                double.tryParse(_amount.text.trim().replaceAll(',', '.'));
            final description = _description.text.trim();
            if (amount == null ||
                amount <= 0 ||
                description.isEmpty ||
                (widget.manager && _memberId == null)) {
              return;
            }
            Navigator.pop(
              context,
              _ReimbursementDraft(
                memberId: _memberId,
                amount: amount,
                description: description,
              ),
            );
          },
          child: const Text('Continuar'),
        ),
      ],
    );
  }
}

class _ChargeDraft {
  const _ChargeDraft({
    required this.memberIds,
    required this.category,
    required this.amount,
    required this.description,
    this.dueDate,
  });

  final List<String> memberIds;
  final String category;
  final double amount;
  final String description;
  final DateTime? dueDate;
}

class _ChargeDialog extends StatefulWidget {
  const _ChargeDialog({required this.members});

  final List<Map<String, dynamic>> members;

  @override
  State<_ChargeDialog> createState() => _ChargeDialogState();
}

class _ChargeDialogState extends State<_ChargeDialog> {
  final _amount = TextEditingController();
  final _description = TextEditingController();
  final _dueDate = TextEditingController();
  final Set<String> _selected = <String>{};
  String _category = 'other';

  @override
  void dispose() {
    _amount.dispose();
    _description.dispose();
    _dueDate.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Nova cobrança'),
      content: SizedBox(
        width: 620,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              DropdownButtonFormField<String>(
                initialValue: _category,
                decoration: const InputDecoration(labelText: 'Tipo'),
                items: const [
                  DropdownMenuItem(value: 'fee', child: Text('Quota')),
                  DropdownMenuItem(
                    value: 'euromillions',
                    child: Text('Euromilhões'),
                  ),
                  DropdownMenuItem(value: 'bar', child: Text('Cartão Bar')),
                  DropdownMenuItem(value: 'other', child: Text('Outro')),
                ],
                onChanged: (value) =>
                    setState(() => _category = value ?? 'other'),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: _amount,
                keyboardType:
                    const TextInputType.numberWithOptions(decimal: true),
                decoration: const InputDecoration(
                  labelText: 'Valor por membro (€)',
                ),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: _description,
                minLines: 2,
                maxLines: 4,
                decoration: const InputDecoration(labelText: 'Descrição'),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: _dueDate,
                decoration: const InputDecoration(
                  labelText: 'Data limite (opcional)',
                  hintText: 'AAAA-MM-DD',
                ),
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Text(
                    'Membros (${_selected.length})',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  const Spacer(),
                  TextButton(
                    onPressed: () {
                      setState(() {
                        if (_selected.length == widget.members.length) {
                          _selected.clear();
                        } else {
                          _selected
                            ..clear()
                            ..addAll(widget.members.map((m) => m['id'].toString()));
                        }
                      });
                    },
                    child: Text(
                      _selected.length == widget.members.length
                          ? 'Limpar'
                          : 'Selecionar todos elegíveis',
                    ),
                  ),
                ],
              ),
              ConstrainedBox(
                constraints: const BoxConstraints(maxHeight: 260),
                child: ListView(
                  shrinkWrap: true,
                  children: widget.members.map((member) {
                    final id = member['id'].toString();
                    return CheckboxListTile(
                      dense: true,
                      value: _selected.contains(id),
                      title: Text(_memberLabel(member)),
                      subtitle: Text(
                        FinancialRequestsRepository.statusLabel(
                          member['status']?.toString(),
                        ),
                      ),
                      onChanged: (checked) {
                        setState(() {
                          if (checked == true) {
                            _selected.add(id);
                          } else {
                            _selected.remove(id);
                          }
                        });
                      },
                    );
                  }).toList(),
                ),
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancelar'),
        ),
        FilledButton(
          onPressed: () {
            final amount =
                double.tryParse(_amount.text.trim().replaceAll(',', '.'));
            final description = _description.text.trim();
            final due = _dueDate.text.trim().isEmpty
                ? null
                : DateTime.tryParse(_dueDate.text.trim());
            if (amount == null ||
                amount <= 0 ||
                description.isEmpty ||
                _selected.isEmpty ||
                (_dueDate.text.trim().isNotEmpty && due == null)) {
              return;
            }
            Navigator.pop(
              context,
              _ChargeDraft(
                memberIds: _selected.toList(),
                category: _category,
                amount: amount,
                description: description,
                dueDate: due,
              ),
            );
          },
          child: const Text('Criar cobranças'),
        ),
      ],
    );
  }
}

class _PaymentDraft {
  const _PaymentDraft({
    required this.accountId,
    required this.method,
    this.note,
  });

  final String accountId;
  final String method;
  final String? note;
}

class _PaymentDialog extends StatefulWidget {
  const _PaymentDialog({
    required this.accounts,
    required this.title,
  });

  final List<Map<String, dynamic>> accounts;
  final String title;

  @override
  State<_PaymentDialog> createState() => _PaymentDialogState();
}

class _PaymentDialogState extends State<_PaymentDialog> {
  final _note = TextEditingController();
  String? _accountId;
  String _method = 'bank_transfer';

  @override
  void dispose() {
    _note.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.title),
      content: SizedBox(
        width: 460,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            DropdownButtonFormField<String>(
              initialValue: _accountId,
              decoration: const InputDecoration(labelText: 'Conta financeira'),
              items: widget.accounts
                  .map(
                    (account) => DropdownMenuItem(
                      value: account['id'].toString(),
                      child: Text(
                        '${account['icon'] ?? '💰'} ${account['name'] ?? 'Conta'}',
                      ),
                    ),
                  )
                  .toList(),
              onChanged: (value) => setState(() => _accountId = value),
            ),
            const SizedBox(height: 10),
            DropdownButtonFormField<String>(
              initialValue: _method,
              decoration: const InputDecoration(labelText: 'Método'),
              items: const [
                DropdownMenuItem(
                  value: 'bank_transfer',
                  child: Text('Transferência'),
                ),
                DropdownMenuItem(value: 'mbway', child: Text('MB Way')),
                DropdownMenuItem(value: 'cash', child: Text('Numerário')),
                DropdownMenuItem(value: 'other', child: Text('Outro')),
              ],
              onChanged: (value) =>
                  setState(() => _method = value ?? 'bank_transfer'),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: _note,
              minLines: 1,
              maxLines: 3,
              decoration: const InputDecoration(
                labelText: 'Observação (opcional)',
              ),
            ),
            if (_method != 'cash') ...[
              const SizedBox(height: 10),
              const Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  'Para reembolsos por transferência/MB Way, anexa primeiro o comprovativo de pagamento.',
                ),
              ),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancelar'),
        ),
        FilledButton(
          onPressed: _accountId == null
              ? null
              : () => Navigator.pop(
                    context,
                    _PaymentDraft(
                      accountId: _accountId!,
                      method: _method,
                      note: _note.text.trim().isEmpty ? null : _note.text.trim(),
                    ),
                  ),
          child: const Text('Confirmar'),
        ),
      ],
    );
  }
}

class _AccountDialog extends StatefulWidget {
  const _AccountDialog({
    required this.accounts,
    required this.title,
  });

  final List<Map<String, dynamic>> accounts;
  final String title;

  @override
  State<_AccountDialog> createState() => _AccountDialogState();
}

class _AccountDialogState extends State<_AccountDialog> {
  String? _accountId;

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.title),
      content: DropdownButtonFormField<String>(
        initialValue: _accountId,
        decoration: const InputDecoration(labelText: 'Conta financeira'),
        items: widget.accounts
            .map(
              (account) => DropdownMenuItem(
                value: account['id'].toString(),
                child: Text(
                  '${account['icon'] ?? '💰'} ${account['name'] ?? 'Conta'}',
                ),
              ),
            )
            .toList(),
        onChanged: (value) => setState(() => _accountId = value),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancelar'),
        ),
        FilledButton(
          onPressed: _accountId == null
              ? null
              : () => Navigator.pop(context, _accountId),
          child: const Text('Confirmar'),
        ),
      ],
    );
  }
}

List<Map<String, dynamic>> _attachments(Map<String, dynamic> row) {
  final raw = row['attachments'];
  if (raw is! List) return const <Map<String, dynamic>>[];
  return raw.map((item) => Map<String, dynamic>.from(item as Map)).toList();
}

String _attachmentKindLabel(String? kind) => switch (kind) {
      'receipt' => 'Talão / recibo',
      'member_payment_proof' => 'Comprovativo do membro',
      'club_payment_proof' => 'Comprovativo do clube',
      _ => 'Anexo',
    };

String _memberLabel(Map<String, dynamic> member) {
  final nickname = member['nickname']?.toString().trim() ?? '';
  final name = member['full_name']?.toString().trim() ?? 'Membro';
  return nickname.isEmpty ? name : '$nickname · $name';
}

String _formatDate(Object? raw) {
  final value = raw?.toString() ?? '';
  if (value.isEmpty) return '';
  final date = DateTime.tryParse(value);
  return date == null ? value : DateFormat('dd/MM/yyyy').format(date);
}

double _asDouble(Object? value) {
  if (value is num) return value.toDouble();
  return double.tryParse(value?.toString().replaceAll(',', '.') ?? '') ?? 0;
}

String _errorText(Object error) {
  final value = error.toString();
  const markers = ['message: ', 'PostgrestException(message: '];
  for (final marker in markers) {
    final index = value.indexOf(marker);
    if (index >= 0) {
      final tail = value.substring(index + marker.length);
      final end = tail.indexOf(',');
      return (end >= 0 ? tail.substring(0, end) : tail).trim();
    }
  }
  return value;
}
