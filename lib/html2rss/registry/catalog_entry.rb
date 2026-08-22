# frozen_string_literal: true

module Html2rss
  module Registry
    ##
    # Domain catalog entry for a registry-sourced feed config.
    CatalogEntry = Data.define(
      :id,
      :path,
      :directory,
      :channel,
      :parameters
    )
  end
end
