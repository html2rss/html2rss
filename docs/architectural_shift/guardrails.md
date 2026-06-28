# Engineering Design & Guardrails Blueprint

This document details the idiomatic design patterns, strict performance guardrails, complexity budgets, and architectural standards for making the codebase readable, maintainable, and highly approachable by both humans and AI agents.

---

## 1. AI-Agent & Human Friendliness in Ruby

AI agents struggle with Ruby due to its highly dynamic nature, implicit returns, metaprogramming, and duck typing. To make the codebase easily navigable by both agents and humans, we enforce these coding standards:

### A. Strict Type and Contract Documentation
Every class and public method must have explicit YARD documentation. This provides a clear type contract for IDEs, developers, and AI context windows.

```ruby
# GOOD: Explicit type contract for both humans and AI agents
class TextDensityFeature
  # Computes the word-to-link density ratio for a simplified node.
  #
  # @param node [Html2rss::SST::Node] the normalized tree node
  # @return [Float] normalized density score in the range [0.0, 1.0]
  # @raise [ArgumentError] if the node is nil
  def call(node)
    raise ArgumentError, 'node cannot be nil' unless node
    # ...
  end
end
```

### B. Functional Composition Over Metaprogramming
- Avoid `send`, `method_missing`, or `instance_eval` for routing or loading features.
- Use explicit registration maps and dependency injection:

```ruby
# GOOD: Explicit registry pattern
module Html2rss
  module Scoring
    REGISTRY = {
      text_density: TextDensityFeature,
      image_presence: ImageFeature
    }.freeze

    # @param name [Symbol]
    # @return [Class<FeatureEvaluator>]
    def self.fetch(name)
      REGISTRY.fetch(name) { raise ArgumentError, "Unknown feature: #{name}" }
    end
  end
end
```

### C. Immutability by Default
Avoid mutating data structures (like mutating parameters in place). Mutating state leads to side effects that AI agents struggle to track.
- Use Ruby 3.2+ `Data` classes.
- Freeze all strings, arrays, hashes, and sets.

---

## 2. Performance Guardrails (Preventing Afterthoughts)

To ensure performance is built into the engine rather than patched later, we implement three core guardrails:

### A. The Node Ceiling Guard
Large documents can exhaust memory. We enforce a maximum node count ceiling during the normalization phase.
- If the document contains more than, say, 5,000 nodes, the normalizer stops parsing immediately and falls back to top-level semantic tags only (e.g. searching only `article` blocks).

```ruby
module Html2rss
  module SST
    class Normalizer
      MAX_NODES = 5000

      # @param node [Nokogiri::XML::Node]
      # @param counter [Integer] track recursive node allocations
      # @return [SST::Node, nil]
      def self.normalize(node, counter: 0)
        return nil if counter > MAX_NODES
        # ...
      end
    end
  end
end
```

### B. Allocation-Free Traversals
- Never call `.ancestors` or `.css` inside loops.
- Use pre-calculated indices or hashes when looking up element relationships.

### C. Lazy Extraction (Deferred Operations)
- Heavy operations (like resolving remote URLs, generating full IDs, or running heavy regex on description text) are deferred until the final scoring phase has selected the top 10 candidates. This ensures we never waste CPU cycles parsing nodes that get discarded.

---

## 3. Complexity Budgets

To keep the codebase maintainable, we establish strict static analysis constraints:

| Metric | Budget | Enforcement Tool |
| :--- | :--- | :--- |
| **Method Length** | Max 10 lines | RuboCop `Metrics/MethodLength` |
| **Cyclomatic Complexity** | Max 6 | RuboCop `Metrics/CyclomaticComplexity` |
| **AbcSize Complexity** | Max 15 | RuboCop `Metrics/AbcSize` |
| **Class Length** | Max 150 lines | RuboCop `Metrics/ClassLength` |

---

## 4. Unlocked Developer Experience

By enforcing these constraints:
1. **Readable Context**: An AI agent reading a class can easily infer its inputs, outputs, and side-effects. The entire file fits inside a 100-line context window.
2. **Deterministic Errors**: Descriptive errors and explicit contract validations make debugging highly predictable.
3. **No Hidden State**: Pure functions make unit testing trivial, removing the need for complex mock/stub structures in RSpec.
