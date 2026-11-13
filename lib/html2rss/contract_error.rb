# frozen_string_literal: true

module Html2rss
  ##
  # Base for programmer errors: a value object built from wrong parts (each owner's +InvalidError+) or a
  # component breaking its contract ({AutoSource::ScraperContractError}). It is an {Error}, but no
  # operational rescue may swallow it: every broad +rescue Html2rss::Error+ in +lib/+ re-raises it first.
  class ContractError < Error; end
end
