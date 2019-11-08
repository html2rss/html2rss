# [](https://github.com/gildesmarais/html2rss/compare/v0.8.1...v) (2019-11-08)



## [0.8.1](https://github.com/gildesmarais/html2rss/compare/v0.8.0...v0.8.1) (2019-11-08)


### Features

* auto generate nicer channel's title and description ([#63](https://github.com/gildesmarais/html2rss/issues/63)) ([6db28f6](https://github.com/gildesmarais/html2rss/commit/6db28f6))
* change default ttl to 360 ([#65](https://github.com/gildesmarais/html2rss/issues/65)) ([605c8db](https://github.com/gildesmarais/html2rss/commit/605c8db))
* **config:** improve generation of channel.title from channel.url ([#68](https://github.com/gildesmarais/html2rss/issues/68)) ([bc8ecbb](https://github.com/gildesmarais/html2rss/commit/bc8ecbb))
* **parse_uri:** squish url to not fail on url with padding spaces ([#67](https://github.com/gildesmarais/html2rss/issues/67)) ([e349449](https://github.com/gildesmarais/html2rss/commit/e349449))



# [0.8.0](https://github.com/gildesmarais/html2rss/compare/v0.7.0...v0.8.0) (2019-11-02)


### Features

* **post_processors:** add markdown to html ([#54](https://github.com/gildesmarais/html2rss/issues/54)) ([cdf77b8](https://github.com/gildesmarais/html2rss/commit/cdf77b8))
* **post_processors:** support annotated tokens ([#62](https://github.com/gildesmarais/html2rss/issues/62)) ([b57bd7b](https://github.com/gildesmarais/html2rss/commit/b57bd7b)), closes [#56](https://github.com/gildesmarais/html2rss/issues/56)



# [0.7.0](https://github.com/gildesmarais/html2rss/compare/v0.6.0...v0.7.0) (2019-10-28)


### Features

* handle json array response ([#49](https://github.com/gildesmarais/html2rss/issues/49)) ([288c2af](https://github.com/gildesmarais/html2rss/commit/288c2af))
* support enclosure on items ([#52](https://github.com/gildesmarais/html2rss/issues/52)) ([80a30a1](https://github.com/gildesmarais/html2rss/commit/80a30a1)), closes [#50](https://github.com/gildesmarais/html2rss/issues/50)
* use zeitwerk for autoloading ([#47](https://github.com/gildesmarais/html2rss/issues/47)) ([bce523d](https://github.com/gildesmarais/html2rss/commit/bce523d))
* **post_processors:** add gsub ([#53](https://github.com/gildesmarais/html2rss/issues/53)) ([de268ae](https://github.com/gildesmarais/html2rss/commit/de268ae))
* **postprocessor:** always wrap img tag in an a tag in sanitze html ([#51](https://github.com/gildesmarais/html2rss/issues/51)) ([6c7fb88](https://github.com/gildesmarais/html2rss/commit/6c7fb88))



# [0.6.0](https://github.com/gildesmarais/html2rss/compare/v0.5.2...v0.6.0) (2019-10-05)


### Bug Fixes

* **specs:** simplecov does not exclude files from spec/ ([#44](https://github.com/gildesmarais/html2rss/issues/44)) ([b0ca780](https://github.com/gildesmarais/html2rss/commit/b0ca780))


### Features

* **ci:** run rubocop on ci ([#40](https://github.com/gildesmarais/html2rss/issues/40)) ([f4ec8d1](https://github.com/gildesmarais/html2rss/commit/f4ec8d1))
* memoize ItemExtractor lookups ([#45](https://github.com/gildesmarais/html2rss/issues/45)) ([e88321c](https://github.com/gildesmarais/html2rss/commit/e88321c))
* support setting of request headers in feed config ([#41](https://github.com/gildesmarais/html2rss/issues/41)) ([a7aca11](https://github.com/gildesmarais/html2rss/commit/a7aca11)), closes [#38](https://github.com/gildesmarais/html2rss/issues/38)



## [0.5.2](https://github.com/gildesmarais/html2rss/compare/v0.5.1...v0.5.2) (2019-09-19)



## [0.5.1](https://github.com/gildesmarais/html2rss/compare/v0.5.0...v0.5.1) (2019-09-19)


### Bug Fixes

* rss contains additional categories ([#39](https://github.com/gildesmarais/html2rss/issues/39)) ([ed164ef](https://github.com/gildesmarais/html2rss/commit/ed164ef))



# [0.5.0](https://github.com/gildesmarais/html2rss/compare/v0.4.1...v0.5.0) (2019-09-18)


### Features

* support JSON ([#37](https://github.com/gildesmarais/html2rss/issues/37)) ([d258f73](https://github.com/gildesmarais/html2rss/commit/d258f73))



## [0.4.1](https://github.com/gildesmarais/html2rss/compare/v0.4.0...v0.4.1) (2019-09-18)


### Bug Fixes

* building absolute url fails when a fragment is present ([#35](https://github.com/gildesmarais/html2rss/issues/35)) ([c1b6dc7](https://github.com/gildesmarais/html2rss/commit/c1b6dc7))


### Features

* **postprocessors:** add html to markdown ([#34](https://github.com/gildesmarais/html2rss/issues/34)) ([6a4a462](https://github.com/gildesmarais/html2rss/commit/6a4a462))



# [0.4.0](https://github.com/gildesmarais/html2rss/compare/v0.3.3...v0.4.0) (2019-09-07)


### Bug Fixes

* **template:** breaks when any method returns nil ([#32](https://github.com/gildesmarais/html2rss/issues/32)) ([0709958](https://github.com/gildesmarais/html2rss/commit/0709958))


### Features

* **parse_time:** support setting of a time_zone ([#31](https://github.com/gildesmarais/html2rss/issues/31)) ([cecbe5e](https://github.com/gildesmarais/html2rss/commit/cecbe5e)), closes [#19](https://github.com/gildesmarais/html2rss/issues/19)
* **postprocessor:** add referrer-policy on img tag in sanitze html ([#24](https://github.com/gildesmarais/html2rss/issues/24)) ([a3b1d18](https://github.com/gildesmarais/html2rss/commit/a3b1d18))
* **rubocop:** add rubocop-rspec and (auto-)fix issues ([#22](https://github.com/gildesmarais/html2rss/issues/22)) ([dd539f6](https://github.com/gildesmarais/html2rss/commit/dd539f6))
* **rubocop:** enable more performance cops and relax config ([#21](https://github.com/gildesmarais/html2rss/issues/21)) ([67132bb](https://github.com/gildesmarais/html2rss/commit/67132bb))
* **sanitize_html:** rewrite relative urls to absolute in a and img elements ([#30](https://github.com/gildesmarais/html2rss/issues/30)) ([caf4e80](https://github.com/gildesmarais/html2rss/commit/caf4e80))
* **sanitze_html:** strip more attributes ([#28](https://github.com/gildesmarais/html2rss/issues/28)) ([9daa42e](https://github.com/gildesmarais/html2rss/commit/9daa42e)), closes [#26](https://github.com/gildesmarais/html2rss/issues/26)



## [0.3.3](https://github.com/gildesmarais/html2rss/compare/v0.3.2...v0.3.3) (2019-07-01)



## [0.3.2](https://github.com/gildesmarais/html2rss/compare/v0.3.1...v0.3.2) (2019-07-01)


### Features

* enable usage of multiple post processors ([#17](https://github.com/gildesmarais/html2rss/issues/17)) ([8a9f7b4](https://github.com/gildesmarais/html2rss/commit/8a9f7b4))



## [0.3.1](https://github.com/gildesmarais/html2rss/compare/v0.3.0...v0.3.1) (2019-06-23)


### Features

* handle string and symbol keys in config hashes ([#15](https://github.com/gildesmarais/html2rss/issues/15)) ([93ad824](https://github.com/gildesmarais/html2rss/commit/93ad824))
* support attributes without selector, fallback to root element then ([#16](https://github.com/gildesmarais/html2rss/issues/16)) ([d99ae3d](https://github.com/gildesmarais/html2rss/commit/d99ae3d))



# [0.3.0](https://github.com/gildesmarais/html2rss/compare/v0.2.2...v0.3.0) (2019-06-20)


### Features

* add rubocop and update development deps ([#13](https://github.com/gildesmarais/html2rss/issues/13)) ([6e06329](https://github.com/gildesmarais/html2rss/commit/6e06329))
* change Config constructor arguments ([#14](https://github.com/gildesmarais/html2rss/issues/14)) ([21f8746](https://github.com/gildesmarais/html2rss/commit/21f8746))



## [0.2.2](https://github.com/gildesmarais/html2rss/compare/v0.2.0...v0.2.2) (2019-01-31)


### Bug Fixes

* generates invalid feeds ([00309e7](https://github.com/gildesmarais/html2rss/commit/00309e7))



# [0.2.0](https://github.com/gildesmarais/html2rss/compare/v0.1.0...v0.2.0) (2018-11-13)


### Features

* **category:** support item categories ([#10](https://github.com/gildesmarais/html2rss/issues/10)) ([4572bcb](https://github.com/gildesmarais/html2rss/commit/4572bcb)), closes [#2](https://github.com/gildesmarais/html2rss/issues/2)



# [0.1.0](https://github.com/gildesmarais/html2rss/compare/v0.0.1...v0.1.0) (2018-11-04)


### Bug Fixes

* handling of url query breaks processing ([ace289e](https://github.com/gildesmarais/html2rss/commit/ace289e))
* only set supported attributes on rss item ([dae0d8e](https://github.com/gildesmarais/html2rss/commit/dae0d8e))
* **config:** feed generation fails ([7dd5586](https://github.com/gildesmarais/html2rss/commit/7dd5586))
* **parse_uri:** handle non-absolute paths ([9215025](https://github.com/gildesmarais/html2rss/commit/9215025))


### Features

* **item_extractor:** add static and current_time ([25043dc](https://github.com/gildesmarais/html2rss/commit/25043dc))
* **item_extractor:** handle absolute urls ([f96be00](https://github.com/gildesmarais/html2rss/commit/f96be00))
* **item_extractor:** text strips strings ([f598285](https://github.com/gildesmarais/html2rss/commit/f598285))
* **post_processing:** add configurable post_processing ([#5](https://github.com/gildesmarais/html2rss/issues/5)) ([4cf6cac](https://github.com/gildesmarais/html2rss/commit/4cf6cac)), closes [#1](https://github.com/gildesmarais/html2rss/issues/1)
* **post_processor:** add substring ([6f2a32a](https://github.com/gildesmarais/html2rss/commit/6f2a32a))
* **postprocessors:** add Template ([#6](https://github.com/gildesmarais/html2rss/issues/6)) ([f1db542](https://github.com/gildesmarais/html2rss/commit/f1db542)), closes [#4](https://github.com/gildesmarais/html2rss/issues/4)
* **sanitize_html:** add target="_blank" to anchors ([975a73b](https://github.com/gildesmarais/html2rss/commit/975a73b))
* add logo [skip ci] ([857a55f](https://github.com/gildesmarais/html2rss/commit/857a55f))
* do not fail on invalid item, just skip it ([3b83d71](https://github.com/gildesmarais/html2rss/commit/3b83d71))
* require updated to be present ([e1bedae](https://github.com/gildesmarais/html2rss/commit/e1bedae))



## [0.0.1](https://github.com/gildesmarais/html2rss/compare/219cac8...v0.0.1) (2018-06-03)


### Bug Fixes

* gem's version and readme-typos ([eab39d9](https://github.com/gildesmarais/html2rss/commit/eab39d9))


### Features

* **html2rss:** add initial version of the html2rss gem ([219cac8](https://github.com/gildesmarais/html2rss/commit/219cac8))



