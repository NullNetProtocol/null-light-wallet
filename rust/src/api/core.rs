//! Address checks and compact-block decoding over the null-chain crates.

use null_protocol::address::{Address, AddressPrefix};
use null_protocol::bytes::Encodable;
use null_protocol::compact::CompactBlock;

/// Sets up panic reporting and logging for the bridge.
#[flutter_rust_bridge::frb(init)]
pub fn init_app() {
    flutter_rust_bridge::setup_default_user_utils();
}

/// This crate's version, shown in Settings.
#[flutter_rust_bridge::frb(sync)]
#[must_use]
pub fn core_version() -> String {
    env!("CARGO_PKG_VERSION").to_string()
}

/// Whether text is a main-network address, and why not.
pub struct AddressCheck {
    /// The address decodes on the main network.
    pub valid: bool,
    /// Why it does not, when it does not.
    pub error: Option<String>,
}

/// Checks a main-network address, as the Send screen types it.
#[flutter_rust_bridge::frb(sync)]
#[must_use]
pub fn check_address(address: String) -> AddressCheck {
    match Address::decode(address.trim(), AddressPrefix::Main) {
        Ok(_) => AddressCheck {
            valid: true,
            error: None,
        },
        Err(error) => AddressCheck {
            valid: false,
            error: Some(error.to_string()),
        },
    }
}

/// The parts of a compact block the sync screen shows.
pub struct CompactSummary {
    /// The block height.
    pub height: u32,
    /// The block hash, lowercase hex.
    pub hash: String,
    /// Actions the block appends to the commitment tree.
    pub actions: u32,
}

/// Decodes a compact block as a light server sends it.
///
/// # Errors
/// Fails on bytes that are not one canonical compact block.
#[flutter_rust_bridge::frb(sync)]
pub fn summarize_compact_block(bytes: Vec<u8>) -> anyhow::Result<CompactSummary> {
    let block = CompactBlock::from_slice(&bytes)?;
    Ok(CompactSummary {
        height: block.height,
        hash: block.hash.to_string(),
        actions: u32::try_from(block.actions.len())?,
    })
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn garbage_is_neither_an_address_nor_a_block() {
        let check = check_address("null1notanaddress".into());
        assert!(!check.valid);
        assert!(check.error.is_some());
        assert!(summarize_compact_block(vec![1, 2, 3]).is_err());
    }

    #[test]
    fn an_empty_compact_block_round_trips() {
        let mut bytes = 7u32.to_le_bytes().to_vec();
        bytes.extend([0xab; 32]);
        bytes.extend(0u32.to_le_bytes());
        let summary = summarize_compact_block(bytes).unwrap();
        assert_eq!((summary.height, summary.actions), (7, 0));
        assert_eq!(summary.hash.len(), 64);
    }

    #[test]
    fn a_format_2_compact_block_decodes() {
        let mut bytes = 9u32.to_le_bytes().to_vec();
        bytes.extend([0xcd; 32]);
        bytes.extend(0u32.to_le_bytes());
        bytes.extend(1u32.to_le_bytes());
        bytes.extend([0u8; 32]);
        let summary = summarize_compact_block(bytes).unwrap();
        assert_eq!((summary.height, summary.actions), (9, 0));
    }

    #[test]
    fn the_version_is_the_crate_version() {
        assert_eq!(core_version(), env!("CARGO_PKG_VERSION"));
    }
}
