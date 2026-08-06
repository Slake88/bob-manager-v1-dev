import '../core/app_role.dart';
import '../core/app_session.dart';
import '../core/permissions.dart';
import '../services/data_service.dart';

class DocumentRepository {
  DocumentRepository({DataService? dataService})
      : _dataService = dataService ?? DataService.instance;

  final DataService _dataService;

  AppRole get _role => AppRole.fromValue(AppSession.instance.role);

  Future<List<Map<String, dynamic>>> listDocuments() async {
    _require(AppPermission.viewDocuments);
    final rows = await _dataService.list('documents');
    final visible = rows.where((row) {
      if (row['sensitive'] != true) return true;
      return PermissionPolicy.allows(_role, AppPermission.viewSensitiveDocuments);
    }).map(Map<String, dynamic>.from).toList();
    visible.sort((a, b) => (b['document_date']?.toString() ?? '')
        .compareTo(a['document_date']?.toString() ?? ''));
    return visible;
  }

  Future<Map<String, dynamic>> saveDocument(
    Map<String, dynamic> values, {
    String? documentId,
  }) {
    _require(AppPermission.manageDocuments);
    final payload = Map<String, dynamic>.from(values)
      ..['updated_at'] = DateTime.now().toIso8601String();
    if (documentId == null) {
      payload['created_by'] = AppSession.instance.profileId;
      return _dataService.insert('documents', payload);
    }
    return _dataService.update('documents', documentId, payload);
  }

  Future<void> deleteDocument(String documentId) {
    _require(AppPermission.manageDocuments);
    return _dataService.delete('documents', documentId);
  }

  static bool isExpired(Map<String, dynamic> document, {DateTime? now}) {
    final value = document['expires_at']?.toString();
    if (value == null || value.isEmpty) return false;
    final expiry = DateTime.tryParse(value);
    if (expiry == null) return false;
    final reference = now ?? DateTime.now();
    return expiry.isBefore(DateTime(reference.year, reference.month, reference.day));
  }

  static bool expiresSoon(
    Map<String, dynamic> document, {
    DateTime? now,
    int days = 30,
  }) {
    final value = document['expires_at']?.toString();
    if (value == null || value.isEmpty) return false;
    final expiry = DateTime.tryParse(value);
    if (expiry == null) return false;
    final reference = now ?? DateTime.now();
    final difference = expiry.difference(reference).inDays;
    return difference >= 0 && difference <= days;
  }

  void _require(AppPermission permission) {
    if (!PermissionPolicy.allows(_role, permission)) {
      throw StateError('Sem permissão para executar esta operação.');
    }
  }
}
