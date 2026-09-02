//! NativeEngine::Document — Phase 3 wires CSS ducks.

use magnus::{error::Error, RModule, Ruby};

#[allow(clippy::unnecessary_wraps)] // signature fixed for later methods
pub fn register(_ruby: &Ruby, _native: RModule) -> Result<(), Error> {
    // Document class registered in Phase 3.
    Ok(())
}
