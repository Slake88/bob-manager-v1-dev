import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../repositories/inventory_control_repository.dart';

class InventoryMovementsScreen extends StatefulWidget {
  const InventoryMovementsScreen({super.key});
  @override State<InventoryMovementsScreen> createState()=>_InventoryMovementsScreenState();
}

class _InventoryMovementsScreenState extends State<InventoryMovementsScreen>{
  final _repo=InventoryControlRepository();
  late Future<List<Map<String,dynamic>>> _future;
  final _search=TextEditingController();
  String _kind='all'; String _area='all';
  @override void initState(){super.initState();_reload();}
  @override void dispose(){_search.dispose();super.dispose();}
  void _reload()=>_future=_repo.movements();
  Future<void> _refresh() async{setState(_reload);await _future;}

  @override Widget build(BuildContext context)=>FutureBuilder<List<Map<String,dynamic>>>(future:_future,builder:(context,snapshot){
    if(snapshot.hasError)return Center(child:Text('Erro: ${snapshot.error}'));
    if(!snapshot.hasData)return const Center(child:CircularProgressIndicator());
    final all=snapshot.data!;
    final q=_search.text.trim().toLowerCase();
    final rows=all.where((r){final p=r['products'];final v=r['product_variants'];final e=r['events'];final u=r['profiles'];final text='${p is Map?p['name']:''} ${v is Map?v['name']:''} ${e is Map?e['name']:''} ${u is Map?u['full_name']:''} ${r['notes']??''}'.toLowerCase();final area=p is Map?p['inventory_area']?.toString()??'':'';return (q.isEmpty||text.contains(q))&&(_kind=='all'||r['kind']==_kind)&&(_area=='all'||area==_area);}).toList();
    final inQty=rows.where((r)=>_num(r['quantity'])>0).fold<double>(0,(a,r)=>a+_num(r['quantity']));
    final outQty=rows.where((r)=>_num(r['quantity'])<0).fold<double>(0,(a,r)=>a+_num(r['quantity']).abs());
    return RefreshIndicator(onRefresh:_refresh,child:ListView(padding:const EdgeInsets.fromLTRB(16,16,16,96),children:[
      Text('Movimentos de Inventário',style:Theme.of(context).textTheme.headlineSmall?.copyWith(fontWeight:FontWeight.w900)),const SizedBox(height:4),const Text('Histórico unificado de entradas, vendas, consumos, perdas, devoluções e ajustes.'),const SizedBox(height:14),
      Wrap(spacing:10,runSpacing:10,children:[_metric('Movimentos','${rows.length}',Icons.swap_horiz),_metric('Entradas',_qty(inQty),Icons.south_west),_metric('Saídas',_qty(outQty),Icons.north_east)]),const SizedBox(height:14),
      Wrap(spacing:10,runSpacing:10,crossAxisAlignment:WrapCrossAlignment.center,children:[SizedBox(width:280,child:TextField(controller:_search,onChanged:(_)=>setState((){}),decoration:const InputDecoration(prefixIcon:Icon(Icons.search),labelText:'Pesquisar',border:OutlineInputBorder()))),SizedBox(width:190,child:DropdownButtonFormField<String>(initialValue:_kind,decoration:const InputDecoration(labelText:'Tipo',border:OutlineInputBorder()),items:const {'all':'Todos','purchase':'Compra','sale':'Venda','adjustment':'Ajuste','loss':'Perda','transfer':'Transferência','event_consumption':'Consumo evento','return':'Devolução'}.entries.map((e)=>DropdownMenuItem(value:e.key,child:Text(e.value))).toList(),onChanged:(v)=>setState(()=>_kind=v??'all'))),SizedBox(width:170,child:DropdownButtonFormField<String>(initialValue:_area,decoration:const InputDecoration(labelText:'Área',border:OutlineInputBorder()),items:const [DropdownMenuItem(value:'all',child:Text('Todas')),DropdownMenuItem(value:'shop',child:Text('Loja')),DropdownMenuItem(value:'bar',child:Text('Bar'))],onChanged:(v)=>setState(()=>_area=v??'all')))]),const SizedBox(height:12),
      if(rows.isEmpty)const Card(child:ListTile(title:Text('Sem movimentos para os filtros selecionados.'))) else for(final r in rows)_movementCard(r),
    ]));
  });

  Widget _movementCard(Map<String,dynamic> r){final p=r['products'];final v=r['product_variants'];final e=r['events'];final u=r['profiles'];final qty=_num(r['quantity']);final name=p is Map?p['name']?.toString()??'Artigo':'Artigo';final variant=v is Map?' · ${v['name']}':'';return Card(child:ListTile(leading:CircleAvatar(child:Icon(qty>=0?Icons.add:Icons.remove)),title:Text('$name$variant'),subtitle:Text([_kindLabel(r['kind']?.toString()),if(e is Map)'Evento: ${e['name']}',if(u is Map)'Utilizador: ${u['full_name']}',if((r['notes']?.toString()??'').isNotEmpty)r['notes'].toString(),_dateTime(r['created_at'])].join(' · ')),trailing:Text('${qty>0?'+':''}${_qty(qty)}',style:TextStyle(fontWeight:FontWeight.w900,color:qty>=0?Colors.greenAccent:Colors.redAccent))));}
  Widget _metric(String l,String v,IconData i)=>SizedBox(width:190,child:Card(child:ListTile(leading:CircleAvatar(child:Icon(i)),title:Text(l),subtitle:Text(v,style:Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight:FontWeight.w900)))));
}

double _num(Object? v)=>v is num?v.toDouble():double.tryParse(v?.toString()??'')??0;
String _qty(double v)=>v==v.roundToDouble()?v.toInt().toString():v.toStringAsFixed(2).replaceAll('.',',');
String _dateTime(Object? v){final d=DateTime.tryParse(v?.toString()??'');return d==null?'—':DateFormat('dd/MM/yyyy HH:mm').format(d.toLocal());}
String _kindLabel(String? v)=>switch(v){'purchase'=>'Compra','sale'=>'Venda','adjustment'=>'Ajuste','loss'=>'Perda','transfer'=>'Transferência','event_consumption'=>'Consumo evento','return'=>'Devolução',_=>'Movimento'};
