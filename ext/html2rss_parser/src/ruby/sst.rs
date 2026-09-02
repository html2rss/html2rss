//! IR → Ruby SST::* — Phase 2 wires `to_sst`.

use magnus::{error::Error, RModule, Ruby};

#[allow(clippy::unnecessary_wraps)]
pub fn register(_ruby: &Ruby, _native: RModule) -> Result<(), Error> {
    // SST helpers registered in Phase 2.
    Ok(())
}
