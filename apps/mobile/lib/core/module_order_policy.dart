/// Normalizes a stored module order against the currently supported modules.
/// Unknown, duplicate and malformed entries are ignored; newly added modules
/// are appended in their canonical order so navigation is never lost.
List<String> normalizeModuleOrder(Object? value, Iterable<String> knownCodes) {
  final known = <String>[];
  final knownSet = <String>{};
  for (final code in knownCodes) {
    if (code.isNotEmpty && knownSet.add(code)) known.add(code);
  }

  final result = <String>[];
  final seen = <String>{};
  if (value is List) {
    for (final item in value) {
      if (item is String && knownSet.contains(item) && seen.add(item)) {
        result.add(item);
      }
    }
  }
  for (final code in known) {
    if (seen.add(code)) result.add(code);
  }
  return List<String>.unmodifiable(result);
}

bool isCanonicalModuleOrder(
    Iterable<String> order, Iterable<String> knownCodes) {
  final normalized = normalizeModuleOrder(order.toList(), knownCodes);
  final canonical = normalizeModuleOrder(null, knownCodes);
  if (normalized.length != canonical.length) return false;
  for (var i = 0; i < canonical.length; i++) {
    if (normalized[i] != canonical[i]) return false;
  }
  return true;
}
