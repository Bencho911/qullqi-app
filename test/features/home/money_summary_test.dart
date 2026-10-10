import 'package:flutter_test/flutter_test.dart';
import 'package:qullqi/core/scope/scope.dart';
import 'package:qullqi/features/accounts/data/accounts_repository.dart';
import 'package:qullqi/features/accounts/domain/account.dart';
import 'package:qullqi/features/commitments/data/commitments_repository.dart';
import 'package:qullqi/features/commitments/domain/commitment.dart';
import 'package:qullqi/features/home/domain/money_summary.dart';

void main() {
  final now = DateTime(2026, 10, 24, 14, 45);
  late List<Account> accounts;
  late List<Commitment> commitments;

  setUpAll(() async {
    accounts = await MockAccountsRepository(
      now: () => now,
      latency: Duration.zero,
    ).watch().first;
    commitments = await MockCommitmentsRepository(
      now: () => now,
      latency: Duration.zero,
    ).watch().first;
  });

  MoneySummary summary(Scope s) => MoneySummary.compute(
    accounts: accounts,
    commitments: commitments,
    scope: s,
    now: now,
  );

  group('Disponible para gastar', () {
    test('personal: cuentas líquidas menos pagos de 30 días', () {
      final s = summary(Scope.personal);
      expect(s.liquid, 4050000); // Bancolombia + Nequi (sin tarjetas)
      // Visa 1.320.000 + Nu 450.000 + internet 89.000 + arriendo 1.200.000
      expect(s.committed, 3059000);
      expect(s.available, 991000);
    });

    test(
      'negocio: descuenta los pagos fijos (el IVA se suma en el Inicio)',
      () {
        final s = summary(Scope.business);
        expect(s.liquid, 3750000);
        expect(s.committed, 89000);
        expect(s.available, 3661000);
      },
    );

    test('todo es la suma de personal y negocio', () {
      final all = summary(Scope.all);
      expect(
        all.available,
        summary(Scope.personal).available + summary(Scope.business).available,
      );
      expect(all.available, 4652000);
    });

    test('el patrimonio resta la deuda de las tarjetas', () {
      expect(summary(Scope.all).netWorth, 7800000 - 1770000);
      expect(summary(Scope.personal).netWorth, 4050000 - 1770000);
    });

    test('no cuenta pagos más allá de 30 días, sí los vencidos', () {
      final later = [
        Commitment(
          id: 'lejos',
          title: 'Seguro anual',
          amount: 900000,
          due: now.add(const Duration(days: 45)),
          ownership: Ownership.personal,
          kind: CommitmentKind.bill,
        ),
        Commitment(
          id: 'vencido',
          title: 'Administración',
          amount: 250000,
          due: now.subtract(const Duration(days: 2)),
          ownership: Ownership.personal,
          kind: CommitmentKind.bill,
        ),
      ];
      final s = MoneySummary.compute(
        accounts: const [],
        commitments: later,
        scope: Scope.personal,
        now: now,
      );
      expect(s.committed, 250000);
      expect(s.available, -250000);
    });
  });

  group('Próximos pagos', () {
    test('ordenados por vencimiento y filtrados por vista', () {
      final p = summary(Scope.all).payments;
      final days = p.map((e) => e.due.difference(p.first.due).inDays).toList();
      expect(days, orderedEquals([...days]..sort()));
      expect(p.first.kind, PaymentKind.card); // Visa vence en 3 días
      expect(p.first.minimum, 180000);
      expect(
        summary(Scope.business).payments.map((e) => e.id),
        unorderedEquals(['claro']),
      );
    });

    test('una tarjeta sin saldo del corte no genera pago', () {
      final noDebt = accounts
          .where((a) => a.id == 'visa')
          .map(
            (a) => Account(
              id: a.id,
              institution: a.institution,
              kind: a.kind,
              last4: a.last4,
              ownership: a.ownership,
              balance: 0,
              status: a.status,
              lastSync: a.lastSync,
              statementBalance: 0,
              paymentDue: a.paymentDue,
            ),
          )
          .toList();
      expect(
        upcomingPayments(
          accounts: noDebt,
          commitments: const [],
          scope: Scope.all,
        ),
        isEmpty,
      );
    });
  });
}
