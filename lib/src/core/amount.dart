/// Base units per NULL (eight decimals), as in the null-chain crates.
final BigInt unitsPerCoin = BigInt.from(100000000);

/// Decimal places of a NULL amount.
const amountDecimals = 8;

/// The base units of an amount typed as decimal NULL ("1.5", "0.00000001",
/// "2"), or `null` if it is not one: no sign, no exponent, at most eight
/// decimals, and a `.` or `,` as the separator.
BigInt? parseAmount(String text) {
  final value = text.trim().replaceAll(',', '.');
  final match = RegExp(r'^(\d*)(?:\.(\d*))?$').firstMatch(value);
  if (match == null || value.isEmpty || value == '.') return null;
  final whole = match.group(1)!;
  final fraction = match.group(2) ?? '';
  if (fraction.length > amountDecimals) return null;
  final units =
      BigInt.parse(whole.isEmpty ? '0' : whole) * unitsPerCoin +
      BigInt.parse(fraction.padRight(amountDecimals, '0'));
  return units;
}

/// Base units as decimal NULL, without trailing zeros ("1.5", "0", "21").
String formatAmount(BigInt units) {
  final negative = units.isNegative;
  final abs = units.abs();
  final whole = abs ~/ unitsPerCoin;
  final fraction = (abs % unitsPerCoin)
      .toString()
      .padLeft(amountDecimals, '0')
      .replaceFirst(RegExp(r'0+$'), '');
  final text = fraction.isEmpty ? '$whole' : '$whole.$fraction';
  return negative ? '-$text' : text;
}
