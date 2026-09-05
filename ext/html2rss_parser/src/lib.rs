//! Optional Rust HTML parser extension for html2rss.
//!
//! Pure parse/SST logic lives in sibling modules; Magnus registration only under
//! [`ruby`] (feature `ruby`, on by default). Criterion benches link the `rlib`
//! with `--no-default-features` and call [`sst`] / [`parse`] without Ruby.

pub mod parse;
pub mod sst;

#[cfg(feature = "ruby")]
mod ruby;

#[cfg(feature = "ruby")]
use magnus::{error::Error, Ruby};

#[cfg(feature = "ruby")]
#[magnus::init]
fn init(ruby: &Ruby) -> Result<(), Error> {
    ruby::register(ruby)
}