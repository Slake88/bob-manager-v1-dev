import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../core/app_session.dart';
import '../core/permissions.dart';
import '../repositories/assets_operations_repository.dart';

class AssetsPhase2Screen extends StatefulWidget {
  const AssetsPhase2Screen({super.key});

  @override
  State<AssetsPhase2Screen> createState() => _AssetsPhase2ScreenState();
}

class _AssetsPhase2ScreenState extends State<AssetsPhase2Screen> {
  final _repository = AssetsOperationsRepository();
  late Future<_Phase2Data> _future;

  bool get _canManage => AppSession.instance.can(AppPermission.manageAssets);

  @override
  void initState() {
    super.initState();
    _reload();
  }

  void _reload() {
    _future = Future.wait<dynamic>([
      _repository.assets(),
      _repository.members(),
      _repository.events(),
      _canManage ? _repository.accounts() : Future.value(<Map<String, dynamic>>[]),
      _repository.activeLoans(),
      _repository.maintenanceHistory(),
      _repository.kits(),
    ]).then((values) => _Phase2Data(
          assets: List<Map<String, dynamic>>.from(values[0] as List),
          members: List<Map<String, dynamic>>.from(values[1] as List),
          events: List<Map<String, dynamic>>.from(values[2] as List),
          accounts: List<Map<String, dynamic>>.from(values[3] as List),
          loans: List<Map<String, dynamic>>.from(values[4] as List),
          maintenance: List<Map<String, dynamic>>.from(values[5] as List),
          kits: List<Map<String, dynamic>>.from(values[6] as List),
        ));
  }

  Future<void> _refresh() async {
    setState(_reload);
    await _future;
  }

  void _error(Object error) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(error.toString())));
  }

  Future<void> _newLoan(_Phase2Data data) async {
    final result = await showDialog<_LoanInput>(
      context: context,
      builder: (_) => _LoanDialog(data: data),
    );
    if (result == null) return;
    try {
      await _repository.loan(
        assetId: result.assetId,
        borrowerType: result.borrowerType,
        memberId: result.memberId,
        eventId: result.eventId,
        externalName: result.externalName,
        expectedReturn: result.expectedReturn,
        notes: result.notes,
      );
      if (mounted) setState(_reload);
    } catch (error) {
      _error(error);
    }
  }

  Future<void> _returnLoan(Map<String, dynamic> loan) async {
    final result = await showDialog<_ReturnInput>(
      context: context,
      builder: (_) => const _ReturnDialog(),
    );
    if (result == null) return;
    try {
      await _repository.returnLoan(
        loanId: loan['id'].toString(),
        condition: result.condition,
        notes: result.notes,
      );
      if (mounted) setState(_reload);
    } catch (error) {
      _error(error);
    }
  }

  Future<void> _newMaintenance(_Phase2Data data, {String? presetType}) async {
    final result = await showDialog<_MaintenanceInput>(
      context: context,
      builder: (_) => _MaintenanceDialog(data: data, presetType: presetType),
    );
    if (result == null) return;
    try {
      await _repository.maintenance(
        assetId: result.assetId,
        type: result.type,
        date: result.date,
        description: result.description,
        cost: result.cost,
        supplier: result.supplier,
        nextDue: result.nextDue,
        accountId: result.accountId,
        paymentMethod: result.paymentMethod,
        postFinancial: result.postFinancial,
      );
      if (mounted) setState(_reload);
    } catch (error) {
      _error(error);
    }
  }

  Future<void> _newKit(_Phase2Data data) async {
    final result = await showDialog<_KitInput>(
      context: context,
      builder: (_) => _KitDialog(assets: data.assets),
    );
    if (result == null) return;
    try {
      await _repository.saveKit(
        name: result.name,
        description: result.description,
        assetIds: result.assetIds,
      );
      if (mounted) setState(_reload);
    } catch (error) {
      _error(error);
    }
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<_Phase2Data>(
      future: _future,
      builder: (context, snapshot) {
        if (snapshot.hasError) return Center(child: Text('Erro: ${snapshot.error}'));
        if (!snapshot.hasData) return const Center(child: CircularProgressIndicator());
        final data = snapshot.data!;
        final now = DateTime.now();
        final overdueLoans = data.loans.where((loan) {
          final date = DateTime.tryParse(loan['expected_return_at']?.toString() ?? '');
          return date != null && date.isBefore(now);
        }).length;
        final inspectionsDue = data.assets.where((asset) {
          if (asset['requires_inspection'] != true) return false;
          final date = DateTime.tryParse(asset['next_inspection_at']?.toString() ?? '');
          return date != null && !date.isAfter(now.add(const Duration(days: 30)));
        }).length;

        return DefaultTabController(
          length: 4,
          child: Column(
            children: [
              Material(
                child: TabBar(
                  isScrollable: true,
                  tabs: const [
                    Tab(text: 'Empréstimos', icon: Icon(Icons.swap_horiz_outlined)),
                    Tab(text: 'Manutenção', icon: Icon(Icons.build_outlined)),
                    Tab(text: 'Inspeções', icon: Icon(Icons.fact_check_outlined)),
                    Tab(text: 'Kits', icon: Icon(Icons.inventory_2_outlined)),
                  ],
                ),
              ),
              Expanded(
                child: TabBarView(
                  children: [
                    _LoansTab(
                      loans: data.loans,
                      overdue: overdueLoans,
                      canManage: _canManage,
                      onAdd: () => _newLoan(data),
                      onReturn: _returnLoan,
                      onRefresh: _refresh,
                    ),
                    _MaintenanceTab(
                      rows: data.maintenance,
                      canManage: _canManage,
                      onAdd: () => _newMaintenance(data),
                      onRefresh: _refresh,
                    ),
                    _InspectionTab(
                      assets: data.assets,
                      dueCount: inspectionsDue,
                      canManage: _canManage,
                      onAdd: () => _newMaintenance(data, presetType: 'inspection'),
                      onRefresh: _refresh,
                    ),
                    _KitsTab(
                      kits: data.kits,
                      canManage: _canManage,
                      onAdd: () => _newKit(data),
                      onRefresh: _refresh,
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

class _LoansTab extends StatelessWidget {
  const _LoansTab({required this.loans,required this.overdue,required this.canManage,required this.onAdd,required this.onReturn,required this.onRefresh});
  final List<Map<String,dynamic>> loans;
  final int overdue;
  final bool canManage;
  final VoidCallback onAdd;
  final Future<void> Function(Map<String,dynamic>) onReturn;
  final Future<void> Function() onRefresh;

  @override
  Widget build(BuildContext context) {
    return RefreshIndicator(
      onRefresh: onRefresh,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16,16,16,96),
        children: [
          Wrap(spacing: 10,runSpacing: 10,children: [
            _Metric('Ativos','${loans.length}',Icons.swap_horiz_outlined),
            _Metric('Atrasados','$overdue',Icons.warning_amber_outlined),
            if (canManage) FilledButton.icon(onPressed: onAdd,icon: const Icon(Icons.add),label: const Text('Novo empréstimo')),
          ]),
          const SizedBox(height: 16),
          if (loans.isEmpty)
            const Card(child: ListTile(leading: Icon(Icons.inventory_2_outlined),title: Text('Sem empréstimos ativos.')))
          else
            for (final loan in loans) _LoanCard(loan: loan,canManage: canManage,onReturn: () => onReturn(loan)),
        ],
      ),
    );
  }
}

class _MaintenanceTab extends StatelessWidget {
  const _MaintenanceTab({required this.rows,required this.canManage,required this.onAdd,required this.onRefresh});
  final List<Map<String,dynamic>> rows;
  final bool canManage;
  final VoidCallback onAdd;
  final Future<void> Function() onRefresh;
  @override
  Widget build(BuildContext context) {
    return RefreshIndicator(
      onRefresh: onRefresh,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16,16,16,96),
        children: [
          if (canManage) Align(alignment: Alignment.centerLeft,child: FilledButton.icon(onPressed: onAdd,icon: const Icon(Icons.add),label: const Text('Registar intervenção'))),
          const SizedBox(height: 12),
          if (rows.isEmpty) const Card(child: ListTile(title: Text('Ainda não existem manutenções ou reparações registadas.')))
          else for (final row in rows) _MaintenanceCard(row: row),
        ],
      ),
    );
  }
}

class _InspectionTab extends StatelessWidget {
  const _InspectionTab({required this.assets,required this.dueCount,required this.canManage,required this.onAdd,required this.onRefresh});
  final List<Map<String,dynamic>> assets;
  final int dueCount;
  final bool canManage;
  final VoidCallback onAdd;
  final Future<void> Function() onRefresh;
  @override
  Widget build(BuildContext context) {
    final rows = assets.where((a) => a['requires_inspection'] == true).toList();
    rows.sort((a,b) => (a['next_inspection_at']?.toString() ?? '9999').compareTo(b['next_inspection_at']?.toString() ?? '9999'));
    return RefreshIndicator(
      onRefresh: onRefresh,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16,16,16,96),
        children: [
          Wrap(spacing:10,runSpacing:10,children:[
            _Metric('Com inspeção','${rows.length}',Icons.fact_check_outlined),
            _Metric('Próximas / vencidas','$dueCount',Icons.notification_important_outlined),
            if (canManage) FilledButton.icon(onPressed: onAdd,icon: const Icon(Icons.add_task),label: const Text('Registar inspeção')),
          ]),
          const SizedBox(height:16),
          if (rows.isEmpty) const Card(child: ListTile(title: Text('Nenhum bem exige inspeção periódica.')))
          else for (final asset in rows) _InspectionCard(asset: asset),
        ],
      ),
    );
  }
}

class _KitsTab extends StatelessWidget {
  const _KitsTab({required this.kits,required this.canManage,required this.onAdd,required this.onRefresh});
  final List<Map<String,dynamic>> kits;
  final bool canManage;
  final VoidCallback onAdd;
  final Future<void> Function() onRefresh;
  @override
  Widget build(BuildContext context) {
    return RefreshIndicator(
      onRefresh: onRefresh,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16,16,16,96),
        children: [
          if (canManage) Align(alignment: Alignment.centerLeft,child: FilledButton.icon(onPressed: onAdd,icon: const Icon(Icons.add),label: const Text('Novo Kit'))),
          const SizedBox(height:12),
          if (kits.isEmpty) const Card(child: ListTile(title: Text('Ainda não existem Kits.'),subtitle: Text('Agrupa equipamentos que costumam ser usados em conjunto.')))
          else for (final kit in kits) _KitCard(kit: kit),
        ],
      ),
    );
  }
}

class _LoanCard extends StatelessWidget {
  const _LoanCard({required this.loan,required this.canManage,required this.onReturn});
  final Map<String,dynamic> loan;
  final bool canManage;
  final VoidCallback onReturn;
  @override
  Widget build(BuildContext context) {
    final asset = loan['inventory_assets'];
    final member = loan['members'];
    final event = loan['events'];
    final due = DateTime.tryParse(loan['expected_return_at']?.toString() ?? '');
    final overdue = due != null && due.isBefore(DateTime.now());
    final who = member is Map ? _memberName(member) : event is Map ? event['name']?.toString() ?? '' : loan['external_name']?.toString() ?? '';
    return Card(child: ListTile(
      leading: CircleAvatar(child: Icon(overdue ? Icons.warning_amber_outlined : Icons.swap_horiz_outlined)),
      title: Text(asset is Map ? '${asset['asset_number']} · ${asset['name']}' : 'Bem'),
      subtitle: Text(['Destino: $who',if (due != null) 'Devolução: ${DateFormat('dd/MM/yyyy').format(due)}',if ((loan['notes']?.toString() ?? '').isNotEmpty) loan['notes'].toString()].join('\n')),
      trailing: canManage ? FilledButton.tonal(onPressed: onReturn,child: const Text('Devolver')) : null,
    ));
  }
}

class _MaintenanceCard extends StatelessWidget {
  const _MaintenanceCard({required this.row});
  final Map<String,dynamic> row;
  @override
  Widget build(BuildContext context) {
    final asset = row['inventory_assets'];
    final account = row['treasury_accounts'];
    return Card(child: ListTile(
      leading: CircleAvatar(child: Icon(_maintenanceIcon(row['maintenance_type']?.toString()))),
      title: Text(asset is Map ? '${asset['asset_number']} · ${asset['name']}' : 'Intervenção'),
      subtitle: Text([
        _maintenanceLabel(row['maintenance_type']?.toString()),
        _formatDate(row['maintenance_date']),
        if ((row['description']?.toString() ?? '').isNotEmpty) row['description'].toString(),
        if (_double(row['cost']) > 0) 'Custo: ${_money(row['cost'])}',
        if (account is Map) 'Conta: ${account['name']}',
        if (row['next_due_date'] != null) 'Próxima: ${_formatDate(row['next_due_date'])}',
      ].join(' · ')),
    ));
  }
}

class _InspectionCard extends StatelessWidget {
  const _InspectionCard({required this.asset});
  final Map<String,dynamic> asset;
  @override
  Widget build(BuildContext context) {
    final next = DateTime.tryParse(asset['next_inspection_at']?.toString() ?? '');
    final dueSoon = next != null && !next.isAfter(DateTime.now().add(const Duration(days:30)));
    return Card(child: ListTile(
      leading: CircleAvatar(child: Icon(dueSoon ? Icons.notification_important_outlined : Icons.fact_check_outlined)),
      title: Text('${asset['asset_number']} · ${asset['name']}'),
      subtitle: Text(next == null ? 'Próxima inspeção por definir' : 'Próxima inspeção: ${DateFormat('dd/MM/yyyy').format(next)}'),
    ));
  }
}

class _KitCard extends StatelessWidget {
  const _KitCard({required this.kit});
  final Map<String,dynamic> kit;
  @override
  Widget build(BuildContext context) {
    final items = List<Map<String,dynamic>>.from(kit['asset_kit_items'] as List? ?? const []);
    return Card(child: ExpansionTile(
      leading: const CircleAvatar(child: Icon(Icons.inventory_2_outlined)),
      title: Text(kit['name']?.toString() ?? 'Kit'),
      subtitle: Text('${items.length} equipamentos'),
      children: [
        if ((kit['description']?.toString() ?? '').isNotEmpty) ListTile(title: Text(kit['description'].toString())),
        for (final item in items)
          ListTile(dense:true,leading: const Icon(Icons.chevron_right),title: Text(item['inventory_assets'] is Map ? '${item['inventory_assets']['asset_number']} · ${item['inventory_assets']['name']}' : 'Equipamento')),
      ],
    ));
  }
}

class _LoanDialog extends StatefulWidget {
  const _LoanDialog({required this.data});
  final _Phase2Data data;
  @override State<_LoanDialog> createState() => _LoanDialogState();
}
class _LoanDialogState extends State<_LoanDialog> {
  String? assetId;
  String type='member';
  String? memberId;
  String? eventId;
  final external=TextEditingController();
  final notes=TextEditingController();
  DateTime? expected;
  @override void dispose(){external.dispose();notes.dispose();super.dispose();}
  @override Widget build(BuildContext context){
    return AlertDialog(title: const Text('Novo empréstimo / associação'),content:SizedBox(width:560,child:SingleChildScrollView(child:Column(mainAxisSize:MainAxisSize.min,children:[
      _dropdown('Bem',assetId,widget.data.assets.map((e)=>e['id'].toString()).toList(),(v)=>'${widget.data.assets.firstWhere((e)=>e['id'].toString()==v)['asset_number']} · ${widget.data.assets.firstWhere((e)=>e['id'].toString()==v)['name']}',(v)=>setState(()=>assetId=v)),
      const SizedBox(height:12),
      DropdownButtonFormField<String>(initialValue:type,decoration:const InputDecoration(labelText:'Destino',border:OutlineInputBorder()),items:const [DropdownMenuItem(value:'member',child:Text('Membro')),DropdownMenuItem(value:'external',child:Text('Externo')),DropdownMenuItem(value:'event',child:Text('Evento'))],onChanged:(v)=>setState(()=>type=v??type)),
      const SizedBox(height:12),
      if(type=='member') _dropdown('Membro',memberId,widget.data.members.map((e)=>e['id'].toString()).toList(),(v)=>_memberName(widget.data.members.firstWhere((e)=>e['id'].toString()==v)),(v)=>setState(()=>memberId=v)),
      if(type=='event') _dropdown('Evento',eventId,widget.data.events.map((e)=>e['id'].toString()).toList(),(v)=>widget.data.events.firstWhere((e)=>e['id'].toString()==v)['name'].toString(),(v)=>setState(()=>eventId=v)),
      if(type=='external') TextField(controller:external,decoration:const InputDecoration(labelText:'Nome / entidade externa',border:OutlineInputBorder())),
      const SizedBox(height:12),
      ListTile(contentPadding:EdgeInsets.zero,leading:const Icon(Icons.event),title:Text(expected==null?'Data prevista de devolução':'Devolução: ${DateFormat('dd/MM/yyyy').format(expected!)}'),trailing:IconButton(icon:const Icon(Icons.calendar_month),onPressed:() async {final d=await showDatePicker(context:context,initialDate:DateTime.now(),firstDate:DateTime.now(),lastDate:DateTime.now().add(const Duration(days:3650)));if(d!=null){setState(()=>expected=d);}})),
      TextField(controller:notes,maxLines:2,decoration:const InputDecoration(labelText:'Notas',border:OutlineInputBorder())),
    ]))),actions:[TextButton(onPressed:()=>Navigator.pop(context),child:const Text('Cancelar')),FilledButton(onPressed:assetId==null?null:()=>Navigator.pop(context,_LoanInput(assetId!,type,memberId,eventId,external.text,expected,notes.text)),child:const Text('Registar'))]);
  }
}

class _ReturnDialog extends StatefulWidget { const _ReturnDialog(); @override State<_ReturnDialog> createState()=>_ReturnDialogState(); }
class _ReturnDialogState extends State<_ReturnDialog>{String condition='good';final notes=TextEditingController();@override void dispose(){notes.dispose();super.dispose();}@override Widget build(BuildContext context)=>AlertDialog(title:const Text('Devolver bem'),content:Column(mainAxisSize:MainAxisSize.min,children:[DropdownButtonFormField<String>(initialValue:condition,decoration:const InputDecoration(labelText:'Estado na devolução',border:OutlineInputBorder()),items:const [DropdownMenuItem(value:'excellent',child:Text('Excelente')),DropdownMenuItem(value:'good',child:Text('Bom')),DropdownMenuItem(value:'regular',child:Text('Regular')),DropdownMenuItem(value:'maintenance',child:Text('Necessita manutenção')),DropdownMenuItem(value:'damaged',child:Text('Avariado'))],onChanged:(v)=>setState(()=>condition=v??condition)),const SizedBox(height:12),TextField(controller:notes,maxLines:2,decoration:const InputDecoration(labelText:'Notas da devolução',border:OutlineInputBorder()))]),actions:[TextButton(onPressed:()=>Navigator.pop(context),child:const Text('Cancelar')),FilledButton(onPressed:()=>Navigator.pop(context,_ReturnInput(condition,notes.text)),child:const Text('Confirmar devolução'))]);}

class _MaintenanceDialog extends StatefulWidget {const _MaintenanceDialog({required this.data,this.presetType});final _Phase2Data data;final String? presetType;@override State<_MaintenanceDialog> createState()=>_MaintenanceDialogState();}
class _MaintenanceDialogState extends State<_MaintenanceDialog>{String? assetId;late String type;DateTime date=DateTime.now();DateTime? nextDue;final description=TextEditingController();final cost=TextEditingController(text:'0');final supplier=TextEditingController();String? accountId;String payment='Dinheiro';bool financial=false;@override void initState(){super.initState();type=widget.presetType??'maintenance';final caixa=widget.data.accounts.where((a)=>a['name']?.toString().toLowerCase()=='caixa');if(caixa.isNotEmpty)accountId=caixa.first['id'].toString();else if(widget.data.accounts.isNotEmpty)accountId=widget.data.accounts.first['id'].toString();}@override void dispose(){description.dispose();cost.dispose();supplier.dispose();super.dispose();}@override Widget build(BuildContext context)=>AlertDialog(title:const Text('Registar intervenção'),content:SizedBox(width:560,child:SingleChildScrollView(child:Column(mainAxisSize:MainAxisSize.min,children:[_dropdown('Bem',assetId,widget.data.assets.map((e)=>e['id'].toString()).toList(),(v)=>'${widget.data.assets.firstWhere((e)=>e['id'].toString()==v)['asset_number']} · ${widget.data.assets.firstWhere((e)=>e['id'].toString()==v)['name']}',(v)=>setState(()=>assetId=v)),const SizedBox(height:12),DropdownButtonFormField<String>(initialValue:type,decoration:const InputDecoration(labelText:'Tipo',border:OutlineInputBorder()),items:const [DropdownMenuItem(value:'maintenance',child:Text('Manutenção')),DropdownMenuItem(value:'repair',child:Text('Reparação')),DropdownMenuItem(value:'inspection',child:Text('Inspeção'))],onChanged:(v)=>setState(()=>type=v??type)),const SizedBox(height:12),TextField(controller:description,maxLines:2,decoration:const InputDecoration(labelText:'Descrição',border:OutlineInputBorder())),const SizedBox(height:12),TextField(controller:supplier,decoration:const InputDecoration(labelText:'Fornecedor / oficina',border:OutlineInputBorder())),const SizedBox(height:12),TextField(controller:cost,keyboardType:const TextInputType.numberWithOptions(decimal:true),decoration:const InputDecoration(labelText:'Custo (€)',border:OutlineInputBorder())),const SizedBox(height:12),ListTile(contentPadding:EdgeInsets.zero,leading:const Icon(Icons.event),title:Text('Data: ${DateFormat('dd/MM/yyyy').format(date)}'),trailing:IconButton(icon:const Icon(Icons.calendar_month),onPressed:() async {final d=await showDatePicker(context:context,initialDate:date,firstDate:DateTime(2020),lastDate:DateTime.now().add(const Duration(days:3650)));if(d!=null){setState(()=>date=d);}})),ListTile(contentPadding:EdgeInsets.zero,leading:const Icon(Icons.update),title:Text(nextDue==null?'Próxima intervenção (opcional)':'Próxima: ${DateFormat('dd/MM/yyyy').format(nextDue!)}'),trailing:IconButton(icon:const Icon(Icons.calendar_month),onPressed:() async {final d=await showDatePicker(context:context,initialDate:date.add(const Duration(days:180)),firstDate:date,lastDate:DateTime.now().add(const Duration(days:3650)));if(d!=null){setState(()=>nextDue=d);}})),SwitchListTile(contentPadding:EdgeInsets.zero,value:financial,onChanged:(v)=>setState(()=>financial=v),title:const Text('Registar despesa na Tesouraria')),if(financial&&widget.data.accounts.isNotEmpty)...[const SizedBox(height:8),_dropdown('Conta / fundo',accountId,widget.data.accounts.map((e)=>e['id'].toString()).toList(),(v)=>widget.data.accounts.firstWhere((e)=>e['id'].toString()==v)['name'].toString(),(v)=>setState(()=>accountId=v)),const SizedBox(height:12),DropdownButtonFormField<String>(initialValue:payment,decoration:const InputDecoration(labelText:'Pagamento',border:OutlineInputBorder()),items:const ['Dinheiro','MB Way','Transferência bancária'].map((v)=>DropdownMenuItem(value:v,child:Text(v))).toList(),onChanged:(v)=>setState(()=>payment=v??payment))]]))),actions:[TextButton(onPressed:()=>Navigator.pop(context),child:const Text('Cancelar')),FilledButton(onPressed:assetId==null?null:()=>Navigator.pop(context,_MaintenanceInput(assetId!,type,date,description.text,_parse(cost.text),supplier.text,nextDue,accountId,payment,financial)),child:const Text('Registar'))]);}

class _KitDialog extends StatefulWidget {const _KitDialog({required this.assets});final List<Map<String,dynamic>> assets;@override State<_KitDialog> createState()=>_KitDialogState();}
class _KitDialogState extends State<_KitDialog>{final name=TextEditingController();final description=TextEditingController();final selected=<String>{};@override void dispose(){name.dispose();description.dispose();super.dispose();}@override Widget build(BuildContext context)=>AlertDialog(title:const Text('Novo Kit'),content:SizedBox(width:560,height:520,child:Column(children:[TextField(controller:name,decoration:const InputDecoration(labelText:'Nome do Kit',border:OutlineInputBorder())),const SizedBox(height:12),TextField(controller:description,decoration:const InputDecoration(labelText:'Descrição',border:OutlineInputBorder())),const SizedBox(height:12),const Align(alignment:Alignment.centerLeft,child:Text('Equipamentos',style:TextStyle(fontWeight:FontWeight.w700))),const SizedBox(height:6),Expanded(child:ListView(children:[for(final asset in widget.assets) CheckboxListTile(value:selected.contains(asset['id'].toString()),onChanged:(v)=>setState((){final id=asset['id'].toString();if(v==true){selected.add(id);}else{selected.remove(id);}}),title:Text('${asset['asset_number']} · ${asset['name']}'),subtitle:Text(asset['category']?.toString()??''))]))])),actions:[TextButton(onPressed:()=>Navigator.pop(context),child:const Text('Cancelar')),FilledButton(onPressed:()=>Navigator.pop(context,_KitInput(name.text,description.text,selected.toList())),child:const Text('Guardar Kit'))]);}

Widget _dropdown(String label,String? value,List<String> items,String Function(String) text,ValueChanged<String?> onChanged)=>DropdownButtonFormField<String>(initialValue:value,isExpanded:true,decoration:InputDecoration(labelText:label,border:const OutlineInputBorder()),items:items.map((v)=>DropdownMenuItem(value:v,child:Text(text(v),overflow:TextOverflow.ellipsis))).toList(),onChanged:onChanged);

class _Metric extends StatelessWidget{const _Metric(this.label,this.value,this.icon);final String label,value;final IconData icon;@override Widget build(BuildContext context)=>SizedBox(width:210,child:Card(child:ListTile(leading:CircleAvatar(child:Icon(icon)),title:Text(label),subtitle:Text(value,style:Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight:FontWeight.w900)))));}
class _Phase2Data{const _Phase2Data({required this.assets,required this.members,required this.events,required this.accounts,required this.loans,required this.maintenance,required this.kits});final List<Map<String,dynamic>> assets,members,events,accounts,loans,maintenance,kits;}
class _LoanInput{const _LoanInput(this.assetId,this.borrowerType,this.memberId,this.eventId,this.externalName,this.expectedReturn,this.notes);final String assetId,borrowerType;final String? memberId,eventId;final String externalName,notes;final DateTime? expectedReturn;}
class _ReturnInput{const _ReturnInput(this.condition,this.notes);final String condition,notes;}
class _MaintenanceInput{const _MaintenanceInput(this.assetId,this.type,this.date,this.description,this.cost,this.supplier,this.nextDue,this.accountId,this.paymentMethod,this.postFinancial);final String assetId,type,description,supplier,paymentMethod;final DateTime date;final double cost;final DateTime? nextDue;final String? accountId;final bool postFinancial;}
class _KitInput{const _KitInput(this.name,this.description,this.assetIds);final String name,description;final List<String> assetIds;}

String _memberName(Map<dynamic,dynamic> row){final full=row['full_name']?.toString()??'';final nick=row['nickname']?.toString()??'';return nick.isEmpty?full:'$full ($nick)';}
String _formatDate(Object? value){final d=DateTime.tryParse(value?.toString()??'');return d==null?'—':DateFormat('dd/MM/yyyy').format(d);}
String _money(Object? value)=>'${_double(value).toStringAsFixed(2).replaceAll('.', ',')} €';
double _double(Object? value)=>value is num?value.toDouble():double.tryParse(value?.toString().replaceAll(',','.')??'')??0;
double _parse(String value)=>double.tryParse(value.replaceAll(',','.'))??0;
String _maintenanceLabel(String? type)=>switch(type){'inspection'=>'Inspeção','repair'=>'Reparação',_=>'Manutenção'};
IconData _maintenanceIcon(String? type)=>switch(type){'inspection'=>Icons.fact_check_outlined,'repair'=>Icons.handyman_outlined,_=>Icons.build_outlined};
