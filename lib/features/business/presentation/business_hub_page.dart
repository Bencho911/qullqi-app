import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:inti/app/routes.dart';
import 'package:inti/core/clock/clock.dart';
import 'package:inti/core/money/money.dart';
import 'package:inti/core/theme/app_tokens.dart';
import 'package:inti/core/widgets/widgets.dart';
import 'package:inti/features/business/data/business_back_office.dart';
import 'package:inti/features/business/data/invoices_repository.dart';
import 'package:inti/features/business/domain/bill.dart';
import 'package:inti/features/business/domain/business.dart';
import 'package:inti/features/business/domain/reconcile.dart';
import 'package:inti/features/sales/data/sales_repositories.dart';
import 'package:inti/features/sales/domain/sales.dart';

/// "1 por cobrar" / "3 por cobrar".
String _count(int n, String one, String many) => n == 1 ? '1 $one' : '$n $many';

/// Herramientas del negocio: todo lo que se hace con clientes, proveedores e
/// impuestos, en un solo lugar.
class BusinessHubPage extends ConsumerWidget {
  const BusinessHubPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final now = ref.watch(clockProvider)();
    final invoices = ref.watch(invoicesProvider).value ?? const <Invoice>[];
    final quotes = ref.watch(quotesProvider).value ?? const <Quote>[];
    final templates =
        ref.watch(invoiceTemplatesProvider).value ?? const <InvoiceTemplate>[];
    final links =
        ref.watch(paymentLinksProvider).value ?? const <PaymentLink>[];

    final open = invoices.where((i) => i.paidOn == null).toList();
    final openBills = (ref.watch(billsProvider).value ?? const <Bill>[])
        .where((b) => b.paidOn == null)
        .toList();
    final owed = openBills.fold<int>(0, (s, b) => s + b.amount);
    final reconcile =
        ref.watch(reconcileSuggestionsProvider).value ??
        const <ReconcileSuggestion>[];
    final waiting = quotes
        .where((q) => q.statusAt(now) == QuoteStatus.sent)
        .length;
    final activeTemplates = templates.where((t) => t.active).length;
    final activeLinks = links
        .where((l) => l.statusAt(now) == PaymentLinkStatus.active)
        .length;

    Widget option(
      IconData icon,
      String title,
      String subtitle,
      String route, {
      bool emphasized = false,
    }) => Padding(
      padding: const EdgeInsets.only(bottom: AppSpace.xs),
      child: OptionRow(
        icon: icon,
        title: title,
        subtitle: subtitle,
        emphasized: emphasized,
        onTap: () => context.push(route),
      ),
    );

    return Scaffold(
      appBar: AppBar(title: const Text('Herramientas del negocio')),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(
            AppSpace.gutter,
            AppSpace.xs,
            AppSpace.gutter,
            AppSpace.xxl,
          ),
          children: [
            const SectionHeader('Vender y cobrar'),
            const SizedBox(height: AppSpace.xs),
            option(
              Icons.receipt_long_outlined,
              'Facturas por cobrar',
              open.isEmpty
                  ? 'Nada pendiente'
                  : '${_count(open.length, 'pendiente', 'pendientes')} · '
                        '${Cop.format(open.fold(0, (s, i) => s + i.total))}',
              Routes.invoices,
              emphasized: true,
            ),
            option(
              Icons.request_quote_outlined,
              'Cotizaciones',
              waiting == 0
                  ? 'Propón un precio y conviértelo en factura'
                  : _count(
                      waiting,
                      'esperando respuesta',
                      'esperando respuesta',
                    ),
              Routes.quotes,
            ),
            option(
              Icons.event_repeat_rounded,
              'Facturas recurrentes',
              activeTemplates == 0
                  ? 'Cobra lo mismo cada mes sin repetir'
                  : _count(activeTemplates, 'activa', 'activas'),
              Routes.invoiceTemplates,
            ),
            option(
              Icons.add_link_rounded,
              'Enlaces de pago',
              activeLinks == 0
                  ? 'Que tu cliente te pague desde el celular'
                  : _count(activeLinks, 'activo', 'activos'),
              Routes.paymentLinks,
            ),
            const SizedBox(height: AppSpace.lg),
            const SectionHeader('Cuadrar y pagar'),
            const SizedBox(height: AppSpace.xs),
            option(
              Icons.compare_arrows_rounded,
              'Conciliar cobros',
              reconcile.isEmpty
                  ? 'Todo cuadra'
                  : _count(
                      reconcile.length,
                      'depósito parece pagar una factura',
                      'depósitos parecen pagar facturas',
                    ),
              Routes.reconcile,
              emphasized: reconcile.isNotEmpty,
            ),
            option(
              Icons.request_page_outlined,
              'Cuentas por pagar',
              openBills.isEmpty
                  ? 'Anota lo que le debes a tus proveedores'
                  : '${_count(openBills.length, 'pendiente', 'pendientes')} · '
                        '${Cop.format(owed)}',
              Routes.bills,
            ),
            const SizedBox(height: AppSpace.lg),
            const SectionHeader('Impuestos'),
            const SizedBox(height: AppSpace.xs),
            option(
              Icons.account_balance_outlined,
              'IVA del bimestre',
              'Lo que cobraste menos lo que puedes descontar',
              Routes.iva,
            ),
            option(
              Icons.event_note_outlined,
              'Impuestos y obligaciones',
              'Tus fechas, el 4x1000 y el resumen para la renta',
              Routes.taxes,
            ),
            option(
              Icons.groups_outlined,
              'Tu contador',
              'Dale acceso de solo lectura o mándale un archivo',
              Routes.accountant,
            ),
          ],
        ),
      ),
    );
  }
}
