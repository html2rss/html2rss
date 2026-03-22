# Semantic HTML Primary Anchor Plan

## Problem

`SemanticHtml` currently behaves as an anchor-centric scraper rather than a container-centric scraper.

Today it:

- finds descendant anchors first
- walks upward to a semantic container
- yields the same container multiple times when that container has multiple links
- relies on `HtmlExtractor` to pick a "main" link by DOM order

That creates three recurring problems:

1. Redundant processing. A block with several links can be processed several times.
2. Wrong URL selection. Utility or metadata links can win simply because they appear earlier than the headline link.
3. Blurred responsibilities. Candidate discovery and primary-link selection are not clearly separated.

This shows up most clearly on multi-link cards containing combinations of:

- a primary content link
- category or taxonomy links
- author/profile links
- comments or share links
- newsletter or CTA links
- image overlays and duplicate links to the same destination

## Goal

Improve `SemanticHtml` so it chooses the most content-like anchor within each candidate block before extraction.

The immediate success condition is not "perfect link intelligence." It is:

- one emitted candidate per container
- more consistent selection of the intended article URL
- fewer noisy candidates entering cleanup
- permission to emit no candidate for a container when every descendant link is low-signal

The first slice should prefer suppressing obvious utility noise over extracting every possible semantic card.

## Non-Goals

- No site-specific scraping rules for individual publishers.
- No immediate generalization to the `Html` scraper.
- No premature commitment to exact heuristic weights.
- No cross-page URL normalization or canonicalization framework.
- No requirement in the first slice to solve image-only teaser cards without a heading or meaningful anchor text.
- No requirement in the first slice to solve multi-story containers such as link bundles or related-story clusters.

## Agreed Direction

The first implementation slice should be `SemanticHtml` only.

The architectural shift is:

- discovery becomes container-centric
- selection becomes an explicit in-container responsibility
- extraction consumes the selected anchor rather than making a second guess

This keeps responsibilities clear:

- `SemanticHtml` owns candidate block discovery
- in-block selection logic owns primary-anchor choice
- `HtmlExtractor` owns field extraction from a container plus an explicitly selected anchor
- cleanup remains a safety net, not the first line of defense against multi-link noise

## Initial Pipeline

The intended `SemanticHtml` pipeline is:

1. Identify candidate containers from the existing semantic selector set.
2. Deduplicate those containers by node identity so each block is considered once.
3. Collect eligible descendant anchors within each container.
4. Collapse repeated links to the same article destination within that container to one representative candidate set.
5. Rank anchors within the container scope only.
6. Select one primary anchor for the container, or none if no eligible anchor remains.
7. Pass both the container and the selected anchor into extraction.
8. Emit at most one article candidate for that container.

This is the core behavioral change: move from "finding anchors and going up" to "finding containers and ranking down."

The existing leaf-style semantic selectors are a good first filter, especially for nested semantic tags, but they are not a complete guarantee across mixed tag families. A final deduplication safeguard on node identity should remain part of the scraper.

## Responsibilities and Contracts

The plan intentionally stays flexible on naming, but the responsibility split should be explicit.

### In-Container Selection Responsibility

Introduce a dedicated responsibility for choosing the primary anchor within a candidate block.

Reasons:

- the logic is substantive enough to deserve focused unit tests
- it keeps `SemanticHtml` readable
- it prevents `HtmlExtractor` from accumulating ranking heuristics that belong earlier in the pipeline

The implementation may become a class or service object, but the plan does not require a specific class name yet.

### Extraction Contract

Extraction should accept both:

- the content container
- the selected primary anchor

When a selected anchor is provided, extraction must use it rather than rediscovering a main link from DOM order.

This is essential. Without an explicit extractor contract, selection logic in `SemanticHtml` can be bypassed by a second "best guess" later in the pipeline.

Field ownership should be explicit:

- URL: selected anchor
- title: primarily heading/block-derived
- description: container-derived unless an existing fallback explicitly depends on the selected anchor
- image: container-derived unless an existing fallback explicitly depends on the selected anchor
- published_at: container-derived
- categories: container-derived
- enclosures: container-derived unless an existing fallback explicitly depends on the selected anchor

## Heuristic Strategy

The first version should use a two-stage model:

1. filtering-first
2. ranking-second

This is safer than one large additive score table because some links are better treated as ineligible or near-ineligible rather than merely weak candidates.

### Eligible Descendant Anchors

Eligibility in v1 should be a real contract, not just implementation guidance.

At minimum, exclude:

- empty or missing `href`
- fragment-only destinations
- obvious non-content schemes
- obvious action-oriented links such as comments, share, login, signup, and newsletter flows

At minimum, exclude or heavily down-rank when a stronger content link exists:

- author/profile links
- taxonomy/category/tag links
- icon-only links
- generic utility links with no article-like structural association

Eligibility should require either:

- meaningful visible anchor text, or
- a strong structural signal such as heading alignment or article-style overlay semantics

Image-only teaser cards without a heading or meaningful link text are not a first-slice target. If they do not meet eligibility through a clear structural signal, the container may be skipped.

### Likely Positive Signals

- anchor inside a heading
- anchor aligned with the block heading text
- meaningful visible text
- content-like destination path
- overlay or stretched-link semantics when present

The strongest positive signal in the first implementation should be heading-anchor synergy: structural association with the block heading plus text alignment with that heading. This should be prioritized over weaker generic signals such as raw text length alone.

Blocks with no heading still need secondary signals, but they should not force v1 into broad weak-link recovery logic.

### Duplicate Links Inside One Block

The plan should explicitly handle the common case where several links in one block point to the same story, such as:

- image overlay plus headline link
- repeated CTA plus title link
- icon or thumbnail link plus text link

These should not be treated as competing stories. Within one container, same-destination links should collapse to one story candidate, and the selector should choose the strongest representative anchor for extraction.

This is intentionally scoped to within-container representative selection, not full URL normalization across the whole scraper.

### Multiple Plausible Article Links

Some containers may contain several plausible content links, such as:

- live blog cards
- related-story bundles
- mixed teaser groups inside one semantic wrapper

The first-slice rule should be simple: choose the strongest single link, do not attempt to extract multiple stories from one container, and do not attempt to fully solve multi-story containers in v1.

### Guidance on Scoring

- Do not lock the initial plan to exact numeric weights.
- Prefer signal categories and ranking intent over hardcoded point values.
- Keep ranking scoped to the candidate block to avoid page-wide performance and correctness issues.
- Avoid heuristic sprawl and publisher-specific class names unless they express generic, reusable utility/content patterns.

The first implementation should optimize for common multi-link cards, not for exhaustive classification.

## TDD Plan

The work should be driven test-first.

### First Red Tests: Focused Unit Coverage

Start with focused scraper and extractor regressions because they are the fastest way to lock the contract and isolate behavior.

Current seed coverage exists in:

- [spec/fixtures/multi_link_block.html](/Users/gil/versioned/html2rss/html2rss/spec/fixtures/multi_link_block.html)
- [spec/lib/html2rss/auto_source/scraper/semantic_html_ranking_spec.rb](/Users/gil/versioned/html2rss/html2rss/spec/lib/html2rss/auto_source/scraper/semantic_html_ranking_spec.rb)

That seed now exercises:

- heading link vs category/comments/share links
- utility-only block behavior
- heading link vs thumbnail/gallery and author links
- utility text vs actual article link
- exact emitted URL expectations

Additional focused tests should cover:

- the extractor honoring an explicitly selected anchor
- one emitted candidate per container
- absence of duplicate emission from multi-link blocks
- repeated links to the same destination inside one block selecting one representative anchor
- block skipping when no eligible anchor remains

### Semantic Scraper Expectations

Existing semantic scraper expectations that reward over-collection need revision.

In particular, the broad count-based expectation in [spec/lib/html2rss/auto_source/scraper/semantic_html_spec.rb](/Users/gil/versioned/html2rss/html2rss/spec/lib/html2rss/auto_source/scraper/semantic_html_spec.rb) conflicts with the new objective. Lower raw candidate counts on noisy pages are part of the intended outcome, not a regression.

Behavior-focused assertions should replace or narrow those expectations.

### Fixture Growth Policy

When a new heuristic bug appears:

1. add a focused fixture or targeted spec first
2. reproduce the failure in the smallest realistic semantic block
3. then tune the selection logic

Do not grow the heuristic set without pinning the behavior in tests.

## Validation and Rollout

Validation should be explicit:

1. focused semantic/extractor red-green specs
2. targeted semantic scraper specs
3. `mise exec -- make quick`
4. `mise exec -- make ready` before merge

Observability for this slice should stay lightweight and fixture-driven. Compare before/after behavior on the focused fixture corpus and a small set of representative pages:

- raw semantic candidate counts should decrease on noisy blocks
- duplicate-per-container behavior should disappear
- obvious wrong-link selections should drop
- some false negatives are acceptable if they remove utility-link false positives

## Migration and Compatibility Risk

This change is expected to alter current semantic scraper behavior in ways that are desirable but not silent.

In particular:

- raw candidate counts on noisy pages should decrease
- duplicate-per-container behavior should disappear
- some currently emitted utility-link "articles" should stop appearing

Existing tests that implicitly reward over-collection need review.

This is a behavior change, not merely an internal refactor. Stakeholders should treat lower recall on ambiguous or weak-signal blocks as an acceptable first-slice tradeoff when it improves link quality.

## Implementation Slice

The first implementation slice should aim for the following:

1. make `SemanticHtml` enumerate unique candidate containers
2. add explicit in-container anchor eligibility and selection
3. collapse same-destination links inside a container to one representative story candidate
4. update extraction to honor a provided selected anchor
5. keep title and description block-oriented
6. preserve cleanup as a downstream safeguard

This should be treated as a disciplined first step, not a full ranking framework rollout.

## Deferred Follow-Ups

The following are reasonable follow-up expansions, but should not be required for the first slice:

- threshold tuning beyond the initial eligibility contract
- stronger support for image-only teaser cards
- URL-level normalization beyond within-container representative selection
- evaluation of whether the same selection pattern should later inform the `Html` scraper
- heuristic tuning against a broader fixture and examples corpus
- example scenarios and README updates documenting the behavior publicly

## Summary

The agreed direction is to make `SemanticHtml` container-centric, select one primary anchor per block, and require extraction to honor that choice.

The first implementation should be small, test-driven, and scoped to `SemanticHtml`, with explicit acceptance of false negatives where they reduce utility-link noise.
