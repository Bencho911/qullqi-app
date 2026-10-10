import 'package:file_picker/file_picker.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:qullqi/core/clock/clock.dart';
import 'package:qullqi/core/data/latency.dart';
import 'package:qullqi/features/accounts/domain/account.dart';
import 'package:qullqi/features/statements/domain/statement.dart';
import 'package:qullqi/features/transactions/data/ledger.dart';
import 'package:qullqi/features/transactions/data/transactions_repository.dart';
import 'package:qullqi/features/transactions/domain/transaction.dart';

/// Abre el selector de archivos del teléfono.
abstract interface class StatementPicker {
  /// `null` si la persona cerró el selector sin elegir.
  Future<StatementFile?> pick();
}

final statementPickerProvider = Provider<StatementPicker>(
  (ref) => const DeviceStatementPicker(),
);

class DeviceStatementPicker implements StatementPicker {
  const DeviceStatementPicker();

  @override
  Future<StatementFile?> pick() async {
    final file = await FilePicker.pickFile(
      dialogTitle: 'Elige tu extracto',
      type: FileType.custom,
      allowedExtensions: StatementFormat.extensions,
    );
    if (file == null) return null;
    final bytes = await file.xFile.readAsBytes();
    return StatementFile(name: file.name, bytes: bytes);
  }
}

/// Convierte un extracto en renglones.
abstract interface class StatementReader {
  Future<List<StatementLine>> read(StatementFile file);
}

final statementReaderProvider = Provider<StatementReader>(
  (ref) => DefaultStatementReader(
    server: MockServerStatementReader(
      now: ref.watch(clockProvider),
      latency: ref.watch(mockLatencyProvider),
    ),
  ),
);

/// El CSV se lee en el teléfono. El PDF y el Excel van al servidor, que
/// tiene los lectores de cada banco.
class DefaultStatementReader implements StatementReader {
  const DefaultStatementReader({required this.server});

  final StatementReader server;

  @override
  Future<List<StatementLine>> read(StatementFile file) async {
    final format = file.format;
    if (format == null) {
      throw const StatementException(StatementProblem.unsupported);
    }
    if (file.bytes.length > maxStatementBytes) {
      throw const StatementException(StatementProblem.tooLarge);
    }
    if (file.bytes.isEmpty) {
      throw const StatementException(StatementProblem.noMovements);
    }
    return switch (format) {
      StatementFormat.csv => parseCsvStatement(decodeStatementText(file.bytes)),
      StatementFormat.excel || StatementFormat.pdf => await server.read(file),
    };
  }
}

/// Lector del servidor simulado: devuelve movimientos de ejemplo del mes
/// pasado. Un PDF cifrado se rechaza como lo haría el servidor.
class MockServerStatementReader implements StatementReader {
  MockServerStatementReader({required this.now, required this.latency});

  final DateTime Function() now;
  final Duration latency;

  @override
  Future<List<StatementLine>> read(StatementFile file) async {
    await Future<void>.delayed(latency * 3);
    // Los PDF cifrados declaran /Encrypt en su diccionario.
    if (file.format == StatementFormat.pdf &&
        String.fromCharCodes(file.bytes).contains('/Encrypt')) {
      throw const StatementException(StatementProblem.protected);
    }
    final today = dateOnly(now());
    DateTime ago(int d) => today.subtract(Duration(days: d));
    return [
      StatementLine(date: ago(34), description: 'Arriendo', amount: -1200000),
      StatementLine(
        date: ago(36),
        description: 'Compra en Carulla Pepe Sierra',
        amount: -186300,
      ),
      StatementLine(date: ago(38), description: 'Uber', amount: -23400),
      StatementLine(date: ago(40), description: 'Netflix.com', amount: -38900),
      StatementLine(
        date: ago(41),
        description: 'Transferencia de Laura Gómez',
        amount: 150000,
      ),
      StatementLine(
        date: ago(45),
        description: 'Droguería Cruz Verde',
        amount: -42700,
      ),
    ];
  }
}

/// Guarda los renglones elegidos como movimientos de la cuenta.
///
/// No cambia el saldo: el extracto cuenta el pasado, y el saldo de hoy ya
/// los incluye (lo trae el banco o lo escribió la persona).
class StatementImporter {
  StatementImporter({required this.transactions, required this.ledger});

  final TransactionsRepository transactions;
  final Ledger ledger;

  Future<int> import(Account account, List<StatementLine> lines) async {
    for (final l in lines) {
      final transfer = looksLikeTransfer(l);
      await transactions.add(
        Transaction(
          id: ledger.newId('x'),
          title: l.description,
          amount: l.amount.abs(),
          kind: l.amount > 0 ? TransactionKind.income : TransactionKind.expense,
          accountId: account.id,
          categoryId: guessCategory(l),
          ownership: account.ownership,
          date: l.date,
          needsReview: transfer,
          source: TransactionSource.imported,
        ),
      );
    }
    return lines.length;
  }
}

final statementImporterProvider = Provider<StatementImporter>(
  (ref) => StatementImporter(
    transactions: ref.watch(transactionsRepositoryProvider),
    ledger: ref.watch(ledgerProvider),
  ),
);
