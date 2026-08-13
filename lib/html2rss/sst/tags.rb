# frozen_string_literal: true

module Html2rss
  module SST
    ##
    # Shared tag-name and href constants for SST nodes.
    module Tags
      # Heading element names.
      HEADING_NAMES = %i[h1 h2 h3 h4 h5 h6].to_set.freeze
      # Block-level names that contribute structural newlines in text.
      BLOCK_NAMES = %i[p div li ul ol h1 h2 h3 h4 h5 h6 tr br].to_set.freeze
      # Names skipped when collecting visible text.
      INVISIBLE_NAMES = %i[svg script noscript style template].to_set.freeze
      # Landmark names treated as utility chrome.
      UTILITY_LANDMARK_NAMES = %i[nav aside footer menu].to_set.freeze
      # Container names ignored as article roots.
      IGNORED_CONTAINER_NAMES = %i[nav footer header svg script style].to_set.freeze
      # Names excluded from class/structure clustering.
      CLUSTER_EXCLUDED_NAMES = %i[html body nav footer header svg script style].to_set.freeze
      # Href prefixes that never count as content destinations.
      SKIP_HREF_PREFIXES = ['#', 'javascript:', 'mailto:', 'tel:', 'file://', 'sms:', 'data:'].freeze
      # Layout-ish names used when resolving nested wrapper groups.
      LAYOUT_NAMES = %i[div section article li ul ol].to_set.freeze
    end
  end
end
