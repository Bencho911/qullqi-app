import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:qullqi/app/dev/gallery_page.dart';
import 'package:qullqi/app/routes.dart';
import 'package:qullqi/app/shell/app_shell.dart';
import 'package:qullqi/core/session/session.dart';
import 'package:qullqi/features/accounts/presentation/account_detail_page.dart';
import 'package:qullqi/features/accounts/presentation/accounts_page.dart';
import 'package:qullqi/features/accounts/presentation/connect_account_page.dart';
import 'package:qullqi/features/accounts/presentation/manual_account_page.dart';
import 'package:qullqi/features/add/presentation/add_transaction_page.dart';
import 'package:qullqi/features/add/presentation/scan_receipt_page.dart';
import 'package:qullqi/features/auth/presentation/sign_in_pages.dart';
import 'package:qullqi/features/auth/presentation/sign_up_pages.dart';
import 'package:qullqi/features/auth/presentation/welcome_page.dart';
import 'package:qullqi/features/business/presentation/business_pages.dart';
import 'package:qullqi/features/debts/presentation/debt_plan_page.dart';
import 'package:qullqi/features/home/presentation/home_page.dart';
import 'package:qullqi/features/investments/presentation/add_investment_page.dart';
import 'package:qullqi/features/investments/presentation/connect_investment_page.dart';
import 'package:qullqi/features/investments/presentation/investment_pages.dart';
import 'package:qullqi/features/investments/presentation/investments_page.dart';
import 'package:qullqi/features/investments/presentation/simulator_page.dart';
import 'package:qullqi/features/move_money/presentation/move_money_page.dart';
import 'package:qullqi/features/networth/presentation/net_worth_page.dart';
import 'package:qullqi/features/notifications/presentation/notifications_page.dart';
import 'package:qullqi/features/planning/presentation/budget_pages.dart';
import 'package:qullqi/features/planning/presentation/goal_pages.dart';
import 'package:qullqi/features/planning/presentation/planning_page.dart';
import 'package:qullqi/features/profile/presentation/profile_page.dart';
import 'package:qullqi/features/profile/presentation/profile_pages.dart';
import 'package:qullqi/features/recurring/presentation/recurring_page.dart';
import 'package:qullqi/features/rules/presentation/rules_pages.dart';
import 'package:qullqi/features/statements/presentation/import_statement_page.dart';
import 'package:qullqi/features/taxes/presentation/taxes_page.dart';
import 'package:qullqi/features/transactions/domain/transaction.dart';
import 'package:qullqi/features/transactions/presentation/review_transfers_page.dart';
import 'package:qullqi/features/transactions/presentation/transaction_detail_page.dart';
import 'package:qullqi/features/transactions/presentation/transactions_page.dart';

final rootNavigatorKey = GlobalKey<NavigatorState>(debugLabel: 'root');

/// Pantalla que se abre como tarea modal (se cierra con X, entra desde abajo
/// en Android y como hoja completa en iOS).
Page<void> _modal(GoRouterState state, Widget child) => MaterialPage<void>(
  key: state.pageKey,
  fullscreenDialog: true,
  child: child,
);

final routerProvider = Provider<GoRouter>((ref) {
  // Cada cambio de sesión vuelve a evaluar a dónde puede ir la persona.
  final sessionChanges = ValueNotifier<int>(0);
  ref
    ..listen(sessionProvider, (_, _) => sessionChanges.value++)
    ..onDispose(sessionChanges.dispose);

  final router = GoRouter(
    navigatorKey: rootNavigatorKey,
    initialLocation: Routes.home,
    refreshListenable: sessionChanges,
    redirect: (context, state) {
      final status = ref.read(sessionProvider).status;
      final loc = state.matchedLocation;
      final isPublic = Routes.public.contains(loc);
      return switch (status) {
        SessionStatus.signedOut => isPublic ? null : Routes.welcome,
        SessionStatus.locked => loc == Routes.lock ? null : Routes.lock,
        SessionStatus.unlocked =>
          isPublic || loc == Routes.lock ? Routes.home : null,
      };
    },
    routes: [
      StatefulShellRoute(
        builder: (context, state, shell) => shell,
        navigatorContainerBuilder: (context, shell, children) =>
            AppShell(navigationShell: shell, children: children),
        branches: [
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: Routes.home,
                builder: (context, state) => const HomePage(),
              ),
            ],
          ),
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: Routes.transactions,
                builder: (context, state) => const TransactionsPage(),
              ),
            ],
          ),
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: Routes.planning,
                builder: (context, state) => const PlanningPage(),
              ),
            ],
          ),
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: Routes.accounts,
                builder: (context, state) => const AccountsPage(),
              ),
            ],
          ),
        ],
      ),
      GoRoute(
        path: Routes.welcome,
        builder: (context, state) => const WelcomePage(),
      ),
      GoRoute(
        path: Routes.signUp,
        builder: (context, state) => const SignUpPage(),
      ),
      GoRoute(
        path: Routes.signUpPhone,
        builder: (context, state) => const PhonePage(),
      ),
      GoRoute(
        path: Routes.signUpCode,
        builder: (context, state) => CodePage(
          phone: state.extra is String ? state.extra! as String : '',
        ),
      ),
      GoRoute(
        path: Routes.createPin,
        builder: (context, state) => const CreatePinPage(),
      ),
      GoRoute(
        path: Routes.signIn,
        builder: (context, state) => const SignInPage(),
      ),
      GoRoute(
        path: Routes.resetPassword,
        builder: (context, state) => const ResetPasswordPage(),
      ),
      GoRoute(
        path: Routes.lock,
        pageBuilder: (context, state) =>
            NoTransitionPage<void>(key: state.pageKey, child: const LockPage()),
      ),
      GoRoute(
        path: Routes.profile,
        builder: (context, state) => const ProfilePage(),
      ),
      GoRoute(
        path: Routes.transactionPattern,
        builder: (context, state) =>
            TransactionDetailPage(id: state.pathParameters['id']!),
      ),
      GoRoute(
        path: Routes.accountPattern,
        builder: (context, state) =>
            AccountDetailPage(id: state.pathParameters['id']!),
      ),
      GoRoute(
        path: Routes.manualAccount,
        pageBuilder: (context, state) =>
            _modal(state, const ManualAccountPage()),
      ),
      GoRoute(
        path: Routes.invoices,
        builder: (context, state) => const InvoicesPage(),
      ),
      GoRoute(
        path: Routes.newInvoice,
        pageBuilder: (context, state) => _modal(state, const NewInvoicePage()),
      ),
      GoRoute(
        path: Routes.invoicePattern,
        builder: (context, state) =>
            InvoiceDetailPage(id: state.pathParameters['id']!),
      ),
      GoRoute(path: Routes.iva, builder: (context, state) => const IvaPage()),
      GoRoute(
        path: Routes.budgetPattern,
        builder: (context, state) =>
            BudgetDetailPage(id: state.pathParameters['id']!),
      ),
      GoRoute(
        path: Routes.budgetEditor,
        pageBuilder: (context, state) => _modal(
          state,
          BudgetEditorPage(editId: state.uri.queryParameters['id']),
        ),
      ),
      GoRoute(
        path: Routes.newGoal,
        pageBuilder: (context, state) => _modal(state, const NewGoalPage()),
      ),
      GoRoute(
        path: Routes.contributePattern,
        pageBuilder: (context, state) =>
            _modal(state, ContributePage(goalId: state.pathParameters['id']!)),
      ),
      GoRoute(
        path: Routes.goalPattern,
        builder: (context, state) =>
            GoalDetailPage(id: state.pathParameters['id']!),
      ),
      GoRoute(
        path: Routes.taxes,
        builder: (context, state) => const TaxesPage(),
      ),
      GoRoute(
        path: Routes.netWorth,
        builder: (context, state) => const NetWorthPage(),
      ),
      GoRoute(
        path: Routes.debtPlan,
        builder: (context, state) => const DebtPlanPage(),
      ),
      GoRoute(
        path: Routes.recurring,
        builder: (context, state) => const RecurringPage(),
      ),
      GoRoute(
        path: Routes.rules,
        builder: (context, state) => const RulesPage(),
      ),
      GoRoute(
        path: Routes.newRule,
        pageBuilder: (context, state) => _modal(
          state,
          RuleEditorPage(
            keyword: state.uri.queryParameters['comercio'],
            categoryId: state.uri.queryParameters['categoria'],
          ),
        ),
      ),
      GoRoute(
        path: Routes.investments,
        builder: (context, state) => const InvestmentsPage(),
      ),
      GoRoute(
        path: Routes.investmentPattern,
        builder: (context, state) =>
            InvestmentDetailPage(id: state.pathParameters['id']!),
      ),
      GoRoute(
        path: Routes.updateInvestmentPattern,
        pageBuilder: (context, state) => _modal(
          state,
          UpdateInvestmentValuePage(id: state.pathParameters['id']!),
        ),
      ),
      GoRoute(
        path: Routes.addInvestment,
        pageBuilder: (context, state) =>
            _modal(state, const AddInvestmentPage()),
      ),
      GoRoute(
        path: Routes.connectInvestment,
        pageBuilder: (context, state) =>
            _modal(state, const ConnectInvestmentPage()),
      ),
      GoRoute(
        path: Routes.simulator,
        builder: (context, state) => SimulatorPage(
          goalId: state.uri.queryParameters['meta'],
          initial: int.tryParse(state.uri.queryParameters['inicial'] ?? ''),
          rate: double.tryParse(state.uri.queryParameters['tasa'] ?? ''),
        ),
      ),
      GoRoute(
        path: Routes.reviewTransfers,
        builder: (context, state) => const ReviewTransfersPage(),
      ),
      GoRoute(
        path: Routes.editProfile,
        pageBuilder: (context, state) => _modal(state, const EditProfilePage()),
      ),
      GoRoute(
        path: Routes.changePin,
        builder: (context, state) => const ChangePinPage(),
      ),
      GoRoute(
        path: Routes.devices,
        builder: (context, state) => const DevicesPage(),
      ),
      GoRoute(
        path: Routes.notificationSettings,
        builder: (context, state) => const NotificationSettingsPage(),
      ),
      GoRoute(
        path: Routes.notifications,
        builder: (context, state) => const NotificationsPage(),
      ),
      GoRoute(
        path: Routes.moveMoney,
        pageBuilder: (context, state) => _modal(
          state,
          MoveMoneyPage(
            preset: state.extra is MovePreset
                ? state.extra! as MovePreset
                : null,
          ),
        ),
      ),
      GoRoute(
        path: Routes.addExpense,
        pageBuilder: (context, state) => _modal(
          state,
          AddTransactionPage(
            kind: TransactionKind.expense,
            prefill: state.extra is AddPrefill
                ? state.extra! as AddPrefill
                : null,
          ),
        ),
      ),
      GoRoute(
        path: Routes.addIncome,
        pageBuilder: (context, state) => _modal(
          state,
          const AddTransactionPage(kind: TransactionKind.income),
        ),
      ),
      GoRoute(
        path: Routes.importStatement,
        pageBuilder: (context, state) => _modal(
          state,
          ImportStatementPage(accountId: state.uri.queryParameters['cuenta']),
        ),
      ),
      GoRoute(
        path: Routes.scanReceipt,
        pageBuilder: (context, state) => _modal(state, const ScanReceiptPage()),
      ),
      GoRoute(
        path: Routes.connectAccount,
        pageBuilder: (context, state) => _modal(
          state,
          ConnectAccountPage(
            reconnectAccountId: state.uri.queryParameters['reconectar'],
          ),
        ),
      ),
      if (kDebugMode)
        GoRoute(
          path: Routes.gallery,
          builder: (context, state) => const GalleryPage(),
        ),
    ],
  );
  ref.onDispose(router.dispose);
  return router;
});
