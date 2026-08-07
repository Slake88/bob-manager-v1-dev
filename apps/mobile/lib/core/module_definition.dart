import 'package:flutter/material.dart';
class ModuleDefinition {
 const ModuleDefinition(this.code,this.title,this.icon,this.description);
 final String code; final String title; final IconData icon; final String description;
}
const appModules = <ModuleDefinition>[
 ModuleDefinition('dashboard','Dashboard',Icons.dashboard_outlined,'Resumo do clube e alertas'),
 ModuleDefinition('activity','Atividade',Icons.dynamic_feed_outlined,'Activity Feed e histórico do clube'),
 ModuleDefinition('members','Membros',Icons.groups_outlined,'Membros, motas, manutenção, patches e Timeline'),
 ModuleDefinition('treasury','Tesouraria',Icons.account_balance_wallet_outlined,'Contas, fundos, movimentos e reembolsos'),
 ModuleDefinition('fees','Quotas',Icons.receipt_long_outlined,'Planos, cobranças, pagamentos e saldos'),
 ModuleDefinition('lottery','Euromilhões',Icons.casino_outlined,'Participantes, chaves, sorteios e prémios'),
 ModuleDefinition('events','Eventos',Icons.event_outlined,'Eventos, passeios e Rock & Ride In'),
 ModuleDefinition('inventory','Inventário',Icons.inventory_2_outlined,'Stock, merchandising, patches e vendas'),
 ModuleDefinition('documents','Documentos',Icons.folder_outlined,'Arquivo, atas, licenças e Cápsula do Tempo'),
 ModuleDefinition('communication','Comunicação',Icons.campaign_outlined,'Comunicados, votações e inquéritos'),
 ModuleDefinition('reports','Relatórios',Icons.assessment_outlined,'PDF, Excel, CSV e importações'),
 ModuleDefinition('settings','Configurações',Icons.settings_outlined,'Clube, cargos, permissões e integrações'),
 ModuleDefinition('emergency','Emergência',Icons.emergency_outlined,'Contactos e dados médicos essenciais'),
];
