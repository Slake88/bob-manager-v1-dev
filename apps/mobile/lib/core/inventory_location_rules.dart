class InventoryLocationRules {
  const InventoryLocationRules._();

  static String? validateTransfer({
    required String? fromLocationId,
    required String? toLocationId,
    required double quantity,
    required double available,
  }) {
    if (fromLocationId == null || fromLocationId.isEmpty) {
      return 'Seleciona o local de origem.';
    }
    if (toLocationId == null || toLocationId.isEmpty) {
      return 'Seleciona o local de destino.';
    }
    if (fromLocationId == toLocationId) {
      return 'A origem e o destino têm de ser diferentes.';
    }
    if (quantity <= 0) {
      return 'A quantidade deve ser superior a zero.';
    }
    if (quantity > available + 0.0000001) {
      return 'Stock disponível insuficiente no local de origem.';
    }
    return null;
  }
}
