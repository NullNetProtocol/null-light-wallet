import 'package:flutter_test/flutter_test.dart';
import 'package:null_light_wallet/src/core/amount.dart';

void main() {
  test('decimal amounts parse to base units', () {
    expect(parseAmount('1'), BigInt.from(100000000));
    expect(parseAmount('1.5'), BigInt.from(150000000));
    expect(parseAmount('0,25'), BigInt.from(25000000));
    expect(parseAmount('.5'), BigInt.from(50000000));
    expect(parseAmount('3.'), BigInt.from(300000000));
    expect(parseAmount(' 0.00000001 '), BigInt.one);
    expect(parseAmount('21000000'), BigInt.parse('2100000000000000'));
  });

  test('anything else is not an amount', () {
    for (final bad in [
      '',
      '.',
      '-1',
      '+1',
      '1e5',
      '1.000000001',
      '1.2.3',
      'abc',
      '1 000',
    ]) {
      expect(parseAmount(bad), isNull, reason: bad);
    }
  });

  test('base units format without trailing zeros', () {
    expect(formatAmount(BigInt.zero), '0');
    expect(formatAmount(BigInt.one), '0.00000001');
    expect(formatAmount(BigInt.from(150000000)), '1.5');
    expect(formatAmount(BigInt.from(2100000000)), '21');
    expect(formatAmount(BigInt.from(-50000000)), '-0.5');
  });

  test('format and parse round-trip', () {
    for (final units in [0, 1, 99, 12345678, 100000000, 987654321012]) {
      final big = BigInt.from(units);
      expect(parseAmount(formatAmount(big)), big);
    }
  });
}
