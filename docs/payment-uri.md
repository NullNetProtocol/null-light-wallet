# NULL payment URIs

A payment URI asks a wallet to pay an address, optionally a given amount.
NULL Wallet reads one from a QR code, from a pasted text, or from a link
that opens it. It never pays on its own: it fills in the Send screen, and
the user reviews and confirms.

## Syntax

```
null:<address>[?<param>=<value>[&<param>=<value>]...]
```

- **Scheme:** `null`, matched case-insensitively.
- **Address:** a main-network shielded address (bech32m, human-readable
  part `null`, so it starts with `null1`). The wallet decodes it in its
  core. A test-network address (`tnull1…`) is refused.
- **Values:** percent-encoded UTF-8 (RFC 3986). `+` is a literal plus, not
  a space.

| param | meaning |
|---|---|
| `amount` | Decimal NULL: digits, an optional `.` and 1–8 digits after it. No sign, exponent or grouping. Must be greater than 0 and at most the supply. |
| `message` | Shown to the payer, at most 200 characters after decoding. The wallet does not copy it into the payment's encrypted memo; the payer writes the memo. |

- **Names:** matched case-insensitively, so an all-uppercase QR code
  (alphanumeric mode) reads; the address is then lowercased.
- **Empty parts** (`?&amount=1&`) are skipped.
- **Duplicates:** a parameter given twice makes the URI invalid.
- **Unknown parameters:** ignored, unless their name starts with `req-`.
  A `req-` parameter is one the wallet must understand, so an unknown one
  makes the URI invalid.

Examples:

```
null:null1qy…x7
null:null1qy…x7?amount=12.5
null:null1qy…x7?amount=0.00000001&message=Invoice%20%2342
```

## Opening the wallet

- **Android:** NULL Wallet handles the `null:` scheme, so tapping such a
  link or scanning its QR code opens the Send screen with the fields filled.
- **Web wallet:** `https://wallet.nullnet.sh/#pay=<percent-encoded URI>`.
  The URI is in the fragment, so it never reaches the server.
- **QR codes:** the URI as is, uppercase scheme allowed.

## Producing one

The Receive screen can add an amount and a message. The QR code then holds
the URI instead of the bare address.
