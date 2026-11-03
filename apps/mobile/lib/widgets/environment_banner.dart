import 'package:flutter/material.dart';

import '../core/app_config.dart';

/// Identificação de ambiente definida pela build, nunca pelo utilizador.
class EnvironmentBanner extends StatelessWidget implements PreferredSizeWidget {
  const EnvironmentBanner({super.key, this.appBarStrip = false});

  final bool appBarStrip;

  @override
  Size get preferredSize => Size.fromHeight(appBarStrip ? 28 : 36);

  @override
  Widget build(BuildContext context) {
    final environment = AppConfig.environment;
    final colorScheme = Theme.of(context).colorScheme;
    final (label, background, foreground, icon) = switch (environment) {
      AppEnvironment.test => (
          'AMBIENTE DE TESTES',
          const Color(0xFFFFC857),
          const Color(0xFF241900),
          Icons.science_outlined,
        ),
      AppEnvironment.real => (
          'BOB REAL · VERSÃO OFICIAL',
          colorScheme.surfaceContainerHighest,
          colorScheme.onSurfaceVariant,
          Icons.verified_outlined,
        ),
      AppEnvironment.unconfigured => (
          'AMBIENTE NÃO CONFIGURADO',
          colorScheme.errorContainer,
          colorScheme.onErrorContainer,
          Icons.warning_amber_rounded,
        ),
    };

    return Semantics(
      label: label,
      child: Container(
        height: appBarStrip ? preferredSize.height : null,
        width: appBarStrip ? double.infinity : null,
        alignment: Alignment.center,
        padding: EdgeInsets.symmetric(
          horizontal: appBarStrip ? 8 : 14,
          vertical: appBarStrip ? 0 : 7,
        ),
        decoration: BoxDecoration(
          color: background,
          borderRadius:
              appBarStrip ? BorderRadius.zero : BorderRadius.circular(24),
        ),
        child: Row(
          mainAxisSize: appBarStrip ? MainAxisSize.max : MainAxisSize.min,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, size: appBarStrip ? 16 : 18, color: foreground),
            const SizedBox(width: 7),
            Flexible(
              child: Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: foreground,
                  fontSize: appBarStrip ? 11 : 12,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 0.45,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
