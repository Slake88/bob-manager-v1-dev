import 'dart:async';

import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../repositories/events_advanced_repository.dart';
import '../repositories/events_repository.dart';
import '../services/roadbook_places_service.dart';

class RoadbookStopsScreen extends StatefulWidget {
  const RoadbookStopsScreen({
    super.key,
    required this.eventId,
    required this.route,
    required this.repository,
  });

  final String eventId;
  final Map<String, dynamic> route;
  final EventsAdvancedRepository repository;

  @override
  State<RoadbookStopsScreen> createState() => _RoadbookStopsScreenState();
}

class _RoadbookStopsScreenState extends State<RoadbookStopsScreen> {
  final EventsRepository _events = EventsRepository();
  final RoadbookPlacesService _places = RoadbookPlacesService();
  late Future<List<Map<String, dynamic>>> _future;
  late Future<DateTime?> _eventStartFuture;
  bool _reordering = false;

  String get _routeId => widget.route['id'].toString();

  @override
  void initState() {
    super.initState();
    _reload();
    _eventStartFuture = _loadEventStart();
  }

  void _reload() => _future = widget.repository.listRouteStops(_routeId);

  Future<DateTime?> _loadEventStart() async {
    try {
      final rows = await _events.listEvents();
      for (final row in rows) {
        if (row['id']?.toString() == widget.eventId) {
          return DateTime.tryParse(row['starts_at']?.toString() ?? '');
        }
      }
    } catch (_) {
      // A hora continua editável; em último caso usa a data local atual.
    }
    return null;
  }

  Future<void> _refreshStops() async {
    final next = widget.repository.listRouteStops(_routeId);
    if (!mounted) return;
    setState(() {
      _future = next;
    });
    await next;
  }

  int _nextStopSequence(List<Map<String, dynamic>> current) {
    var highest = 0;
    for (final row in current) {
      final sequence =
          int.tryParse(row['sequence_no']?.toString() ?? '') ?? 0;
      if (sequence > highest) highest = sequence;
    }
    return highest + 1;
  }

  Future<void> _editStop(
    List<Map<String, dynamic>> current, {
    Map<String, dynamic>? stop,
  }) async {
    final eventStart = await _eventStartFuture;
    if (!mounted) return;

    final editing = stop != null;
    final name = TextEditingController(
      text: editing ? stop['name']?.toString() ?? '' : '',
    );
    final location = TextEditingController(
      text: editing ? stop['location']?.toString() ?? '' : '',
    );
    final notes = TextEditingController(
      text: editing ? stop['notes']?.toString() ?? '' : '',
    );
    final existingPlannedAt =
        editing ? DateTime.tryParse(stop['planned_at']?.toString() ?? '') : null;
    TimeOfDay? plannedTime = existingPlannedAt == null
        ? null
        : TimeOfDay.fromDateTime(existingPlannedAt.toLocal());
    double? latitude = _asDouble(stop?['latitude']);
    double? longitude = _asDouble(stop?['longitude']);
    bool saving = false;
    Timer? locationDebounce;
    var locationSearchVersion = 0;
    var locationSearching = false;
    var locationSelecting = false;
    String? locationSearchError;
    List<RoadbookPlaceSuggestion> locationSuggestions = const [];
    var locationSessionToken = _places.newSessionToken();

    final saved = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: Text(editing ? 'Editar paragem' : 'Nova paragem'),
          content: SizedBox(
            width: 560,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextField(
                    controller: name,
                    enabled: !saving,
                    decoration: const InputDecoration(
                      labelText: 'Nome',
                      prefixIcon: Icon(Icons.flag_outlined),
                    ),
                  ),
                  const SizedBox(height: 10),
                  TextField(
                    controller: location,
                    enabled: !saving && !locationSelecting,
                    onChanged: (value) {
                      latitude = null;
                      longitude = null;
                      locationDebounce?.cancel();
                      locationSearchVersion += 1;
                      final version = locationSearchVersion;
                      final normalized = value.trim();
                      if (normalized.length < 3) {
                        setDialogState(() {
                          locationSearching = false;
                          locationSearchError = null;
                          locationSuggestions = const [];
                        });
                        return;
                      }
                      locationDebounce = Timer(
                        const Duration(milliseconds: 450),
                        () async {
                          if (!dialogContext.mounted ||
                              version != locationSearchVersion) {
                            return;
                          }
                          setDialogState(() {
                            locationSearching = true;
                            locationSearchError = null;
                          });
                          try {
                            final suggestions = await _places.autocomplete(
                              normalized,
                              sessionToken: locationSessionToken,
                            );
                            if (!dialogContext.mounted ||
                                version != locationSearchVersion) {
                              return;
                            }
                            setDialogState(() {
                              locationSuggestions = suggestions;
                              locationSearching = false;
                            });
                          } catch (error) {
                            if (!dialogContext.mounted ||
                                version != locationSearchVersion) {
                              return;
                            }
                            setDialogState(() {
                              locationSuggestions = const [];
                              locationSearching = false;
                              locationSearchError = _friendly(error);
                            });
                          }
                        },
                      );
                    },
                    decoration: InputDecoration(
                      labelText: 'Local',
                      hintText: 'Escreve ou pesquisa um local',
                      prefixIcon: const Icon(Icons.location_on_outlined),
                      suffixIcon: IconButton(
                        tooltip: 'Pesquisar no Google Maps',
                        onPressed: saving || locationSelecting
                            ? null
                            : () async {
                                locationDebounce?.cancel();
                                locationSearchVersion += 1;
                                final selected = await showDialog<_PlaceSelection>(
                                  context: dialogContext,
                                  builder: (_) => _RoadbookPlacePickerDialog(
                                    service: _places,
                                    initialQuery: location.text,
                                  ),
                                );
                                if (selected == null ||
                                    !dialogContext.mounted) {
                                  return;
                                }
                                setDialogState(() {
                                  location.value = TextEditingValue(
                                    text: selected.label,
                                    selection: TextSelection.collapsed(
                                      offset: selected.label.length,
                                    ),
                                  );
                                  latitude = selected.latitude;
                                  longitude = selected.longitude;
                                  locationSuggestions = const [];
                                  locationSearchError = null;
                                  locationSearching = false;
                                  locationSessionToken =
                                      _places.newSessionToken();
                                });
                              },
                        icon: const Icon(Icons.search),
                      ),
                    ),
                  ),
                  if (locationSearching)
                    const Padding(
                      padding: EdgeInsets.only(top: 6),
                      child: LinearProgressIndicator(),
                    ),
                  if (locationSearchError != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 6),
                      child: Align(
                        alignment: Alignment.centerLeft,
                        child: Text(
                          locationSearchError!,
                          style: TextStyle(
                            color: Theme.of(context).colorScheme.error,
                            fontSize: 12,
                          ),
                        ),
                      ),
                    ),
                  if (locationSuggestions.isNotEmpty) ...[
                    const SizedBox(height: 6),
                    ConstrainedBox(
                      constraints: const BoxConstraints(maxHeight: 220),
                      child: Card(
                        margin: EdgeInsets.zero,
                        clipBehavior: Clip.antiAlias,
                        child: ListView.separated(
                          shrinkWrap: true,
                          itemCount: locationSuggestions.length,
                          separatorBuilder: (_, __) =>
                              const Divider(height: 1),
                          itemBuilder: (context, index) {
                            final suggestion = locationSuggestions[index];
                            return ListTile(
                              dense: true,
                              leading:
                                  const Icon(Icons.location_on_outlined),
                              title: Text(suggestion.mainText),
                              subtitle: suggestion.secondaryText.isEmpty
                                  ? null
                                  : Text(suggestion.secondaryText),
                              enabled: !locationSelecting,
                              onTap: locationSelecting
                                  ? null
                                  : () async {
                                      locationDebounce?.cancel();
                                      locationSearchVersion += 1;
                                      setDialogState(() {
                                        locationSelecting = true;
                                        locationSearching = false;
                                        locationSearchError = null;
                                      });
                                      try {
                                        final details = await _places.details(
                                          suggestion.placeId,
                                          sessionToken: locationSessionToken,
                                        );
                                        if (!dialogContext.mounted) return;
                                        final label = suggestion.text.isNotEmpty
                                            ? suggestion.text
                                            : details.formattedAddress;
                                        setDialogState(() {
                                          location.value = TextEditingValue(
                                            text: label,
                                            selection: TextSelection.collapsed(
                                              offset: label.length,
                                            ),
                                          );
                                          latitude = details.latitude;
                                          longitude = details.longitude;
                                          locationSuggestions = const [];
                                          locationSelecting = false;
                                          locationSearchError = null;
                                          locationSessionToken =
                                              _places.newSessionToken();
                                        });
                                      } catch (error) {
                                        if (!dialogContext.mounted) return;
                                        setDialogState(() {
                                          locationSelecting = false;
                                          locationSearchError =
                                              _friendly(error);
                                        });
                                      }
                                    },
                            );
                          },
                        ),
                      ),
                    ),
                    const Padding(
                      padding: EdgeInsets.only(top: 4),
                      child: Align(
                        alignment: Alignment.centerRight,
                        child: Text(
                          'Resultados fornecidos pelo Google',
                          style: TextStyle(fontSize: 11),
                        ),
                      ),
                    ),
                  ],
                  const SizedBox(height: 10),
                  DecoratedBox(
                    decoration: BoxDecoration(
                      border: Border.all(
                        color: Theme.of(context).colorScheme.outlineVariant,
                      ),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: ListTile(
                      leading: const Icon(Icons.schedule_outlined),
                      title: const Text('Hora prevista'),
                      subtitle: Text(
                        plannedTime == null
                            ? 'Por definir'
                            : _timeLabel(plannedTime!),
                      ),
                      trailing: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          if (plannedTime != null)
                            IconButton(
                              tooltip: 'Limpar hora',
                              onPressed: saving
                                  ? null
                                  : () => setDialogState(
                                        () => plannedTime = null,
                                      ),
                              icon: const Icon(Icons.clear),
                            ),
                          const Icon(Icons.edit_outlined),
                        ],
                      ),
                      onTap: saving
                          ? null
                          : () async {
                              final picked = await showTimePicker(
                                context: dialogContext,
                                initialTime: plannedTime ??
                                    TimeOfDay.fromDateTime(
                                      (eventStart ?? DateTime.now()).toLocal(),
                                    ),
                              );
                              if (picked != null && dialogContext.mounted) {
                                setDialogState(() => plannedTime = picked);
                              }
                            },
                    ),
                  ),
                  const SizedBox(height: 10),
                  TextField(
                    controller: notes,
                    enabled: !saving,
                    minLines: 2,
                    maxLines: 5,
                    decoration: const InputDecoration(
                      labelText: 'Notas',
                      hintText: 'Informação útil para esta paragem',
                      prefixIcon: Icon(Icons.notes_outlined),
                      alignLabelWithHint: true,
                    ),
                  ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: saving
                  ? null
                  : () => Navigator.pop(dialogContext, false),
              child: const Text('Cancelar'),
            ),
            FilledButton(
              onPressed: saving
                  ? null
                  : () async {
                      if (name.text.trim().isEmpty) return;
                      setDialogState(() => saving = true);
                      try {
                        await widget.repository.saveRouteStop(
                          eventId: widget.eventId,
                          routeId: _routeId,
                          id: editing ? stop['id']?.toString() : null,
                          values: {
                            'sequence_no': editing
                                ? stop['sequence_no'] ??
                                    current.indexOf(stop) + 1
                                : _nextStopSequence(current),
                            'name': name.text.trim(),
                            'location': _nullText(location.text),
                            'planned_at': _plannedAt(
                              plannedTime,
                              eventStart: eventStart,
                            ),
                            'latitude': latitude,
                            'longitude': longitude,
                            'notes': _nullText(notes.text),
                          },
                        );
                        if (dialogContext.mounted) {
                          Navigator.pop(dialogContext, true);
                        }
                      } catch (error) {
                        if (dialogContext.mounted) {
                          _snack(dialogContext, _friendly(error));
                          setDialogState(() => saving = false);
                        }
                      }
                    },
              child: Text(saving ? 'A guardar...' : 'Guardar'),
            ),
          ],
        ),
      ),
    );
    locationDebounce?.cancel();
    name.dispose();
    location.dispose();
    notes.dispose();
    if (saved == true && mounted) {
      try {
        await _refreshStops();
        if (mounted) {
          _snack(
            context,
            editing ? 'Paragem atualizada.' : 'Paragem adicionada.',
          );
        }
      } catch (error) {
        if (mounted) _snack(context, _friendly(error));
      }
    }
  }

  Future<void> _deleteStop(Map<String, dynamic> stop) async {
    final stopId = stop['id']?.toString().trim() ?? '';
    if (stopId.isEmpty) {
      _snack(context, 'Não foi possível identificar a paragem.');
      return;
    }
    final stopName = stop['name']?.toString().trim() ?? '';
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Eliminar paragem'),
        content: Text(
          stopName.isEmpty
              ? 'Queres eliminar esta paragem? Esta ação não pode ser anulada.'
              : 'Queres eliminar a paragem "$stopName"? Esta ação não pode ser anulada.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(dialogContext).colorScheme.error,
              foregroundColor: Theme.of(dialogContext).colorScheme.onError,
            ),
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Eliminar'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    try {
      await widget.repository.deleteRouteStop(
        eventId: widget.eventId,
        routeId: _routeId,
        stopId: stopId,
      );
      await _refreshStops();
      if (mounted) _snack(context, 'Paragem eliminada.');
    } catch (error) {
      if (mounted) _snack(context, _friendly(error));
    }
  }

  Future<void> _reorderStops(
    List<Map<String, dynamic>> current,
    int oldIndex,
    int newIndex,
  ) async {
    if (_reordering || oldIndex == newIndex) return;

    final reordered = List<Map<String, dynamic>>.from(current);
    final moved = reordered.removeAt(oldIndex);
    reordered.insert(newIndex, moved);
    for (var index = 0; index < reordered.length; index++) {
      reordered[index]['sequence_no'] = index + 1;
    }

    setState(() {
      _reordering = true;
      current
        ..clear()
        ..addAll(reordered);
    });

    try {
      await widget.repository.reorderRouteStops(
        eventId: widget.eventId,
        routeId: _routeId,
        stopIds: reordered.map((row) => row['id'].toString()).toList(),
      );
      await _refreshStops();
      if (mounted) _snack(context, 'Ordem das paragens atualizada.');
    } catch (error) {
      try {
        await _refreshStops();
      } catch (_) {
        // Mantém a mensagem do erro original de reordenação.
      }
      if (mounted) _snack(context, _friendly(error));
    } finally {
      if (mounted) {
        setState(() {
          _reordering = false;
        });
      }
    }
  }

  Future<void> _openMaps(Map<String, dynamic> stop) async {
    final location = stop['location']?.toString().trim() ?? '';
    final latitude = _asDouble(stop['latitude']);
    final longitude = _asDouble(stop['longitude']);
    final query = latitude != null && longitude != null
        ? '$latitude,$longitude'
        : location;
    if (query.isEmpty) {
      _snack(context, 'Esta paragem ainda não tem um local definido.');
      return;
    }
    final uri = Uri.https(
      'www.google.com',
      '/maps/search/',
      {'api': '1', 'query': query},
    );
    try {
      final opened = await launchUrl(uri);
      if (!opened && mounted) {
        _snack(context, 'Não foi possível abrir o Google Maps.');
      }
    } catch (_) {
      if (mounted) _snack(context, 'Não foi possível abrir o Google Maps.');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.route['name']?.toString() ?? 'Roadbook'),
      ),
      body: FutureBuilder<List<Map<String, dynamic>>>(
        future: _future,
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return Center(child: Text(_friendly(snapshot.error!)));
          }
          if (!snapshot.hasData) {
            return const Center(child: CircularProgressIndicator());
          }
          final rows = snapshot.data!;
          final canManage = widget.repository.canManageRoadbook;
          return Column(
            children: [
              Expanded(
                child: rows.isEmpty
                    ? ListView(
                        padding: const EdgeInsets.all(12),
                        children: const [
                          Card(child: ListTile(title: Text('Sem paragens.'))),
                        ],
                      )
                    : ReorderableListView.builder(
                        padding: const EdgeInsets.fromLTRB(12, 12, 12, 12),
                        buildDefaultDragHandles: false,
                        itemCount: rows.length,
                        onReorderItem: canManage
                            ? (oldIndex, newIndex) async {
                                await _reorderStops(rows, oldIndex, newIndex);
                              }
                            : (_, __) {},
                        itemBuilder: (context, index) {
                          final row = rows[index];
                          final location =
                              row['location']?.toString().trim() ?? '';
                          final plannedAt = DateTime.tryParse(
                            row['planned_at']?.toString() ?? '',
                          );
                          final notes = row['notes']?.toString().trim() ?? '';
                          return Card(
                            key: ValueKey(
                              'route-stop-${row['id']?.toString() ?? index}',
                            ),
                            child: Padding(
                              padding: const EdgeInsets.fromLTRB(12, 12, 4, 12),
                              child: Row(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  CircleAvatar(
                                    child: Text('${row['sequence_no'] ?? ''}'),
                                  ),
                                  const SizedBox(width: 12),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          row['name']?.toString() ?? 'Paragem',
                                          style: Theme.of(context)
                                              .textTheme
                                              .titleMedium,
                                        ),
                                        const SizedBox(height: 6),
                                        _StopInfoRow(
                                          icon: Icons.location_on_outlined,
                                          text: location.isEmpty
                                              ? 'Local por definir'
                                              : location,
                                        ),
                                        if (plannedAt != null) ...[
                                          const SizedBox(height: 4),
                                          _StopInfoRow(
                                            icon: Icons.schedule_outlined,
                                            text: _timeLabel(
                                              TimeOfDay.fromDateTime(
                                                plannedAt.toLocal(),
                                              ),
                                            ),
                                          ),
                                        ],
                                        if (notes.isNotEmpty) ...[
                                          const SizedBox(height: 4),
                                          _StopInfoRow(
                                            icon: Icons.notes_outlined,
                                            text: notes,
                                          ),
                                        ],
                                        if (location.isNotEmpty) ...[
                                          const SizedBox(height: 2),
                                          TextButton.icon(
                                            onPressed: _reordering
                                                ? null
                                                : () => _openMaps(row),
                                            icon: const Icon(Icons.map_outlined),
                                            label: const Text(
                                              'Abrir no Google Maps',
                                            ),
                                          ),
                                        ],
                                      ],
                                    ),
                                  ),
                                  if (canManage)
                                    Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        IconButton(
                                          tooltip: 'Editar paragem',
                                          onPressed: _reordering
                                              ? null
                                              : () => _editStop(
                                                    rows,
                                                    stop: row,
                                                  ),
                                          icon: const Icon(
                                            Icons.edit_outlined,
                                          ),
                                        ),
                                        IconButton(
                                          tooltip: 'Eliminar paragem',
                                          color: Theme.of(context)
                                              .colorScheme
                                              .error,
                                          onPressed: _reordering
                                              ? null
                                              : () => _deleteStop(row),
                                          icon: const Icon(
                                            Icons.delete_outline,
                                          ),
                                        ),
                                        Tooltip(
                                          message: 'Arrastar para reordenar',
                                          child: ReorderableDragStartListener(
                                            index: index,
                                            enabled: !_reordering,
                                            child: const Padding(
                                              padding: EdgeInsets.all(12),
                                              child: Icon(Icons.drag_handle),
                                            ),
                                          ),
                                        ),
                                      ],
                                    ),
                                ],
                              ),
                            ),
                          );
                        },
                      ),
              ),
              if (canManage)
                SafeArea(
                  top: false,
                  minimum: const EdgeInsets.fromLTRB(12, 8, 12, 12),
                  child: SizedBox(
                    width: double.infinity,
                    child: FilledButton.icon(
                      onPressed: _reordering ? null : () => _editStop(rows),
                      icon: const Icon(Icons.add_location_alt_outlined),
                      label: const Text('Adicionar paragem'),
                    ),
                  ),
                ),
            ],
          );
        },
      ),
    );
  }
}

class _StopInfoRow extends StatelessWidget {
  const _StopInfoRow({required this.icon, required this.text});

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(
          icon,
          size: 18,
          color: Theme.of(context).colorScheme.onSurfaceVariant,
        ),
        const SizedBox(width: 6),
        Expanded(
          child: Text(
            text,
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
          ),
        ),
      ],
    );
  }
}

class _PlaceSelection {
  const _PlaceSelection({
    required this.label,
    required this.latitude,
    required this.longitude,
  });

  final String label;
  final double latitude;
  final double longitude;
}

class _RoadbookPlacePickerDialog extends StatefulWidget {
  const _RoadbookPlacePickerDialog({
    required this.service,
    required this.initialQuery,
  });

  final RoadbookPlacesService service;
  final String initialQuery;

  @override
  State<_RoadbookPlacePickerDialog> createState() =>
      _RoadbookPlacePickerDialogState();
}

class _RoadbookPlacePickerDialogState
    extends State<_RoadbookPlacePickerDialog> {
  late final TextEditingController _query;
  late final String _sessionToken;
  Timer? _debounce;
  List<RoadbookPlaceSuggestion> _suggestions = const [];
  bool _loading = false;
  bool _selecting = false;
  String? _error;
  int _searchVersion = 0;

  @override
  void initState() {
    super.initState();
    _query = TextEditingController(text: widget.initialQuery);
    _sessionToken = widget.service.newSessionToken();
    if (_query.text.trim().length >= 3) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) unawaited(_search(_query.text));
      });
    }
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _query.dispose();
    super.dispose();
  }

  void _changed(String value) {
    _debounce?.cancel();
    _searchVersion += 1;
    final version = _searchVersion;
    final normalized = value.trim();
    if (normalized.length < 3) {
      setState(() {
        _loading = false;
        _error = null;
        _suggestions = const [];
      });
      return;
    }
    _debounce = Timer(const Duration(milliseconds: 450), () {
      if (version == _searchVersion) unawaited(_search(normalized));
    });
  }

  Future<void> _search(String value) async {
    final normalized = value.trim();
    if (normalized.length < 3 || !mounted) return;
    final version = ++_searchVersion;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final suggestions = await widget.service.autocomplete(
        normalized,
        sessionToken: _sessionToken,
      );
      if (!mounted || version != _searchVersion) return;
      setState(() {
        _suggestions = suggestions;
        _loading = false;
      });
    } catch (error) {
      if (!mounted || version != _searchVersion) return;
      setState(() {
        _suggestions = const [];
        _loading = false;
        _error = _friendly(error);
      });
    }
  }

  Future<void> _select(RoadbookPlaceSuggestion suggestion) async {
    if (_selecting) return;
    setState(() {
      _selecting = true;
      _error = null;
    });
    try {
      final details = await widget.service.details(
        suggestion.placeId,
        sessionToken: _sessionToken,
      );
      if (!mounted) return;
      Navigator.of(context).pop(
        _PlaceSelection(
          label: suggestion.text.isNotEmpty
              ? suggestion.text
              : details.formattedAddress,
          latitude: details.latitude,
          longitude: details.longitude,
        ),
      );
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _selecting = false;
        _error = _friendly(error);
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Pesquisar local'),
      content: SizedBox(
        width: 600,
        height: 430,
        child: Column(
          children: [
            TextField(
              controller: _query,
              autofocus: true,
              enabled: !_selecting,
              onChanged: _changed,
              decoration: const InputDecoration(
                labelText: 'Local',
                hintText: 'Ex.: Praça do Giraldo, Évora',
                prefixIcon: Icon(Icons.location_on_outlined),
                suffixIcon: Icon(Icons.search),
              ),
            ),
            const SizedBox(height: 10),
            if (_loading || _selecting) const LinearProgressIndicator(),
            if (_error != null)
              Padding(
                padding: const EdgeInsets.only(top: 10),
                child: Text(
                  _error!,
                  style: TextStyle(
                    color: Theme.of(context).colorScheme.error,
                  ),
                ),
              ),
            const SizedBox(height: 4),
            Expanded(
              child: _query.text.trim().length < 3
                  ? const Center(
                      child: Text('Escreve pelo menos 3 caracteres.'),
                    )
                  : _suggestions.isEmpty && !_loading && _error == null
                      ? const Center(child: Text('Sem resultados.'))
                      : ListView.separated(
                          itemCount: _suggestions.length,
                          separatorBuilder: (_, __) => const Divider(height: 1),
                          itemBuilder: (context, index) {
                            final suggestion = _suggestions[index];
                            return ListTile(
                              leading:
                                  const Icon(Icons.location_on_outlined),
                              title: Text(suggestion.mainText),
                              subtitle: suggestion.secondaryText.isEmpty
                                  ? null
                                  : Text(suggestion.secondaryText),
                              enabled: !_selecting,
                              onTap: _selecting
                                  ? null
                                  : () => _select(suggestion),
                            );
                          },
                        ),
            ),
            const Divider(height: 1),
            const Padding(
              padding: EdgeInsets.only(top: 8),
              child: Text(
                'Resultados fornecidos pelo Google',
                style: TextStyle(fontSize: 12),
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: _selecting ? null : () => Navigator.pop(context),
          child: const Text('Cancelar'),
        ),
      ],
    );
  }
}

String? _plannedAt(TimeOfDay? time, {required DateTime? eventStart}) {
  if (time == null) return null;
  final base = (eventStart ?? DateTime.now()).toLocal();
  final local = DateTime(
    base.year,
    base.month,
    base.day,
    time.hour,
    time.minute,
  );
  return local.toUtc().toIso8601String();
}

String _timeLabel(TimeOfDay time) {
  return '${time.hour.toString().padLeft(2, '0')}:${time.minute.toString().padLeft(2, '0')}';
}

double? _asDouble(Object? value) {
  if (value is num) return value.toDouble();
  return double.tryParse(value?.toString() ?? '');
}

String? _nullText(String value) {
  final text = value.trim();
  return text.isEmpty ? null : text;
}

String _friendly(Object error) {
  if (error is StateError) return error.message.toString();
  if (error is ArgumentError) {
    return error.message?.toString() ?? 'Dados inválidos.';
  }
  final text = error.toString();
  return text.startsWith('Exception: ') ? text.substring(11) : text;
}

void _snack(BuildContext context, String text) {
  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(content: Text(text)));
}
