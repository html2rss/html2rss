# frozen_string_literal: true

module Html2rss
  class AutoSource
    ##
    # The time of one run (+now+, the channel +time_zone+; nil reads as UTC): the only clock any stage reads.
    Clock = Data.define(:now, :time_zone)
  end
end
