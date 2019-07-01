module Html2rss
  module Utils
    class IndifferentAccessHash < Hash
      include Hashie::Extensions::MergeInitializer
      include Hashie::Extensions::IndifferentAccess
    end
  end
end
