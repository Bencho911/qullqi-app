import 'package:flutter/material.dart';

import 'package:inti/core/theme/app_tokens.dart';
import 'package:inti/core/widgets/widgets.dart';

/// Pantalla provisional para flujos que se construyen en hitos siguientes.
/// Mantiene la navegación completa sin callejones sin salida.
class ComingSoonPage extends StatelessWidget {
  const ComingSoonPage({
    required this.title,
    required this.message,
    required this.icon,
    super.key,
  });

  final String title;
  final String message;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(title), leading: const CloseButton()),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.symmetric(horizontal: AppSpace.gutter),
          children: [
            EmptyState(icon: icon, title: 'Muy pronto', message: message),
          ],
        ),
      ),
    );
  }
}
