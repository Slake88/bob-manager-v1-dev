import '../services/data_service.dart';

class MemberRepository {
  MemberRepository({DataService? dataService})
      : _dataService = dataService ?? DataService.instance;

  final DataService _dataService;

  Future<List<Map<String, dynamic>>> listMembers() async {
    final rows = await _dataService.list('members');
    rows.sort((a, b) {
      final aNumber = int.tryParse(a['member_number']?.toString() ?? '');
      final bNumber = int.tryParse(b['member_number']?.toString() ?? '');
      return (aNumber ?? 999999).compareTo(bNumber ?? 999999);
    });
    return rows;
  }

  Future<Map<String, dynamic>?> getMember(String memberId) {
    return _dataService.getById('members', memberId);
  }

  Future<Map<String, dynamic>> saveMember(
    Map<String, dynamic> values, {
    String? memberId,
  }) {
    if (memberId == null) {
      return _dataService.insert('members', values);
    }
    return _dataService.update('members', memberId, values);
  }

  Future<List<Map<String, dynamic>>> related(
    String table,
    String memberId,
  ) {
    return _dataService.listWhere(
      table,
      field: 'member_id',
      value: memberId,
    );
  }
}
