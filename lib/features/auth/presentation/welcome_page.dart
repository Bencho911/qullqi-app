import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import 'package:qullqi/app/routes.dart';
import 'package:qullqi/core/theme/app_theme.dart';
import 'package:qullqi/core/theme/app_tokens.dart';
import 'package:qullqi/core/theme/app_typography.dart';
import 'package:qullqi/core/widgets/widgets.dart';

class _Slide {
  const _Slide(this.icon, this.title, this.text);

  final IconData icon;
  final String title;
  final String text;
}

const _slides = [
  _Slide(
    Icons.account_balance_wallet_outlined,
    'Todas tus cuentas en un solo lugar',
    'Bancos, billeteras y tarjetas juntos, sin abrir cada app.',
  ),
  _Slide(
    Icons.verified_outlined,
    'Lo que puedes gastar de verdad',
    'Descontamos tus pagos próximos para que no te quedes corto.',
  ),
  _Slide(
    Icons.storefront_outlined,
    'Tu plata y la de tu negocio, separadas',
    'Utilidad, cobros e IVA claros, en la misma app.',
  ),
];

/// Bienvenida: tres ideas, crear cuenta o ingresar.
class WelcomePage extends StatefulWidget {
  const WelcomePage({super.key});

  @override
  State<WelcomePage> createState() => _WelcomePageState();
}

class _WelcomePageState extends State<WelcomePage> {
  final _pages = PageController();
  int _index = 0;

  @override
  void dispose() {
    _pages.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            const Padding(
              padding: EdgeInsets.all(AppSpace.gutter),
              child: Align(
                alignment: Alignment.centerLeft,
                child: QullqiLockup(),
              ),
            ),
            Expanded(
              child: PageView.builder(
                controller: _pages,
                itemCount: _slides.length,
                onPageChanged: (i) => setState(() => _index = i),
                itemBuilder: (context, i) {
                  final s = _slides[i];
                  return SingleChildScrollView(
                    padding: const EdgeInsets.symmetric(
                      horizontal: AppSpace.gutter,
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const SizedBox(height: AppSpace.xl),
                        ExcludeSemantics(
                          child: Container(
                            width: _artSize,
                            height: _artSize,
                            decoration: BoxDecoration(
                              color: c.primaryContainer,
                              borderRadius: AppRadius.cardAll,
                            ),
                            child: Icon(
                              s.icon,
                              size: AppSize.avatarLg,
                              color: c.onPrimaryContainer,
                            ),
                          ),
                        ),
                        const SizedBox(height: AppSpace.xl),
                        Semantics(
                          header: true,
                          child: Text(
                            s.title,
                            style: context.text.headlineSmall,
                          ),
                        ),
                        const SizedBox(height: AppSpace.sm),
                        Text(
                          s.text,
                          style: AppTypography.body.copyWith(color: c.inkMuted),
                        ),
                      ],
                    ),
                  );
                },
              ),
            ),
            Semantics(
              label: 'Paso ${_index + 1} de ${_slides.length}',
              excludeSemantics: true,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  for (var i = 0; i < _slides.length; i++)
                    AnimatedContainer(
                      duration: AppMotion.of(context, AppMotion.standard),
                      margin: const EdgeInsets.symmetric(
                        horizontal: AppSpace.xxs,
                      ),
                      width: i == _index ? AppSpace.lg : AppSpace.xs,
                      height: AppSpace.xs,
                      decoration: BoxDecoration(
                        color: i == _index ? c.primary : c.outlineStrong,
                        borderRadius: AppRadius.pill,
                      ),
                    ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(AppSpace.gutter),
              child: Column(
                children: [
                  QButton(
                    label: 'Crear cuenta',
                    onPressed: () => context.push(Routes.signUp),
                  ),
                  const SizedBox(height: AppSpace.xs),
                  QButton.secondary(
                    label: 'Ya tengo cuenta',
                    onPressed: () => context.push(Routes.signIn),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Tamaño de la ilustración de cada idea.
const double _artSize = 96;
