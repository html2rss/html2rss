# [](https://github.com/gildesmarais/html2rss/compare/v0.4.0...v) (2019-09-07)



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



