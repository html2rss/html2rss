# Challenge corpus (vendored)

HTML fixtures used by gem specs for `BlockedSurface` / `ResponseGuard` interstitial detection.

**Authoring home:** `botasaurus-scrape-api/tests/fixtures/challenge/`  
That repo owns the shared corpus. This directory is a CI-self-contained copy so gem-only CI does not need a sibling scrape-api checkout.

When challenge HTML changes upstream, copy the updated files here (keep marker lists in code singular — duplicate fixtures only, not detector logic).
