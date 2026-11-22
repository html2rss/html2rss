# frozen_string_literal: true

module Html2rss
  module Vocabulary
    # One language: its code and its terms per concept (see {Vocabulary::CONCEPTS}).
    Language = Data.define(:code, :terms)
  end
end
