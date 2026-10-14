import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:inti/app/routes.dart';
import 'package:inti/core/theme/app_theme.dart';
import 'package:inti/core/theme/app_tokens.dart';
import 'package:inti/core/widgets/widgets.dart';
import 'package:inti/features/rules/data/rules_provider.dart';
import 'package:inti/features/rules/domain/category_rule.dart';
import 'package:inti/features/transactions/data/transactions_repository.dart';
import 'package:inti/features/transactions/domain/transaction.dart';

/// "1 movimiento" / "3 movimientos".
String _movements(int n) => n == 1 ? '1 movimiento' : '$n movimientos';

/// Cuántos movimientos dicen lo que dice la regla.
int _matching(CategoryRule r, List<Transaction> txs) =>
    txs.where((t) => r.matches(t.title)).length;

/// Reglas de categorías: lo que la app clasifica sola por ti.
class RulesPage extends ConsumerWidget {
  const RulesPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final rules = ref.watch(categoryRulesProvider);
    final txs = ref.watch(transactionsProvider).value ?? const <Transaction>[];

    Future<void> remove(CategoryRule r) async {
      final ok = await confirmDestructive(
        context,
        title: '¿Quitar la regla de ${r.keyword}?',
        message:
            'Los movimientos que ya clasificó se quedan como están. Lo '
            'nuevo ya no se clasifica solo.',
        confirmLabel: 'Quitar regla de ${r.keyword}',
      );
      if (!ok || !context.mounted) return;
      await ref.read(categoryRulesProvider.notifier).remove(r.id);
      if (context.mounted) showQToast(context, 'Quitamos la regla');
    }

    return Scaffold(
      appBar: AppBar(title: const Text('Reglas de categorías')),
      body: rules.isEmpty
          ? MessageBody(
              child: EmptyState(
                icon: Icons.rule_rounded,
                title: 'Enséñale a clasificar',
                message:
                    'Crea una regla como «Rappi → Cafés y salidas» y la app '
                    'clasifica sola lo que registres o importes.',
                actionLabel: 'Crear regla',
                onAction: () => context.push(Routes.newRule),
              ),
            )
          : SafeArea(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(
                  AppSpace.gutter,
                  AppSpace.xs,
                  AppSpace.gutter,
                  AppSpace.xxl,
                ),
                children: [
                  const SectionHeader('Tus reglas'),
                  const SizedBox(height: AppSpace.xs),
                  QCard(
                    padding: const EdgeInsets.symmetric(
                      horizontal: AppSpace.md,
                    ),
                    child: Column(
                      children: [
                        for (final (i, r) in rules.indexed) ...[
                          if (i > 0) const Divider(),
                          SettingsRow(
                            leading: IconTile(icon: r.category.icon),
                            title: 'Si dice «${r.keyword}»',
                            subtitle:
                                '${r.category.name} · '
                                '${_movements(_matching(r, txs))}',
                            trailing: IconButton(
                              tooltip: 'Quitar la regla de ${r.keyword}',
                              onPressed: () => remove(r),
                              icon: const Icon(Icons.delete_outline_rounded),
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                  const SizedBox(height: AppSpace.lg),
                  QButton(
                    label: 'Crear regla',
                    icon: Icons.add_rounded,
                    onPressed: () => context.push(Routes.newRule),
                  ),
                  const SizedBox(height: AppSpace.md),
                  const TrustNote(
                    'Las reglas valen para lo que registres o importes y, si '
                    'quieres, para lo que ya tienes. Lo que clasifiques a '
                    'mano siempre manda.',
                  ),
                ],
              ),
            ),
    );
  }
}

/// Crear una regla: la palabra, la categoría y si se aplica a lo anterior.
class RuleEditorPage extends ConsumerStatefulWidget {
  const RuleEditorPage({super.key, this.keyword, this.categoryId});

  final String? keyword;
  final String? categoryId;

  @override
  ConsumerState<RuleEditorPage> createState() => _RuleEditorPageState();
}

class _RuleEditorPageState extends ConsumerState<RuleEditorPage> {
  late final _keyword = TextEditingController(text: widget.keyword ?? '');
  late String? _categoryId = widget.categoryId;
  bool _applyToPast = true;
  bool _tried = false;
  bool _saving = false;

  @override
  void dispose() {
    _keyword.dispose();
    super.dispose();
  }

  String? get _keywordError => _keyword.text.trim().length < 2
      ? 'Escribe al menos 2 letras del comercio.'
      : null;

  CategoryRule? get _rule => _keywordError != null || _categoryId == null
      ? null
      : CategoryRule(keyword: _keyword.text.trim(), categoryId: _categoryId!);

  Future<void> _save(List<Transaction> all) async {
    setState(() => _tried = true);
    final rule = _rule;
    if (rule == null) return;
    setState(() => _saving = true);
    try {
      final affected = _applyToPast
          ? affectedBy(rule, all)
          : const <Transaction>[];
      await ref
          .read(categoryRulesProvider.notifier)
          .add(keyword: rule.keyword, categoryId: rule.categoryId);
      final repo = ref.read(transactionsRepositoryProvider);
      for (final t in affected) {
        await repo.update(t.copyWith(categoryId: rule.categoryId));
      }
      if (!mounted) return;
      showQToast(
        context,
        affected.isEmpty
            ? 'Creamos la regla de ${rule.keyword}'
            : 'Creamos la regla y cambiamos ${_movements(affected.length)}',
      );
      context.pop();
    } on Object {
      if (!mounted) return;
      setState(() => _saving = false);
      showQToast(context, 'No pudimos crearla. Inténtalo de nuevo.');
    }
  }

  @override
  Widget build(BuildContext context) {
    final all = ref.watch(transactionsProvider).value ?? const <Transaction>[];
    final rule = _rule;
    final count = rule == null ? 0 : affectedBy(rule, all).length;
    return DiscardGuard(
      dirty: !_saving && _keyword.text.trim() != (widget.keyword ?? ''),
      title: '¿Descartar esta regla?',
      confirmLabel: 'Descartar regla',
      child: Scaffold(
        appBar: AppBar(
          leading: const CloseButton(),
          title: const Text('Crear regla'),
        ),
        body: SafeArea(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(
              AppSpace.gutter,
              AppSpace.xs,
              AppSpace.gutter,
              AppSpace.xl,
            ),
            children: [
              TextField(
                controller: _keyword,
                autofocus: widget.keyword == null,
                textCapitalization: TextCapitalization.words,
                onChanged: (_) => setState(() {}),
                decoration: InputDecoration(
                  labelText: 'Cuando el comercio diga…',
                  hintText: 'Ej. Rappi, Éxito, Uber',
                  errorText: _tried ? _keywordError : null,
                ),
              ),
              const SizedBox(height: AppSpace.lg),
              const SectionHeader('Usar la categoría'),
              const SizedBox(height: AppSpace.xs),
              Wrap(
                spacing: AppSpace.xs,
                runSpacing: AppSpace.xs,
                children: [
                  for (final cat in Categories.pickable)
                    ChoiceChip(
                      label: Text(cat.name),
                      selected: _categoryId == cat.id,
                      onSelected: (_) => setState(() => _categoryId = cat.id),
                    ),
                ],
              ),
              if (_tried && _categoryId == null)
                Padding(
                  padding: const EdgeInsets.only(top: AppSpace.xs),
                  child: Text(
                    'Elige una categoría.',
                    style: context.text.bodySmall?.copyWith(
                      color: context.colors.onDangerContainer,
                    ),
                  ),
                ),
              const SizedBox(height: AppSpace.lg),
              QCard(
                padding: const EdgeInsets.symmetric(horizontal: AppSpace.md),
                child: SwitchRow(
                  title: 'Aplicar a lo que ya tienes',
                  subtitle: rule == null
                      ? 'Elige la palabra y la categoría para ver cuántos '
                            'movimientos cambian.'
                      : count == 0
                      ? 'No hay movimientos por cambiar.'
                      : 'Cambia ${_movements(count)}.',
                  value: _applyToPast,
                  onChanged: (v) => setState(() => _applyToPast = v),
                ),
              ),
              const SizedBox(height: AppSpace.xl),
              QButton(
                label: 'Crear regla',
                loading: _saving,
                loadingLabel: 'Guardando',
                onPressed: () => _save(all),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
