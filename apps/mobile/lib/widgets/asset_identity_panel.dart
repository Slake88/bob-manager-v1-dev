import 'package:flutter/material.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../services/asset_label_service.dart';

class AssetIdentityPanel extends StatelessWidget {
  const AssetIdentityPanel({
    super.key,
    required this.assetNumber,
    required this.qrCode,
    required this.name,
    required this.category,
    required this.condition,
    required this.compact,
  });

  final String assetNumber;
  final String qrCode;
  final String name;
  final String category;
  final String condition;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final payload = AssetLabelService.payload(qrCode);
    final status = _status(condition);
    final qrSize = compact ? 190.0 : 220.0;

    return Container(
      constraints: const BoxConstraints(maxWidth: 310),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        boxShadow: const [
          BoxShadow(color: Color(0x33000000), blurRadius: 14, offset: Offset(0, 5)),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text(
            'IDENTIFICAÇÃO PATRIMONIAL',
            textAlign: TextAlign.center,
            style: TextStyle(color: Colors.black87, fontSize: 12, fontWeight: FontWeight.w900, letterSpacing: .6),
          ),
          const SizedBox(height: 10),
          Center(
            child: Container(
              color: Colors.white,
              padding: const EdgeInsets.all(14),
              child: QrImageView(
                data: payload,
                size: qrSize,
                backgroundColor: Colors.white,
                eyeStyle: const QrEyeStyle(color: Colors.black, eyeShape: QrEyeShape.square),
                dataModuleStyle: const QrDataModuleStyle(color: Colors.black, dataModuleShape: QrDataModuleShape.square),
              ),
            ),
          ),
          const SizedBox(height: 8),
          Text(assetNumber, textAlign: TextAlign.center, style: const TextStyle(color: Colors.black, fontSize: 18, fontWeight: FontWeight.w900)),
          const SizedBox(height: 2),
          Text(payload, textAlign: TextAlign.center, style: const TextStyle(color: Colors.black87, fontSize: 11, fontWeight: FontWeight.w700)),
          const SizedBox(height: 10),
          Text(name, maxLines: 2, overflow: TextOverflow.ellipsis, textAlign: TextAlign.center, style: const TextStyle(color: Colors.black, fontWeight: FontWeight.w800)),
          Text(category, textAlign: TextAlign.center, style: const TextStyle(color: Colors.black54, fontSize: 12)),
          const SizedBox(height: 8),
          Align(
            alignment: Alignment.center,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(color: status.color.withValues(alpha: .14), borderRadius: BorderRadius.circular(999)),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.circle, size: 11, color: status.color),
                  const SizedBox(width: 6),
                  Text(status.label, style: TextStyle(color: status.color, fontWeight: FontWeight.w800)),
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),
          FilledButton.icon(
            style: FilledButton.styleFrom(backgroundColor: Colors.black87, foregroundColor: Colors.white),
            onPressed: () => AssetLabelService.printLabel(
              assetNumber: assetNumber,
              qrCode: qrCode,
              name: name,
              category: category,
            ),
            icon: const Icon(Icons.print_outlined),
            label: const Text('Imprimir etiqueta'),
          ),
        ],
      ),
    );
  }
}

({String label, Color color}) _status(String value) => switch (value) {
      'excellent' => (label: 'Excelente', color: const Color(0xFF16803D)),
      'good' => (label: 'Bom', color: const Color(0xFF1769AA)),
      'regular' => (label: 'Regular', color: const Color(0xFFA56A00)),
      'maintenance' => (label: 'Necessita manutenção', color: const Color(0xFFC35A00)),
      'damaged' => (label: 'Avariado', color: const Color(0xFFB3261E)),
      'retired' => (label: 'Abatido', color: const Color(0xFF555555)),
      _ => (label: 'Bom', color: const Color(0xFF1769AA)),
    };
