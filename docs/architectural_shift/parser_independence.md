# Parser Independence & Nokogiri Alternatives

This document evaluates whether the proposed decoupled architecture allows dropping Nokogiri in favor of lighter alternatives (like REXML or pure-Ruby HTML parsers), outlining the trade-offs and transition paths.

---

## 1. Parser Isolation at Tier 1 (The Normalizer)

In the decoupled Three-Tier architecture, the dependency on Nokogiri is isolated entirely within the **Normalizer** stage:

```
[Raw HTML] -> [Normalizer (Nokogiri)] -> [SST::Node (Pure Ruby)] -> [Scorer/Extractor]
                                          (Parser-agnostic downstream logic)
```

Because Tiers 2, 3, and 4 operate strictly on `SST::Node` instances (which are pure-Ruby immutable `Data` objects), we can swap out Nokogiri with *any* HTML parser by implementing a new Normalizer class that maps to the same `SST::Node` structure.

---

## 2. Evaluating the Alternatives

### A. REXML (Ruby Standard Library)
- **Feasibility**: **Low**
- **Analysis**: REXML is a strict XML parser. Real-world HTML on the web is rarely well-formed XML (it has unclosed tags, void tags like `<img>` without `</img>`, and loose attribute quoting). Running REXML on typical web pages will raise parse errors on almost every site.
- **Verdict**: REXML is unsuitable for general-purpose web scraping.

---

### B. Pure-Ruby HTML Parsers (e.g., Oga)
- **Feasibility**: **High**
- **Analysis**: Oga is a pure-Ruby XML/HTML parser that does not require native C compilation (making gem installation fast and robust across architectures).
- **Trade-off**: Because it is written in pure Ruby, it is slower and consumes more memory than C-based parsers like Nokogiri. However, since the Normalizer immediately throws away 70–80% of the nodes (scripts, styles, layout classes), the downstream processing overhead remains tiny.
- **Verdict**: A great alternative if compilation-free installation is a priority.

---

### C. Nokolexbor (Lexbor HTML5 Bindings)
- **Feasibility**: **High**
- **Analysis**: Nokolexbor is a Ruby binding to the Lexbor HTML5 parsing library (written in C). It is fully compliant with the HTML5 specification and is often faster and lighter than Nokogiri/libxml2.
- **Verdict**: The best state-of-the-art native alternative if parsing performance and exact HTML5 compliance are desired.

---

## 3. Implementing a New Parser (Transition Blueprint)

To switch parsers, we only need to define a new Normalizer. For example, if we wanted to use **Oga** to drop Nokogiri:

```ruby
# frozen_string_literal: true

module Html2rss
  module SST
    class OgaNormalizer
      STRIPPED_TAGS = Set['script', 'style', 'noscript', 'iframe', 'svg'].freeze

      # Normalizes an Oga HTML node into our standard SST structure.
      #
      # @param oga_node [Oga::XML::Node]
      # @return [SST::Node, nil]
      def self.normalize(oga_node)
        return nil if STRIPPED_TAGS.include?(oga_node.name)

        children = oga_node.children.map { |child| normalize(child) }.compact

        Node.new(
          name: oga_node.name,
          attributes: {
            href: oga_node.get('href'),
            src: oga_node.get('src'),
            class: oga_node.get('class')
          }.compact,
          text: oga_node.text.to_s.strip,
          children: children
        )
      end
    end
  end
end
```

By keeping the normalizer interface simple, swapping the underlying parser requires changing exactly **one line of configuration** at the entry point of the pipeline.
