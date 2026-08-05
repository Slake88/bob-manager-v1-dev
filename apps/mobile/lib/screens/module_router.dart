import 'package:flutter/material.dart'; import '../core/module_definition.dart'; import 'dashboard_screen.dart'; import 'members_screen.dart'; import 'entity_list_screen.dart'; import 'emergency_screen.dart';
class ModuleRouter extends StatelessWidget{const ModuleRouter({super.key,required this.module});final ModuleDefinition module;
 @override Widget build(BuildContext c)=>switch(module.code){
 'dashboard'=>const DashboardScreen(),'members'=>const MembersScreen(),'treasury'=>const EntityListScreen(title:'Contas financeiras',table:'financial_accounts',primaryField:'name',subtitleFields:['account_type','opening_balance']),
 'fees'=>const EntityListScreen(title:'Quotas',table:'fee_obligations',primaryField:'period_start',subtitleFields:['status','amount','paid_amount']),
 'lottery'=>const EntityListScreen(title:'Euromilhões',table:'lottery_groups',primaryField:'name',subtitleFields:['billing_frequency','participant_amount']),
 'events'=>const EntityListScreen(title:'Eventos',table:'events',primaryField:'name',subtitleFields:['event_type','status','starts_at']),
 'inventory'=>const EntityListScreen(title:'Produtos',table:'products',primaryField:'name',subtitleFields:['category','active']),
 'documents'=>const EntityListScreen(title:'Documentos',table:'documents',primaryField:'name',subtitleFields:['category','status','expires_at']),
 'communication'=>const EntityListScreen(title:'Comunicação',table:'announcements',primaryField:'title',subtitleFields:['priority','body']),
 'reports'=>const _Info('Relatórios e exportações','PDF, Excel, CSV, importador editável e Livro Anual.'),
 'settings'=>const _Info('Configurações','Identidade, cargos, permissões, contas, fundos e integrações.'),
 'emergency'=>const EmergencyScreen(),_=>const SizedBox.shrink()};}
class _Info extends StatelessWidget{const _Info(this.title,this.body);final String title,body;@override Widget build(BuildContext c)=>ListView(padding:const EdgeInsets.all(16),children:[Card(child:ListTile(leading:const Icon(Icons.construction),title:Text(title),subtitle:Text(body)))]);}
