import 'package:flutter/material.dart';

import '../repositories/polls_repository.dart';

class PollEditorScreen extends StatefulWidget {
  const PollEditorScreen({
    super.key,
    required this.repository,
    this.initialPoll,
    this.initialOptions = const [],
  });

  final PollsRepository repository;
  final Map<String, dynamic>? initialPoll;
  final List<Map<String, dynamic>> initialOptions;

  @override
  State<PollEditorScreen> createState() => _PollEditorScreenState();
}

class _PollEditorScreenState extends State<PollEditorScreen> {
  late final TextEditingController _title;
  late final TextEditingController _description;
  final List<TextEditingController> _options = [];
  late String _pollType;
  late bool _anonymous;
  late bool _multipleChoice;
  late bool _showResults;
  late DateTime _startsAt;
  DateTime? _endsAt;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    final poll = widget.initialPoll;
    _title = TextEditingController(text: poll?['title']?.toString() ?? '');
    _description = TextEditingController(text: poll?['description']?.toString() ?? '');
    _pollType = poll?['poll_type']?.toString() ?? 'vote';
    _anonymous = poll?['anonymous'] != false;
    _multipleChoice = poll?['multiple_choice'] == true;
    _showResults = poll?['show_results_before_close'] == true;
    _startsAt = DateTime.tryParse(poll?['starts_at']?.toString() ?? '')?.toLocal() ?? DateTime.now();
    final endValue = poll?['ends_at'];
    _endsAt = poll == null
        ? DateTime.now().add(const Duration(days: 7))
        : (endValue == null
            ? null
            : DateTime.tryParse(endValue.toString())?.toLocal());
    for (final option in widget.initialOptions) {
      _options.add(TextEditingController(text: option['label']?.toString() ?? ''));
    }
    while (_options.length < 2) {
      _options.add(TextEditingController());
    }
  }

  @override
  void dispose() {
    _title.dispose();
    _description.dispose();
    for (final controller in _options) {
      controller.dispose();
    }
    super.dispose();
  }

  Future<DateTime?> _pickDateTime(DateTime initial) async {
    final date = await showDatePicker(
      context: context,
      initialDate: initial,
      firstDate: DateTime.now().subtract(const Duration(days: 365)),
      lastDate: DateTime.now().add(const Duration(days: 3650)),
    );
    if (date == null || !mounted) return null;
    final time = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(initial),
    );
    if (time == null) return null;
    return DateTime(date.year, date.month, date.day, time.hour, time.minute);
  }

  Future<void> _save() async {
    if (_saving) return;
    setState(() => _saving = true);
    try {
      await widget.repository.saveDraft(
        pollId: widget.initialPoll?['id']?.toString(),
        title: _title.text,
        description: _description.text,
        pollType: _pollType,
        anonymous: _anonymous,
        multipleChoice: _multipleChoice,
        showResultsBeforeClose: _showResults,
        startsAt: _startsAt,
        endsAt: _endsAt,
        optionLabels: _options.map((controller) => controller.text).toList(),
      );
      if (!mounted) return;
      Navigator.pop(context, true);
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(_friendly(error))),
      );
      setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final editing = widget.initialPoll != null;
    return Scaffold(
      appBar: AppBar(title: Text(editing ? 'Editar rascunho' : 'Nova votação / inquérito')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 110),
        children: [
          SegmentedButton<String>(
            segments: const [
              ButtonSegment(value: 'vote', icon: Icon(Icons.how_to_vote_outlined), label: Text('Votação')),
              ButtonSegment(value: 'survey', icon: Icon(Icons.fact_check_outlined), label: Text('Inquérito')),
            ],
            selected: {_pollType},
            onSelectionChanged: (values) => setState(() => _pollType = values.first),
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _title,
            textCapitalization: TextCapitalization.sentences,
            decoration: const InputDecoration(
              labelText: 'Título / pergunta',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _description,
            minLines: 3,
            maxLines: 6,
            decoration: const InputDecoration(
              labelText: 'Descrição (opcional)',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 16),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('Votação anónima'),
            subtitle: const Text('A gestão vê apenas resultados agregados, não a associação pessoa → opção.'),
            value: _anonymous,
            onChanged: (value) => setState(() => _anonymous = value),
          ),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('Escolha múltipla'),
            subtitle: const Text('Permite selecionar mais do que uma opção no mesmo voto.'),
            value: _multipleChoice,
            onChanged: (value) => setState(() => _multipleChoice = value),
          ),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('Mostrar resultados enquanto decorre'),
            subtitle: const Text('Por defeito, os resultados só ficam visíveis depois do fecho.'),
            value: _showResults,
            onChanged: (value) => setState(() => _showResults = value),
          ),
          const Divider(height: 28),
          Text('Calendário', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 8),
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.play_circle_outline),
            title: const Text('Abertura'),
            subtitle: Text(pollDateLabel(_startsAt)),
            trailing: const Icon(Icons.edit_calendar_outlined),
            onTap: () async {
              final value = await _pickDateTime(_startsAt);
              if (value != null && mounted) setState(() => _startsAt = value);
            },
          ),
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.stop_circle_outlined),
            title: const Text('Fecho'),
            subtitle: Text(_endsAt == null ? 'Sem data de fecho' : pollDateLabel(_endsAt)),
            trailing: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (_endsAt != null)
                  IconButton(
                    tooltip: 'Sem data de fecho',
                    onPressed: () => setState(() => _endsAt = null),
                    icon: const Icon(Icons.clear),
                  ),
                const Icon(Icons.edit_calendar_outlined),
              ],
            ),
            onTap: () async {
              final initial = _endsAt ?? _startsAt.add(const Duration(days: 7));
              final value = await _pickDateTime(initial);
              if (value != null && mounted) setState(() => _endsAt = value);
            },
          ),
          const Divider(height: 28),
          Row(
            children: [
              Expanded(
                child: Text('Opções', style: Theme.of(context).textTheme.titleMedium),
              ),
              TextButton.icon(
                onPressed: () => setState(() => _options.add(TextEditingController())),
                icon: const Icon(Icons.add),
                label: const Text('Adicionar'),
              ),
            ],
          ),
          const SizedBox(height: 8),
          for (var index = 0; index < _options.length; index++) ...[
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _options[index],
                    textCapitalization: TextCapitalization.sentences,
                    decoration: InputDecoration(
                      labelText: 'Opção ${index + 1}',
                      border: const OutlineInputBorder(),
                    ),
                  ),
                ),
                const SizedBox(width: 6),
                IconButton(
                  tooltip: 'Remover opção',
                  onPressed: _options.length <= 2
                      ? null
                      : () {
                          final controller = _options.removeAt(index);
                          controller.dispose();
                          setState(() {});
                        },
                  icon: const Icon(Icons.delete_outline),
                ),
              ],
            ),
            const SizedBox(height: 10),
          ],
          const Card(
            child: ListTile(
              leading: Icon(Icons.info_outline),
              title: Text('Primeiro fica em rascunho'),
              subtitle: Text(
                'Depois de publicada, a pergunta, opções, anonimato e calendário ficam bloqueados. O voto submetido também não pode ser alterado.',
              ),
            ),
          ),
        ],
      ),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: FilledButton.icon(
            onPressed: _saving ? null : _save,
            icon: _saving
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.save_outlined),
            label: Text(_saving ? 'A guardar…' : 'Guardar rascunho'),
          ),
        ),
      ),
    );
  }
}

String _friendly(Object error) => error
    .toString()
    .replaceFirst('Exception: ', '')
    .replaceFirst('Bad state: ', '')
    .replaceFirst('Invalid argument(s): ', '');
