import 'package:flutter/material.dart';

import '../repositories/polls_repository.dart';
import 'poll_detail_screen.dart';
import 'poll_editor_screen.dart';

class PollsScreen extends StatefulWidget {
  const PollsScreen({super.key});

  @override
  State<PollsScreen> createState() => _PollsScreenState();
}

class _PollsScreenState extends State<PollsScreen> {
  final PollsRepository _repository = PollsRepository();
  late Future<List<Map<String, dynamic>>> _future;

  @override
  void initState() {
    super.initState();
    _reload();
  }

  void _reload() => _future = _repository.listPolls();

  void _refresh() {
    if (!mounted) return;
    setState(_reload);
  }

  Future<void> _create() async {
    final changed = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) => PollEditorScreen(repository: _repository),
      ),
    );
    if (changed == true) _refresh();
  }

  Future<void> _open(Map<String, dynamic> poll) async {
    final changed = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) => PollDetailScreen(
          repository: _repository,
          poll: poll,
        ),
      ),
    );
    if (changed == true) _refresh();
  }

  @override
  Widget build(BuildContext context) {
    if (!_repository.canView) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(24),
          child: Text('Sem permissão para consultar Comunicação.'),
        ),
      );
    }

    return DefaultTabController(
      length: 2,
      child: Scaffold(
        body: Column(
          children: [
            const Material(
              child: TabBar(
                tabs: [
                  Tab(icon: Icon(Icons.how_to_vote_outlined), text: 'Votações'),
                  Tab(icon: Icon(Icons.bar_chart_outlined), text: 'Resultados'),
                ],
              ),
            ),
            Expanded(
              child: FutureBuilder<List<Map<String, dynamic>>>(
                future: _future,
                builder: (context, snapshot) {
                  if (snapshot.hasError) {
                    return _PollError(error: snapshot.error!, onRetry: _refresh);
                  }
                  if (!snapshot.hasData) {
                    return const Center(child: CircularProgressIndicator());
                  }
                  final polls = snapshot.data!;
                  final resultPolls = polls
                      .where((poll) => pollResultsVisible(
                            poll,
                            canManage: _repository.canManage,
                          ))
                      .toList();
                  return TabBarView(
                    children: [
                      _PollList(
                        polls: polls,
                        emptyText: _repository.isEligible
                            ? 'Ainda não existem votações ou inquéritos.'
                            : 'Não existem votações disponíveis para o teu perfil.',
                        onOpen: _open,
                        onRefresh: () async {
                          _refresh();
                          await _future;
                        },
                      ),
                      _PollList(
                        polls: resultPolls,
                        emptyText: 'Ainda não existem resultados disponíveis.',
                        resultsMode: true,
                        onOpen: _open,
                        onRefresh: () async {
                          _refresh();
                          await _future;
                        },
                      ),
                    ],
                  );
                },
              ),
            ),
          ],
        ),
        floatingActionButton: _repository.canManage
            ? FloatingActionButton.extended(
                onPressed: _create,
                icon: const Icon(Icons.add),
                label: const Text('Nova votação'),
              )
            : null,
      ),
    );
  }
}

class _PollList extends StatelessWidget {
  const _PollList({
    required this.polls,
    required this.emptyText,
    required this.onOpen,
    required this.onRefresh,
    this.resultsMode = false,
  });

  final List<Map<String, dynamic>> polls;
  final String emptyText;
  final ValueChanged<Map<String, dynamic>> onOpen;
  final Future<void> Function() onRefresh;
  final bool resultsMode;

  @override
  Widget build(BuildContext context) {
    return RefreshIndicator(
      onRefresh: onRefresh,
      child: polls.isEmpty
          ? ListView(
              padding: const EdgeInsets.all(24),
              children: [
                const SizedBox(height: 80),
                Icon(
                  resultsMode ? Icons.bar_chart_outlined : Icons.ballot_outlined,
                  size: 54,
                ),
                const SizedBox(height: 12),
                Center(child: Text(emptyText, textAlign: TextAlign.center)),
              ],
            )
          : ListView.builder(
              padding: const EdgeInsets.fromLTRB(12, 12, 12, 96),
              itemCount: polls.length,
              itemBuilder: (context, index) {
                final poll = polls[index];
                final effectiveStatus = pollEffectiveStatus(poll);
                final starts = pollDateLabel(poll['starts_at']);
                final ends = poll['ends_at'] == null
                    ? 'Sem data de fecho'
                    : 'Fecha ${pollDateLabel(poll['ends_at'])}';
                return Card(
                  child: InkWell(
                    borderRadius: BorderRadius.circular(12),
                    onTap: () => onOpen(poll),
                    child: Padding(
                      padding: const EdgeInsets.all(14),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              CircleAvatar(
                                child: Icon(
                                  poll['poll_type'] == 'survey'
                                      ? Icons.fact_check_outlined
                                      : Icons.how_to_vote_outlined,
                                ),
                              ),
                              const SizedBox(width: 10),
                              Expanded(
                                child: Text(
                                  poll['title']?.toString() ?? 'Votação',
                                  style: Theme.of(context).textTheme.titleMedium,
                                ),
                              ),
                              const Icon(Icons.chevron_right),
                            ],
                          ),
                          if (poll['description']?.toString().trim().isNotEmpty == true) ...[
                            const SizedBox(height: 8),
                            Text(
                              poll['description'].toString(),
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ],
                          const SizedBox(height: 10),
                          Wrap(
                            spacing: 7,
                            runSpacing: 6,
                            children: [
                              Chip(label: Text(pollTypeLabel(poll['poll_type']))),
                              Chip(label: Text(pollStatusLabel(effectiveStatus))),
                              Chip(
                                label: Text(
                                  poll['anonymous'] == true ? 'Anónima' : 'Identificada',
                                ),
                              ),
                              if (poll['multiple_choice'] == true)
                                const Chip(label: Text('Escolha múltipla')),
                            ],
                          ),
                          const SizedBox(height: 8),
                          Text('Abre $starts · $ends'),
                        ],
                      ),
                    ),
                  ),
                );
              },
            ),
    );
  }
}

class _PollError extends StatelessWidget {
  const _PollError({required this.error, required this.onRetry});

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
