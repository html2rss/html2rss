//! NativeEngine::Node — Phase 3 wires attr / CSS ducks.

use magnus::{error::Error, RModule, Ruby};

#[allow(clippy::unnecessary_wraps)]
pub fn register(_ruby: &Ruby, _native: RModule) -> Result<(), Error> {
    // Node class registered in Phase 3.
    Ok(())
}
