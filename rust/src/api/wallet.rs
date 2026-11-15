//! The wallet itself: create, restore, unlock, sync from compact blocks,
//! balance, activity and send, over `null-wallet`. Dart drives the network
//! (the light server) and storage of the browser image; everything that
//! touches a key happens here.
//!
//! On Android the wallet is a file in the app's private directory. In the
//! browser it is a byte image ([`LightWallet::image`]) that Dart keeps in
//! `IndexedDB`; both hold the same sealed records.

// The bridge hands every argument over as an owned value from Dart.
#![allow(clippy::needless_pass_by_value)]

use std::sync::{Mutex, OnceLock};

use anyhow::{anyhow, bail, Context as _, Result};
use null_chain::genesis::genesis;
use null_chain::params::ChainParams;
use null_circuit::proof::ProvingKey;
use null_protocol::address::{Address, AddressPrefix};
use null_protocol::amount::{Amount, COIN};
use null_protocol::block::BlockHash;
use null_protocol::bytes::Encodable;
use null_protocol::compact::CompactBlock;
use null_protocol::memo::Memo;
use null_wallet::operations::{Operation, OperationStatus};
use null_wallet::scan::OwnedNote;
use null_wallet::seed::{AccountPhrase, SeedPhrase};
use null_wallet::spend::{build_payments, quote_payments, Payment};
use null_wallet::wallet::{Buffer, Wallet};
use rand_core::OsRng;

/// The account every NULL wallet derives from a phrase, so a phrase works
/// in the desktop wallet and here alike.
const ACCOUNT: u32 = 0;

/// Confirmations a note needs before it is spent, as on the desktop.
const MIN_CONFIRMATIONS: u32 = 1;

/// Base units per coin, for Dart's amount formatting.
#[flutter_rust_bridge::frb(sync)]
#[must_use]
pub fn units_per_coin() -> u64 {
    COIN
}

/// Main-network parameters.
fn params() -> &'static ChainParams {
    static PARAMS: OnceLock<ChainParams> = OnceLock::new();
    PARAMS.get_or_init(ChainParams::mainnet)
}

/// The main network's genesis hash: wallets refuse files of other chains.
fn genesis_hash() -> BlockHash {
    static HASH: OnceLock<BlockHash> = OnceLock::new();
    *HASH.get_or_init(|| genesis(params()).hash())
}

/// The genesis hash as lowercase hex, for the server check in Dart.
#[flutter_rust_bridge::frb(sync)]
#[must_use]
pub fn main_genesis() -> String {
    genesis_hash().to_string()
}

/// The proving key, built once per launch (it takes seconds).
fn proving_key() -> Result<&'static ProvingKey> {
    static PK: OnceLock<ProvingKey> = OnceLock::new();
    static BUILDING: Mutex<()> = Mutex::new(());
    if let Some(pk) = PK.get() {
        return Ok(pk);
    }
    let _guard = BUILDING.lock().map_err(|_| anyhow!("proving key lock"))?;
    if let Some(pk) = PK.get() {
        return Ok(pk);
    }
    let pk = ProvingKey::build().context("building the proving key")?;
    Ok(PK.get_or_init(|| pk))
}

/// Builds the proving key ahead of the first send, off the UI thread.
///
/// # Errors
/// Fails if the key cannot be generated.
pub fn warm_up_proving() -> Result<()> {
    proving_key().map(|_| ())
}

/// A new 24-word recovery phrase. Shown once, then kept sealed in the wallet.
///
/// # Errors
/// Fails without system randomness.
#[flutter_rust_bridge::frb(sync)]
pub fn generate_phrase() -> Result<String> {
    Ok(SeedPhrase::generate(&mut OsRng)?.words().to_string())
}

/// Why `words` is not a recovery phrase, or `None` if it is one.
#[flutter_rust_bridge::frb(sync)]
#[must_use]
pub fn check_phrase(words: String) -> Option<String> {
    SeedPhrase::parse(&normalize(&words))
        .err()
        .map(|e| e.to_string())
}

/// Lowercase words separated by single spaces, as typed or pasted.
fn normalize(words: &str) -> String {
    words
        .split_whitespace()
        .map(str::to_lowercase)
        .collect::<Vec<_>>()
        .join(" ")
}

fn account_phrase(words: &str) -> Result<AccountPhrase> {
    Ok(AccountPhrase {
        phrase: SeedPhrase::parse(&normalize(words))?,
        account: ACCOUNT,
    })
}

fn require_passphrase(passphrase: &str) -> Result<()> {
    if passphrase.is_empty() {
        bail!("choose a wallet passphrase");
    }
    Ok(())
}

/// Parses a main-network address.
fn parse_address(text: &str) -> Result<Address> {
    Address::decode(text.trim(), AddressPrefix::Main).map_err(|e| anyhow!("invalid address: {e}"))
}

/// The balance, in base units.
pub struct Balance {
    /// Every unspent note.
    pub total: u64,
    /// What a send can use now: unspent, confirmed and not set aside for
    /// a payment still on its way.
    pub spendable: u64,
    /// Set aside for payments not yet mined.
    pub pending: u64,
}

/// What one sync step changed.
#[derive(Debug)]
pub struct SyncStep {
    /// Blocks scanned.
    pub blocks: u32,
    /// Notes found.
    pub found: u32,
    /// Our notes the blocks spent.
    pub spent: u32,
    /// The next height to ask the server for.
    pub next_height: u32,
}

/// What an activity row is.
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum ActivityKind {
    /// A payment to the wallet.
    Received,
    /// A payment the wallet made.
    Sent,
    /// Change back from a payment the wallet made.
    Change,
}

/// Where a sent payment is.
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum SendState {
    /// Built and handed to the server, not mined yet.
    Pending,
    /// Mined.
    Confirmed,
    /// Given up; its notes are free again.
    Failed,
}

/// One row of the activity list.
pub struct ActivityItem {
    /// What it is.
    pub kind: ActivityKind,
    /// Base units received or sent (sent excludes the fee).
    pub amount: u64,
    /// The block height, once mined.
    pub height: Option<u32>,
    /// Seconds since the epoch the send was made; `None` for notes.
    pub created_at: Option<u64>,
    /// For sends: where it is.
    pub state: Option<SendState>,
    /// For sends: the recipient address.
    pub address: Option<String>,
    /// For sends: the transaction id.
    pub txid: Option<String>,
    /// The memo, when it is text (sends; notes in light mode have none).
    pub memo: Option<String>,
    /// For failed sends: why.
    pub error: Option<String>,
    /// For sends this wallet has no record of (restored from the phrase):
    /// `amount` is what left the wallet, the fee included, because the
    /// chain does not say how it divides.
    pub includes_fee: bool,
}

/// A send built and recorded, ready to hand to the light server.
pub struct PreparedSend {
    /// The wallet's id for it, to report a rejection.
    pub operation: u64,
    /// The transaction id, lowercase hex.
    pub txid: String,
    /// The transaction bytes for `sendrawtransaction`.
    pub transaction: Vec<u8>,
    /// The fee paid, in base units.
    pub fee: u64,
}

/// An unlocked wallet.
#[flutter_rust_bridge::frb(opaque)]
pub struct LightWallet {
    wallet: Wallet,
    /// The image the wallet lives in, in the browser; `None` for a file.
    buffer: Option<Buffer>,
}

impl LightWallet {
    /// Creates a wallet file at `path` from `words` under `passphrase`.
    ///
    /// # Errors
    /// Fails if the file exists, the phrase is invalid or the passphrase
    /// is empty.
    pub fn create_file(path: String, words: String, passphrase: String) -> Result<Self> {
        require_passphrase(&passphrase)?;
        if std::path::Path::new(&path).exists() {
            bail!("a wallet already exists here");
        }
        let phrase = account_phrase(&words)?;
        let wallet = Wallet::create_from_phrase(
            &path,
            &phrase,
            genesis_hash(),
            passphrase.as_bytes(),
            &mut OsRng,
        )?;
        Ok(Self {
            wallet,
            buffer: None,
        })
    }

    /// Unlocks the wallet file at `path`.
    ///
    /// # Errors
    /// Fails on a wrong passphrase or a file of another network.
    pub fn open_file(path: String, passphrase: String) -> Result<Self> {
        let wallet = Wallet::open(&path, genesis_hash(), passphrase.as_bytes())?;
        Ok(Self {
            wallet,
            buffer: None,
        })
    }

    /// Creates a wallet in a new byte image (the browser).
    ///
    /// # Errors
    /// Fails if the phrase is invalid or the passphrase is empty.
    pub fn create_image(words: String, passphrase: String) -> Result<Self> {
        require_passphrase(&passphrase)?;
        let phrase = account_phrase(&words)?;
        let buffer = Buffer::new();
        let wallet = Wallet::create_from_phrase_in(
            &buffer,
            &phrase,
            genesis_hash(),
            passphrase.as_bytes(),
            &mut OsRng,
        )?;
        Ok(Self {
            wallet,
            buffer: Some(buffer),
        })
    }

    /// Unlocks a byte image saved from [`Self::image`].
    ///
    /// # Errors
    /// Fails on a wrong passphrase, a damaged image or another network.
    pub fn open_image(image: Vec<u8>, passphrase: String) -> Result<Self> {
        let buffer = Buffer::from_bytes(image);
        let wallet = Wallet::open_in(&buffer, genesis_hash(), passphrase.as_bytes())?;
        Ok(Self {
            wallet,
            buffer: Some(buffer),
        })
    }

    /// The byte image to save after a change, or `None` for a file wallet.
    ///
    /// # Errors
    /// Fails only if the image is unreadable.
    #[flutter_rust_bridge::frb(sync)]
    pub fn image(&self) -> Result<Option<Vec<u8>>> {
        self.buffer
            .as_ref()
            .map(|b| b.to_bytes().map_err(Into::into))
            .transpose()
    }

    /// The recovery phrase, after checking `passphrase` again.
    ///
    /// # Errors
    /// Fails on a wrong passphrase or a wallet without a stored phrase.
    pub fn reveal_phrase(&self, passphrase: String) -> Result<String> {
        let phrase = self
            .wallet
            .reveal_seed_phrase(passphrase.as_bytes())?
            .ok_or_else(|| anyhow!("this wallet keeps no recovery phrase"))?;
        Ok(phrase.phrase.words().to_string())
    }

    /// The next height to scan.
    ///
    /// # Errors
    /// Fails on a database error.
    #[flutter_rust_bridge::frb(sync)]
    pub fn next_height(&self) -> Result<u32> {
        Ok(self.wallet.next_height()?)
    }

    /// The hash the wallet scanned at `height`, to compare with the
    /// server's and detect a reorganization.
    ///
    /// # Errors
    /// Fails on a database error.
    #[flutter_rust_bridge::frb(sync)]
    pub fn scanned_hash(&self, height: u32) -> Result<Option<String>> {
        Ok(self.wallet.scanned_hash(height)?.map(|h| h.to_string()))
    }

    /// Scans consecutive compact blocks starting at [`Self::next_height`].
    ///
    /// # Errors
    /// Fails on a block that does not decode or is not the next one; the
    /// blocks before it stay scanned.
    pub fn apply_blocks(&self, blocks: Vec<Vec<u8>>) -> Result<SyncStep> {
        let mut step = SyncStep {
            blocks: 0,
            found: 0,
            spent: 0,
            next_height: self.wallet.next_height()?,
        };
        for bytes in &blocks {
            let block = CompactBlock::from_slice(bytes)?;
            if block.height != step.next_height {
                bail!(
                    "server sent block {} when {} was next",
                    block.height,
                    step.next_height
                );
            }
            let report = self.wallet.scan_compact(&block)?;
            step.blocks = step.blocks.saturating_add(1);
            step.found = step.found.saturating_add(u32::try_from(report.found)?);
            step.spent = step.spent.saturating_add(u32::try_from(report.spent)?);
            step.next_height = self.wallet.next_height()?;
        }
        self.settle_sends()?;
        Ok(step)
    }

    /// Forgets every block above `height` after a reorganization.
    ///
    /// # Errors
    /// Fails on a database error.
    pub fn rollback_to(&self, height: u32) -> Result<()> {
        self.wallet.rollback_to(height)?;
        self.settle_sends()
    }

    /// The balance now.
    ///
    /// # Errors
    /// Fails on a database error.
    #[flutter_rust_bridge::frb(sync)]
    pub fn balance(&self) -> Result<Balance> {
        let unspent = self.wallet.unspent()?;
        let locked = self.wallet.locked_positions()?;
        let max_height = self.max_note_height()?;
        let sum = |notes: &mut dyn Iterator<Item = &OwnedNote>| {
            notes.fold(0u64, |acc, n| acc.saturating_add(n.note.value().raw()))
        };
        Ok(Balance {
            total: sum(&mut unspent.iter()),
            spendable: sum(&mut unspent
                .iter()
                .filter(|n| !locked.contains(&n.position) && n.height <= max_height)),
            pending: sum(&mut unspent.iter().filter(|n| locked.contains(&n.position))),
        })
    }

    /// The address to show on the Receive screen: the newest one handed
    /// out, or a first one.
    ///
    /// # Errors
    /// Fails on a database error.
    pub fn receive_address(&self) -> Result<String> {
        let newest = self
            .wallet
            .addresses()?
            .into_iter()
            .max_by_key(|(index, _, _)| *index)
            .map(|(_, address, _)| address);
        let address = match newest {
            Some(address) => address,
            None => self.wallet.new_address("")?.1,
        };
        Ok(address.encode(AddressPrefix::Main))
    }

    /// A new, unused address.
    ///
    /// # Errors
    /// Fails on a database error.
    pub fn new_address(&self) -> Result<String> {
        Ok(self.wallet.new_address("")?.1.encode(AddressPrefix::Main))
    }

    /// Notes received and payments sent, newest first, change marked.
    ///
    /// # Errors
    /// Fails on a database error.
    #[flutter_rust_bridge::frb(sync)]
    pub fn activity(&self) -> Result<Vec<ActivityItem>> {
        let change_address = self.wallet.keys().default_address()?;
        let notes: Vec<NoteView> = self
            .wallet
            .notes()?
            .iter()
            .map(|n| NoteView::of(n, &change_address))
            .collect();
        Ok(activity_items(&notes, &self.wallet.operations()?))
    }

    /// The fee a payment of `amount` base units to `to` would pay now.
    ///
    /// # Errors
    /// Fails on a bad address or amount, or insufficient funds.
    pub fn quote(&self, to: String, amount: u64) -> Result<u64> {
        let payment = payment(&to, amount, "")?;
        let quote = quote_payments(
            &self.wallet,
            &[payment],
            &self.wallet.locked_positions()?,
            self.max_note_height()?,
        )
        .map_err(explain)?;
        Ok(quote.fee.raw())
    }

    /// Builds, proves and records a payment; Dart then submits
    /// [`PreparedSend::transaction`]. Its notes stay set aside until it is
    /// mined or [`Self::send_rejected`] is called.
    ///
    /// # Errors
    /// Fails on a bad address, amount or memo, insufficient funds, or a
    /// proving error; nothing is recorded then.
    pub fn prepare_send(
        &self,
        to: String,
        amount: u64,
        memo: String,
        created_at: u64,
    ) -> Result<PreparedSend> {
        let payment = payment(&to, amount, &memo)?;
        let tip = self.wallet.next_height()?;
        let built = build_payments(
            &self.wallet,
            std::slice::from_ref(&payment),
            proving_key()?,
            params().branch_at(tip),
            &self.wallet.locked_positions()?,
            self.max_note_height()?,
            &mut OsRng,
        )
        .map_err(explain)?;
        let bytes = built.transaction.to_vec();
        let txid = built.transaction.txid();
        let fee = fee_of(&built.transaction)?;
        let mut op = self
            .wallet
            .add_operation(vec![payment], MIN_CONFIRMATIONS, created_at)?;
        op.locked = built.spent;
        op.attempts = 1;
        op.record_transaction(bytes.clone());
        op.status = OperationStatus::Submitted {
            txid,
            built_at: tip,
        };
        self.wallet.put_operation(&op)?;
        Ok(PreparedSend {
            operation: op.id,
            txid: txid.to_string(),
            transaction: bytes,
            fee,
        })
    }

    /// Marks a send the server refused as failed, freeing its notes. Only
    /// for a definite rejection: if the reply was lost, the transaction may
    /// still be mined and must stay pending.
    ///
    /// # Errors
    /// Fails on an unknown operation or one that is no longer pending.
    pub fn send_rejected(&self, operation: u64, reason: String) -> Result<()> {
        let previous = self.wallet.operation(operation)?;
        if !matches!(previous.status, OperationStatus::Submitted { .. }) {
            bail!("payment #{operation} is not waiting to be mined");
        }
        let mut op = previous.clone();
        op.status = OperationStatus::Failed(reason);
        if !self.wallet.compare_and_swap_operation(&previous, &op)? {
            bail!("payment #{operation} changed; try again");
        }
        Ok(())
    }

    /// Transactions of sends still waiting to be mined, to submit again
    /// after the app restarts or the server forgot them.
    ///
    /// # Errors
    /// Fails on a database error.
    #[flutter_rust_bridge::frb(sync)]
    pub fn pending_transactions(&self) -> Result<Vec<Vec<u8>>> {
        Ok(self
            .wallet
            .operations()?
            .into_iter()
            .filter(|op| matches!(op.status, OperationStatus::Submitted { .. }))
            .filter_map(|op| op.transaction)
            .collect())
    }

    /// Notes above this height have too few confirmations to spend.
    fn max_note_height(&self) -> Result<u32> {
        Ok(self
            .wallet
            .next_height()?
            .saturating_sub(MIN_CONFIRMATIONS.max(1)))
    }

    /// Moves sends whose notes a scanned block spent to confirmed, and
    /// confirmed sends a rollback un-mined back to pending.
    fn settle_sends(&self) -> Result<()> {
        let notes = self.wallet.notes()?;
        for previous in self.wallet.operations()? {
            if let Some(status) = settled(&previous, &notes) {
                let mut op = previous.clone();
                op.status = status;
                self.wallet.compare_and_swap_operation(&previous, &op)?;
            }
        }
        Ok(())
    }
}

/// The new status of `op` given the wallet's notes, if it changed.
fn settled(op: &Operation, notes: &[OwnedNote]) -> Option<OperationStatus> {
    let spent_at = op
        .locked
        .iter()
        .filter_map(|p| notes.iter().find(|n| n.position == *p))
        .find_map(|n| n.spent_at);
    match (&op.status, spent_at) {
        (OperationStatus::Submitted { txid, .. }, Some(height)) => {
            Some(OperationStatus::Confirmed {
                txid: *txid,
                height,
            })
        }
        (OperationStatus::Confirmed { txid, height }, None) => Some(OperationStatus::Submitted {
            txid: *txid,
            built_at: *height,
        }),
        _ => None,
    }
}

/// A wallet error as the Send screen shows it: amounts in NULL.
fn explain(error: null_wallet::Error) -> anyhow::Error {
    match error {
        null_wallet::Error::InsufficientFunds { have, need } => anyhow!(
            "not enough funds: {} NULL needed with the fee, {} NULL spendable",
            coins(need),
            coins(have)
        ),
        other => other.into(),
    }
}

/// Base units as decimal NULL without trailing zeros.
fn coins(units: u64) -> String {
    let whole = units / COIN;
    let fraction = format!("{:08}", units % COIN);
    let fraction = fraction.trim_end_matches('0');
    if fraction.is_empty() {
        whole.to_string()
    } else {
        format!("{whole}.{fraction}")
    }
}

fn payment(to: &str, amount: u64, memo: &str) -> Result<Payment> {
    if amount == 0 {
        bail!("enter an amount above zero");
    }
    Ok(Payment {
        recipient: parse_address(to)?,
        amount: Amount::from_raw(amount)?,
        memo: Memo::from_text(memo)?,
    })
}

/// The fee a built transaction pays.
fn fee_of(tx: &null_protocol::transaction::Transaction) -> Result<u64> {
    Ok(null_protocol::consensus::fee_for_actions(tx.actions().len())?.raw())
}

/// What the activity list needs from one owned note.
#[derive(Clone, Debug, PartialEq, Eq)]
struct NoteView {
    value: u64,
    height: u32,
    spent_at: Option<u32>,
    /// Paid to the wallet's default address, where its change goes.
    to_change: bool,
    memo: Option<String>,
}

impl NoteView {
    fn of(note: &OwnedNote, change_address: &Address) -> Self {
        Self {
            value: note.note.value().raw(),
            height: note.height,
            spent_at: note.spent_at,
            to_change: note.note.recipient() == change_address,
            memo: note
                .memo
                .to_text()
                .filter(|t| !t.is_empty())
                .map(str::to_owned),
        }
    }
}

/// Notes and recorded sends as the activity list, newest first.
///
/// A send leaves two traces in the chain a wallet can see: its notes are
/// spent at the height it was mined, and its change comes back to the
/// default address in that same block. So a note to the default address
/// mined where the wallet spent is change, whether or not this wallet made
/// the send. A send it made has its record (recipient, amount, memo). One it
/// has no record of, because the wallet was restored from its phrase, is
/// shown from those traces: what was spent minus the change, fee included.
fn activity_items(notes: &[NoteView], operations: &[Operation]) -> Vec<ActivityItem> {
    let recorded: Vec<u32> = operations
        .iter()
        .filter_map(|op| match op.status {
            OperationStatus::Confirmed { height, .. } => Some(height),
            _ => None,
        })
        .collect();
    let mut spend_heights: Vec<u32> = notes.iter().filter_map(|n| n.spent_at).collect();
    spend_heights.sort_unstable();
    spend_heights.dedup();
    let is_change = |n: &NoteView| n.to_change && spend_heights.contains(&n.height);

    let received = notes.iter().map(|n| ActivityItem {
        kind: if is_change(n) {
            ActivityKind::Change
        } else {
            ActivityKind::Received
        },
        amount: n.value,
        height: Some(n.height),
        created_at: None,
        state: None,
        address: None,
        txid: None,
        memo: n.memo.clone(),
        error: None,
        includes_fee: false,
    });
    let unrecorded = spend_heights
        .iter()
        .filter(|h| !recorded.contains(h))
        .filter_map(|&height| {
            let sum = |f: &dyn Fn(&NoteView) -> bool| {
                notes
                    .iter()
                    .filter(|n| f(n))
                    .fold(0u64, |a, n| a.saturating_add(n.value))
            };
            let spent = sum(&|n| n.spent_at == Some(height));
            let change = sum(&|n| n.height == height && is_change(n));
            let out = spent.saturating_sub(change);
            (out > 0).then_some(ActivityItem {
                kind: ActivityKind::Sent,
                amount: out,
                height: Some(height),
                created_at: None,
                state: Some(SendState::Confirmed),
                address: None,
                txid: None,
                memo: None,
                error: None,
                includes_fee: true,
            })
        });
    let mut items: Vec<ActivityItem> = received
        .chain(unrecorded)
        .chain(operations.iter().filter_map(operation_item))
        .collect();
    items.sort_by_key(|item| std::cmp::Reverse(item.height.unwrap_or(u32::MAX)));
    items
}

fn operation_item(op: &Operation) -> Option<ActivityItem> {
    let (state, height, txid, error) = match &op.status {
        OperationStatus::Submitted { txid, .. } => (SendState::Pending, None, Some(txid), None),
        OperationStatus::Confirmed { txid, height } => {
            (SendState::Confirmed, Some(*height), Some(txid), None)
        }
        OperationStatus::Failed(reason) => (SendState::Failed, None, None, Some(reason.clone())),
        _ => return None,
    };
    let first = op.recipients.first();
    Some(ActivityItem {
        kind: ActivityKind::Sent,
        amount: op.total(),
        height,
        created_at: Some(op.created_at),
        state: Some(state),
        address: first.map(|p| p.recipient.encode(AddressPrefix::Main)),
        txid: txid.map(ToString::to_string),
        memo: first
            .and_then(|p| p.memo.to_text())
            .filter(|t| !t.is_empty())
            .map(str::to_owned),
        error,
        includes_fee: false,
    })
}

#[cfg(test)]
mod tests {
    use super::*;

    const WORDS: &str = "abandon abandon abandon abandon abandon abandon abandon abandon \
        abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon \
        abandon abandon abandon abandon abandon art";

    #[test]
    fn phrases_are_checked_and_normalized() {
        assert!(check_phrase(WORDS.into()).is_none());
        assert!(check_phrase(format!("  {}  ", WORDS.to_uppercase())).is_none());
        assert!(check_phrase("abandon art".into()).is_some());
        let fresh = generate_phrase().unwrap();
        assert_eq!(fresh.split(' ').count(), 24);
        assert!(check_phrase(fresh).is_none());
    }

    #[test]
    fn base_units_read_as_null() {
        assert_eq!(coins(0), "0");
        assert_eq!(coins(1), "0.00000001");
        assert_eq!(coins(150_020_000), "1.5002");
        assert_eq!(coins(21 * COIN), "21");
    }

    #[test]
    fn the_genesis_is_the_main_network_one() {
        assert_eq!(
            main_genesis(),
            "a47d659978361de625cfb4d84641b4f2de6f69ef04338e52612e5f8d95853c92"
        );
    }

    #[test]
    fn an_image_wallet_reopens_with_its_addresses_and_phrase() {
        let wallet = LightWallet::create_image(WORDS.into(), "pass".into()).unwrap();
        let address = wallet.receive_address().unwrap();
        assert_eq!(wallet.receive_address().unwrap(), address);
        let image = wallet.image().unwrap().unwrap();
        drop(wallet);

        assert!(LightWallet::open_image(image.clone(), "nope".into()).is_err());
        let wallet = LightWallet::open_image(image, "pass".into()).unwrap();
        assert_eq!(wallet.receive_address().unwrap(), address);
        assert_ne!(wallet.new_address().unwrap(), address);
        assert_eq!(wallet.reveal_phrase("pass".into()).unwrap(), WORDS);
        assert!(wallet.reveal_phrase("nope".into()).is_err());
        assert_eq!(wallet.next_height().unwrap(), 0);
        let balance = wallet.balance().unwrap();
        assert_eq!(
            (balance.total, balance.spendable, balance.pending),
            (0, 0, 0)
        );
        assert_eq!(wallet.activity().unwrap().len(), 0);
    }

    #[test]
    fn a_file_wallet_is_created_once_and_reopened() {
        let dir = tempfile::tempdir().unwrap();
        let path = dir.path().join("wallet.redb").display().to_string();
        assert!(LightWallet::create_file(path.clone(), WORDS.into(), String::new()).is_err());
        let wallet = LightWallet::create_file(path.clone(), WORDS.into(), "pass".into()).unwrap();
        assert!(wallet.image().unwrap().is_none());
        let address = wallet.receive_address().unwrap();
        drop(wallet);
        assert!(LightWallet::create_file(path.clone(), WORDS.into(), "pass".into()).is_err());
        let wallet = LightWallet::open_file(path, "pass".into()).unwrap();
        assert_eq!(wallet.receive_address().unwrap(), address);
    }

    #[test]
    fn blocks_must_arrive_in_order() {
        let wallet = LightWallet::create_image(WORDS.into(), "pass".into()).unwrap();
        assert!(wallet.apply_blocks(vec![vec![1, 2, 3]]).is_err());
        let mut out_of_order = 5u32.to_le_bytes().to_vec();
        out_of_order.extend([0xab; 32]);
        out_of_order.extend(0u32.to_le_bytes());
        let error = wallet.apply_blocks(vec![out_of_order]).unwrap_err();
        assert!(error.to_string().contains("block 5"), "{error}");
        assert_eq!(wallet.next_height().unwrap(), 0);
    }

    #[test]
    fn sends_check_their_inputs_before_building() {
        let wallet = LightWallet::create_image(WORDS.into(), "pass".into()).unwrap();
        let to = wallet.new_address().unwrap();
        assert!(wallet.quote(to.clone(), 0).is_err());
        assert!(wallet.quote("null1bad".into(), 5).is_err());
        let error = wallet.quote(to, COIN).unwrap_err().to_string();
        assert_eq!(
            error,
            "not enough funds: 1.0002 NULL needed with the fee, 0 NULL spendable"
        );
        assert!(wallet.send_rejected(1, "x".into()).is_err());
        assert_eq!(wallet.pending_transactions().unwrap().len(), 0);
    }

    fn note(value: u64, height: u32, spent_at: Option<u32>, to_change: bool) -> NoteView {
        NoteView {
            value,
            height,
            spent_at,
            to_change,
            memo: None,
        }
    }

    fn summary(items: &[ActivityItem]) -> Vec<(ActivityKind, u64, Option<u32>, bool)> {
        items
            .iter()
            .map(|i| (i.kind, i.amount, i.height, i.includes_fee))
            .collect()
    }

    #[test]
    fn a_restored_wallet_shows_its_send_and_change_from_the_chain() {
        // 10 received at 100 on a handed-out address; 2 sent at 120 with a
        // 0.0002 fee, 7.9998 change back to the default address.
        let notes = [
            note(10 * COIN, 100, Some(120), false),
            note(799_980_000, 120, None, true),
        ];
        assert_eq!(
            summary(&activity_items(&notes, &[])),
            vec![
                (ActivityKind::Change, 799_980_000, Some(120), false),
                (ActivityKind::Sent, 200_020_000, Some(120), true),
                (ActivityKind::Received, 10 * COIN, Some(100), false),
            ]
        );
    }

    #[test]
    fn a_recorded_send_is_shown_from_its_record_only() {
        let notes = [
            note(10 * COIN, 100, Some(120), false),
            note(799_980_000, 120, None, true),
        ];
        let recipient = Address::decode(
            &LightWallet::create_image(
                "abandon abandon abandon abandon abandon abandon abandon abandon \
                 abandon abandon abandon abandon abandon abandon abandon abandon \
                 abandon abandon abandon abandon abandon abandon abandon art"
                    .into(),
                "pass".into(),
            )
            .unwrap()
            .new_address()
            .unwrap(),
            AddressPrefix::Main,
        )
        .unwrap();
        let mut op = Operation::new(
            1,
            0,
            vec![Payment {
                recipient,
                amount: Amount::from_raw(2 * COIN).unwrap(),
                memo: Memo::empty(),
            }],
            1,
        );
        op.status = OperationStatus::Confirmed {
            txid: null_protocol::transaction::TxId::from_bytes([7; 32]),
            height: 120,
        };
        let items = activity_items(&notes, &[op]);
        assert_eq!(
            summary(&items)
                .iter()
                .map(|(k, a, _, f)| (*k, *a, *f))
                .collect::<Vec<_>>(),
            vec![
                (ActivityKind::Change, 799_980_000, false),
                (ActivityKind::Sent, 2 * COIN, false),
                (ActivityKind::Received, 10 * COIN, false),
            ]
        );
        assert!(items[1].address.is_some());
    }

    #[test]
    fn a_payment_to_the_default_address_is_received_unless_the_wallet_spent_there() {
        let notes = [note(5 * COIN, 50, None, true), note(COIN, 60, None, false)];
        assert_eq!(
            summary(&activity_items(&notes, &[])),
            vec![
                (ActivityKind::Received, COIN, Some(60), false),
                (ActivityKind::Received, 5 * COIN, Some(50), false),
            ]
        );
    }
}
