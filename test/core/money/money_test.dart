import 'package:flutter_test/flutter_test.dart';
import 'package:qullqi/core/money/money.dart';

void main() {
  group('Cop.format', () {
    test('usa punto de miles y signo de pesos', () {
      expect(Cop.format(1200000), r'$1.200.000');
      expect(Cop.format(0), r'$0');
      expect(Cop.format(999), r'$999');
    });

    test('pone el menos antes del signo de pesos', () {
      expect(Cop.format(-85400), r'-$85.400');
    });

    test('agrega + solo si se pide y el valor es positivo', () {
      expect(Cop.format(2500000, signed: true), r'+$2.500.000');
      expect(Cop.format(0, signed: true), r'$0');
      expect(Cop.format(-1, signed: true), r'-$1');
    });
  });

  group('Cop.compact', () {
    test('millones con una decimal y coma', () {
      expect(Cop.compact(1250000), r'$1,3 M');
      expect(Cop.compact(2000000), r'$2 M');
      expect(Cop.compact(15400000), r'$15 M');
    });

    test('miles redondeados', () {
      expect(Cop.compact(85400), r'$85 mil');
      expect(Cop.compact(-85400), r'-$85 mil');
    });

    test('montos pequeños sin abreviar', () {
      expect(Cop.compact(950), r'$950');
    });
  });

  test('Cop.spoken se lee bien en voz alta', () {
    expect(Cop.spoken(-85400), 'menos 85.400 pesos');
    expect(Cop.spoken(1200000), '1.200.000 pesos');
  });

  test('Cop.percent usa coma decimal', () {
    expect(Cop.percent(3.7, decimals: 1), '3,7 %');
    expect(Cop.percent(78), '78 %');
  });

  group('AmountInput', () {
    test('escribe dígitos y borra el último', () {
      var d = '';
      for (final k in ['8', '5', '4', '0', '0']) {
        d = AmountInput.press(d, k);
      }
      expect(d, '85400');
      expect(AmountInput.value(d), 85400);
      expect(AmountInput.press(d, 'del'), '8540');
      expect(AmountInput.press('', 'del'), '');
    });

    test('no deja ceros a la izquierda', () {
      expect(AmountInput.press('', '0'), '');
      expect(AmountInput.press('', '000'), '');
      expect(AmountInput.press('5', '000'), '5000');
    });

    test('al llegar al límite la tecla no cambia lo escrito', () {
      final full = '9' * AmountInput.maxDigits;
      expect(AmountInput.press(full, '1'), full);
      final almost = '9' * (AmountInput.maxDigits - 1);
      expect(AmountInput.press(almost, '000'), almost);
    });
  });
}
