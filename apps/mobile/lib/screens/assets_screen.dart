import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';

import '../core/app_session.dart';
import '../core/permissions.dart';
import '../repositories/assets_repository.dart';

class AssetsScreen extends StatefulWidget {
  const AssetsScreen({super.key});

  @override
  State<AssetsScreen> createState() => _AssetsScreenState();
}

class _AssetsScreenState extends State<AssetsScreen> {
  final AssetsRepository _repository = AssetsRepository();
  final TextEditingController _search = TextEditingController();
  late Future<_AssetsData> _future;
  String? _category;
  String? _condition;
  String? _locationId;
  String? _responsibleId;

  bool get _canManage => AppSession.instance.can(AppPermission.manageAssets);

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

  void _reload() {
    _future = Future.wait([
      _repository.assets(),
      _repository.categories(),
      _repository.locations(),
      _repository.members(),
    ]).then(
      (values) => _AssetsData(
        assets: List<Map<String, dynamic>>.from(values[0]),
        categories: List<Map<String, dynamic>>.from(values[1]),
        locations: List<Map<String, dynamic>>.from(values[2]),
        members: List<Map<String, dynamic>>.from(values[3]),
      ),
    );
  }

  Future<void> _refresh() async {
    setState(_reload);
    await _future;
  }

  void _error(Object error) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(error.toString())));
  }

  Future<void> _edit(
    _AssetsData data, [
    Map<String, dynamic>? asset,
  ]) async {
    try {
      final codes = asset == null
          ? await _repository.nextCodes()
          : {
              'asset_number': asset['asset_number']?.toString() ?? '',
              'qr_code': asset['qr_code']?.toString() ?? '',
            };
      if (!mounted) return;
      final result = await Navigator.of(context).push<_AssetInput>(
        MaterialPageRoute(
          builder: (_) => _AssetEditor(
            repository: _repository,
            asset: asset,
            codes: codes,
            categories: data.categories,
            locations: data.locations,
            members: data.members,
          ),
        ),
      );
      if (result == null) return;

      final saved = await _repository.saveAsset(
        id: asset?['id']?.toString(),
        assetNumber: result.assetNumber,
        qrCode: result.qrCode,
        name: result.name,
        category: result.category,
        description: result.description,
        brand: result.brand,
        model: result.model,
        serialNumber: result.serialNumber,
        condition: result.condition,
        locationId: result.locationId,
        responsibleMemberId: result.responsibleMemberId,
        acquisitionDate: result.acquisitionDate,
        acquisitionValue: result.acquisitionValue,
        currentValue: result.currentValue,
        supplier: result.supplier,
        warrantyUntil: result.warrantyUntil,
        requiresInspection: result.requiresInspection,
        inspectionIntervalMonths: result.inspectionIntervalMonths,
        lastInspectionAt: result.lastInspectionAt,
        nextInspectionAt: result.nextInspectionAt,
        customAttributes: result.customAttributes,
        notes: result.notes,
      );
      if (result.image != null) {
        await _repository.uploadPrimaryImage(
          assetId: saved['id'].toString(),
          file: result.image!,
        );
      }
      if (mounted) setState(_reload);
    } catch (error) {
      _error(error);
    }
  }

  Future<void> _detail(_AssetsData data, Map<String, dynamic> asset) async {
    await Navigator.of(context).push<void>(
      MaterialPageRoute(
        builder: (_) => _AssetDetail(
          repository: _repository,
          asset: asset,
          canManage: _canManage,
          onEdit: () => _edit(data, asset),
        ),
      ),
    );
    if (mounted) setState(_reload);
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<_AssetsData>(
      future: _future,
      builder: (context, snapshot) {
        if (snapshot.hasError) return Center(child: Text('Erro: ${snapshot.error}'));
        if (!snapshot.hasData) return const Center(child: CircularProgressIndicator());
        final data = snapshot.data!;
        final query = _search.text.trim().toLowerCase();
        final filtered = data.assets.where((asset) {
          final location = asset['inventory_locations'];
          final member = asset['members'];
          final haystack = [
            asset['asset_number'], asset['name'], asset['category'], asset['brand'], asset['model'], asset['serial_number'],
            location is Map ? location['name'] : null,
            member is Map ? member['full_name'] : null,
          ].whereType<Object>().join(' ').toLowerCase();
          if (query.isNotEmpty && !haystack.contains(query)) return false;
          if (_category != null && asset['category']?.toString() != _category) return false;
          if (_condition != null && asset['condition']?.toString() != _condition) return false;
          if (_locationId != null && asset['location_id']?.toString() != _locationId) return false;
          if (_responsibleId != null && asset['responsible_member_id']?.toString() != _responsibleId) return false;
          return true;
        }).toList();

        final active = data.assets.where((a) => a['condition'] != 'retired').toList();
        final acquisition = active.fold<double>(0, (sum, a) => sum + _double(a['acquisition_value']));
        final current = active.fold<double>(0, (sum, a) => sum + _double(a['current_value']));
        final maintenance = data.assets.where((a) => a['condition'] == 'maintenance').length;
        final retired = data.assets.where((a) => a['condition'] == 'retired').length;

        return Scaffold(
          body: RefreshIndicator(
            onRefresh: _refresh,
            child: ListView(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 96),
              children: [
                Wrap(
                  spacing: 10,
                  runSpacing: 10,
                  children: [
                    _Metric('Bens', '${data.assets.length}', Icons.home_repair_service_outlined),
                    _Metric('Valor aquisição', _money(acquisition), Icons.receipt_long_outlined),
                    _Metric('Valor atual', _money(current), Icons.euro_outlined),
                    _Metric('Em manutenção', '$maintenance', Icons.build_outlined),
                    _Metric('Abatidos', '$retired', Icons.archive_outlined),
                  ],
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: _search,
                  onChanged: (_) => setState(() {}),
                  decoration: const InputDecoration(
                    prefixIcon: Icon(Icons.search),
                    labelText: 'Pesquisar património',
                    hintText: 'Nome, PAT, marca, modelo, série...',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 10),
                Wrap(
                  spacing: 10,
                  runSpacing: 10,
                  children: [
                    _Filter<String>(
                      label: 'Categoria', value: _category,
                      items: data.categories.map((e) => e['name'].toString()).toList(),
                      text: (v) => v,
                      onChanged: (v) => setState(() => _category = v),
                    ),
                    _Filter<String>(
                      label: 'Estado', value: _condition,
                      items: _conditions.keys.toList(),
                      text: (v) => _conditions[v]!,
                      onChanged: (v) => setState(() => _condition = v),
                    ),
                    _Filter<String>(
                      label: 'Localização', value: _locationId,
                      items: data.locations.map((e) => e['id'].toString()).toList(),
                      text: (v) => data.locations.firstWhere((e) => e['id'].toString() == v)['name'].toString(),
                      onChanged: (v) => setState(() => _locationId = v),
                    ),
                    _Filter<String>(
                      label: 'Responsável', value: _responsibleId,
                      items: data.members.map((e) => e['id'].toString()).toList(),
                      text: (v) => _memberName(data.members.firstWhere((e) => e['id'].toString() == v)),
                      onChanged: (v) => setState(() => _responsibleId = v),
                    ),
                    if (_category != null || _condition != null || _locationId != null || _responsibleId != null)
                      OutlinedButton.icon(
                        onPressed: () => setState(() {
                          _category = null;
                          _condition = null;
                          _locationId = null;
                          _responsibleId = null;
                        }),
                        icon: const Icon(Icons.filter_alt_off_outlined),
                        label: const Text('Limpar filtros'),
                      ),
                  ],
                ),
                const SizedBox(height: 16),
                if (filtered.isEmpty)
                  const Card(
                    child: ListTile(
                      leading: Icon(Icons.home_repair_service_outlined),
                      title: Text('Nenhum bem encontrado.'),
                      subtitle: Text('Cria o primeiro bem ou altera os filtros.'),
                    ),
                  )
                else
                  for (final asset in filtered)
                    _AssetCard(
                      repository: _repository,
                      asset: asset,
                      onTap: () => _detail(data, asset),
                    ),
              ],
            ),
          ),
          floatingActionButton: _canManage
              ? FloatingActionButton.extended(
                  onPressed: () => _edit(data),
                  icon: const Icon(Icons.add),
                  label: const Text('Novo bem'),
                )
              : null,
        );
      },
    );
  }
}

class _AssetCard extends StatelessWidget {
  const _AssetCard({required this.repository, required this.asset, required this.onTap});
  final AssetsRepository repository;
  final Map<String, dynamic> asset;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final image = repository.publicImageUrl(asset['photo_path']);
    final location = asset['inventory_locations'];
    final member = asset['members'];
    final condition = asset['condition']?.toString() ?? 'good';
    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox(
                width: 86,
                height: 86,
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(12),
                  child: image == null
                      ? const ColoredBox(color: Color(0xFFECEFF1), child: Icon(Icons.image_outlined, size: 36))
                      : Image.network(image, fit: BoxFit.cover),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(asset['name']?.toString() ?? 'Bem', style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800)),
                        ),
                        _ConditionChip(condition: condition),
                      ],
                    ),
                    Text('${asset['asset_number'] ?? ''} · ${asset['category'] ?? 'Outros'}'),
                    const SizedBox(height: 6),
                    Wrap(
                      spacing: 8,
                      runSpacing: 4,
                      children: [
                        if (location is Map) _SmallInfo(Icons.place_outlined, location['name']?.toString() ?? ''),
                        if (member is Map) _SmallInfo(Icons.person_outline, _memberName(Map<String, dynamic>.from(member))),
                        _SmallInfo(Icons.euro_outlined, 'Atual ${_money(asset['current_value'])}'),
                        if (asset['requires_inspection'] == true) const _SmallInfo(Icons.fact_check_outlined, 'Inspeção periódica'),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _AssetDetail extends StatefulWidget {
  const _AssetDetail({required this.repository, required this.asset, required this.canManage, required this.onEdit});
  final AssetsRepository repository;
  final Map<String, dynamic> asset;
  final bool canManage;
  final Future<void> Function() onEdit;

  @override
  State<_AssetDetail> createState() => _AssetDetailState();
}

class _AssetDetailState extends State<_AssetDetail> {
  late Future<List<Map<String, dynamic>>> _timeline;

  @override
  void initState() {
    super.initState();
    _timeline = widget.repository.eventsForAsset(widget.asset['id'].toString());
  }

  @override
  Widget build(BuildContext context) {
    final asset = widget.asset;
    final image = widget.repository.publicImageUrl(asset['photo_path']);
    final location = asset['inventory_locations'];
    final member = asset['members'];
    final attrs = asset['custom_attributes'] is Map ? Map<String, dynamic>.from(asset['custom_attributes'] as Map) : <String, dynamic>{};
    return Scaffold(
      appBar: AppBar(
        title: Text(asset['asset_number']?.toString() ?? 'Património'),
        actions: [
          if (widget.canManage)
            IconButton(
              tooltip: 'Editar',
              onPressed: () async {
                await widget.onEdit();
                if (mounted) Navigator.pop(context);
              },
              icon: const Icon(Icons.edit_outlined),
            ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          if (image != null)
            ClipRRect(borderRadius: BorderRadius.circular(18), child: Image.network(image, height: 220, fit: BoxFit.cover)),
          const SizedBox(height: 12),
          Text(asset['name']?.toString() ?? '', style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w900)),
          const SizedBox(height: 8),
          Wrap(spacing: 8, runSpacing: 8, children: [
            _ConditionChip(condition: asset['condition']?.toString() ?? 'good'),
            Chip(label: Text(asset['category']?.toString() ?? 'Outros')),
            if ((asset['qr_code']?.toString() ?? '').isNotEmpty) Chip(avatar: const Icon(Icons.qr_code_2, size: 18), label: Text(asset['qr_code'].toString())),
          ]),
          const SizedBox(height: 12),
          _InfoCard(title: 'Identificação', rows: {
            'Marca': asset['brand'], 'Modelo': asset['model'], 'N.º série': asset['serial_number'],
            'Localização': location is Map ? location['name'] : null,
            'Responsável': member is Map ? _memberName(Map<String, dynamic>.from(member)) : null,
          }),
          _InfoCard(title: 'Aquisição e valor', rows: {
            'Data aquisição': _formatDate(asset['acquisition_date']),
            'Fornecedor': asset['supplier'],
            'Valor aquisição': _money(asset['acquisition_value']),
            'Valor atual': _money(asset['current_value']),
            'Garantia até': _formatDate(asset['warranty_until']),
          }),
          if (attrs.isNotEmpty) _InfoCard(title: 'Características', rows: attrs),
          if (asset['requires_inspection'] == true)
            _InfoCard(title: 'Inspeção periódica', rows: {
              'Periodicidade': '${asset['inspection_interval_months'] ?? '-'} meses',
              'Última inspeção': _formatDate(asset['last_inspection_at']),
              'Próxima inspeção': _formatDate(asset['next_inspection_at']),
            }),
          if ((asset['notes']?.toString() ?? '').isNotEmpty) _InfoCard(title: 'Observações', rows: {'Notas': asset['notes']}),
          const SizedBox(height: 8),
          Text('Histórico', style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800)),
          const SizedBox(height: 8),
          FutureBuilder<List<Map<String, dynamic>>>(
            future: _timeline,
            builder: (context, snapshot) {
              if (!snapshot.hasData) return const Center(child: CircularProgressIndicator());
              if (snapshot.data!.isEmpty) return const Card(child: ListTile(title: Text('Sem movimentos registados.')));
              return Column(
                children: snapshot.data!.map((event) {
                  final date = DateTime.tryParse(event['created_at']?.toString() ?? '')?.toLocal();
                  return Card(
                    child: ListTile(
                      leading: const CircleAvatar(child: Icon(Icons.history_outlined)),
                      title: Text(event['title']?.toString() ?? 'Alteração'),
                      subtitle: Text([
                        event['description']?.toString(),
                        if (date != null) DateFormat('dd/MM/yyyy HH:mm').format(date),
                      ].whereType<String>().where((e) => e.isNotEmpty).join(' · ')),
                    ),
                  );
                }).toList(),
              );
            },
          ),
        ],
      ),
    );
  }
}

class _AssetEditor extends StatefulWidget {
  const _AssetEditor({required this.repository, required this.asset, required this.codes, required this.categories, required this.locations, required this.members});
  final AssetsRepository repository;
  final Map<String, dynamic>? asset;
  final Map<String, String> codes;
  final List<Map<String, dynamic>> categories;
  final List<Map<String, dynamic>> locations;
  final List<Map<String, dynamic>> members;

  @override
  State<_AssetEditor> createState() => _AssetEditorState();
}

class _AssetEditorState extends State<_AssetEditor> {
  late final TextEditingController _name;
  late final TextEditingController _description;
  late final TextEditingController _brand;
  late final TextEditingController _model;
  late final TextEditingController _serial;
  late final TextEditingController _supplier;
  late final TextEditingController _acquisitionValue;
  late final TextEditingController _currentValue;
  late final TextEditingController _notes;
  late final TextEditingController _specific1;
  late final TextEditingController _specific2;
  String _category = 'Outros';
  String _condition = 'good';
  String? _locationId;
  String? _responsibleId;
  DateTime? _acquisitionDate;
  DateTime? _warrantyUntil;
  bool _requiresInspection = false;
  int? _inspectionMonths = 12;
  DateTime? _lastInspection;
  DateTime? _nextInspection;
  XFile? _image;

  @override
  void initState() {
    super.initState();
    final a = widget.asset ?? const <String, dynamic>{};
    final attrs = a['custom_attributes'] is Map ? Map<String, dynamic>.from(a['custom_attributes'] as Map) : <String, dynamic>{};
    _name = TextEditingController(text: a['name']?.toString() ?? '');
    _description = TextEditingController(text: a['description']?.toString() ?? '');
    _brand = TextEditingController(text: a['brand']?.toString() ?? '');
    _model = TextEditingController(text: a['model']?.toString() ?? '');
    _serial = TextEditingController(text: a['serial_number']?.toString() ?? '');
    _supplier = TextEditingController(text: a['supplier']?.toString() ?? '');
    _acquisitionValue = TextEditingController(text: _number(a['acquisition_value'] ?? 0));
    _currentValue = TextEditingController(text: _number(a['current_value'] ?? a['acquisition_value'] ?? 0));
    _notes = TextEditingController(text: a['notes']?.toString() ?? '');
    _category = a['category']?.toString() ?? (widget.categories.isNotEmpty ? widget.categories.first['name'].toString() : 'Outros');
    _condition = a['condition']?.toString() ?? 'good';
    _locationId = a['location_id']?.toString();
    _responsibleId = a['responsible_member_id']?.toString();
    _acquisitionDate = _parseDate(a['acquisition_date']);
    _warrantyUntil = _parseDate(a['warranty_until']);
    _requiresInspection = a['requires_inspection'] == true;
    _inspectionMonths = int.tryParse(a['inspection_interval_months']?.toString() ?? '') ?? 12;
    _lastInspection = _parseDate(a['last_inspection_at']);
    _nextInspection = _parseDate(a['next_inspection_at']);
    final labels = _attributeLabels(_category);
    _specific1 = TextEditingController(text: labels.$3 == null ? '' : attrs[labels.$3]?.toString() ?? '');
    _specific2 = TextEditingController(text: labels.$4 == null ? '' : attrs[labels.$4]?.toString() ?? '');
  }

  @override
  void dispose() {
    for (final c in [_name,_description,_brand,_model,_serial,_supplier,_acquisitionValue,_currentValue,_notes,_specific1,_specific2]) { c.dispose(); }
    super.dispose();
  }

  Future<void> _pickImage() async {
    final source = await showModalBottomSheet<ImageSource>(
      context: context,
      builder: (context) => SafeArea(
        child: Wrap(children: [
          ListTile(leading: const Icon(Icons.photo_camera_outlined), title: const Text('Tirar fotografia'), onTap: () => Navigator.pop(context, ImageSource.camera)),
          ListTile(leading: const Icon(Icons.photo_library_outlined), title: const Text('Escolher da galeria'), onTap: () => Navigator.pop(context, ImageSource.gallery)),
        ]),
      ),
    );
    if (source == null) return;
    final image = await ImagePicker().pickImage(source: source, imageQuality: 85, maxWidth: 1800);
    if (image != null) setState(() => _image = image);
  }

  Future<DateTime?> _date(DateTime? current) => showDatePicker(
    context: context,
    initialDate: current ?? DateTime.now(),
    firstDate: DateTime(2000),
    lastDate: DateTime(2100),
  );

  InputDecoration _dec(String label, {String? helper}) => InputDecoration(labelText: label, helperText: helper, border: const OutlineInputBorder(), floatingLabelBehavior: FloatingLabelBehavior.always);

  Widget _section(String title, IconData icon, List<Widget> children) => Card(
    margin: const EdgeInsets.only(bottom: 14),
    child: Padding(
      padding: const EdgeInsets.all(14),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Row(children: [Icon(icon, size: 20), const SizedBox(width: 8), Text(title, style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800))]),
        const SizedBox(height: 14),
        ...children.map((e) => Padding(padding: const EdgeInsets.only(bottom: 12), child: e)),
      ]),
    ),
  );

  @override
  Widget build(BuildContext context) {
    final labels = _attributeLabels(_category);
    final imageUrl = widget.repository.publicImageUrl(widget.asset?['photo_path']);
    return Scaffold(
      appBar: AppBar(title: Text(widget.asset == null ? 'Novo bem patrimonial' : 'Editar bem')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _section('Identificação', Icons.badge_outlined, [
            Row(children: [
              Expanded(child: Text('Código: ${widget.codes['asset_number']}')),
              Expanded(child: Text('QR: ${widget.codes['qr_code']}')),
            ]),
            TextField(controller: _name, decoration: _dec('Nome *')),
            DropdownButtonFormField<String>(
              initialValue: _category,
              decoration: _dec('Categoria'),
              items: widget.categories.map((c) => DropdownMenuItem(value: c['name'].toString(), child: Text(c['name'].toString()))).toList(),
              onChanged: (v) {
                if (v == null) return;
                setState(() { _category = v; _specific1.clear(); _specific2.clear(); });
              },
            ),
            DropdownButtonFormField<String>(
              initialValue: _condition,
              decoration: _dec('Estado'),
              items: _conditions.entries.map((e) => DropdownMenuItem(value: e.key, child: Text(e.value))).toList(),
              onChanged: (v) => setState(() => _condition = v ?? _condition),
            ),
            TextField(controller: _description, maxLines: 3, decoration: _dec('Descrição')),
          ]),
          _section('Fotografia', Icons.photo_camera_outlined, [
            if (_image != null)
              ClipRRect(borderRadius: BorderRadius.circular(12), child: Image.network(_image!.path, height: 180, fit: BoxFit.cover, errorBuilder: (_, __, ___) => const SizedBox.shrink()))
            else if (imageUrl != null)
              ClipRRect(borderRadius: BorderRadius.circular(12), child: Image.network(imageUrl, height: 180, fit: BoxFit.cover))
            else
              const SizedBox(height: 120, child: ColoredBox(color: Color(0xFFECEFF1), child: Icon(Icons.image_outlined, size: 44))),
            OutlinedButton.icon(onPressed: _pickImage, icon: const Icon(Icons.add_a_photo_outlined), label: const Text('Tirar foto / escolher da galeria')),
          ]),
          _section('Localização e responsável', Icons.place_outlined, [
            DropdownButtonFormField<String?>(
              initialValue: _locationId,
              decoration: _dec('Localização'),
              items: [const DropdownMenuItem<String?>(value: null, child: Text('Sem localização')), ...widget.locations.map((l) => DropdownMenuItem<String?>(value: l['id'].toString(), child: Text(l['name'].toString())))],
              onChanged: (v) => setState(() => _locationId = v),
            ),
            DropdownButtonFormField<String?>(
              initialValue: _responsibleId,
              decoration: _dec('Responsável'),
              items: [const DropdownMenuItem<String?>(value: null, child: Text('Sem responsável')), ...widget.members.map((m) => DropdownMenuItem<String?>(value: m['id'].toString(), child: Text(_memberName(m))))],
              onChanged: (v) => setState(() => _responsibleId = v),
            ),
          ]),
          _section('Dados do equipamento', Icons.settings_outlined, [
            TextField(controller: _brand, decoration: _dec('Marca')),
            TextField(controller: _model, decoration: _dec('Modelo')),
            TextField(controller: _serial, decoration: _dec('Número de série')),
            if (labels.$1 != null) TextField(controller: _specific1, decoration: _dec(labels.$1!)),
            if (labels.$2 != null) TextField(controller: _specific2, decoration: _dec(labels.$2!)),
          ]),
          _section('Aquisição e valor', Icons.euro_outlined, [
            ListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Data de aquisição'),
              subtitle: Text(_dateText(_acquisitionDate)),
              trailing: const Icon(Icons.calendar_month_outlined),
              onTap: () async { final v = await _date(_acquisitionDate); if (v != null) setState(() => _acquisitionDate = v); },
            ),
            TextField(controller: _supplier, decoration: _dec('Fornecedor')),
            TextField(controller: _acquisitionValue, keyboardType: const TextInputType.numberWithOptions(decimal: true), decoration: _dec('Valor de aquisição (€)')),
            TextField(controller: _currentValue, keyboardType: const TextInputType.numberWithOptions(decimal: true), decoration: _dec('Valor atual (€)')),
            ListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Garantia até'),
              subtitle: Text(_dateText(_warrantyUntil)),
              trailing: const Icon(Icons.calendar_month_outlined),
              onTap: () async { final v = await _date(_warrantyUntil); if (v != null) setState(() => _warrantyUntil = v); },
            ),
          ]),
          _section('Inspeção periódica', Icons.fact_check_outlined, [
            SwitchListTile(contentPadding: EdgeInsets.zero, value: _requiresInspection, onChanged: (v) => setState(() => _requiresInspection = v), title: const Text('Necessita inspeção periódica')),
            if (_requiresInspection) ...[
              DropdownButtonFormField<int>(
                initialValue: _inspectionMonths,
                decoration: _dec('Periodicidade'),
                items: const [3,6,12,24].map((m) => DropdownMenuItem(value: m, child: Text('$m meses'))).toList(),
                onChanged: (v) => setState(() => _inspectionMonths = v),
              ),
              ListTile(contentPadding: EdgeInsets.zero, title: const Text('Última inspeção'), subtitle: Text(_dateText(_lastInspection)), trailing: const Icon(Icons.calendar_month_outlined), onTap: () async { final v = await _date(_lastInspection); if (v != null) setState(() => _lastInspection = v); }),
              ListTile(contentPadding: EdgeInsets.zero, title: const Text('Próxima inspeção'), subtitle: Text(_dateText(_nextInspection)), trailing: const Icon(Icons.calendar_month_outlined), onTap: () async { final v = await _date(_nextInspection); if (v != null) setState(() => _nextInspection = v); }),
            ],
          ]),
          _section('Observações', Icons.notes_outlined, [TextField(controller: _notes, maxLines: 4, decoration: _dec('Notas'))]),
          FilledButton.icon(
            onPressed: () {
              if (_name.text.trim().isEmpty) return;
              final custom = <String,dynamic>{};
              if (labels.$3 != null && _specific1.text.trim().isNotEmpty) custom[labels.$3!] = _specific1.text.trim();
              if (labels.$4 != null && _specific2.text.trim().isNotEmpty) custom[labels.$4!] = _specific2.text.trim();
              Navigator.pop(context, _AssetInput(
                assetNumber: widget.codes['asset_number']!, qrCode: widget.codes['qr_code']!, name: _name.text,
                category: _category, description: _description.text, brand: _brand.text, model: _model.text,
                serialNumber: _serial.text, condition: _condition, locationId: _locationId, responsibleMemberId: _responsibleId,
                acquisitionDate: _acquisitionDate, acquisitionValue: _parse(_acquisitionValue.text), currentValue: _parse(_currentValue.text),
                supplier: _supplier.text, warrantyUntil: _warrantyUntil, requiresInspection: _requiresInspection,
                inspectionIntervalMonths: _inspectionMonths, lastInspectionAt: _lastInspection, nextInspectionAt: _nextInspection,
                customAttributes: custom, notes: _notes.text, image: _image,
              ));
            },
            icon: const Icon(Icons.save_outlined),
            label: const Text('Guardar bem'),
          ),
          const SizedBox(height: 32),
        ],
      ),
    );
  }
}

class _Metric extends StatelessWidget {
  const _Metric(this.label, this.value, this.icon);
  final String label, value;
  final IconData icon;
  @override
  Widget build(BuildContext context) => SizedBox(width: 205, child: Card(child: ListTile(leading: CircleAvatar(child: Icon(icon)), title: Text(label), subtitle: Text(value, style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w900)))));
}

class _Filter<T> extends StatelessWidget {
  const _Filter({required this.label, required this.value, required this.items, required this.text, required this.onChanged});
  final String label;
  final T? value;
  final List<T> items;
  final String Function(T) text;
  final ValueChanged<T?> onChanged;
  @override
  Widget build(BuildContext context) => SizedBox(
    width: 205,
    child: DropdownButtonFormField<T?>(
      initialValue: value,
      isExpanded: true,
      decoration: InputDecoration(labelText: label, border: const OutlineInputBorder()),
      items: [DropdownMenuItem<T?>(value: null, child: const Text('Todos')), ...items.map((v) => DropdownMenuItem<T?>(value: v, child: Text(text(v), overflow: TextOverflow.ellipsis)))],
      onChanged: onChanged,
    ),
  );
}

class _ConditionChip extends StatelessWidget {
  const _ConditionChip({required this.condition});
  final String condition;
  @override
  Widget build(BuildContext context) => Chip(avatar: Icon(_conditionIcon(condition), size: 18), label: Text(_conditions[condition] ?? condition));
}

class _SmallInfo extends StatelessWidget {
  const _SmallInfo(this.icon, this.text);
  final IconData icon;
  final String text;
  @override
  Widget build(BuildContext context) => Row(mainAxisSize: MainAxisSize.min, children: [Icon(icon, size: 16), const SizedBox(width: 3), Text(text)]);
}

class _InfoCard extends StatelessWidget {
  const _InfoCard({required this.title, required this.rows});
  final String title;
  final Map<String,Object?> rows;
  @override
  Widget build(BuildContext context) {
    final visible = rows.entries.where((e) => e.value != null && e.value.toString().isNotEmpty && e.value.toString() != '-').toList();
    if (visible.isEmpty) return const SizedBox.shrink();
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Text(title, style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800)),
          const SizedBox(height: 8),
          ...visible.map((e) => Padding(padding: const EdgeInsets.symmetric(vertical: 3), child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [SizedBox(width: 130, child: Text(e.key, style: const TextStyle(fontWeight: FontWeight.w600))), Expanded(child: Text(e.value.toString()))]))),
        ]),
      ),
    );
  }
}

class _AssetsData {
  const _AssetsData({required this.assets,required this.categories,required this.locations,required this.members});
  final List<Map<String,dynamic>> assets,categories,locations,members;
}

class _AssetInput {
  const _AssetInput({required this.assetNumber,required this.qrCode,required this.name,required this.category,required this.description,required this.brand,required this.model,required this.serialNumber,required this.condition,required this.locationId,required this.responsibleMemberId,required this.acquisitionDate,required this.acquisitionValue,required this.currentValue,required this.supplier,required this.warrantyUntil,required this.requiresInspection,required this.inspectionIntervalMonths,required this.lastInspectionAt,required this.nextInspectionAt,required this.customAttributes,required this.notes,required this.image});
  final String assetNumber,qrCode,name,category,description,brand,model,serialNumber,condition,supplier,notes;
  final String? locationId,responsibleMemberId;
  final DateTime? acquisitionDate,warrantyUntil,lastInspectionAt,nextInspectionAt;
  final double acquisitionValue,currentValue;
  final bool requiresInspection;
  final int? inspectionIntervalMonths;
  final Map<String,dynamic> customAttributes;
  final XFile? image;
}

const _conditions = <String,String>{
  'excellent':'Excelente','good':'Bom','regular':'Regular','maintenance':'Necessita manutenção','damaged':'Avariado','retired':'Abatido',
};

IconData _conditionIcon(String condition) => switch(condition) {
  'excellent' => Icons.verified_outlined,
  'good' => Icons.check_circle_outline,
  'regular' => Icons.info_outline,
  'maintenance' => Icons.build_outlined,
  'damaged' => Icons.error_outline,
  'retired' => Icons.archive_outlined,
  _ => Icons.circle_outlined,
};

(String?,String?,String?,String?) _attributeLabels(String category) {
  final c = category.toLowerCase();
  if (c.contains('gerador')) return ('Potência','Combustível','potencia','combustivel');
  if (c.contains('som')) return ('Potência','N.º de colunas','potencia','numero_colunas');
  if (c.contains('tenda')) return ('Dimensões','Material','dimensoes','material');
  if (c.contains('ilumina')) return ('Potência','Tipo','potencia','tipo');
  return (null,null,null,null);
}

String _memberName(Map<String,dynamic> member) {
  final nick = member['nickname']?.toString().trim() ?? '';
  final full = member['full_name']?.toString().trim() ?? 'Membro';
  return nick.isEmpty ? full : '$full ($nick)';
}

double _double(Object? value) => value is num ? value.toDouble() : double.tryParse(value?.toString().replaceAll(',','.') ?? '') ?? 0;
double _parse(String value) => double.tryParse(value.replaceAll(',','.')) ?? 0;
String _number(Object? value) { final n=_double(value); return n==n.roundToDouble()?n.toInt().toString():n.toStringAsFixed(2).replaceAll('.',','); }
String _money(Object? value) => NumberFormat.currency(locale:'pt_PT',symbol:'€').format(_double(value));
DateTime? _parseDate(Object? value) => DateTime.tryParse(value?.toString() ?? '');
String _formatDate(Object? value) { final d=_parseDate(value); return d==null?'-':DateFormat('dd/MM/yyyy').format(d); }
String _dateText(DateTime? value) => value==null?'Não definida':DateFormat('dd/MM/yyyy').format(value);
