# frozen_string_literal: true

module Html2rss
  module SST
    ##
    # Shared tag-name and href constants for SST nodes.
    module Tags
      HEADING_NAMES = %i[h1 h2 h3 h4 h5 h6].to_set.freeze
      BLOCK_NAMES = %i[p div li ul ol h1 h2 h3 h4 h5 h6 tr br].to_set.freeze
      INVISIBLE_NAMES = %i[svg script noscript style template].to_set.freeze
      UTILITY_LANDMARK_NAMES = %i[nav aside footer menu].to_set.freeze
      IGNORED_CONTAINER_NAMES = %i[nav footer header svg script style].to_set.freeze
      CLUSTER_EXCLUDED_NAMES = %i[html body nav footer header svg script style].to_set.freeze
      SKIP_HREF_PREFIXES = ['#', 'javascript:', 'mailto:', 'tel:', 'file://', 'sms:', 'data:'].freeze
      LAYOUT_NAMES = %i[div section article li ul ol].to_set.freeze
    end
  end
end
