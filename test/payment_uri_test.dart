import 'package:flutter_test/flutter_test.dart';
import 'package:null_light_wallet/src/core/amount.dart';
import 'package:null_light_wallet/src/core/payment_uri.dart';
import 'package:null_light_wallet/src/core/wallet_core.dart';

/// The fake core's rule: lowercase `null1good…` is an address.
AddressValidity check(String address) => address.startsWith('null1good')
    ? const AddressValidity(true)
    : const AddressValidity(false, 'invalid checksum');

const addr = 'null1goodaddress';

PaymentUriResult parse(String text) =>
    parsePaymentUri(text, checkAddress: check);

PaymentRequest ok(String text) {
  final result = parse(text);
  expect(result.error, isNull, reason: text);
  return result.request!;
}

void expectInvalid(String text, String error) {
  final result = parse(text);
  expect(result.request, isNull, reason: text);
  expect(result.error, contains(error), reason: text);
}

void main() {
  group('parsePaymentUri', () {
    test('a bare address', () {
      expect(ok('null:$addr'), const PaymentRequest(addr));
    });

    test('amount and message', () {
      expect(
        ok('null:$addr?amount=12.5&message=Invoice%20%2342'),
        PaymentRequest(
          addr,
          amount: BigInt.from(1250000000),
          message: 'Invoice #42',
        ),
      );
    });

    test('the scheme is case-insensitive and whitespace is trimmed', () {
      expect(ok('  NULL:$addr\n').address, addr);
      expect(ok('Null:$addr').address, addr);
    });

    test('an all-uppercase URI, as a QR code may hold it, is read', () {
      final request = ok('NULL:${addr.toUpperCase()}?AMOUNT=1&MESSAGE=HI');
      expect(request.address, addr);
      expect(request.amount, unitsPerCoin);
      expect(request.message, 'HI');
    });

    test('plus is a literal plus', () {
      expect(ok('null:$addr?message=a+b').message, 'a+b');
    });

    test('percent-encoded UTF-8 is decoded', () {
      expect(ok('null:$addr?message=caf%C3%A9%20%E2%9C%93').message, 'café ✓');
    });

    test('an empty message counts as none', () {
      expect(ok('null:$addr?message=').message, isNull);
    });

    test('a message of exactly 200 characters is kept', () {
      final message = 'é' * maxPaymentMessageChars;
      expect(
        ok('null:$addr?message=${Uri.encodeComponent(message)}').message,
        message,
      );
    });

    test('a longer message is refused', () {
      expectInvalid(
        'null:$addr?message=${'a' * (maxPaymentMessageChars + 1)}',
        'too long',
      );
    });

    test('unknown parameters are ignored, req- ones refused', () {
      expect(ok('null:$addr?label=shop&amount=1').amount, unitsPerCoin);
      expectInvalid('null:$addr?req-expiry=1', 'newer wallet');
      expectInvalid('null:$addr?REQ-EXPIRY=1', 'newer wallet');
    });

    test('a parameter given twice is refused', () {
      expectInvalid('null:$addr?amount=1&amount=2', 'malformed');
      expectInvalid('null:$addr?amount=1&Amount=1', 'malformed');
      expectInvalid('null:$addr?label=a&label=b', 'malformed');
    });

    test('empty parts are skipped', () {
      expect(ok('null:$addr?&amount=1&').amount, unitsPerCoin);
      expect(ok('null:$addr?').amount, isNull);
    });

    test('bad percent-encoding is refused', () {
      expectInvalid('null:$addr?message=%E2%9C', 'malformed');
      expectInvalid('null:$addr?message=%zz', 'malformed');
      expectInvalid('null:$addr?=1', 'malformed');
    });

    test('the address goes through the core', () {
      expectInvalid('null:null1bad', 'invalid address: invalid checksum');
      expectInvalid('null:tnull1goodaddress', 'invalid address');
      expectInvalid('null:', 'Not a NULL payment link');
      expectInvalid('null:?amount=1', 'no address');
    });

    test('mixed-case addresses are passed on as they are', () {
      // The core refuses mixed case; the fake rule sees the original text.
      expectInvalid('null:Null1goodaddress', 'invalid address');
    });

    test('anything that is not a payment URI', () {
      expectInvalid(addr, 'Not a NULL payment link');
      expectInvalid('bitcoin:$addr', 'Not a NULL payment link');
      expectInvalid('null', 'Not a NULL payment link');
      expectInvalid('', 'Not a NULL payment link');
    });

    test('a very long text is refused before parsing', () {
      expectInvalid('null:$addr?x=${'a' * maxPaymentUriChars}', 'too long');
    });

    test('amounts follow the strict grammar', () {
      for (final bad in [
        '0',
        '0.0',
        '-1',
        '+1',
        '1e3',
        '1.',
        '.5',
        '1,5',
        '1.123456789',
        ' 1',
        '1 000',
        '',
        '21000000.00000001',
        '99999999999999999999',
      ]) {
        expectInvalid(
          'null:$addr?amount=${Uri.encodeComponent(bad)}',
          'invalid amount',
        );
      }
      expect(ok('null:$addr?amount=0.00000001').amount, BigInt.one);
      expect(ok('null:$addr?amount=21000000').amount, maxMoney);
      expect(ok('null:$addr?amount=007').amount, unitsPerCoin * BigInt.from(7));
    });
  });

  group('looksLikePaymentUri', () {
    test('only a null: prefix with something after it', () {
      expect(looksLikePaymentUri('null:x'), isTrue);
      expect(looksLikePaymentUri('  NULL:x'), isTrue);
      expect(looksLikePaymentUri('null:'), isFalse);
      expect(looksLikePaymentUri('null1abc'), isFalse);
      expect(looksLikePaymentUri('nul'), isFalse);
    });
  });

  group('formatPaymentUri', () {
    test('a bare address', () {
      expect(formatPaymentUri(const PaymentRequest(addr)), 'null:$addr');
    });

    test('amount and message, encoded', () {
      expect(
        formatPaymentUri(
          PaymentRequest(
            addr,
            amount: BigInt.from(150000000),
            message: 'Rent & 50% + café',
          ),
        ),
        'null:$addr?amount=1.5&message=Rent%20%26%2050%25%20%2B%20caf%C3%A9',
      );
    });

    test('an empty message is left out', () {
      expect(
        formatPaymentUri(PaymentRequest(addr, amount: BigInt.one, message: '')),
        'null:$addr?amount=0.00000001',
      );
    });

    test('what it writes, it reads back', () {
      for (final request in [
        const PaymentRequest(addr),
        PaymentRequest(addr, amount: maxMoney),
        const PaymentRequest(addr, message: 'a+b=c&d?#'),
        PaymentRequest(addr, amount: BigInt.from(42), message: '✓ ok'),
      ]) {
        expect(ok(formatPaymentUri(request)), request);
      }
    });
  });

  group('paymentUriFromFragment', () {
    test('reads one pay= value', () {
      final uri = 'null:$addr?amount=1&message=a%20b';
      expect(paymentUriFromFragment('pay=${Uri.encodeComponent(uri)}'), uri);
      expect(paymentUriFromFragment('x=1&pay=null%3Aa'), 'null:a');
    });

    test('none, twice, empty or malformed is nothing', () {
      expect(paymentUriFromFragment(''), isNull);
      expect(paymentUriFromFragment('k=1'), isNull);
      expect(paymentUriFromFragment('pay=a&pay=b'), isNull);
      expect(paymentUriFromFragment('pay='), isNull);
      expect(paymentUriFromFragment('pay=%E2'), isNull);
    });
  });

  group('parseUriAmount', () {
    test('the cap is the supply', () {
      expect(parseUriAmount('21000000'), maxMoney);
      expect(parseUriAmount('21000000.00000001'), isNull);
    });
  });
}
