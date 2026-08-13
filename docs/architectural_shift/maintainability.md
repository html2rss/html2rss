# Maintainability & Extensibility Analysis

This document evaluates the long-term maintenance characteristics of the decoupled three-tier architecture and maps out how to integrate state-of-the-art web scraping approaches (such as LLMs, visual/browserless segmenters, and ML-based ranking).

---

## 1. Long-Term Maintainability

The maintenance profile of a codebase is defined by its **isolation boundaries** (how easy it is to change a rule without causing a regression elsewhere).

```
[Current Architecture]
Raw DOM -> Single Scraper Loop -> Extraction Heuristics -> Feed Items
(Changing a regex or layout rule affects traversal, scoring, and output simultaneously)

[Proposed Architecture]
Raw HTML -> [1. Normalizer] -> [2. Segmenter] -> [3. Scorer] -> [4. Extractor]
(Each stage has zero side effects on adjacent stages; inputs and outputs are isolated)
```

### A. Testing Isolation (Trivial Mocks)
- **Current**: To test a scraper behavior, you need large, complex HTML fixtures.
- **Proposed**: You can unit test a `FeatureEvaluator` by passing a small, mock `SST::Node` directly:
  ```ruby
  it "scores high for text-dense nodes" do
    node = Html2rss::SST::Node.new(name: 'div', attributes: {}, text: "Lots of words here", children: [])
    expect(Html2rss::Scoring::TextDensityFeature.new.call(node)).to be > 0.8
  end
  ```

### B. Regression Protection
- Adjusting candidate selection (Tier 2/3) has **zero** impact on HTML normalization (Tier 1) or RSS formatting (Tier 4).
- If a specific website requires a custom rule, you can create a specialized `FeatureEvaluator` that runs only for that domain type, keeping the core engine clean.

---

## 2. Integrating State-of-the-Art Scraping Techniques

Because the pipeline is cleanly decoupled, integrating next-generation scraping techniques is extremely straightforward:

### A. LLM-Based Extraction (Zero-Shot)
Feeding raw HTML to an LLM is expensive, slow, and error-prone due to context token limits.
- **Integration**: Run Tiers 1 & 2 first to prune the page and segment candidates. The resulting pruned `SST` is small enough to fit inside a minimal prompt.
- **Action**: Swap Tier 4 (Extractor) with an LLM call using Structured Outputs (JSON schema) to extract titles/dates, completely bypassing heuristic string parsing.

```ruby
class LLMScorer < FeatureEvaluator
  def call(node)
    # Send the pruned SST node text to a lightweight local model (e.g. Llama-3-8B)
    # to evaluate if this block represents a distinct article entry.
  end
end
```

---

### B. Vision-Based / Browserless Segmenters (VIPS)
State-of-the-art scraping often relies on visual coordinates (where cards are positioned on the screen) to handle dynamic viewport rendering.
- **Integration**: Extend `SST::Node` to accept coordinates (`x, y, width, height`) fetched from Chromium/Browserless.
- **Action**: Introduce a `VisualLayoutSegmenter` in Tier 2 that clusters nodes based on bounding box overlaps. The scoring features and downstream RSS builders remain untouched.

---

### C. Machine-Learning Scoring Model
Instead of manually tweaking weights (e.g., `TextDensityFeature => 0.5`), we can train a simple classifier.
- **Integration**: Gather features from the SST candidates and represent them as feature vectors.
- **Action**: Load a simple linear regression model or decision tree model at startup. The scoring engine evaluates candidate nodes using model predictions instead of hardcoded rules.
