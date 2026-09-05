import 'module_definition.dart';

class AppNavigationPlan {
  const AppNavigationPlan({
    required this.primary,
    required this.secondary,
  });

  final List<ModuleDefinition> primary;
  final List<ModuleDefinition> secondary;

  int compactSelectedIndex(String selectedCode) {
    final index = primary.indexWhere((module) => module.code == selectedCode);
    return index >= 0 ? index : primary.length;
  }
}

class AppNavigationPolicy {
  const AppNavigationPolicy._();

  static const int maxCompactDestinations = 4;

  static const List<String> compactPriorityCodes = <String>[
    'dashboard',
    'members',
    'bar',
    'events',
  ];

  static AppNavigationPlan plan(List<ModuleDefinition> visibleModules) {
    final byCode = <String, ModuleDefinition>{
      for (final module in visibleModules) module.code: module,
    };

    final primary = <ModuleDefinition>[];
    for (final code in compactPriorityCodes) {
      final module = byCode[code];
      if (module != null) primary.add(module);
    }

    for (final module in visibleModules) {
      if (primary.length >= maxCompactDestinations) break;
      if (!primary.any((item) => item.code == module.code)) {
        primary.add(module);
      }
    }

    final primaryCodes = primary.map((module) => module.code).toSet();
    final secondary = visibleModules
        .where((module) => !primaryCodes.contains(module.code))
        .toList(growable: false);

    return AppNavigationPlan(
      primary: List<ModuleDefinition>.unmodifiable(primary),
      secondary: List<ModuleDefinition>.unmodifiable(secondary),
    );
  }

  static ModuleDefinition resolveSelected(
    List<ModuleDefinition> visibleModules,
    String selectedCode,
  ) {
    for (final module in visibleModules) {
      if (module.code == selectedCode) return module;
    }
    for (final module in visibleModules) {
      if (module.code == 'dashboard') return module;
    }
    return visibleModules.first;
  }
}
