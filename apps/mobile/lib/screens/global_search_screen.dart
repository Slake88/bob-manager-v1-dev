import 'dart:async';

import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../core/app_session.dart';
import '../core/global_search.dart';
import '../repositories/document_repository.dart';
import '../repositories/global_search_repository.dart';
import '../repositories/member_repository.dart';
import 'member_detail_screen.dart';

class GlobalSearchScreen extends StatefulWidget {
  const GlobalSearchScreen({super.key});

  @override
  State<GlobalSearchScreen> createState() => _GlobalSearchScreenState();
}

class _GlobalSearchScreenState extends State<GlobalSearchScreen> {
  final TextEditingController _controller = TextEditingController();
  final GlobalSearchRepository _repository = GlobalSearchRepository();
  final MemberRepository _members = MemberRepository();
  final DocumentRepository _documents = DocumentRepository();

  Timer? _debounce;
  List<GlobalSearchResult> _results = const [];
  bool _loading = false;
  bool _opening = false;
  String? _error;

  List<GlobalSearchType> get _visibleTypes =>
      GlobalSearchPolicy.visibleTypes(AppSession.instance.can);

  @override
  void dispose() {
    _debounce?.cancel();
    _controller.dispose();
    super.dispose();
  }

  void _onChanged(String raw) {
    _debounce?.cancel();
    final query = raw.trim();
    if (query.length < 2) {
      setState(() {
        _results = const [];
        _loading = false;
        _error = null;
      });
      return;
    }

    setState(() {
      _loading = true;
      _error = null;
    });
    _debounce = Timer(
      const Duration(milliseconds: 350),
      () => _search(query),
    );
  }

  Future<void> _search(String query) async {
    try {
      final results = await _repository.search(query);
      if (!mounted || _controller.text.trim() != query) return;
      setState(() {
        _results = results;
        _loading = false;
        _error = null;
      });
    } catch (_) {
      if (!mounted || _controller.text.trim() != query) return;
      setState(() {
        _results = const [];
        _loading = false;
        _error = 'Não foi possível concluir a pesquisa.';
      });
    }
  }

  Future<void> _openResult(GlobalSearchResult result) async {
    if (_opening) return;
    setState(() => _opening = true);
    try {
      switch (result.type) {
        case GlobalSearchType.member:
        case GlobalSearchType.motorcycle:
          await _openMember(result);
          break;
        case GlobalSearchType.document:
          await _openDocument(result);
          break;
        case GlobalSearchType.product:
        case GlobalSearchType.event:
          if (mounted) Navigator.pop(context, result.moduleCode);
          break;
      }
    } catch (_) {
      _message('Não foi possível abrir este resultado.');
    } finally {
      if (mounted) setState(() => _opening = false);
    }
  }

  Future<void> _openMember(GlobalSearchResult result) async {
    final memberId = result.type == GlobalSearchType.motorcycle
        ? result.parentId
        : result.entityId;
    if (memberId == null || memberId.isEmpty) {
      throw StateError('Membro associado em falta.');
    }
    final member = await _members.getMember(memberId);
    if (member == null) throw StateError('Membro não encontrado.');
    if (!mounted) return;
    await Navigator.of(context).push<void>(
      MaterialPageRoute(
        builder: (_) => MemberDetailScreen(member: member),
      ),
    );
  }

  Future<void> _openDocument(GlobalSearchResult result) async {
    final rows = await _documents.listDocuments();
    Map<String, dynamic>? document;
    for (final row in rows) {
      if (row['id']?.toString() == result.entityId) {
        document = row;
        break;
      }
    }
    if (document == null) throw StateError('Documento não encontrado.');

    final hasFile = document['storage_path']?.toString().isNotEmpty == true;
    if (!hasFile) {
      if (mounted) Navigator.pop(context, 'documents');
      return;
    }

    final url = await _documents.signedUrl(document);
    final launched = await launchUrl(
      Uri.parse(url),
      mode: LaunchMode.externalApplication,
    );
    if (!launched) throw StateError('Não foi possível abrir o documento.');
  }

  void _message(String text) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
  }

  void _clear() {
    _debounce?.cancel();
    _controller.clear();
    setState(() {
      _results = const [];
      _loading = false;
      _error = null;
    });
  }

  @override
  Widget build(BuildContext context) {
    final query = _controller.text.trim();
    final visibleTypes = _visibleTypes;

    return Scaffold(
      appBar: AppBar(title: const Text('Pesquisa Global')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 96),
        children: [
          TextField(
            controller: _controller,
            autofocus: true,
            textInputAction: TextInputAction.search,
            onChanged: _onChanged,
            decoration: InputDecoration(
              labelText: 'Pesquisar em todo o clube',
              hintText: 'Nome, alcunha, matrícula, documento, produto ou evento',
              prefixIcon: const Icon(Icons.search),
              suffixIcon: query.isEmpty
                  ? null
                  : IconButton(
                      tooltip: 'Limpar',
                      onPressed: _clear,
                      icon: const Icon(Icons.close),
                    ),
            ),
          ),
          const SizedBox(height: 12),
          if (visibleTypes.isNotEmpty)
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: visibleTypes
                  .map((type) => Chip(label: Text(type.label)))
                  .toList(),
            ),
          const SizedBox(height: 12),
          if (_opening || _loading) const LinearProgressIndicator(),
          if (query.length < 2)
            const _SearchHint()
          else if (_error != null)
            Card(
              child: ListTile(
                leading: const Icon(Icons.error_outline),
                title: Text(_error!),
                trailing: TextButton(
                  onPressed: () => _search(query),
                  child: const Text('Tentar novamente'),
                ),
              ),
            )
          else if (!_loading && _results.isEmpty)
            const Card(
              child: ListTile(
                leading: Icon(Icons.search_off),
                title: Text('Sem resultados'),
                subtitle: Text(
                  'Não existem resultados visíveis para esta pesquisa e para as tuas permissões.',
                ),
              ),
            )
          else
            ..._sections(),
        ],
      ),
    );
  }

  List<Widget> _sections() {
    final widgets = <Widget>[];
    for (final type in GlobalSearchType.values) {
      final rows = _results.where((row) => row.type == type).toList();
      if (rows.isEmpty) continue;
      widgets
        ..add(const SizedBox(height: 10))
        ..add(
          Text(
            '${type.label} · ${rows.length}',
            style: Theme.of(context)
                .textTheme
                .titleMedium
                ?.copyWith(fontWeight: FontWeight.w800),
          ),
        )
        ..add(const SizedBox(height: 4))
        ..addAll(rows.map(_resultCard));
    }
    return widgets;
  }

  Widget _resultCard(GlobalSearchResult result) {
    return Card(
      child: ListTile(
        leading: CircleAvatar(child: Icon(_icon(result.type))),
        title: Text(result.title),
        subtitle: Text(
          [
            if (result.subtitle.isNotEmpty) result.subtitle,
            if (result.detail?.isNotEmpty == true) result.detail!,
          ].join('\n'),
          maxLines: 3,
          overflow: TextOverflow.ellipsis,
        ),
        trailing: const Icon(Icons.chevron_right),
        onTap: _opening ? null : () => _openResult(result),
      ),
    );
  }

  IconData _icon(GlobalSearchType type) => switch (type) {
        GlobalSearchType.member => Icons.person_outline,
        GlobalSearchType.motorcycle => Icons.two_wheeler,
        GlobalSearchType.document => Icons.description_outlined,
        GlobalSearchType.product => Icons.inventory_2_outlined,
        GlobalSearchType.event => Icons.event_outlined,
      };
}

class _SearchHint extends StatelessWidget {
  const _SearchHint();

  @override
  Widget build(BuildContext context) {
    return const Card(
      child: ListTile(
        leading: Icon(Icons.manage_search_outlined),
        title: Text('Escreve pelo menos 2 caracteres'),
        subtitle: Text(
          'A pesquisa ignora acentos, espaços e hífens. Por exemplo, uma matrícula pode ser procurada com ou sem separadores.',
        ),
      ),
    );
  }
}
