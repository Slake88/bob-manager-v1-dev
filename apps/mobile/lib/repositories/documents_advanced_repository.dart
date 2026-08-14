import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../core/app_config.dart';
import '../core/app_session.dart';
import '../core/permissions.dart';
import 'document_repository.dart';

class DocumentsAdvancedRepository {
  DocumentsAdvancedRepository({SupabaseClient? client}) : _client = client;

  static const int personalLimitBytes = 500 * 1024 * 1024;
  static const int maxFileBytes = 20 * 1024 * 1024;
  static const String bucketName = DocumentRepository.bucketName;

  final SupabaseClient? _client;
  SupabaseClient get _supabase => _client ?? Supabase.instance.client;
  String get _clubId => AppSession.instance.clubId;
  String get _profileId =>
      _supabase.auth.currentUser?.id ?? AppSession.instance.profileId;

  bool get isDemo => AppConfig.demoMode;
  bool get canManageDocuments =>
      AppSession.instance.can(AppPermission.manageDocuments);
  bool get canApprove =>
      AppSession.instance.can(AppPermission.approveDocuments);
  bool get canRunOcr => AppSession.instance.can(AppPermission.runDocumentOcr);
  bool get canManageGallery =>
      AppSession.instance.can(AppPermission.manageEventGallery);
  bool get canManageBooks =>
      AppSession.instance.can(AppPermission.manageAnnualBooks);

  Future<List<Map<String, dynamic>>> listDocuments({String? scope}) async {
    if (isDemo) return _demoDocuments(scope: scope);
    var query = _supabase
        .from('documents')
        .select()
        .eq('club_id', _clubId);
    if (scope != null) query = query.eq('scope', scope);
    final response = await query
        .order('document_date', ascending: false)
        .order('created_at', ascending: false)
        .limit(500);
    return List<Map<String, dynamic>>.from(response);
  }

  Future<Map<String, dynamic>> document(String id) async {
    if (isDemo) {
      return _demoDocuments().firstWhere(
        (row) => row['id'] == id,
        orElse: () => _demoDocuments().first,
      );
    }
    final response = await _supabase
        .from('documents')
        .select()
        .eq('club_id', _clubId)
        .eq('id', id)
        .single();
    return Map<String, dynamic>.from(response);
  }

  Future<List<Map<String, dynamic>>> listVersions(String documentId) async {
    if (isDemo) {
      return [
        {
          'id': 'demo-version-1',
          'document_id': documentId,
          'version_no': 1,
          'version_label': '1.0',
          'original_file_name': 'documento.pdf',
          'file_size': 245760,
          'is_current': true,
          'created_at': DateTime.now().toIso8601String(),
        },
      ];
    }
    final response = await _supabase
        .from('document_versions')
        .select()
        .eq('document_id', documentId)
        .order('version_no', ascending: false);
    return List<Map<String, dynamic>>.from(response);
  }

  Future<List<Map<String, dynamic>>> listLinks(String documentId) async {
    if (isDemo) return const [];
    final response = await _supabase
        .from('document_links')
        .select()
        .eq('document_id', documentId)
        .order('created_at', ascending: false);
    return List<Map<String, dynamic>>.from(response);
  }

  Future<void> addLink({
    required String documentId,
    required String entityType,
    required String entityId,
    String label = '',
  }) async {
    _require(AppPermission.manageDocuments);
    if (isDemo) return;
    await _supabase.from('document_links').insert({
      'club_id': _clubId,
      'document_id': documentId,
      'link_type': 'related',
      'linked_entity_type': entityType.trim(),
      'linked_entity_id': entityId.trim(),
      'label': _nullable(label),
      'created_by': _profileId,
    });
  }

  Future<int> personalUsageBytes() async {
    if (isDemo) return 74 * 1024 * 1024;
    final response = await _supabase.rpc(
      'personal_document_usage_bytes_v1',
      params: {'target_club': _clubId},
    );
    return int.tryParse(response.toString()) ?? 0;
  }

  Future<List<Map<String, dynamic>>> listPersonal() =>
      listDocuments(scope: 'personal');

  Future<Map<String, dynamic>> uploadPersonal(PlatformFile file) async {
    _ensureReadable(file);
    if (file.size > maxFileBytes) {
      throw StateError('O ficheiro ultrapassa o limite de 20 MB.');
    }
    final used = await personalUsageBytes();
    if (used + file.size > personalLimitBytes) {
      throw StateError('O arquivo pessoal ultrapassaria o limite de 500 MB.');
    }
    if (isDemo) {
      return {
        'id': 'demo-personal-${DateTime.now().millisecondsSinceEpoch}',
        'name': file.name,
        'scope': 'personal',
        'file_size': file.size,
      };
    }
    final safe = safeFileName(file.name);
    final path = '$_clubId/personal/$_profileId/'
        '${DateTime.now().microsecondsSinceEpoch}_$safe';
    final mime = mimeTypeForFile(file);
    await _upload(path, file, mime);
    try {
      final response = await _supabase
          .from('documents')
          .insert({
            'club_id': _clubId,
            'name': file.name,
            'category': 'Arquivo pessoal',
            'document_date': _today(),
            'version': '1.0',
            'status': 'active',
            'sensitive': true,
            'scope': 'personal',
            'owner_profile_id': _profileId,
            'storage_path': path,
            'original_file_name': file.name,
            'mime_type': mime,
            'file_size': file.size,
            'created_by': _profileId,
            'updated_by': _profileId,
          })
          .select()
          .single();
      return Map<String, dynamic>.from(response);
    } catch (_) {
      await _supabase.storage.from(bucketName).remove([path]);
      rethrow;
    }
  }

  Future<String> uploadVersion({
    required Map<String, dynamic> document,
    required PlatformFile file,
    String notes = '',
  }) async {
    _require(AppPermission.manageDocuments);
    _ensureReadable(file);
    if (file.size > maxFileBytes) {
      throw StateError('O ficheiro ultrapassa o limite de 20 MB.');
    }
    if (isDemo) return 'demo-version';
    final documentId = document['id'].toString();
    final path = '$_clubId/versions/$documentId/'
        '${DateTime.now().microsecondsSinceEpoch}_${safeFileName(file.name)}';
    final mime = mimeTypeForFile(file);
    await _upload(path, file, mime);
    try {
      final response = await _supabase.rpc(
        'register_document_version_v1',
        params: {
          'p_document': documentId,
          'p_storage_path': path,
          'p_original_file_name': file.name,
          'p_mime_type': mime,
          'p_file_size': file.size,
          'p_change_notes': _nullable(notes),
        },
      );
      return response.toString();
    } catch (_) {
      await _supabase.storage.from(bucketName).remove([path]);
      rethrow;
    }
  }

  Future<String> signedUrl(
    Map<String, dynamic> document, {
    String action = 'signed_url',
  }) async {
    if (isDemo) {
      throw StateError('A abertura de ficheiros não está disponível em Demo.');
    }
    final path = document['storage_path']?.toString() ?? '';
    if (path.isEmpty) throw StateError('Documento sem ficheiro associado.');
    final url = await _supabase.storage
        .from(bucketName)
        .createSignedUrl(path, 300);
    try {
      await _supabase.from('document_access_log').insert({
        'club_id': _clubId,
        'document_id': document['id'],
        'version_id': document['current_version_id'],
        'profile_id': _profileId,
        'action': action,
        'metadata': {'source': 'mobile'},
      });
    } catch (_) {
      // Logging must not block an authorized opening.
    }
    return url;
  }

  Future<List<Map<String, dynamic>>> listApprovals({
    bool pendingOnly = false,
  }) async {
    if (isDemo) {
      return [
        {
          'id': 'demo-approval',
          'document_id': 'demo-club',
          'status': 'pending',
          'notes': 'Confirmar versão final.',
          'documents': {'name': 'Ata da Direção'},
          'requested_at': DateTime.now().toIso8601String(),
        },
      ];
    }
    var query = _supabase
        .from('document_approvals')
        .select('*,documents(name,category,version,scope)')
        .eq('club_id', _clubId);
    if (pendingOnly) query = query.eq('status', 'pending');
    final response = await query
        .order('requested_at', ascending: false)
        .limit(250);
    return List<Map<String, dynamic>>.from(response);
  }

  Future<String> requestApproval(
    String documentId, {
    String notes = '',
  }) async {
    _require(AppPermission.manageDocuments);
    if (isDemo) return 'demo-approval';
    final response = await _supabase.rpc(
      'request_document_approval_v1',
      params: {
        'p_document': documentId,
        'p_notes': _nullable(notes),
      },
    );
    return response.toString();
  }

  Future<void> decideApproval(
    String approvalId, {
    required bool approve,
    String notes = '',
  }) async {
    _require(AppPermission.approveDocuments);
    if (isDemo) return;
    await _supabase.rpc(
      'decide_document_approval_v1',
      params: {
        'p_approval': approvalId,
        'p_approve': approve,
        'p_notes': _nullable(notes),
      },
    );
  }

  Future<List<Map<String, dynamic>>> listOcrJobs(String documentId) async {
    if (isDemo) return const [];
    final response = await _supabase
        .from('document_ocr')
        .select()
        .eq('document_id', documentId)
        .order('created_at', ascending: false)
        .limit(20);
    return List<Map<String, dynamic>>.from(response);
  }

  Future<Map<String, dynamic>> runOcr(String documentId) async {
    _require(AppPermission.runDocumentOcr);
    if (isDemo) {
      return {
        'id': 'demo-ocr',
        'status': 'ready',
        'raw_text': 'Texto OCR de demonstração.',
        'confidence': 0.93,
      };
    }
    final id = (await _supabase.rpc(
      'start_document_ocr_v1',
      params: {'p_document': documentId},
    ))
        .toString();
    try {
      await _supabase.functions.invoke(
        'document-ocr',
        body: {'ocr_id': id},
      );
    } catch (_) {
      final latest = await _ocrJob(id);
      final status = latest['status']?.toString();
      if (status == 'unconfigured' || status == 'failed') return latest;
      rethrow;
    }
    return _ocrJob(id);
  }

  Future<Map<String, dynamic>> _ocrJob(String id) async {
    final response = await _supabase
        .from('document_ocr')
        .select()
        .eq('id', id)
        .single();
    return Map<String, dynamic>.from(response);
  }

  Future<List<Map<String, dynamic>>> listEvents() async {
    if (isDemo) {
      return [
        {
          'id': 'demo-event',
          'name': 'Rock & Ride In',
          'starts_at': DateTime.now().toIso8601String(),
        },
      ];
    }
    final response = await _supabase
        .from('events')
        .select('id,name,starts_at,location,status')
        .eq('club_id', _clubId)
        .order('starts_at', ascending: false)
        .limit(100);
    return List<Map<String, dynamic>>.from(response);
  }

  Future<List<Map<String, dynamic>>> listGallery(String eventId) async {
    if (isDemo) return _demoDocuments(scope: 'event_gallery');
    final response = await _supabase
        .from('documents')
        .select()
        .eq('club_id', _clubId)
        .eq('scope', 'event_gallery')
        .eq('event_id', eventId)
        .order('created_at', ascending: false);
    return List<Map<String, dynamic>>.from(response);
  }

  Future<Map<String, dynamic>> uploadGallery(
    String eventId,
    PlatformFile file,
  ) async {
    _require(AppPermission.manageEventGallery);
    _ensureReadable(file);
    final mime = mimeTypeForFile(file);
    if (!isGalleryMime(mime)) {
      throw StateError('A galeria aceita JPG, PNG ou WEBP.');
    }
    if (file.size > maxFileBytes) {
      throw StateError('A fotografia ultrapassa o limite de 20 MB.');
    }
    if (isDemo) {
      return {
        'id': 'demo-gallery-${DateTime.now().millisecondsSinceEpoch}',
        'name': file.name,
        'scope': 'event_gallery',
        'event_id': eventId,
      };
    }
    final path = '$_clubId/gallery/$eventId/'
        '${DateTime.now().microsecondsSinceEpoch}_${safeFileName(file.name)}';
    await _upload(path, file, mime);
    try {
      final response = await _supabase
          .from('documents')
          .insert({
            'club_id': _clubId,
            'name': file.name,
            'category': 'Galeria de evento',
            'document_date': _today(),
            'version': '1.0',
            'status': 'active',
            'sensitive': false,
            'scope': 'event_gallery',
            'event_id': eventId,
            'storage_path': path,
            'original_file_name': file.name,
            'mime_type': mime,
            'file_size': file.size,
            'created_by': _profileId,
            'updated_by': _profileId,
          })
          .select()
          .single();
      final row = Map<String, dynamic>.from(response);
      await _supabase.from('document_links').insert({
        'club_id': _clubId,
        'document_id': row['id'],
        'link_type': 'gallery',
        'linked_entity_type': 'event',
        'linked_entity_id': eventId,
        'label': 'Galeria do evento',
        'created_by': _profileId,
      });
      return row;
    } catch (_) {
      await _supabase.storage.from(bucketName).remove([path]);
      rethrow;
    }
  }

  Future<List<Map<String, dynamic>>> listAnnualBooks() async {
    if (isDemo) {
      return [
        {
          'id': 'demo-book',
          'year': DateTime.now().year,
          'title': 'Livro anual ${DateTime.now().year}',
          'status': 'draft',
          'description': 'Cápsula do tempo do clube.',
        },
      ];
    }
    final response = await _supabase
        .from('annual_books')
        .select()
        .eq('club_id', _clubId)
        .order('year', ascending: false);
    return List<Map<String, dynamic>>.from(response);
  }

  Future<Map<String, dynamic>> saveAnnualBook({
    String? id,
    required int year,
    required String title,
    String description = '',
    String status = 'draft',
  }) async {
    _require(AppPermission.manageAnnualBooks);
    if (isDemo) {
      return {
        'id': id ?? 'demo-book',
        'year': year,
        'title': title,
        'description': description,
        'status': status,
      };
    }
    final payload = <String, dynamic>{
      'club_id': _clubId,
      'year': year,
      'title': title.trim(),
      'description': _nullable(description),
      'status': status,
      'updated_by': _profileId,
      'updated_at': DateTime.now().toIso8601String(),
    };
    if (id == null) {
      final response = await _supabase
          .from('annual_books')
          .insert({...payload, 'created_by': _profileId})
          .select()
          .single();
      return Map<String, dynamic>.from(response);
    }
    final response = await _supabase
        .from('annual_books')
        .update(payload)
        .eq('id', id)
        .select()
        .single();
    return Map<String, dynamic>.from(response);
  }

  Future<List<Map<String, dynamic>>> listBookItems(String bookId) async {
    if (isDemo) {
      return [
        {
          'id': 'demo-book-item',
          'annual_book_id': bookId,
          'sequence_no': 1,
          'item_type': 'custom',
          'title': 'O ano em revista',
          'body': 'Um registo dos momentos marcantes do clube.',
        },
      ];
    }
    final response = await _supabase
        .from('annual_book_items')
        .select()
        .eq('annual_book_id', bookId)
        .order('sequence_no');
    return List<Map<String, dynamic>>.from(response);
  }

  Future<Map<String, dynamic>> addBookItem({
    required String bookId,
    required int sequence,
    required String title,
    String body = '',
    String itemType = 'custom',
    String? documentId,
    String? entityType,
    String? entityId,
    DateTime? eventDate,
  }) async {
    _require(AppPermission.manageAnnualBooks);
    if (isDemo) {
      return {
        'id': 'demo-book-item-$sequence',
        'annual_book_id': bookId,
        'sequence_no': sequence,
        'title': title,
        'body': body,
        'item_type': itemType,
      };
    }
    final response = await _supabase
        .from('annual_book_items')
        .insert({
          'club_id': _clubId,
          'annual_book_id': bookId,
          'sequence_no': sequence,
          'item_type': itemType,
          'title': title.trim(),
          'body': _nullable(body),
          'document_id': documentId,
          'linked_entity_type': entityType,
          'linked_entity_id': entityId,
          'event_date': eventDate?.toIso8601String().split('T').first,
          'created_by': _profileId,
          'updated_by': _profileId,
        })
        .select()
        .single();
    return Map<String, dynamic>.from(response);
  }

  Future<void> deleteBookItem(String id) async {
    _require(AppPermission.manageAnnualBooks);
    if (isDemo) return;
    await _supabase.from('annual_book_items').delete().eq('id', id);
  }

  Future<List<Map<String, dynamic>>> timelineForYear(int year) async {
    if (isDemo) {
      return [
        {
          'id': 'demo-timeline',
          'title': 'Momento marcante do clube',
          'description': 'Registo anual da timeline.',
          'event_date': '$year-06-20',
        },
      ];
    }
    final response = await _supabase
        .from('member_timeline')
        .select()
        .eq('club_id', _clubId)
        .gte('event_date', '$year-01-01')
        .lte('event_date', '$year-12-31')
        .order('event_date');
    return List<Map<String, dynamic>>.from(response);
  }

  Future<void> _upload(
    String path,
    PlatformFile file,
    String? mime,
  ) async {
    final Uint8List bytes = file.bytes!;
    await _supabase.storage.from(bucketName).uploadBinary(
          path,
          bytes,
          fileOptions: FileOptions(contentType: mime, upsert: false),
        );
  }

  void _ensureReadable(PlatformFile file) {
    final Uint8List? bytes = file.bytes;
    if (bytes == null || bytes.isEmpty) {
      throw StateError(
        'Não foi possível ler ${file.name}. Seleciona novamente o ficheiro.',
      );
    }
  }

  void _require(AppPermission permission) {
    if (!AppSession.instance.can(permission)) {
      throw StateError('Sem permissão para executar esta operação.');
    }
  }

  static String scopeLabel(Object? scope) => switch (scope?.toString()) {
        'leadership' => 'Direção',
        'personal' => 'Pessoal',
        'event_gallery' => 'Galeria',
        'annual_book' => 'Livro anual',
        _ => 'Clube',
      };

  static String approvalLabel(Object? status) => switch (status?.toString()) {
        'pending' => 'A aguardar aprovação',
        'approved' => 'Aprovado',
        'rejected' => 'Rejeitado',
        _ => 'Sem aprovação necessária',
      };

  static String ocrLabel(Object? status) => switch (status?.toString()) {
        'pending' => 'A aguardar OCR',
        'processing' => 'A analisar',
        'ready' => 'OCR concluído',
        'unconfigured' => 'OCR por configurar',
        'failed' => 'OCR falhou',
        _ => 'OCR não solicitado',
      };

  static double usageRatio(int usedBytes) =>
      (usedBytes / personalLimitBytes).clamp(0.0, 1.0).toDouble();

  static String formatBytes(num value) {
    final bytes = value.toDouble();
    if (bytes < 1024) return '${bytes.toStringAsFixed(0)} B';
    if (bytes < 1024 * 1024) {
      return '${(bytes / 1024).toStringAsFixed(1)} KB';
    }
    if (bytes < 1024 * 1024 * 1024) {
      return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
    }
    return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(2)} GB';
  }

  static bool isOcrMime(String? mime) => const {
        'image/jpeg',
        'image/png',
        'image/webp',
        'application/pdf',
      }.contains(mime?.toLowerCase());

  static bool isGalleryMime(String? mime) => const {
        'image/jpeg',
        'image/png',
        'image/webp',
      }.contains(mime?.toLowerCase());

  static String safeFileName(String value) {
    final normalized = value
        .trim()
        .replaceAll(RegExp(r'[^A-Za-z0-9._-]+'), '_')
        .replaceAll(RegExp(r'_+'), '_');
    return normalized.isEmpty ? 'documento' : normalized;
  }

  static String? mimeTypeForFile(PlatformFile file) {
    final extension =
        (file.extension ?? _extension(file.name)).toLowerCase();
    return switch (extension) {
      'pdf' => 'application/pdf',
      'jpg' || 'jpeg' => 'image/jpeg',
      'png' => 'image/png',
      'webp' => 'image/webp',
      'doc' => 'application/msword',
      'docx' =>
        'application/vnd.openxmlformats-officedocument.wordprocessingml.document',
      'xls' => 'application/vnd.ms-excel',
      'xlsx' =>
        'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
      _ => null,
    };
  }

  static String _extension(String name) {
    final index = name.lastIndexOf('.');
    return index < 0 ? '' : name.substring(index + 1);
  }

  static String _today() =>
      DateTime.now().toIso8601String().split('T').first;

  static String? _nullable(String value) {
    final text = value.trim();
    return text.isEmpty ? null : text;
  }

  static List<Map<String, dynamic>> _demoDocuments({String? scope}) {
    final rows = <Map<String, dynamic>>[
      {
        'id': 'demo-club',
        'name': 'Ata da Direção',
        'category': 'Atas',
        'scope': 'leadership',
        'version': '2.0',
        'approval_status': 'approved',
        'ocr_status': 'ready',
        'mime_type': 'application/pdf',
        'file_size': 245760,
        'document_date': _today(),
      },
      {
        'id': 'demo-personal',
        'name': 'Documento pessoal',
        'category': 'Arquivo pessoal',
        'scope': 'personal',
        'version': '1.0',
        'approval_status': 'not_required',
        'ocr_status': 'not_requested',
        'mime_type': 'application/pdf',
        'file_size': 1048576,
        'document_date': _today(),
      },
      {
        'id': 'demo-gallery',
        'name': 'evento_001.jpg',
        'category': 'Galeria de evento',
        'scope': 'event_gallery',
        'event_id': 'demo-event',
        'version': '1.0',
        'approval_status': 'not_required',
        'ocr_status': 'not_requested',
        'mime_type': 'image/jpeg',
        'file_size': 2097152,
        'document_date': _today(),
      },
    ];
    return scope == null
        ? rows
        : rows.where((row) => row['scope'] == scope).toList();
  }
}
