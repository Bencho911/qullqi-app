import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:inti/app/routes.dart';
import 'package:inti/core/theme/app_theme.dart';
import 'package:inti/core/theme/app_tokens.dart';
import 'package:inti/core/widgets/widgets.dart';
import 'package:inti/features/notifications/data/notices.dart';
import 'package:inti/features/notifications/domain/notice.dart';

/// Rutas de pestaña: se abren con `go` (no se apilan encima).
const Set<String> _tabRoutes = {
  Routes.home,
  Routes.transactions,
  Routes.planning,
  Routes.accounts,
};

/// Centro de avisos. Al abrirlo, la campana queda en cero; lo que era nuevo
/// en esta visita se muestra arriba, en "Nuevos".
class NotificationsPage extends ConsumerStatefulWidget {
  const NotificationsPage({super.key});

  @override
  ConsumerState<NotificationsPage> createState() => _NotificationsPageState();
}

class _NotificationsPageState extends ConsumerState<NotificationsPage> {
  /// Los avisos que no se habían visto al abrir la página.
  Set<String>? _fresh;

  void _open(Notice n) {
    if (_tabRoutes.contains(n.route)) {
      context.go(n.route);
    } else {
      unawaited(context.push(n.route));
    }
  }

  @override
  Widget build(BuildContext context) {
    final notices = ref.watch(noticesProvider);
    if (notices case AsyncData(:final value) when _fresh == null) {
      final seen = ref.read(seenNoticesProvider);
      _fresh = {
        for (final n in value)
          if (!seen.contains(n.id)) n.id,
      };
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        unawaited(
          ref
              .read(seenNoticesProvider.notifier)
              .markSeen(value.map((n) => n.id)),
        );
      });
    }
    return Scaffold(
      appBar: AppBar(
        title: const Text('Notificaciones'),
        actions: [
          IconButton(
            tooltip: 'Elegir qué avisos recibir',
            onPressed: () => context.push(Routes.notificationSettings),
            icon: const Icon(Icons.tune_rounded),
          ),
        ],
      ),
      body: switch (notices) {
        AsyncData(value: final list) when list.isEmpty => const MessageBody(
          child: EmptyState(
            icon: Icons.notifications_none_rounded,
            title: 'Todo al día',
            message:
                'Cuando haya un pago próximo, un cobro o algo de '
                'seguridad, te avisamos aquí.',
          ),
        ),
        AsyncData(value: final list) => _NoticeList(
          notices: list,
          fresh: _fresh ?? const {},
          onOpen: _open,
        ),
        AsyncError() => MessageBody(
          child: EmptyState(
            icon: Icons.cloud_off_rounded,
            title: 'No pudimos cargar tus avisos',
            message: 'Revisa tu conexión a internet e inténtalo de nuevo.',
            actionLabel: 'Reintentar',
            onAction: () => noticeSources.forEach(ref.invalidate),
          ),
        ),
        _ => const PageSkeleton(label: 'Cargando tus avisos'),
      },
    );
  }
}

class _NoticeList extends StatelessWidget {
  const _NoticeList({
    required this.notices,
    required this.fresh,
    required this.onOpen,
  });

  final List<Notice> notices;
  final Set<String> fresh;
  final ValueChanged<Notice> onOpen;

  @override
  Widget build(BuildContext context) {
    final news = notices.where((n) => fresh.contains(n.id)).toList();
    final before = notices.where((n) => !fresh.contains(n.id)).toList();
    Widget group(String title, List<Notice> items) => Padding(
      padding: const EdgeInsets.only(bottom: AppSpace.xl),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SectionHeader(title),
          const SizedBox(height: AppSpace.xs),
          QCard(
            padding: const EdgeInsets.symmetric(horizontal: AppSpace.md),
            child: Column(
              children: [
                for (final (i, n) in items.indexed) ...[
                  if (i > 0) const Divider(),
                  _NoticeRow(n, onTap: () => onOpen(n)),
                ],
              ],
            ),
          ),
        ],
      ),
    );
    return SafeArea(
      child: ListView(
        padding: const EdgeInsets.fromLTRB(
          AppSpace.gutter,
          AppSpace.xs,
          AppSpace.gutter,
          AppSpace.xl,
        ),
        children: [
          if (news.isNotEmpty) group('Nuevos', news),
          if (before.isNotEmpty)
            group(news.isEmpty ? 'Pendientes' : 'Anteriores', before),
          const TrustNote(
            'Los avisos de seguridad y de conexión con tus bancos siempre '
            'llegan.',
          ),
        ],
      ),
    );
  }
}

class _NoticeRow extends StatelessWidget {
  const _NoticeRow(this.n, {required this.onTap});

  final Notice n;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final (bg, fg) = switch (n.tone) {
      NoticeTone.danger => (c.dangerContainer, c.onDangerContainer),
      NoticeTone.warning => (c.warningContainer, c.warning),
      NoticeTone.info => (c.primaryContainer, c.onPrimaryContainer),
    };
    return SettingsRow(
      leading: IconTile(icon: n.icon, background: bg, foreground: fg),
      title: n.title,
      subtitle: n.body,
      onTap: onTap,
    );
  }
}
