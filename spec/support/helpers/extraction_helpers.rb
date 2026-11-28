# frozen_string_literal: true

# Pages for the extraction kernel specs.
module ExtractionHelpers
  # @param href [String] the card's link
  # @param extra [String] markup after the headline
  # @return [String] a page of one article card
  def harbor_card(href, extra = '')
    "<html><body><article><h2><a href=\"#{href}\">Harbor library plans a summer reading room</a></h2>#{extra}" \
      '<p>Residents will read.</p></article></body></html>'
  end
end
