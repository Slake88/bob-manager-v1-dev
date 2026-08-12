import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../repositories/member_lifecycle_repository.dart';

class MemberHistoryScreen extends StatelessWidget {
  const MemberHistoryScreen({
    super.key,
    required this.member,
    this.initialIndex = 0,
  });

  final Map<String, dynamic> member;
  final int initialIndex;

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 4,
      initialIndex: initialIndex.clamp(0, 3),
      child: Scaffold(
        appBar: AppBar(
          title: Text(member['full_name']?.toString() ?? 'Histórico do membro'),
          bottom: const TabBar(
            isScrollable: true,
            tabs: [
              Tab(icon: Icon(Icons.two_wheeler_outlined), text: 'Motas'),
              Tab(icon: Icon(Icons.build_outlined), text: 'Manutenção'),
              Tab(icon: Icon(Icons.military_tech_outlined), text: 'Patches'),
              Tab(icon: Icon(Icons.timeline_outlined), text: 'Timeline'),
            ],
          ),
        ),
        body: TabBarView(
          children: [
            _MotorcyclesTab(member: member),
            _MaintenanceTab(member: member),
            _PatchesTab(member: member),
            _TimelineTab(member: member),
          ],
        ),
      ),
    );
  }
}

class _MotorcyclesTab extends StatefulWidget {
  const _MotorcyclesTab({required this.member});
  final Map<String, dynamic> member;

  @override
  State<_MotorcyclesTab> createState() => _MotorcyclesTabState();
}

class _MotorcyclesTabState extends State<_MotorcyclesTab> {
  final MemberLifecycleRepository _repository = MemberLifecycleRepository();
  late Future<List<Map<String, dynamic>>> _future;

  @override
  void initState() {
    super.initState();
    _reload();
  }

  void _reload() => _future = _repository.motorcycles(widget.member['id'].toString());

  Future<void> _refresh() async {
    setState(_reload);
    await _future;
  }

  Future<void> _edit([Map<String, dynamic>? motorcycle]) async {
    final brand = TextEditingController(text: motorcycle?['brand']?.toString() ?? '');
    final model = TextEditingController(text: motorcycle?['model']?.toString() ?? '');
    final year = TextEditingController(text: motorcycle?['year']?.toString() ?? '');
    final registration = TextEditingController(text: motorcycle?['registration']?.toString() ?? '');
    final nickname = TextEditingController(text: motorcycle?['nickname']?.toString() ?? '');
    final acquiredOn = TextEditingController(text: motorcycle?['acquired_on']?.toString() ?? '');
    final notes = TextEditingController(text: motorcycle?['notes']?.toString() ?? '');
    var primary = motorcycle?['primary_motorcycle'] == true;

    final save = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: Text(motorcycle == null ? 'Adicionar mota' : 'Editar mota'),
          content: SizedBox(
            width: 620,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextField(controller: brand, decoration: const InputDecoration(labelText: 'Marca')),
                  const SizedBox(height: 8),
                  TextField(controller: model, decoration: const InputDecoration(labelText: 'Modelo')),
                  const SizedBox(height: 8),
                  TextField(controller: year, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'Ano')),
                  const SizedBox(height: 8),
                  TextField(controller: registration, decoration: const InputDecoration(labelText: 'Matrícula')),
                  const SizedBox(height: 8),
                  TextField(controller: nickname, decoration: const InputDecoration(labelText: 'Nome / alcunha da mota')),
                  const SizedBox(height: 8),
                  TextField(controller: acquiredOn, decoration: const InputDecoration(labelText: 'Data de aquisição', hintText: 'AAAA-MM-DD')),
                  const SizedBox(height: 8),
                  TextField(controller: notes, maxLines: 3, decoration: const InputDecoration(labelText: 'Notas')),
                  SwitchListTile.adaptive(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('Mota principal'),
                    value: primary,
                    onChanged: (value) => setDialogState(() => primary = value),
                  ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(dialogContext, false), child: const Text('Cancelar')),
            FilledButton(onPressed: () => Navigator.pop(dialogContext, true), child: const Text('Guardar')),
          ],
        ),
      ),
    );
    if (save != true) {
      for (final c in [brand, model, year, registration, nickname, acquiredOn, notes]) {
        c.dispose();
      }
      return;
    }
    try {
      await _repository.saveMotorcycle(
        member: widget.member,
        motorcycleId: motorcycle?['id']?.toString(),
        brand: brand.text,
        model: model.text,
        year: int.tryParse(year.text.trim()),
        registration: registration.text,
        nickname: nickname.text,
        acquiredOn: acquiredOn.text,
        notes: notes.text,
        primary: primary,
      );
      if (mounted) setState(_reload);
    } catch (error) {
      if (mounted) _message(context, error.toString());
    } finally {
      for (final c in [brand, model, year, registration, nickname, acquiredOn, notes]) {
        c.dispose();
      }
    }
  }

  Future<void> _archive(Map<String, dynamic> motorcycle) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Arquivar mota?'),
        content: const Text('A mota deixa de estar ativa, mas todo o histórico de manutenção é preservado.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dialogContext, false), child: const Text('Cancelar')),
          FilledButton(onPressed: () => Navigator.pop(dialogContext, true), child: const Text('Arquivar')),
        ],
      ),
    );
    if (confirmed != true) return;
    try {
      await _repository.archiveMotorcycle(
        member: widget.member,
        motorcycleId: motorcycle['id'].toString(),
      );
      if (mounted) setState(_reload);
    } catch (error) {
      if (mounted) _message(context, error.toString());
    }
  }

  @override
  Widget build(BuildContext context) {
    final canManage = _repository.canManageMember(widget.member);
    return FutureBuilder<List<Map<String, dynamic>>>(
      future: _future,
      builder: (context, snapshot) {
        if (snapshot.hasError) return _error(snapshot.error);
        if (!snapshot.hasData) return const Center(child: CircularProgressIndicator());
        final rows = snapshot.data!;
        return RefreshIndicator(
          onRefresh: _refresh,
          child: ListView(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 96),
            children: [
              _intro(
                context,
                'Motas do membro',
                'Várias motas podem coexistir. Arquivar preserva o histórico e a mota principal é única.',
                canManage
                    ? FilledButton.icon(onPressed: () => _edit(), icon: const Icon(Icons.add), label: const Text('Adicionar mota'))
                    : null,
              ),
              const SizedBox(height: 12),
              if (rows.isEmpty)
                const Card(child: ListTile(title: Text('Sem motas registadas.')))
              else
                for (final row in rows)
                  Card(
                    child: ListTile(
                      leading: Icon(row['active'] == false ? Icons.archive_outlined : Icons.two_wheeler_outlined),
                      title: Text(_motorcycleLabel(row)),
                      subtitle: Text([
                        if ((row['registration']?.toString() ?? '').isNotEmpty) row['registration'].toString(),
                        if (row['year'] != null) row['year'].toString(),
                        if ((row['nickname']?.toString() ?? '').isNotEmpty) '“${row['nickname']}”',
                        if (row['active'] == false) 'Arquivada ${row['retired_on'] ?? ''}',
                      ].join(' • ')),
                      trailing: Wrap(
                        spacing: 4,
                        crossAxisAlignment: WrapCrossAlignment.center,
                        children: [
                          if (row['primary_motorcycle'] == true)
                            const Chip(label: Text('Principal'), visualDensity: VisualDensity.compact),
                          if (canManage && row['active'] != false)
                            PopupMenuButton<String>(
                              onSelected: (value) {
                                if (value == 'edit') _edit(row);
                                if (value == 'archive') _archive(row);
                              },
                              itemBuilder: (_) => const [
                                PopupMenuItem(value: 'edit', child: Text('Editar')),
                                PopupMenuItem(value: 'archive', child: Text('Arquivar')),
                              ],
                            ),
                        ],
                      ),
                    ),
                  ),
            ],
          ),
        );
      },
    );
  }
}

class _MaintenanceTab extends StatefulWidget {
  const _MaintenanceTab({required this.member});
  final Map<String, dynamic> member;

  @override
  State<_MaintenanceTab> createState() => _MaintenanceTabState();
}

class _MaintenanceTabState extends State<_MaintenanceTab> {
  final MemberLifecycleRepository _repository = MemberLifecycleRepository();
  late Future<_MaintenanceData> _future;

  @override
  void initState() {
    super.initState();
    _reload();
  }

  void _reload() {
    _future = Future.wait([
      _repository.motorcycles(widget.member['id'].toString()),
      _repository.maintenance(widget.member['id'].toString()),
    ]).then((values) => _MaintenanceData(
          motorcycles: values[0],
          records: values[1],
        ));
  }

  Future<void> _refresh() async {
    setState(_reload);
    await _future;
  }

  Future<void> _editMaintenance(_MaintenanceData data, [Map<String, dynamic>? record]) async {
    final activeBikes = data.motorcycles.where((row) => row['active'] != false).toList();
    if (activeBikes.isEmpty) {
      _message(context, 'Regista primeiro uma mota ativa.');
      return;
    }
    var motorcycleId = record?['motorcycle_id']?.toString() ?? activeBikes.first['id'].toString();
    if (!activeBikes.any((row) => row['id'].toString() == motorcycleId)) {
      motorcycleId = activeBikes.first['id'].toString();
    }
    final serviceDate = TextEditingController(text: record?['service_date']?.toString() ?? _today());
    final type = TextEditingController(text: record?['service_type']?.toString() ?? 'Revisão');
    final description = TextEditingController(text: record?['description']?.toString() ?? '');
    final odometer = TextEditingController(text: record?['odometer_km']?.toString() ?? '');
    final workshop = TextEditingController(text: record?['workshop']?.toString() ?? '');
    final cost = TextEditingController(text: record?['cost']?.toString() ?? '0');
    final nextDate = TextEditingController(text: record?['next_service_date']?.toString() ?? '');
    final nextKm = TextEditingController(text: record?['next_service_km']?.toString() ?? '');
    final notes = TextEditingController(text: record?['notes']?.toString() ?? '');

    final save = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: Text(record == null ? 'Nova manutenção' : 'Editar manutenção'),
          content: SizedBox(
            width: 680,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  DropdownButtonFormField<String>(
                    initialValue: motorcycleId,
                    decoration: const InputDecoration(labelText: 'Mota'),
                    items: activeBikes.map((row) => DropdownMenuItem(value: row['id'].toString(), child: Text(_motorcycleLabel(row)))).toList(),
                    onChanged: (value) {
                      if (value != null) setDialogState(() => motorcycleId = value);
                    },
                  ),
                  const SizedBox(height: 8),
                  TextField(controller: serviceDate, decoration: const InputDecoration(labelText: 'Data', hintText: 'AAAA-MM-DD')),
                  const SizedBox(height: 8),
                  TextField(controller: type, decoration: const InputDecoration(labelText: 'Tipo de serviço')),
                  const SizedBox(height: 8),
                  TextField(controller: description, maxLines: 2, decoration: const InputDecoration(labelText: 'Descrição')),
                  const SizedBox(height: 8),
                  TextField(controller: odometer, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'Quilometragem')),
                  const SizedBox(height: 8),
                  TextField(controller: workshop, decoration: const InputDecoration(labelText: 'Oficina / fornecedor')),
                  const SizedBox(height: 8),
                  TextField(controller: cost, keyboardType: const TextInputType.numberWithOptions(decimal: true), decoration: const InputDecoration(labelText: 'Custo (€)')),
                  const SizedBox(height: 8),
                  TextField(controller: nextDate, decoration: const InputDecoration(labelText: 'Próxima revisão', hintText: 'AAAA-MM-DD')),
                  const SizedBox(height: 8),
                  TextField(controller: nextKm, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'Próxima revisão aos km')),
                  const SizedBox(height: 8),
                  TextField(controller: notes, maxLines: 3, decoration: const InputDecoration(labelText: 'Notas')),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(dialogContext, false), child: const Text('Cancelar')),
            FilledButton(onPressed: () => Navigator.pop(dialogContext, true), child: const Text('Guardar')),
          ],
        ),
      ),
    );
    if (save != true) {
      for (final c in [serviceDate, type, description, odometer, workshop, cost, nextDate, nextKm, notes]) {
        c.dispose();
      }
      return;
    }
    try {
      await _repository.saveMaintenance(
        member: widget.member,
        motorcycleId: motorcycleId,
        recordId: record?['id']?.toString(),
        serviceDate: serviceDate.text.trim(),
        serviceType: type.text,
        description: description.text,
        odometerKm: int.tryParse(odometer.text.trim()),
        workshop: workshop.text,
        cost: _double(cost.text),
        nextServiceDate: nextDate.text,
        nextServiceKm: int.tryParse(nextKm.text.trim()),
        notes: notes.text,
      );
      if (mounted) setState(_reload);
    } catch (error) {
      if (mounted) _message(context, error.toString());
    } finally {
      for (final c in [serviceDate, type, description, odometer, workshop, cost, nextDate, nextKm, notes]) {
        c.dispose();
      }
    }
  }

  Future<void> _upload(Map<String, dynamic> record) async {
    final result = await FilePicker.platform.pickFiles(
      allowMultiple: true,
      withData: true,
      type: FileType.custom,
      allowedExtensions: const ['pdf', 'jpg', 'jpeg', 'png', 'webp'],
    );
    if (result == null || result.files.isEmpty) return;
    try {
      await _repository.uploadMaintenanceFiles(
        member: widget.member,
        maintenanceId: record['id'].toString(),
        files: result.files,
      );
      if (mounted) setState(_reload);
    } catch (error) {
      if (mounted) _message(context, error.toString());
    }
  }

  Future<void> _openAttachment(Map<String, dynamic> attachment) async {
    try {
      final url = await _repository.signedMaintenanceUrl(attachment['storage_path'].toString());
      final opened = await launchUrl(Uri.parse(url), mode: LaunchMode.platformDefault);
      if (!opened && mounted) _message(context, 'Não foi possível abrir o documento.');
    } catch (error) {
      if (mounted) _message(context, error.toString());
    }
  }

  Future<void> _deleteAttachment(Map<String, dynamic> attachment) async {
    try {
      await _repository.deleteMaintenanceAttachment(member: widget.member, attachment: attachment);
      if (mounted) setState(_reload);
    } catch (error) {
      if (mounted) _message(context, error.toString());
    }
  }

  @override
  Widget build(BuildContext context) {
    final canManage = _repository.canManageMember(widget.member);
    return FutureBuilder<_MaintenanceData>(
      future: _future,
      builder: (context, snapshot) {
        if (snapshot.hasError) return _error(snapshot.error);
        if (!snapshot.hasData) return const Center(child: CircularProgressIndicator());
        final data = snapshot.data!;
        final byBike = {for (final row in data.motorcycles) row['id'].toString(): row};
        final total = data.records.fold<double>(0, (sum, row) => sum + _double(row['cost']));
        return RefreshIndicator(
          onRefresh: _refresh,
          child: ListView(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 96),
            children: [
              _intro(
                context,
                'Histórico de manutenção',
                'Serviços, custos, quilometragem, próximas revisões e documentos privados.',
                canManage
                    ? FilledButton.icon(onPressed: () => _editMaintenance(data), icon: const Icon(Icons.add), label: const Text('Novo serviço'))
                    : null,
              ),
              const SizedBox(height: 8),
              Card(
                child: ListTile(
                  leading: const Icon(Icons.euro_outlined),
                  title: const Text('Custo total registado'),
                  trailing: Text('${total.toStringAsFixed(2)} €', style: Theme.of(context).textTheme.titleMedium),
                ),
              ),
              if (data.records.isEmpty)
                const Card(child: ListTile(title: Text('Sem manutenções registadas.')))
              else
                for (final record in data.records)
                  Card(
                    child: ExpansionTile(
                      leading: const Icon(Icons.build_circle_outlined),
                      title: Text('${record['service_date']} — ${record['service_type']}'),
                      subtitle: Text('${_motorcycleLabel(byBike[record['motorcycle_id']?.toString()] ?? const {})} • ${_double(record['cost']).toStringAsFixed(2)} €'),
                      trailing: canManage
                          ? IconButton(tooltip: 'Editar', onPressed: () => _editMaintenance(data, record), icon: const Icon(Icons.edit_outlined))
                          : null,
                      childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                      children: [
                        if ((record['description']?.toString() ?? '').isNotEmpty) _detailLine('Descrição', record['description'].toString()),
                        if (record['odometer_km'] != null) _detailLine('Quilometragem', '${record['odometer_km']} km'),
                        if ((record['workshop']?.toString() ?? '').isNotEmpty) _detailLine('Oficina', record['workshop'].toString()),
                        if (record['next_service_date'] != null) _detailLine('Próxima revisão', record['next_service_date'].toString()),
                        if (record['next_service_km'] != null) _detailLine('Próximos km', '${record['next_service_km']} km'),
                        if ((record['notes']?.toString() ?? '').isNotEmpty) _detailLine('Notas', record['notes'].toString()),
                        const Divider(),
                        Align(
                          alignment: Alignment.centerLeft,
                          child: Text('Documentos', style: Theme.of(context).textTheme.titleSmall),
                        ),
                        const SizedBox(height: 4),
                        ..._attachments(record).map(
                          (attachment) => ListTile(
                            dense: true,
                            contentPadding: EdgeInsets.zero,
                            leading: const Icon(Icons.attach_file),
                            title: Text(attachment['original_file_name']?.toString() ?? 'Documento'),
                            onTap: () => _openAttachment(attachment),
                            trailing: canManage
                                ? IconButton(tooltip: 'Remover documento', onPressed: () => _deleteAttachment(attachment), icon: const Icon(Icons.delete_outline))
                                : null,
                          ),
                        ),
                        if (canManage)
                          Align(
                            alignment: Alignment.centerLeft,
                            child: OutlinedButton.icon(onPressed: () => _upload(record), icon: const Icon(Icons.upload_file_outlined), label: const Text('Adicionar documento')),
                          ),
                      ],
                    ),
                  ),
            ],
          ),
        );
      },
    );
  }
}

class _PatchesTab extends StatefulWidget {
  const _PatchesTab({required this.member});
  final Map<String, dynamic> member;

  @override
  State<_PatchesTab> createState() => _PatchesTabState();
}

class _PatchesTabState extends State<_PatchesTab> {
  final MemberLifecycleRepository _repository = MemberLifecycleRepository();
  late Future<List<Map<String, dynamic>>> _future;

  @override
  void initState() {
    super.initState();
    _reload();
  }

  void _reload() => _future = _repository.patches(widget.member['id'].toString());

  Future<void> _refresh() async {
    setState(_reload);
    await _future;
  }

  Future<void> _requestPatch() async {
    try {
      final catalog = await _repository.patchCatalog();
      if (!mounted) return;
      if (catalog.isEmpty) {
        _message(context, 'Não existem artigos da Loja marcados como “entrega institucional”.');
        return;
      }
      String productId = catalog.first['id'].toString();
      String? variantId;
      final notes = TextEditingController();
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (dialogContext) => StatefulBuilder(
          builder: (context, setDialogState) {
            final product = catalog.firstWhere((row) => row['id'].toString() == productId);
            final variants = _mapList(product['variants']);
            if (variants.isNotEmpty && !variants.any((row) => row['id'].toString() == variantId)) {
              variantId = variants.first['id'].toString();
            }
            if (variants.isEmpty) variantId = null;
            return AlertDialog(
              title: const Text('Atribuir patch'),
              content: SizedBox(
                width: 580,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    DropdownButtonFormField<String>(
                      initialValue: productId,
                      decoration: const InputDecoration(labelText: 'Patch / artigo institucional'),
                      items: catalog.map((row) => DropdownMenuItem(value: row['id'].toString(), child: Text(row['name'].toString()))).toList(),
                      onChanged: (value) {
                        if (value != null) setDialogState(() {
                          productId = value;
                          variantId = null;
                        });
                      },
                    ),
                    if (variants.isNotEmpty) ...[
                      const SizedBox(height: 8),
                      DropdownButtonFormField<String>(
                        initialValue: variantId,
                        decoration: const InputDecoration(labelText: 'Variante'),
                        items: variants.map((row) => DropdownMenuItem(value: row['id'].toString(), child: Text(row['name'].toString()))).toList(),
                        onChanged: (value) => setDialogState(() => variantId = value),
                      ),
                    ],
                    const SizedBox(height: 8),
                    TextField(controller: notes, maxLines: 2, decoration: const InputDecoration(labelText: 'Notas')),
                  ],
                ),
              ),
              actions: [
                TextButton(onPressed: () => Navigator.pop(dialogContext, false), child: const Text('Cancelar')),
                FilledButton(onPressed: () => Navigator.pop(dialogContext, true), child: const Text('Criar pedido')),
              ],
            );
          },
        ),
      );
      if (confirmed == true) {
        await _repository.requestPatch(
          memberId: widget.member['id'].toString(),
          productId: productId,
          variantId: variantId,
          notes: notes.text,
        );
        if (mounted) setState(_reload);
      }
      notes.dispose();
    } catch (error) {
      if (mounted) _message(context, error.toString());
    }
  }

  Future<void> _approve(String id) => _action(() => _repository.approvePatch(id), 'Patch aprovado.');
  Future<void> _cancel(String id) => _action(() => _repository.cancelPatch(id), 'Patch cancelado.');

  Future<void> _deliver(String id) async {
    try {
      final locations = await _repository.inventoryLocations();
      if (!mounted) return;
      if (locations.isEmpty) {
        _message(context, 'Não existem locais de inventário ativos.');
        return;
      }
      var locationId = locations.first['id'].toString();
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (dialogContext) => StatefulBuilder(
          builder: (context, setDialogState) => AlertDialog(
            title: const Text('Confirmar entrega e descontar stock'),
            content: SizedBox(
              width: 520,
              child: DropdownButtonFormField<String>(
                initialValue: locationId,
                decoration: const InputDecoration(labelText: 'Local de saída'),
                items: locations.map((row) => DropdownMenuItem(value: row['id'].toString(), child: Text(row['name'].toString()))).toList(),
                onChanged: (value) {
                  if (value != null) setDialogState(() => locationId = value);
                },
              ),
            ),
            actions: [
              TextButton(onPressed: () => Navigator.pop(dialogContext, false), child: const Text('Cancelar')),
              FilledButton(onPressed: () => Navigator.pop(dialogContext, true), child: const Text('Entregar')),
            ],
          ),
        ),
      );
      if (confirmed != true) return;
      await _repository.deliverPatch(awardId: id, locationId: locationId);
      if (mounted) {
        _message(context, 'Patch entregue e stock atualizado.');
        setState(_reload);
      }
    } catch (error) {
      if (mounted) _message(context, error.toString());
    }
  }

  Future<void> _action(Future<void> Function() operation, String success) async {
    try {
      await operation();
      if (mounted) {
        _message(context, success);
        setState(_reload);
      }
    } catch (error) {
      if (mounted) _message(context, error.toString());
    }
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<List<Map<String, dynamic>>>(
      future: _future,
      builder: (context, snapshot) {
        if (snapshot.hasError) return _error(snapshot.error);
        if (!snapshot.hasData) return const Center(child: CircularProgressIndicator());
        final rows = snapshot.data!;
        return RefreshIndicator(
          onRefresh: _refresh,
          child: ListView(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 96),
            children: [
              _intro(
                context,
                'Patches e distinções',
                'A Direção aprova a atribuição. O stock só é descontado quando o Inventário confirma a entrega.',
                _repository.canManagePatches
                    ? FilledButton.icon(onPressed: _requestPatch, icon: const Icon(Icons.add), label: const Text('Atribuir patch'))
                    : null,
              ),
              const SizedBox(height: 12),
              if (rows.isEmpty)
                const Card(child: ListTile(title: Text('Sem patches registados.')))
              else
                for (final row in rows)
                  Card(
                    child: ListTile(
                      leading: const Icon(Icons.military_tech_outlined),
                      title: Text('${row['patch_name']}${row['variant_name'] == null ? '' : ' — ${row['variant_name']}'}'),
                      subtitle: Text('${MemberLifecycleRepository.patchStatusLabel(row['status']?.toString() ?? '')} • ${row['requested_at'] ?? ''}${row['delivery_location_name'] == null ? '' : ' • ${row['delivery_location_name']}'}'),
                      trailing: _patchActions(row),
                    ),
                  ),
            ],
          ),
        );
      },
    );
  }

  Widget? _patchActions(Map<String, dynamic> row) {
    final status = row['status']?.toString();
    final id = row['id'].toString();
    final actions = <PopupMenuEntry<String>>[];
    if (status == 'pending' && _repository.canManagePatches) {
      actions.add(const PopupMenuItem(value: 'approve', child: Text('Aprovar')));
      actions.add(const PopupMenuItem(value: 'cancel', child: Text('Cancelar')));
    }
    if (status == 'approved') {
      if (_repository.canDeliverPatches) {
        actions.add(const PopupMenuItem(value: 'deliver', child: Text('Confirmar entrega')));
      }
      if (_repository.canManagePatches) {
        actions.add(const PopupMenuItem(value: 'cancel', child: Text('Cancelar')));
      }
    }
    if (actions.isEmpty) return null;
    return PopupMenuButton<String>(
      itemBuilder: (_) => actions,
      onSelected: (value) {
        if (value == 'approve') _approve(id);
        if (value == 'cancel') _cancel(id);
        if (value == 'deliver') _deliver(id);
      },
    );
  }
}

class _TimelineTab extends StatefulWidget {
  const _TimelineTab({required this.member});
  final Map<String, dynamic> member;

  @override
  State<_TimelineTab> createState() => _TimelineTabState();
}

class _TimelineTabState extends State<_TimelineTab> {
  final MemberLifecycleRepository _repository = MemberLifecycleRepository();
  late Future<List<Map<String, dynamic>>> _future;

  @override
  void initState() {
    super.initState();
    _reload();
  }

  void _reload() => _future = _repository.timeline(widget.member['id'].toString());

  Future<void> _refresh() async {
    setState(_reload);
    await _future;
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<List<Map<String, dynamic>>>(
      future: _future,
      builder: (context, snapshot) {
        if (snapshot.hasError) return _error(snapshot.error);
        if (!snapshot.hasData) return const Center(child: CircularProgressIndicator());
        final rows = snapshot.data!;
        return RefreshIndicator(
          onRefresh: _refresh,
          child: ListView(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 96),
            children: [
              _intro(
                context,
                'Timeline automática',
                'Percurso do membro: estados, cargos, motas, manutenções e patches. Eventos privados só aparecem a quem tem acesso.',
                null,
              ),
              const SizedBox(height: 12),
              if (rows.isEmpty)
                const Card(child: ListTile(title: Text('Ainda não existem eventos na Timeline.')))
              else
                for (final row in rows)
                  Card(
                    child: ListTile(
                      leading: CircleAvatar(child: Icon(_timelineIcon(row['event_type']?.toString() ?? ''))),
                      title: Text(row['title']?.toString() ?? 'Evento'),
                      subtitle: Text([
                        row['event_date']?.toString() ?? '',
                        if ((row['description']?.toString() ?? '').isNotEmpty) row['description'].toString(),
                      ].join('\n')),
                      trailing: row['visibility'] == 'member_private'
                          ? const Tooltip(message: 'Privado do membro / Direção', child: Icon(Icons.lock_outline, size: 18))
                          : null,
                    ),
                  ),
            ],
          ),
        );
      },
    );
  }
}

class _MaintenanceData {
  const _MaintenanceData({required this.motorcycles, required this.records});
  final List<Map<String, dynamic>> motorcycles;
  final List<Map<String, dynamic>> records;
}

Widget _intro(BuildContext context, String title, String subtitle, Widget? action) {
  return Card(
    child: Padding(
      padding: const EdgeInsets.all(16),
      child: Wrap(
        spacing: 12,
        runSpacing: 12,
        alignment: WrapAlignment.spaceBetween,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 680),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: Theme.of(context).textTheme.titleLarge),
                const SizedBox(height: 4),
                Text(subtitle),
              ],
            ),
          ),
          if (action != null) action,
        ],
      ),
    ),
  );
}

Widget _error(Object? error) => Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Text('Erro: $error', textAlign: TextAlign.center),
      ),
    );

void _message(BuildContext context, String message) {
  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(content: Text(message)));
}

String _motorcycleLabel(Map<String, dynamic> row) {
  final brand = row['brand']?.toString().trim() ?? '';
  final model = row['model']?.toString().trim() ?? '';
  final label = '$brand $model'.trim();
  return label.isEmpty ? 'Mota' : label;
}

String _today() {
  final now = DateTime.now();
  return '${now.year.toString().padLeft(4, '0')}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}';
}

double _double(Object? value) {
  if (value is num) return value.toDouble();
  return double.tryParse(value?.toString().replaceAll(',', '.') ?? '') ?? 0;
}

List<Map<String, dynamic>> _attachments(Map<String, dynamic> record) {
  final raw = record['maintenance_attachments'];
  if (raw is! List) return const [];
  return raw.whereType<Map>().map((row) => Map<String, dynamic>.from(row)).toList();
}

List<Map<String, dynamic>> _mapList(Object? raw) {
  if (raw is! List) return const [];
  return raw.whereType<Map>().map((row) => Map<String, dynamic>.from(row)).toList();
}

Widget _detailLine(String label, String value) {
  return Padding(
    padding: const EdgeInsets.symmetric(vertical: 3),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(width: 145, child: Text(label, style: const TextStyle(fontWeight: FontWeight.w600))),
        Expanded(child: Text(value)),
      ],
    ),
  );
}

IconData _timelineIcon(String type) => switch (type) {
      'member_created' => Icons.person_add_alt_1,
      'status_change' || 'prospect_joined' || 'full_colors' => Icons.badge_outlined,
      'position_assigned' || 'position_ended' => Icons.workspace_premium_outlined,
      'motorcycle_added' || 'motorcycle_primary' || 'motorcycle_archived' => Icons.two_wheeler_outlined,
      'maintenance' => Icons.build_outlined,
      'patch_requested' || 'patch_approved' || 'patch_delivered' || 'patch_cancelled' => Icons.military_tech_outlined,
      _ => Icons.history,
    };
