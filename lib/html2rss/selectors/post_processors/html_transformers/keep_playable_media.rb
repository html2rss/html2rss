# frozen_string_literal: true

module Html2rss
  class Selectors
    module PostProcessors
      module HtmlTransformers
        ##
        # Transformer that keeps only media a reader can play: an +http(s)+ +src+ on +<audio>+, +<video>+
        # and +<source>+, made absolute; any other +src+ (missing, blank, +javascript:+, +data:+, unparsable)
        # is removed. A +<source>+ left without one is dropped, and so is an +<audio>+ or +<video>+ with no
        # playable +src+ of its own or on a child +<source>+ (no empty player shell).
        class KeepPlayableMedia
          # Elements that play a file named by +src+ (theirs or a child +<source>+).
          PLAYERS = %w[audio video].freeze

          # @param base_url [String, Html2rss::Url] base URL used to resolve relative sources
          def initialize(base_url)
            @base_url = base_url
          end

          ##
          # @param node_name [String] node name currently being transformed
          # @param node [Nokogiri::XML::Node] node currently being transformed
          # @param _env [Hash] transformer context
          # @option _env [Object] :_reserved reserved for transformer pipeline context
          # @return [void]
          def call(node_name:, node:, **_env)
            if node_name == 'source'
              node.unlink unless absolutize_src(node)
            elsif PLAYERS.include?(node_name)
              # Children are transformed after their parent, so child sources are only checked here.
              playable = absolutize_src(node) || node.css('source').any? { Url.resolve_web(_1['src'], @base_url) }
              node.unlink unless playable
            end
          end

          private

          # Rewrites +src+ to its absolute playable URL (Nokogiri stores its +to_s+) or removes it;
          # returns the URL kept, if any.
          def absolutize_src(node)
            url = Url.resolve_web(node['src'], @base_url)
            url ? node['src'] = url : node.remove_attribute('src')
            url
          end
        end
      end
    end
  end
end
