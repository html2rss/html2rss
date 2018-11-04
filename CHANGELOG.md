<img width="300px" src="https://github.com/gildesmarais/html2rss/raw/master/support/logo.png" />

# html2rss

_Generate RSS feeds by scraping websites by providing a config._



## Bugfixes
  - handling of url query breaks processing
  ([ace289e9](git@github.com:gildesmarais/html2rss/commit/ace289e911b69cb92433cac6f1ca0403715d8286))
  - only set supported attributes on rss item
  ([dae0d8e7](git@github.com:gildesmarais/html2rss/commit/dae0d8e75541e810275e789a23971a61e60a2154))

  - **config**
    - feed generation fails
  ([7dd55869](git@github.com:gildesmarais/html2rss/commit/7dd55869f79b1de76c004bf0e82d13b16b5b3f0d))

  - **parse_uri**
    - handle non-absolute paths
  ([92150257](git@github.com:gildesmarais/html2rss/commit/921502574e4436d65a30e1d34b9b31f238336247))




## Features
  - add logo [skip ci]
  ([857a55fd](git@github.com:gildesmarais/html2rss/commit/857a55fd8c932930d96c47c5abe57f0507356df1))
  - require updated to be present
  ([e1bedaec](git@github.com:gildesmarais/html2rss/commit/e1bedaecc91e874fe24e96000612abb9cd11e9fe))
  - do not fail on invalid item, just skip it
  ([3b83d715](git@github.com:gildesmarais/html2rss/commit/3b83d715619abbc33b124de1945d17cb0dc7edb0))

  - **item_extractor**
    - text strips strings
  ([f5982859](git@github.com:gildesmarais/html2rss/commit/f59828593dca663bdbe8699392594e2d18658f8f))
    - add static and current_time
  ([25043dcb](git@github.com:gildesmarais/html2rss/commit/25043dcbd8f0f4901202f4a2f66b355ac48825a8))
    - handle absolute urls
  ([f96be008](git@github.com:gildesmarais/html2rss/commit/f96be00857bdcded02d52dd62ec22b9b52c803ed))

  - **post_processing**
    - add configurable post_processing (#5)
  ([4cf6caca](git@github.com:gildesmarais/html2rss/commit/4cf6cacac00bd3c0c53d584ca11274ba24b03ef7),
   [#1](git@github.com:gildesmarais/html2rss/issues/1))

  - **post_processor**
    - add substring
  ([6f2a32a6](git@github.com:gildesmarais/html2rss/commit/6f2a32a6304ef9956577711173de681daf93f55f))

  - **postprocessors**
    - add Template (#6)
  ([f1db542e](git@github.com:gildesmarais/html2rss/commit/f1db542e8c1e9e09a066a3cd6c8514a6ca0aa871),
   [#4](git@github.com:gildesmarais/html2rss/issues/4))

  - **sanitize_html**
    - add target="_blank" to anchors
  ([975a73bf](git@github.com:gildesmarais/html2rss/commit/975a73bfd396ba5942bc0ea80eebd14cc37ad776))




## Documentation
  - add tips and tricks
  ([ea978240](git@github.com:gildesmarais/html2rss/commit/ea9782408107f3637a4c9665396f511fc07be19b))
  - update readme
  ([4743167c](git@github.com:gildesmarais/html2rss/commit/4743167c86959e83524ffb7282c562413a651797))
  - add note about html2rss-web
  ([3371c12f](git@github.com:gildesmarais/html2rss/commit/3371c12ffc6c8d3c29073d03ff206886a39401cd))
  - add a badge for travis-ci
  ([8818d4f4](git@github.com:gildesmarais/html2rss/commit/8818d4f464a9c163ebc9665d01719e2bab132bd6))




## Test
  - don't be so lazy when matching strings
  ([6a0eb627](git@github.com:gildesmarais/html2rss/commit/6a0eb62765523a1405fd269466b2fc57794eac7a))




## Chore
  - upgrade sanitze gem to version 5.0.0
  ([8c4bf3a4](git@github.com:gildesmarais/html2rss/commit/8c4bf3a44885758e395568ec452a7cffdb9a0389))
  - rubocop autocorrect
  ([af6b9fac](git@github.com:gildesmarais/html2rss/commit/af6b9facca547d3ca3ce9ef0d1227707cd16eaea))
  - build against latest ruby releases
  ([17ba79ac](git@github.com:gildesmarais/html2rss/commit/17ba79acd2f68da1fcc984368d3e6de3437cbf1b))
  - update dependencies
  ([855279b4](git@github.com:gildesmarais/html2rss/commit/855279b46d584a8a8c2a317529f7a4be550eaf15))
  - update dependencies
  ([46e5a283](git@github.com:gildesmarais/html2rss/commit/46e5a2832d1f2fe1353dcc2a8d82a9786f15f6bd))
  - add simplecov
  ([b4e1144b](git@github.com:gildesmarais/html2rss/commit/b4e1144b7f8f90126e528cc4a4ec048113d93634))

  - **changelog**
    - add generation with git-changelog
  ([07ad5a51](git@github.com:gildesmarais/html2rss/commit/07ad5a513f0951ee988426abda4b8c233411ead7))

  - **travis**
    - use cache for bundler
  ([ac76b3b2](git@github.com:gildesmarais/html2rss/commit/ac76b3b2dd94adecd4927de18651800438a7e7ba))
    - setup autorelease to rubygems
  ([eb9c8e1b](git@github.com:gildesmarais/html2rss/commit/eb9c8e1b16902dc0e174a0cccb6eb9227307ce82))





---
<sub><sup>*Generated with [git-changelog](https://github.com/rafinskipg/git-changelog). If you have any problems or suggestions, create an issue.* :) **Thanks** </sub></sup>

