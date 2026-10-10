import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:qullqi/app/routes.dart';
import 'package:qullqi/core/scope/scope_provider.dart';
import 'package:qullqi/core/session/session.dart';
import 'package:qullqi/core/theme/app_theme.dart';
import 'package:qullqi/core/theme/app_tokens.dart';
import 'package:qullqi/core/widgets/widgets.dart';
import 'package:qullqi/features/notifications/data/notices.dart';

/// Estructura de toda pestaña principal: título grande que se compacta al
/// hacer scroll (como en iOS y Material 3), campana, avatar al perfil y el
/// selector de vista si la persona tiene negocio.
class TabPage extends ConsumerWidget {
  const TabPage({
    required this.title,
    required this.slivers,
    super.key,
    this.onRefresh,
  });

  final String title;
  final List<Widget> slivers;

  /// Deslizar hacia abajo para actualizar (nativo en cada plataforma).
  final Future<void> Function()? onRefresh;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final user = ref.watch(currentUserProvider);
    final scope = ref.watch(scopeProvider);

    final scroll = CustomScrollView(
      physics: const AlwaysScrollableScrollPhysics(),
      slivers: [
        SliverAppBar.medium(
          title: Text(title),
          actions: const [_NotificationsButton(), _ProfileButton()],
          actionsPadding: const EdgeInsets.only(right: AppSpace.xs),
        ),
        if (user.hasBusiness)
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(
              AppSpace.gutter,
              AppSpace.xxs,
              AppSpace.gutter,
              AppSpace.md,
            ),
            sliver: SliverToBoxAdapter(
              child: ScopeSwitcher(
                value: scope,
                onChanged: (s) => ref.read(scopeProvider.notifier).select(s),
              ),
            ),
          ),
        ...slivers,
        const SliverToBoxAdapter(child: SizedBox(height: AppSpace.xxl)),
      ],
    );

    return Scaffold(
      body: onRefresh == null
          ? scroll
          : RefreshIndicator.adaptive(
              onRefresh: onRefresh!,
              color: context.colors.primary,
              child: scroll,
            ),
    );
  }
}

/// Contenido con el margen lateral estándar.
class GutterSliver extends StatelessWidget {
  const GutterSliver({required this.child, super.key});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return SliverPadding(
      padding: const EdgeInsets.symmetric(horizontal: AppSpace.gutter),
      sliver: SliverToBoxAdapter(child: child),
    );
  }
}

class _NotificationsButton extends ConsumerWidget {
  const _NotificationsButton();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final unread = ref.watch(unreadNotificationsProvider);
    return IconButton(
      tooltip: unread > 0
          ? 'Notificaciones, $unread sin leer'
          : 'Notificaciones',
      onPressed: () => context.push(Routes.notifications),
      icon: Badge(
        isLabelVisible: unread > 0,
        backgroundColor: context.colors.danger,
        textColor: context.colors.onDanger,
        // Como en los íconos nativos, el número crece poco con el texto grande.
        label: MediaQuery.withClampedTextScaling(
          maxScaleFactor: 1.2,
          child: Text('$unread'),
        ),
        child: const Icon(Icons.notifications_none_rounded),
      ),
    );
  }
}

class _ProfileButton extends ConsumerWidget {
  const _ProfileButton();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final user = ref.watch(currentUserProvider);
    final c = context.colors;
    return IconButton(
      tooltip: 'Tu perfil',
      onPressed: () => context.push(Routes.profile),
      icon: InitialsAvatar(
        user.initials,
        size: AppSize.avatarSm,
        background: c.primaryContainer,
        foreground: c.onPrimaryContainer,
      ),
    );
  }
}
