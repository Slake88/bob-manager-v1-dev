import 'package:flutter/material.dart';

import '../repositories/polls_repository.dart';
import 'poll_editor_screen.dart';

class PollDetailScreen extends StatefulWidget {
  const PollDetailScreen({
    super.key,
    required this.repository,
    required this.poll,
  });

  final PollsRepository repository;
  final Map<String, dynamic> poll;

  @override
  State<PollDetailScreen> createState() => _PollDetailScreenState();
}

class _PollDetailScreenState extends State<PollDetailScreen> {
  late Future<_PollDetailData> _future;
  final Set<String> _selected = <String>{};
  bool _submitting = false;

  @override
  void initState() {
    super.initState();
    _future = _load();
  }

  Future<_PollDetailData> _load() async {
    final values = await Future.wait<List<Map<String, dynamic>>>([
      widget.repository.options(widget.poll['id'].toString()),
      widget.repository.ownVotes(widget.poll['id'].toString()),
      widget.repository.results(widget.poll['id'].toString()),
    ]);
    if (_selected.isEmpty && values[1].isNotEmpty) {
      _selected.addAll(values[1].map((row) => row['option_id'].toString()));
    }
    return _PollDetailData(
      options: values[0],
      ownVotes: values[1],
      results: values[2],
    );
  }

  Future<void> _refreshDetail() async {
    if (!mounted) return;
    final next = _load();
    setState(() {
      _future = next;
    });
    await next;
  }

  Future<void> _vote() async {
    if (_submitting) return;
    setState(() {
      _submitting = true;
    });
    try {
      await widget.repository.castVote(
        widget.poll['id'].toString(),
        _selected,
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Voto submetido. Não pode ser alterado.'),
        ),
      );
      await _refreshDetail();
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(_friendly(error))),
      );
    } finally {
      if (mounted) {
        setState(() {
          _submitting = false;
        });
      }
    }
  }

  Future<void> _setStatus(String status) async {
    final label = switch (status) {
      'published' => 'publicar',
      'closed' => 'encerrar',
      _ => 'cancelar',
    };
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text('${label[0].toUpperCase()}${label.substring(1)} votação?'),
        content: Text(
          status == 'published'
              ? 'Depois de publicada, a pergunta, opções e configuração deixam de poder ser editadas.'
              : 'Confirmas que pretendes $label esta votação?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Não'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Confirmar'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    try {
      await widget.repository.setStatus(widget.poll['id'].toString(), status);
      if (!mounted) return;
      Navigator.pop(context, true);
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(_friendly(error))),
      );
    }
  }

  Future<void> _edit(List<Map<String, dynamic>> options) async {
    final changed = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) => PollEditorScreen(
          repository: widget.repository,
          initialPoll: widget.poll,
          initialOptions: options,
        ),
      ),
    );
    if (changed == true && mounted) Navigator.pop(context, true);
  }

  @override
  Widget build(BuildContext context) {
    final poll = widget.poll;
    final status = poll['status']?.toString() ?? 'draft';
    final effectiveStatus = pollEffectiveStatus(poll);
    final multiple = poll['multiple_choice'] == true;
    final resultsVisible = pollResultsVisible(
      poll,
      canManage: widget.repository.canManage,
    );

    return Scaffold(
      appBar: AppBar(
        title: Text(pollTypeLabel(poll['poll_type'])),
        actions: [
          IconButton(
            tooltip: 'Atualizar',
            onPressed: () {
              _refreshDetail();
            },
            icon: const Icon(Icons.refresh),
          ),
          if (widget.repository.canManage && status == 'published')
            PopupMenuButton<String>(
              onSelected: _setStatus,
              itemBuilder: (_) => const [
                PopupMenuItem(
                  value: 'closed',
                  child: Text('Encerrar votação'),
                ),
                PopupMenuItem(
                  value: 'cancelled',
                  child: Text('Cancelar votação'),
                ),
              ],
            ),
        ],
      ),
      body: FutureBuilder<_PollDetailData>(
        future: _future,
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return _DetailError(
              error: snapshot.error!,
              onRetry: () {
                _refreshDetail();
              },
            );
          }
          if (!snapshot.hasData) {
            return const Center(child: CircularProgressIndicator());
          }
          final data = snapshot.data!;
          final alreadyVoted = data.ownVotes.isNotEmpty;
          final canVoteNow =
              widget.repository.isEligible && pollIsOpen(poll) && !alreadyVoted;
          final counts = <String, int>{
            for (final row in data.results)
              row['option_id'].toString():
                  int.tryParse(row['vote_count']?.toString() ?? '') ?? 0,
          };
          final totalVotes =
              counts.values.fold<int>(0, (sum, value) => sum + value);

          return ListView(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 110),
            children: [
              Text(
                poll['title']?.toString() ?? 'Votação',
                style: Theme.of(context).textTheme.headlineSmall,
              ),
              if (poll['description']?.toString().trim().isNotEmpty == true) ...[
                const SizedBox(height: 10),
                Text(poll['description'].toString()),
              ],
              const SizedBox(height: 12),
              Wrap(
                spacing: 7,
                runSpacing: 6,
                children: [
                  Chip(label: Text(pollStatusLabel(effectiveStatus))),
                  Chip(
                    label: Text(
                      poll['anonymous'] == true ? 'Anónima' : 'Identificada',
                    ),
                  ),
                  Chip(
                    label: Text(
                      multiple ? 'Escolha múltipla' : 'Escolha única',
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Text('Abertura: ${pollDateLabel(poll['starts_at'])}'),
              Text(
                poll['ends_at'] == null
                    ? 'Fecho: sem data definida'
                    : 'Fecho: ${pollDateLabel(poll['ends_at'])}',
              ),
              const Divider(height: 30),
              if (status == 'draft') ...[
                const Card(
                  child: ListTile(
                    leading: Icon(Icons.edit_note_outlined),
                    title: Text('Rascunho'),
                    subtitle: Text(
                      'Revê as opções e publica quando estiver pronto.',
                    ),
                  ),
                ),
                for (final option in data.options)
                  ListTile(
                    leading: const Icon(Icons.circle_outlined, size: 18),
                    title: Text(option['label']?.toString() ?? 'Opção'),
                  ),
              ] else ...[
                Text(
                  alreadyVoted
                      ? 'O teu voto'
                      : 'Seleciona ${multiple ? 'as opções' : 'uma opção'}',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const SizedBox(height: 6),
                for (final option in data.options)
                  _VoteOption(
                    label: option['label']?.toString() ?? 'Opção',
                    selected: _selected.contains(option['id'].toString()),
                    enabled: canVoteNow,
                    multiple: multiple,
                    onTap: () {
                      if (!canVoteNow) return;
                      final id = option['id'].toString();
                      setState(() {
                        if (multiple) {
                          if (!_selected.add(id)) _selected.remove(id);
                        } else {
                          _selected
                            ..clear()
                            ..add(id);
                        }
                      });
                    },
                  ),
                if (alreadyVoted)
                  const Card(
                    child: ListTile(
                      leading: Icon(Icons.verified_outlined),
                      title: Text('Voto submetido'),
                      subtitle: Text(
                        'Por integridade da votação, o voto não pode ser editado nem apagado.',
                      ),
                    ),
                  )
                else if (!widget.repository.isEligible)
                  const Card(
                    child: ListTile(
                      leading: Icon(Icons.lock_outline),
                      title: Text('Perfil não elegível para votar'),
                    ),
                  )
                else if (!pollIsOpen(poll))
                  const Card(
                    child: ListTile(
                      leading: Icon(Icons.schedule_outlined),
                      title: Text(
                        'A votação não está aberta neste momento.',
                      ),
                    ),
                  ),
              ],
              const Divider(height: 30),
              Text(
                'Resultados',
                style: Theme.of(context).textTheme.titleMedium,
              ),
              const SizedBox(height: 8),
              if (!resultsVisible)
                const Card(
                  child: ListTile(
                    leading: Icon(Icons.visibility_off_outlined),
                    title: Text('Resultados ainda ocultos'),
                    subtitle: Text(
                      'Ficam disponíveis após o encerramento desta votação.',
                    ),
                  ),
                )
              else ...[
                Text(
                  totalVotes == 1
                      ? '1 seleção registada'
                      : '$totalVotes seleções registadas',
                ),
                const SizedBox(height: 8),
                for (final option in data.options)
                  _ResultRow(
                    label: option['label']?.toString() ?? 'Opção',
                    count: counts[option['id'].toString()] ?? 0,
                    total: totalVotes,
                  ),
              ],
            ],
          );
        },
      ),
      bottomNavigationBar: FutureBuilder<_PollDetailData>(
        future: _future,
        builder: (context, snapshot) {
          final data = snapshot.data;
          if (data == null) return const SizedBox.shrink();
          if (widget.repository.canManage && status == 'draft') {
            return SafeArea(
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Row(
                  children: [
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: () => _edit(data.options),
                        icon: const Icon(Icons.edit_outlined),
                        label: const Text('Editar'),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: FilledButton.icon(
                        onPressed: () => _setStatus('published'),
                        icon: const Icon(Icons.publish_outlined),
                        label: const Text('Publicar'),
                      ),
                    ),
                  ],
                ),
              ),
            );
          }
          final alreadyVoted = data.ownVotes.isNotEmpty;
          if (widget.repository.isEligible &&
              pollIsOpen(poll) &&
              !alreadyVoted) {
            return SafeArea(
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: FilledButton.icon(
                  onPressed:
                      _selected.isEmpty || _submitting ? null : _vote,
                  icon: _submitting
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.how_to_vote_outlined),
                  label: Text(
                    _submitting ? 'A submeter…' : 'Submeter voto',
                  ),
                ),
              ),
            );
          }
          return const SizedBox.shrink();
        },
      ),
    );
  }
}

class _PollDetailData {
  const _PollDetailData({
    required this.options,
    required this.ownVotes,
    required this.results,
  });

  final List<Map<String, dynamic>> options;
  final List<Map<String, dynamic>> ownVotes;
  final List<Map<String, dynamic>> results;
}

class _VoteOption extends StatelessWidget {
  const _VoteOption({
    required this.label,
    required this.selected,
    required this.enabled,
    required this.multiple,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final bool enabled;
  final bool multiple;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: ListTile(
        enabled: enabled,
        onTap: enabled ? onTap : null,
        leading: Icon(
          selected
              ? (multiple ? Icons.check_box : Icons.radio_button_checked)
              : (multiple
                  ? Icons.check_box_outline_blank
                  : Icons.radio_button_unchecked),
        ),
        title: Text(label),
      ),
    );
  }
}

class _ResultRow extends StatelessWidget {
  const _ResultRow({
    required this.label,
    required this.count,
    required this.total,
  });

  final String label;
  final int count;
  final int total;

  @override
  Widget build(BuildContext context) {
    final ratio = total == 0 ? 0.0 : count / total;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 7),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(child: Text(label)),
              Text('$count · ${(ratio * 100).toStringAsFixed(0)}%'),
            ],
          ),
          const SizedBox(height: 5),
          LinearProgressIndicator(value: ratio),
        ],
      ),
    );
  }
}

class _DetailError extends StatelessWidget {
  const _DetailError({required this.error, required this.onRetry});

  final Object error;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.error_outline, size: 44),
            const SizedBox(height: 10),
            Text(_friendly(error), textAlign: TextAlign.center),
            const SizedBox(height: 12),
            FilledButton.tonalIcon(
              onPressed: onRetry,
              icon: const Icon(Icons.refresh),
              label: const Text('Tentar novamente'),
            ),
          ],
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
