import 'package:flutter/material.dart';

enum EntityFieldType {
  text,
  multiline,
  integer,
  decimal,
  date,
  dateTime,
  boolean,
  choice,
}

class EntityFieldDefinition {
  const EntityFieldDefinition({
    required this.key,
    required this.label,
    this.type = EntityFieldType.text,
    this.required = false,
    this.readOnly = false,
    this.choices = const [],
  });

  final String key;
  final String label;
  final EntityFieldType type;
  final bool required;
  final bool readOnly;
  final List<String> choices;
}

class EntityDefinition {
  const EntityDefinition({
    required this.code,
    required this.title,
    required this.singularTitle,
    required this.table,
    required this.primaryField,
    required this.icon,
    required this.fields,
    this.subtitleFields = const [],
    this.canCreate = true,
    this.canEdit = true,
    this.canDelete = true,
  });

  final String code;
  final String title;
  final String singularTitle;
  final String table;
  final String primaryField;
  final IconData icon;
  final List<EntityFieldDefinition> fields;
  final List<String> subtitleFields;
  final bool canCreate;
  final bool canEdit;
  final bool canDelete;
}

const memberDefinition = EntityDefinition(
  code: 'members',
  title: 'Membros',
  singularTitle: 'Membro',
  table: 'members',
  primaryField: 'full_name',
  icon: Icons.groups_outlined,
  subtitleFields: ['nickname', 'member_number', 'status', 'primary_role'],
  fields: [
    EntityFieldDefinition(
      key: 'member_number',
      label: 'Número de membro',
      type: EntityFieldType.integer,
    ),
    EntityFieldDefinition(
      key: 'full_name',
      label: 'Nome completo',
      required: true,
    ),
    EntityFieldDefinition(key: 'nickname', label: 'Alcunha'),
    EntityFieldDefinition(
      key: 'status',
      label: 'Estado',
      type: EntityFieldType.choice,
      required: true,
      choices: [
        'prospect',
        'full_color',
        'honorary',
        'suspended',
        'former',
        'deceased',
      ],
    ),
    EntityFieldDefinition(
      key: 'primary_role',
      label: 'Cargo principal',
      type: EntityFieldType.choice,
      choices: [
        'Presidente',
        'Vice-Presidente',
        'Tesoureiro',
        'Secretário',
        'Sargento de Armas',
        'Road Captain',
        'Prospect',
        'Membro',
      ],
    ),
    EntityFieldDefinition(key: 'additional_roles', label: 'Cargos adicionais'),
    EntityFieldDefinition(key: 'email', label: 'Email'),
    EntityFieldDefinition(key: 'phone', label: 'Telefone'),
    EntityFieldDefinition(key: 'address', label: 'Morada'),
    EntityFieldDefinition(key: 'postal_code', label: 'Código postal'),
    EntityFieldDefinition(key: 'locality', label: 'Localidade'),
    EntityFieldDefinition(key: 'tax_number', label: 'NIF'),
    EntityFieldDefinition(
      key: 'birth_date',
      label: 'Data de nascimento',
      type: EntityFieldType.date,
    ),
    EntityFieldDefinition(
      key: 'prospect_joined_at',
      label: 'Entrada como Prospect',
      type: EntityFieldType.date,
    ),
    EntityFieldDefinition(
      key: 'full_colors_at',
      label: 'Data de Full Color',
      type: EntityFieldType.date,
    ),
    EntityFieldDefinition(key: 'emergency_name', label: 'Contacto de emergência'),
    EntityFieldDefinition(key: 'emergency_relation', label: 'Relação'),
    EntityFieldDefinition(key: 'emergency_phone', label: 'Telefone de emergência'),
    EntityFieldDefinition(key: 'blood_type', label: 'Grupo sanguíneo'),
    EntityFieldDefinition(key: 'allergies', label: 'Alergias', type: EntityFieldType.multiline),
    EntityFieldDefinition(
      key: 'medical_notes',
      label: 'Observações médicas importantes',
      type: EntityFieldType.multiline,
    ),
    EntityFieldDefinition(key: 'motorcycle_brand', label: 'Marca da mota principal'),
    EntityFieldDefinition(key: 'motorcycle_model', label: 'Modelo da mota principal'),
    EntityFieldDefinition(
      key: 'motorcycle_year',
      label: 'Ano da mota',
      type: EntityFieldType.integer,
    ),
    EntityFieldDefinition(key: 'motorcycle_registration', label: 'Matrícula'),
    EntityFieldDefinition(key: 'notes', label: 'Observações', type: EntityFieldType.multiline),
  ],
);

const treasuryDefinition = EntityDefinition(
  code: 'treasury',
  title: 'Movimentos de Tesouraria',
  singularTitle: 'Movimento',
  table: 'financial_transactions',
  primaryField: 'description',
  icon: Icons.account_balance_wallet_outlined,
  subtitleFields: ['transaction_date', 'kind', 'amount', 'account_name', 'fund_name'],
  fields: [
    EntityFieldDefinition(key: 'transaction_date', label: 'Data', type: EntityFieldType.date, required: true),
    EntityFieldDefinition(
      key: 'kind',
      label: 'Tipo',
      type: EntityFieldType.choice,
      required: true,
      choices: ['income', 'expense', 'transfer', 'reversal'],
    ),
    EntityFieldDefinition(key: 'description', label: 'Descrição', required: true),
    EntityFieldDefinition(key: 'amount', label: 'Valor', type: EntityFieldType.decimal, required: true),
    EntityFieldDefinition(key: 'account_name', label: 'Conta financeira', required: true),
    EntityFieldDefinition(key: 'destination_account_name', label: 'Conta de destino'),
    EntityFieldDefinition(key: 'fund_name', label: 'Fundo'),
    EntityFieldDefinition(key: 'cost_center_name', label: 'Centro de custo'),
    EntityFieldDefinition(key: 'payment_method', label: 'Método de pagamento'),
    EntityFieldDefinition(key: 'supplier_name', label: 'Fornecedor/entidade'),
    EntityFieldDefinition(key: 'document_number', label: 'Número de documento'),
    EntityFieldDefinition(key: 'notes', label: 'Observações', type: EntityFieldType.multiline),
  ],
);

const feesDefinition = EntityDefinition(
  code: 'fees',
  title: 'Quotas',
  singularTitle: 'Quota',
  table: 'fee_obligations',
  primaryField: 'member_name',
  icon: Icons.receipt_long_outlined,
  subtitleFields: ['period_label', 'status', 'amount', 'paid_amount', 'balance'],
  fields: [
    EntityFieldDefinition(key: 'member_name', label: 'Membro', required: true),
    EntityFieldDefinition(key: 'period_label', label: 'Período', required: true),
    EntityFieldDefinition(key: 'due_date', label: 'Vencimento', type: EntityFieldType.date),
    EntityFieldDefinition(key: 'amount', label: 'Valor devido', type: EntityFieldType.decimal, required: true),
    EntityFieldDefinition(key: 'paid_amount', label: 'Valor pago', type: EntityFieldType.decimal),
    EntityFieldDefinition(key: 'credit_amount', label: 'Crédito', type: EntityFieldType.decimal),
    EntityFieldDefinition(key: 'balance', label: 'Saldo pendente', type: EntityFieldType.decimal, readOnly: true),
    EntityFieldDefinition(
      key: 'status',
      label: 'Estado',
      type: EntityFieldType.choice,
      choices: ['pending', 'partial', 'paid', 'advance', 'exempt', 'forgiven', 'cancelled', 'overdue'],
    ),
    EntityFieldDefinition(key: 'payment_method', label: 'Método de pagamento'),
    EntityFieldDefinition(key: 'notes', label: 'Observações', type: EntityFieldType.multiline),
  ],
);

const lotteryDefinition = EntityDefinition(
  code: 'lottery',
  title: 'Participantes do Euromilhões',
  singularTitle: 'Participante',
  table: 'lottery_participants',
  primaryField: 'member_name',
  icon: Icons.casino_outlined,
  subtitleFields: ['billing_frequency', 'participant_amount', 'numbers', 'stars', 'balance'],
  fields: [
    EntityFieldDefinition(key: 'member_name', label: 'Membro', required: true),
    EntityFieldDefinition(
      key: 'billing_frequency',
      label: 'Cobrança',
      type: EntityFieldType.choice,
      required: true,
      choices: ['weekly', 'monthly'],
    ),
    EntityFieldDefinition(key: 'participant_amount', label: 'Valor por participante', type: EntityFieldType.decimal, required: true),
    EntityFieldDefinition(key: 'numbers', label: '5 números', required: true),
    EntityFieldDefinition(key: 'stars', label: '2 estrelas', required: true),
    EntityFieldDefinition(key: 'paid_amount', label: 'Total pago', type: EntityFieldType.decimal),
    EntityFieldDefinition(key: 'balance', label: 'Saldo pendente', type: EntityFieldType.decimal),
    EntityFieldDefinition(key: 'active', label: 'Ativo', type: EntityFieldType.boolean),
    EntityFieldDefinition(key: 'notes', label: 'Observações', type: EntityFieldType.multiline),
  ],
);

const eventsDefinition = EntityDefinition(
  code: 'events',
  title: 'Eventos',
  singularTitle: 'Evento',
  table: 'events',
  primaryField: 'name',
  icon: Icons.event_outlined,
  subtitleFields: ['event_type', 'status', 'starts_at', 'location'],
  fields: [
    EntityFieldDefinition(key: 'name', label: 'Nome', required: true),
    EntityFieldDefinition(
      key: 'event_type',
      label: 'Tipo',
      type: EntityFieldType.choice,
      choices: ['ride', 'meeting', 'dinner', 'anniversary', 'solidarity', 'music', 'trip', 'rock_ride', 'other'],
    ),
    EntityFieldDefinition(key: 'starts_at', label: 'Início', type: EntityFieldType.dateTime),
    EntityFieldDefinition(key: 'ends_at', label: 'Fim', type: EntityFieldType.dateTime),
    EntityFieldDefinition(key: 'location', label: 'Local'),
    EntityFieldDefinition(key: 'description', label: 'Descrição', type: EntityFieldType.multiline),
    EntityFieldDefinition(
      key: 'status',
      label: 'Estado',
      type: EntityFieldType.choice,
      choices: ['proposed', 'analysis', 'approved', 'planning', 'published', 'open', 'ongoing', 'completed', 'cancelled', 'archived'],
    ),
    EntityFieldDefinition(key: 'expected_attendance', label: 'Público previsto', type: EntityFieldType.integer),
    EntityFieldDefinition(key: 'budget', label: 'Orçamento', type: EntityFieldType.decimal),
    EntityFieldDefinition(key: 'free_entry', label: 'Entrada livre', type: EntityFieldType.boolean),
    EntityFieldDefinition(key: 'notes', label: 'Observações', type: EntityFieldType.multiline),
  ],
);

const inventoryDefinition = EntityDefinition(
  code: 'inventory',
  title: 'Inventário e Merchandising',
  singularTitle: 'Artigo',
  table: 'products',
  primaryField: 'name',
  icon: Icons.inventory_2_outlined,
  subtitleFields: ['category', 'variant', 'current_stock', 'sale_price'],
  fields: [
    EntityFieldDefinition(key: 'name', label: 'Nome', required: true),
    EntityFieldDefinition(key: 'sku', label: 'SKU'),
    EntityFieldDefinition(key: 'category', label: 'Categoria'),
    EntityFieldDefinition(key: 'variant', label: 'Variante/tamanho'),
    EntityFieldDefinition(key: 'location', label: 'Localização'),
    EntityFieldDefinition(key: 'unit', label: 'Unidade'),
    EntityFieldDefinition(key: 'current_stock', label: 'Stock atual', type: EntityFieldType.decimal),
    EntityFieldDefinition(key: 'reserved_stock', label: 'Stock reservado', type: EntityFieldType.decimal),
    EntityFieldDefinition(key: 'minimum_stock', label: 'Stock mínimo', type: EntityFieldType.decimal),
    EntityFieldDefinition(key: 'cost', label: 'Custo', type: EntityFieldType.decimal),
    EntityFieldDefinition(key: 'sale_price', label: 'Preço de venda', type: EntityFieldType.decimal),
    EntityFieldDefinition(key: 'active', label: 'Ativo', type: EntityFieldType.boolean),
    EntityFieldDefinition(key: 'notes', label: 'Observações', type: EntityFieldType.multiline),
  ],
);

const documentsDefinition = EntityDefinition(
  code: 'documents',
  title: 'Documentos e Arquivo',
  singularTitle: 'Documento',
  table: 'documents',
  primaryField: 'name',
  icon: Icons.folder_outlined,
  subtitleFields: ['category', 'status', 'document_date', 'expires_at'],
  fields: [
    EntityFieldDefinition(key: 'name', label: 'Nome', required: true),
    EntityFieldDefinition(key: 'category', label: 'Categoria'),
    EntityFieldDefinition(key: 'description', label: 'Descrição', type: EntityFieldType.multiline),
    EntityFieldDefinition(key: 'document_date', label: 'Data do documento', type: EntityFieldType.date),
    EntityFieldDefinition(key: 'expires_at', label: 'Validade', type: EntityFieldType.date),
    EntityFieldDefinition(key: 'version', label: 'Versão'),
    EntityFieldDefinition(
      key: 'status',
      label: 'Estado',
      type: EntityFieldType.choice,
      choices: ['draft', 'pending', 'approved', 'archived', 'expired'],
    ),
    EntityFieldDefinition(key: 'sensitive', label: 'Sensível/privado', type: EntityFieldType.boolean),
    EntityFieldDefinition(key: 'storage_path', label: 'Caminho do ficheiro'),
    EntityFieldDefinition(key: 'tags', label: 'Etiquetas'),
  ],
);

const communicationDefinition = EntityDefinition(
  code: 'communication',
  title: 'Centro de Comunicação',
  singularTitle: 'Comunicado',
  table: 'announcements',
  primaryField: 'title',
  icon: Icons.campaign_outlined,
  subtitleFields: ['priority', 'published_at', 'requires_acknowledgement'],
  fields: [
    EntityFieldDefinition(key: 'title', label: 'Título', required: true),
    EntityFieldDefinition(key: 'body', label: 'Mensagem', type: EntityFieldType.multiline, required: true),
    EntityFieldDefinition(
      key: 'priority',
      label: 'Prioridade',
      type: EntityFieldType.choice,
      choices: ['informative', 'normal', 'important', 'urgent', 'critical'],
    ),
    EntityFieldDefinition(key: 'audience', label: 'Destinatários'),
    EntityFieldDefinition(key: 'published_at', label: 'Publicação', type: EntityFieldType.dateTime),
    EntityFieldDefinition(key: 'expires_at', label: 'Expiração', type: EntityFieldType.dateTime),
    EntityFieldDefinition(key: 'requires_acknowledgement', label: 'Exige confirmação de leitura', type: EntityFieldType.boolean),
  ],
);

const mainEntityDefinitions = <String, EntityDefinition>{
  'members': memberDefinition,
  'treasury': treasuryDefinition,
  'fees': feesDefinition,
  'lottery': lotteryDefinition,
  'events': eventsDefinition,
  'inventory': inventoryDefinition,
  'documents': documentsDefinition,
  'communication': communicationDefinition,
};
