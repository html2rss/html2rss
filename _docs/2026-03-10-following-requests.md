# Following Requests Review

Date: 2026-03-10

Scope:

- Planned WordPress API scraper
- PR `#301` `feat(auto_source): follow paginated sites`
- PR `#302` `feat(browserless): support "infinite loading" websites (pagination)`

Goal:

Provide a security and architecture basis for any feature that performs follow-up requests beyond the initial channel URL request.

## Findings

These findings describe the pre-mitigation baseline that motivated the request-governance work.
`Policy`, `Budget`, `ResponseGuard`, and the updated request strategies now address much of this
surface; the notes below record the original design risks and the remaining architectural direction.

### 1. Critical (pre-mitigation baseline): the request layer had no enforceable resource budget

All three features build on an unbounded fetch primitive.

`FaradayStrategy` originally performed a full GET with redirect-following and no explicit timeout,
redirect cap, byte cap, or request budget:

- `lib/html2rss/request_service/faraday_strategy.rb`

`PuppetCommander` similarly had no html2rss-owned wall-clock budget beyond Puppeteer defaults:

- `lib/html2rss/request_service/puppet_commander.rb`

`Response` then fully materialized and parsed remote bodies in memory:

- `lib/html2rss/request_service/response.rb`

This was the common DoS root cause.

### 2. High (pre-mitigation baseline): follow-up requests were not constrained by origin or network policy

`Context` originally only carried `url` and headers:

- `lib/html2rss/request_service/context.rb`

`Url` validation only protects the top-level channel URL shape, not where redirects or discovered links may go:

- `lib/html2rss/url.rb`

For PR `#301` and the planned WordPress API scraper, this means a page can point html2rss at a different host entirely. For WordPress specifically, trusting `<link rel="https://api.w.org/">` without a same-origin policy is an SSRF and amplification footgun.

### 3. High: PR `#302` adds user-configurable preload loops but only validates positivity, not ceilings

A config can drive arbitrarily large `timeout_ms`, `max_clicks`, and `iterations`; the implementation then compounds `goto(...networkidle0)`, explicit waits, click loops, and scroll loops. That is a direct operator-triggered DoS vector unless `RequestService` imposes hard caps independent of feature config.

Also, the named `wait_for_network_idle` is implemented as sleep, not actual network-idle detection, so users may overprovision it.

### 4. Medium (superseded by current implementation): PR `#301` improved pagination behavior, but its broad fallback selector created unnecessary fan-out

`max_pages` limits fetch count, but not candidate breadth or queue growth, and the fallback `.pagination a[href]` makes traversal less deterministic than a strict `rel=next` or single “next” link strategy.

The WordPress API feature should avoid this pattern entirely and follow a single next link chain from response headers.

### 5. Medium: the proposed WordPress API scraper increases the body-size problem, not decreases it

A structured JSON array is easier to parse semantically, but it still arrives as a full response body and is fully `JSON.parse`d today:

- `lib/html2rss/request_service/response.rb`

`per_page=100` plus content/excerpt/media fields is large enough to matter, especially if paginated follow-up is enabled.

## Foundation To Build First

Put the security boundary in `RequestService`, not in paginator / WordPress / Browserless feature code.

Use these concepts:

### `RequestService::Policy`

Hard caps:

- `max_requests_per_feed`
- `max_redirects`
- `connect_timeout_ms`
- `read_timeout_ms`
- `total_timeout_ms`
- `max_response_bytes`
- `max_decompressed_bytes`

Network rules:

- allow `http/https` only
- block localhost/private/link-local by default
- block cross-origin follow-ups by default
- re-check after redirects

### `RequestService::Budget`

Shared across the whole feed build.

Every initial request, pagination request, WordPress API call, and Browserless preload action spends budget.

### `RequestService::FollowUp`

Relation-tagged requests such as:

- `:pagination`
- `:structured_api`
- `:browserless_preload`

Policy can then allow or deny by relation, not by ad hoc feature logic.

### `RequestService::ResponseGuard`

Reject oversized or unsupported responses before HTML/JSON parsing.

Prefer HEAD / headers checks where reliable, but still enforce on streamed bytes.

## Feature-Specific Rules

### PR `#301` pagination

- Same-origin only by default.
- Single-chain traversal preferred over broad candidate harvesting.
- Cap follow-up pages through the shared request budget, not just `max_pages`.

### PR `#302` Browserless preload

- Hard upper bounds in `RequestService`, regardless of config.
- Total preload wall-clock budget.
- Total action budget: max clicks, max scrolls, max waits.

### WordPress API scraper

- Only trust `api.w.org` links on the same origin unless explicitly opted out.
- Treat each `/wp-json/...` call as a follow-up request under the same budget.
- Follow `Link: rel="next"` as a single path, not selector discovery.
- Keep `_fields` minimal.

## TDD Order

1. RequestService policy specs first.
   - reject private IP / localhost
   - reject cross-origin follow-up
   - enforce timeout and byte limits
   - enforce total request budget
2. Strategy specs second.
   - Faraday honors policy and budget
   - Browserless honors total wall-clock and action caps
3. Feature specs last.
   - pagination stops on exhausted budget
   - WordPress API discovery rejects foreign API endpoint
   - Browserless preload stops at hard caps even with oversized config

## Bottom Line

The right move is to land a request-governance layer before shipping any of the three features. Without that, PR `#301`, PR `#302`, and the WordPress API scraper each add a different path to the same operational failure mode: too many requests, too much time, or too much memory, all initiated from remote-controlled input.

## Additional Considerations

To create a clean, secure, lean, hardened, and performant solution, the following concerns should also be addressed.

### Threat Model

Be explicit about what html2rss is allowed to do.

- Untrusted input controls URLs, selectors, pagination hints, and follow-up request targets.
- Remote servers control redirects, response size, response timing, HTML shape, and structured API pointers.
- “Valid config” is not “safe execution”. Safety must be enforced at runtime.

This distinction should drive the architecture.

### Design Boundary

Keep one narrow execution boundary for all outbound activity.

- Every outbound fetch should go through one request gateway.
- Every gateway call should require a typed purpose: `:initial`, `:pagination`, `:structured_api`, `:browserless_navigation`.
- Every gateway call should return normalized metadata, not just body and headers.
- Feature code should ask for “next page” or “WordPress posts page”, but never decide transport policy.

If that boundary stays strict, the rest of the codebase stays lean.

### Defaults

Bias hard toward safe defaults.

- Same-origin follow-ups by default.
- No private-network access by default.
- Low request budget by default.
- Low body-size cap by default.
- Low wall-clock cap by default.
- Fail closed when policy cannot be evaluated.

Most security regressions happen because defaults are permissive and docs say “use conservative values”.

### Redirect Handling

Redirects deserve their own policy, not just “follow redirects”.

- Re-evaluate host / IP policy after each redirect.
- Record the redirect chain.
- Cap chain length.
- Reject scheme downgrade or unsupported schemes.
- Decide whether cross-origin redirects are ever allowed.

Otherwise an apparently safe URL becomes an unsafe target one hop later.

### DNS / IP Hardening

If html2rss wants a serious SSRF posture, hostname validation alone is not enough.

- Resolve DNS and classify resulting IPs.
- Block loopback, RFC1918, link-local, multicast, and unspecified ranges.
- Re-check on connect if possible, not just on initial resolution.
- Treat IPv6 carefully.

This is the part most URL validation implementations miss.

### Streaming and Parsing

Performance and hardening meet here.

- Avoid full-body reads when limits can be enforced while streaming.
- Reject oversized responses before parse.
- Parse only supported content types.
- Prefer extraction from a constrained subset when possible.
- Be careful with gzip: compressed size is not useful protection against decompression bombs.

For WordPress JSON in particular, response-size control matters more than parser cleverness.

### Canonicalization

Define equality rules once.

- URL normalization should be centralized.
- Queue deduplication should use canonical URLs, not ad hoc string cleanup.
- Decide how query params, trailing slashes, fragments, and default ports are treated.
- Apply the same canonicalization to visited tracking, same-origin checks, and redirect history.

If not, loops, duplicate fetches, and policy bypass edges will appear.

### Observability

There should be enough signal to debug abuse and false positives.

- Log request purpose, origin, final URL, status, bytes, duration, redirect count, and policy denials.
- Log budget exhaustion distinctly from network failure.
- Emit structured reasons for rejection.
- Keep logs concise and non-sensitive.

Without this, operators will disable protections because they cannot tell what happened.

### Error Model

Make failures predictable.

- Distinguish policy denial, timeout, redirect violation, body-too-large, parse failure, unsupported content type, and scraper-not-applicable.
- Make these typed errors.
- Decide which are user-facing and which are only operational.
- Avoid “warn and continue” when safety guarantees would be violated.

A clean error taxonomy keeps feature code simple.

### Configuration Shape

Keep configuration sparse and layered.

- User config should express intent.
- Internal policy should express enforcement.
- Do not let every feature introduce its own caps in its own subtree.
- If a limit is security-critical, it should live in one request-policy area.

That keeps the config surface from fragmenting.

### Browserless Containment

Browser automation needs stricter control than plain HTTP.

- Separate navigation budget from preload-action budget.
- Separate max page runtime from per-step waits.
- Limit DOM interactions count.
- Consider restricting selectors used for automated clicking.
- Treat Browserless as a privileged mode, not equivalent to Faraday.

It is much easier to accidentally create expensive behavior there.

### Pagination Semantics

Not all pagination should be generic.

- Prefer single successor semantics over graph traversal.
- `rel=next` is better than harvesting broad anchor sets.
- For API pagination, follow the API’s next mechanism, not HTML heuristics.
- Stop once marginal value drops, not only when a numeric cap is reached.

That keeps it both lean and predictable.

### WordPress-Specific Caution

The WordPress API path is cleaner, but still needs discipline.

- Verify same-origin between page and API root.
- Keep `_fields` aggressively minimal.
- Consider smaller `per_page` if content fields are included.
- Be careful with `featured_media`; extra enrichment calls can multiply cost.
- Decide whether embedded content is worth the budget.

The cleanest implementation is often the one that fetches less.

### Test Strategy

Test invariants, not just examples.

- Shared examples for all follow-up request types.
- Property-like tests for URL normalization and loop prevention.
- Tests for hostile redirects and hostile pagination hints.
- Tests for oversized compressed and decompressed responses.
- Tests for budget exhaustion at each layer.

If the invariants are well tested, new scrapers become safer to add.

### Maintainability

Keep the core small.

- Policy objects should be data-heavy and logic-light.
- Strategies should not know business rules beyond enforcement hooks.
- Scrapers should never perform raw network operations.
- Avoid feature flags that mutate control flow everywhere.

A lean system usually comes from strict boundaries, not from fewer lines.

### Operational Questions

These questions are worth deciding up front.

- What is the maximum acceptable work for one feed build?
- Is partial success acceptable, and when?
- Should unsafe follow-ups be opt-in or impossible?
- Do you want deterministic results or best-effort crawling?
- Is Browserless a first-class path or an escape hatch?

Those answers will simplify a lot of implementation choices.
