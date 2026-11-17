import 'amount.dart';
import 'wallet_core.dart' show AddressValidity;

/// The URI scheme of a NULL payment request (docs/payment-uri.md).
const paymentScheme = 'null';

/// Longest `message`, in characters after decoding.
const maxPaymentMessageChars = 200;

/// Longest payment URI the wallet reads. The longest valid one (address,
/// the largest amount and a 200-character message fully percent-encoded)
/// is far below this; anything longer is not a payment request.
const maxPaymentUriChars = 4096;

/// What a payment URI asks for: an address, and optionally an amount and a
/// message for the payer. Nothing here is a payment yet; the user reviews
/// it on the Send screen.
class PaymentRequest {
  const PaymentRequest(this.address, {this.amount, this.message});

  /// A main-network address, as the core decoded it.
  final String address;

  /// Base units, more than zero; `null` lets the payer choose.
  final BigInt? amount;

  /// Shown to the payer, never put on chain.
  final String? message;

  @override
  bool operator ==(Object other) =>
      other is PaymentRequest &&
      other.address == address &&
      other.amount == amount &&
      other.message == message;

  @override
  int get hashCode => Object.hash(address, amount, message);

  @override
  String toString() => 'PaymentRequest(amount: $amount)';
}

/// A parsed payment URI, or why it is not a valid one.
class PaymentUriResult {
  const PaymentUriResult.ok(PaymentRequest this.request) : error = null;
  const PaymentUriResult.invalid(String this.error) : request = null;

  final PaymentRequest? request;
  final String? error;
}

/// Whether `text` starts like a payment URI (`null:`, any case), so the
/// Send screen reads it as one instead of as an address.
bool looksLikePaymentUri(String text) {
  final value = text.trimLeft();
  return value.length > paymentScheme.length + 1 &&
      value.substring(0, paymentScheme.length + 1).toLowerCase() ==
          '$paymentScheme:';
}

/// Parses `text` as a payment URI. `checkAddress` is the core's address
/// check: Dart never decodes an address itself.
PaymentUriResult parsePaymentUri(
  String text, {
  required AddressValidity Function(String address) checkAddress,
}) {
  final value = text.trim();
  if (value.length > maxPaymentUriChars) {
    return const PaymentUriResult.invalid('The payment link is too long');
  }
  if (!looksLikePaymentUri(value)) {
    return const PaymentUriResult.invalid('Not a NULL payment link');
  }
  final rest = value.substring(paymentScheme.length + 1);
  final question = rest.indexOf('?');
  final rawAddress = question < 0 ? rest : rest.substring(0, question);
  final params = _params(question < 0 ? '' : rest.substring(question + 1));
  if (params == null) {
    return const PaymentUriResult.invalid('The payment link is malformed');
  }
  final address = _address(rawAddress, checkAddress);
  if (address.error != null) return PaymentUriResult.invalid(address.error!);
  final unknown = params.keys.where(
    (name) => name.startsWith('req-') && !_known.contains(name),
  );
  if (unknown.isNotEmpty) {
    return const PaymentUriResult.invalid(
      'The payment link needs a newer wallet',
    );
  }
  BigInt? amount;
  final amountText = params['amount'];
  if (amountText != null) {
    amount = parseUriAmount(amountText);
    if (amount == null) {
      return const PaymentUriResult.invalid(
        'The payment link has an invalid amount',
      );
    }
  }
  final message = params['message'];
  if (message != null && message.runes.length > maxPaymentMessageChars) {
    return const PaymentUriResult.invalid(
      'The payment link has a message that is too long',
    );
  }
  return PaymentUriResult.ok(
    PaymentRequest(
      address.value!,
      amount: amount,
      message: message == null || message.isEmpty ? null : message,
    ),
  );
}

/// Parameters this wallet understands.
const _known = {'amount', 'message'};

/// The decoded parameters of a query, names lowercased (a QR code in
/// alphanumeric mode uppercases the whole URI); `null` if a name repeats
/// or a part is not valid percent-encoded UTF-8. Empty parts are skipped.
Map<String, String>? _params(String query) {
  final params = <String, String>{};
  for (final part in query.split('&')) {
    if (part.isEmpty) continue;
    final eq = part.indexOf('=');
    final name = _decode(eq < 0 ? part : part.substring(0, eq));
    final value = _decode(eq < 0 ? '' : part.substring(eq + 1));
    if (name == null || value == null || name.isEmpty) return null;
    if (params.containsKey(name.toLowerCase())) return null;
    params[name.toLowerCase()] = value;
  }
  return params;
}

/// Percent-decoded UTF-8, `+` kept literal; `null` if malformed.
String? _decode(String text) {
  try {
    return Uri.decodeComponent(text);
  } on FormatException {
    return null;
  } on ArgumentError {
    return null;
  }
}

({String? value, String? error}) _address(
  String raw,
  AddressValidity Function(String) checkAddress,
) {
  final decoded = _decode(raw);
  if (decoded == null || decoded.isEmpty) {
    return (value: null, error: 'The payment link has no address');
  }
  // Bech32m is all lowercase or all uppercase; show it lowercase.
  final address = decoded == decoded.toUpperCase()
      ? decoded.toLowerCase()
      : decoded;
  final check = checkAddress(address);
  if (!check.valid) {
    return (
      value: null,
      error: 'The payment link has an invalid address: ${check.reason}',
    );
  }
  return (value: address, error: null);
}

/// The base units of a URI `amount`: digits, optionally `.` and 1 to 8
/// digits, more than zero and at most [maxMoney]; `null` otherwise. Stricter
/// than [parseAmount], which also takes what people type ("1,5", ".5").
BigInt? parseUriAmount(String text) {
  if (!RegExp(r'^[0-9]+(\.[0-9]{1,8})?$').hasMatch(text)) return null;
  final units = parseAmount(text);
  if (units == null || units <= BigInt.zero || units > maxMoney) return null;
  return units;
}

/// `request` as a payment URI: `null:<address>?amount=…&message=…`.
String formatPaymentUri(PaymentRequest request) {
  final params = [
    if (request.amount != null) 'amount=${formatAmount(request.amount!)}',
    if (request.message != null && request.message!.isNotEmpty)
      'message=${Uri.encodeComponent(request.message!)}',
  ];
  final query = params.isEmpty ? '' : '?${params.join('&')}';
  return '$paymentScheme:${request.address}$query';
}

/// The payment URI in a web wallet fragment (`#pay=<percent-encoded URI>`),
/// or `null` if the fragment has none or has it twice.
String? paymentUriFromFragment(String fragment) {
  final values = fragment
      .split('&')
      .where((part) => part.startsWith('pay='))
      .map((part) => part.substring('pay='.length))
      .toList();
  if (values.length != 1) return null;
  final decoded = _decode(values.single);
  return decoded == null || decoded.isEmpty ? null : decoded;
}
