//! Optional Rust HTML parser extension for html2rss.
//!
//! Pure parse/SST logic lives in sibling modules; Magnus registration only here
//! and under [`ruby`].

mod parse;
mod ruby;
mod sst;

use magnus::{error::Error, Ruby};

#[magnus::init]
fn init(ruby: &Ruby) -> Result<(), Error> {
    ruby::register(ruby)
}
