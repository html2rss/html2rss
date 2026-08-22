# registry.v1 bundle format

Signed registry bundles replace the runtime `html2rss-configs` gem. Each bundle is a directory (or `.tar.gz` archive) that ships feed YAML plus a manifest describing every file digest. Network sync requires an Ed25519 signature; local mounts may use integrity-only verification.

## Layout

```
{bundle}/
  manifest.json
  manifest.sig          # optional for :integrity_only
  configs/
    **/*.yml
```

- **manifest.json** — index of every config file and its SHA-256 digest.
- **manifest.sig** — Base64-encoded Ed25519 signature over the canonical manifest bytes (see below).
- **configs/** — feed YAML files validated by `Html2rss::Config::Validator`.

Feed ids mirror the config path: `configs/anthropic.com/news.yml` → id `anthropic.com/news`.

## manifest.json

```json
{
  "format": "registry.v1",
  "registry_id": "official",
  "version": "2026.08.22",
  "public_key_id": "html2rss:registry:2026",
  "files": {
    "configs/anthropic.com/news.yml": "abc123…"
  }
}
```

| Field | Description |
| --- | --- |
| `format` | Must be `registry.v1`. |
| `registry_id` | Stable registry identifier (`official`, operator-defined). |
| `version` | Publisher version string (release tag, date, semver). |
| `public_key_id` | Key id used to sign this manifest; must match a pinned public key for `:signed` trust. |
| `files` | Map of bundle-relative paths → lowercase hex SHA-256. Every path must start with `configs/`. |

## Canonical manifest bytes

Signatures cover deterministic JSON bytes:

1. Deep-sort all object keys lexicographically (recursively).
2. Serialize with `JSON.generate` (compact, UTF-8, no trailing newline).

Implementations must sign and verify the same byte sequence. Pretty-printed `manifest.json` on disk may differ visually but must represent the same object.

## Signing

- Algorithm: **Ed25519** (`OpenSSL::PKey` or equivalent).
- Signature file: **Base64** (strict, no whitespace) in `manifest.sig`.
- Verification: `public_key.verify(nil, signature, canonical_bytes)` (Ed25519; pass `nil` digest with OpenSSL 3+).

### Key rotation

Publish a new `public_key_id` and public key in the web image (or operator config). Old bundles remain verifiable while their key stays pinned. There is no online revocation list in v1.

## Trust modes

| Mode | When | Checks |
| --- | --- | --- |
| `:signed` | Network sync, release CI | Ed25519 signature + file digests |
| `:integrity_only` | Local `path:` mounts, seed copy | File digests only (disk/image trust) |

`Html2rss::Registry::Verifier.verify!(bundle_dir, trust:, public_keys:)` is the single verify entry point.

## Archive extraction limits

`Html2rss::Registry::Archive.extract!` enforces:

| Limit | Value |
| --- | --- |
| Max tarball bytes | 52_428_800 (50 MiB) |
| Max files | 10_000 |
| Max single file | 1_048_576 (1 MiB) |

Rejected entries: absolute paths, `..` traversal, symlinks, hard links.

## Runtime loading

`Html2rss::Registry::Bundle.load(directory, trust:, public_keys:)`:

1. Verifies the bundle (`Verifier`).
2. Loads every manifest-listed YAML file.
3. Validates each config through `Html2rss::Config::Validator`.
4. Builds catalog entries via `CatalogBuilder` (domain shape: `id`, `path`, `directory`, `channel`, `parameters` — no wire `source` / `registry` fields).

## Catalog domain vs API wire

Core `CatalogEntry#to_h` is **not** the HTTP API contract. The web layer maps entries to wire rows (`source: registry`, `registry: id`, etc.).

## Building bundles

Phase 2 adds `tool/registry-build` in `html2rss-configs`, calling `Manifest.build` and optional `--sign` in release CI. Build tooling must enforce the same size/file limits as `Archive.extract!`.
