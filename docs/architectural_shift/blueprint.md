# Architectural Blueprint: Decoupled Auto-Sourcing in Ruby

This document outlines how to implement the proposed three-tier architecture in modern Ruby (3.2+), evaluates the performance and dependency impacts, and details the new product capabilities this design unlocks.

---

## 1. Implementing the Architecture in Ruby

Here is a concrete blueprint of how the normalized representation, segmenter, and feature-based scoring engine would be structured in Ruby.

### A. The Simplified Semantic Tree (SST) representation
We define a lightweight, read-only representation of nodes using Ruby's native `Data` class (introduced in Ruby 3.2), which is faster and uses less memory than full Nokogiri node wrappers.

```ruby
# frozen_string_literal: true

module Html2rss
  module SST
    # A lightweight, immutable representation of a semantic node.
    Node = Data.define(:name, :attributes, :text, :children) do
      # Returns a flat list of all descendant nodes.
      # @return [Array<Node>]
      def descendants
        children.flat_map { |c| [c] + c.descendants }
      end

      # Computes plain text density (words per child link).
      # @return [Float]
      def text_density
        words = text.scan(/\p{Alnum}+/).size
        links = descendants.count { |d| d.name == 'a' }
        links.zero? ? words.to_f : words.to_f / links
      end
    end
  end
end
```

---

### B. Tier 1: The Normalizer
The normalizer parses raw HTML into the `SST::Node` tree, stripping out script tags, style sheets, and non-semantic wrapper divisions.

```ruby
module Html2rss
  module SST
    class Normalizer
      STRIPPED_TAGS = Set['script', 'style', 'noscript', 'iframe', 'svg'].freeze

      # @param nokogiri_node [Nokogiri::XML::Node]
      # @return [SST::Node]
      def self.normalize(nokogiri_node)
        return nil if STRIPPED_TAGS.include?(nokogiri_node.name)

        children = nokogiri_node.children.map { |child| normalize(child) }.compact

        Node.new(
          name: nokogiri_node.name,
          attributes: extract_attributes(nokogiri_node),
          text: nokogiri_node.text.to_s.strip,
          children: children
        )
      end

      def self.extract_attributes(node)
        {
          href: node['href'],
          src: node['src'],
          class: node['class']
        }.compact
      end
    end
  end
end
```

---

### C. Tier 2 & 3: The Feature Evaluator & Scoring Engine
Each feature is a pure, self-contained class. The scoring engine evaluates candidate blocks against a collection of these features.

```ruby
module Html2rss
  module Scoring
    # Base class/interface for feature evaluators.
    class FeatureEvaluator
      # @param node [SST::Node]
      # @return [Float] score between 0.0 and 1.0
      def call(node)
        raise NotImplementedError
      end
    end

    class TextDensityFeature < FeatureEvaluator
      def call(node)
        density = node.text_density
        # Normalize density to [0, 1] range
        [1.0 - (1.0 / (1.0 + density)), 0.0].max
      end
    end

    class ImageFeature < FeatureEvaluator
      def call(node)
        node.descendants.any? { |d| d.name == 'img' && d.attributes[:src] } ? 1.0 : 0.0
      end
    end

    class Engine
      FEATURES = {
        TextDensityFeature.new => 0.5,
        ImageFeature.new => 0.5
      }.freeze

      # @param candidate_nodes [Array<SST::Node>]
      # @return [Array<SST::Node>] sorted by composite score descending
      def self.rank(candidate_nodes)
        candidate_nodes.sort_by do |node|
          -score_for(node)
        end
      end

      def self.score_for(node)
        FEATURES.sum do |evaluator, weight|
          evaluator.call(node) * weight
        end
      end
    end
  end
end
```

---

## 2. Dependency & Performance Impact

### A. Dependencies
- **No New Dependencies**: Ruby 3.2+'s built-in `Data` class handles immutability natively. We do not need `ActiveSupport` or external struct-validation libraries.
- **Isolation of Nokogiri**: Nokogiri would only be used inside the `Normalizer` stage. The rest of the library (clustering, features, scoring, extraction) would operate purely on pure-Ruby data models, making unit testing extremely lightweight and fast.

### B. Performance
- **Wall-time**: The execution time will be dominated by a single top-down pass to build the `SST` tree. Because the tree is highly pruned (stripping out script, style, and interactive nodes), downstream processing checks operate on a significantly smaller node set.
- **Memory allocations**: Pruning the DOM tree into simple Ruby values avoids the overhead of wrapping large native C structs for each Nokogiri node. The memory footprint becomes predictable and garbage-collection friendly since `Data` instances are small and allocation-light.
- **Big O Complexity**: Nested traversal checks (like descendant matching) now run in linear $O(N)$ time on a shallow, simplified tree, removing the need for manual identity caching layers.

---

## 3. Unlocked Product Capabilities

By decoupling the layout model from raw DOM selection, `html2rss` transitions from a pure "tag scraper" into a semantic "content extractor," unlocking several advanced features:

### A. True Cross-Device & Responsive Scraping
Modern websites render completely different HTML structures for mobile and desktop viewports (e.g., drawer menus vs desktop navigation). Because the `SST` strips out display wrappers and concentrates on content density, the scoring engine resolves the same content cards regardless of viewport layout or styling shifts.

### B. Structured "Feed Customizer" GUI
Since candidate card clustering is scored declaratively:
- We can expose the candidates and their feature scores in a JSON payload.
- This allows web interfaces (like `html2rss-web`) to render a visual selection wizard where users can see why a section was ranked high and easily customize extraction threshold sliders (e.g. "prefer text density" vs "prefer image grids").

### C. Self-Healing Selector Configurations
If a user is running a static selector configuration (YAML) and a layout change breaks the selectors, the auto-sourcing engine can run a "Self-Healing Diff" pass:
- It runs the feature scorer to locate the new content cards.
- It automatically infers the new CSS paths and proposes a config update, preventing feed downtime.

### D. Multi-lingual Eyebrow & Kicker Classification
Because features are decoupled, text classifiers (like tracking kickers or utility links) can be represented as pluggable dictionary loaders. Translating or adjusting classification rules for different languages becomes a matter of loading a YAML locale profile, rather than writing localized regex branches in the parser.
