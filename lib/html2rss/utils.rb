require 'hashie'

module Html2rss
  module Utils
    ##
    # A Hash with indifferent access, build with {https://github.com/intridea/hashie Hashie}.
    class IndifferentAccessHash < Hash
      include Hashie::Extensions::MergeInitializer
      include Hashie::Extensions::IndifferentAccess
    end
  end
end
