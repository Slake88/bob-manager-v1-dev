import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:uuid/uuid.dart';

import '../core/app_session.dart';

class RoadbookPlaceSuggestion {
  const RoadbookPlaceSuggestion({
    required this.placeId,
    required this.text,
    required this.mainText,
    required this.secondaryText,
  });

  final String placeId;
  final String text;
  final String mainText;
  final String secondaryText;

  factory RoadbookPlaceSuggestion.fromMap(Map<String, dynamic> map) {
    return RoadbookPlaceSuggestion(
      placeId: map['place_id']?.toString() ?? '',
      text: map['text']?.toString() ?? '',
      mainText: map['main_text']?.toString() ?? '',
      secondaryText: map['secondary_text']?.toString() ?? '',
    );
  }
}

class RoadbookPlaceDetails {
  const RoadbookPlaceDetails({
    required this.placeId,
    required this.formattedAddress,
    required this.latitude,
    required this.longitude,
  });

  final String placeId;
  final String formattedAddress;
  final double latitude;
  final double longitude;

  factory RoadbookPlaceDetails.fromMap(Map<String, dynamic> map) {
    final latitude = double.tryParse(map['latitude']?.toString() ?? '');
    final longitude = double.tryParse(map['longitude']?.toString() ?? '');
    if (latitude == null || longitude == null) {
      throw const FormatException(
        'O local selecionado não devolveu coordenadas válidas.',
      );
    }
    return RoadbookPlaceDetails(
      placeId: map['place_id']?.toString() ?? '',
      formattedAddress: map['formatted_address']?.toString() ?? '',
      latitude: latitude,
      longitude: longitude,
    );
  }
}

class RoadbookPlacesService {
  RoadbookPlacesService({SupabaseClient? client}) : _client = client;

  final SupabaseClient? _client;
  static const Uuid _uuid = Uuid();

  SupabaseClient get _supabase => _client ?? Supabase.instance.client;

  String newSessionToken() => _uuid.v4();

  Future<List<RoadbookPlaceSuggestion>> autocomplete(
    String input, {
    required String sessionToken,
  }) async {
    final normalized = input.trim();
    if (normalized.length < 3) return const [];
    try {
      final result = await _supabase.functions.invoke(
        'roadbook-places',
        body: {
          'club_id': AppSession.instance.clubId,
          'action': 'autocomplete',
          'input': normalized,
          'session_token': sessionToken,
        },
      );
      final data = _map(result.data);
      final rows = data['suggestions'];
      if (rows is! List) return const [];
      return rows
          .whereType<Map>()
          .map((row) => RoadbookPlaceSuggestion.fromMap(
                Map<String, dynamic>.from(row),
              ))
          .where((row) => row.placeId.isNotEmpty && row.text.isNotEmpty)
          .toList();
    } on FunctionException catch (error) {
      throw StateError(_friendlyFunctionError(error));
    }
  }

  Future<RoadbookPlaceDetails> details(
    String placeId, {
    required String sessionToken,
  }) async {
    final normalized = placeId.trim();
    if (normalized.isEmpty) {
      throw ArgumentError('Não foi possível identificar o local selecionado.');
    }
    try {
      final result = await _supabase.functions.invoke(
        'roadbook-places',
        body: {
          'club_id': AppSession.instance.clubId,
          'action': 'details',
          'place_id': normalized,
          'session_token': sessionToken,
        },
      );
      return RoadbookPlaceDetails.fromMap(_map(result.data));
    } on FunctionException catch (error) {
      throw StateError(_friendlyFunctionError(error));
    } on FormatException catch (error) {
      throw StateError(error.message);
    }
  }

  Map<String, dynamic> _map(dynamic value) {
    if (value is Map<String, dynamic>) return value;
    if (value is Map) return Map<String, dynamic>.from(value);
    throw const FormatException('Resposta inválida do serviço de locais.');
  }

  String _friendlyFunctionError(FunctionException error) {
    final details = error.details;
    if (details is Map) {
      final data = Map<String, dynamic>.from(details);
      final code = data['error']?.toString() ?? '';
      final message = data['message']?.toString().trim() ?? '';
      if (code == 'google_places_not_configured') {
        return 'A pesquisa Google Maps ainda não está configurada.';
      }
      if (code == 'roadbook_manage_permission_required') {
        return 'Sem permissão para pesquisar locais do Roadbook.';
      }
      if (message.isNotEmpty) return message;
    }
    if (error.status == 401) {
      return 'A sessão terminou. Inicia sessão novamente.';
    }
    if (error.status == 403) {
      return 'Sem permissão para pesquisar locais do Roadbook.';
    }
    if (error.status == 503) {
      return 'A pesquisa Google Maps ainda não está configurada.';
    }
    return 'Não foi possível pesquisar locais. Verifica a ligação e tenta novamente.';
  }
}
