# frozen_string_literal: true

module Html2rss
  ##
  # Signed registry.v1 bundles: verify, load configs once, assemble domain catalog rows.
  #
  # Pipeline (contributor story):
  #
  # 1. {Archive} — pack/extract tar.gz with size and path-safety limits
  # 2. {Verifier} — Ed25519 signature and/or file digests (+Manifest+)
  # 3. {Bundle} — YAML load + +Config.validate+ once per path → configs + catalog
  # 4. {CatalogBuilder} — domain {CatalogEntry} rows from already-loaded hashes
  #
  # Path safety under +configs/+ is owned by {BundleRelativePath}. Wire fields
  # (+source+, +registry+) are stamped by html2rss-web Index at the catalog API edge —
  # not by this gem.
  #
  # Public leaf APIs (no namespace forwarding hull):
  # +Bundle.load+, +Verifier.verify!+, +Archive.extract!+ / +Archive.pack_dir+,
  # +Manifest.parse+ / +Manifest.build+, +CatalogBuilder.entries_from_configs+,
  # +Signer.sign!+, +BundleRelativePath+ helpers.
  #
  # {include:file:lib/html2rss/registry/README.md}
  module Registry
  end
end
