# [](https://github.com/html2rss/html2rss/compare/v0.9.0...v) (2020-06-19)



# [0.9.0](https://github.com/html2rss/html2rss/compare/v0.8.2...v0.9.0) (2020-06-19)


### Features

* add option to reverse order of channel items ([#82](https://github.com/html2rss/html2rss/issues/82)) ([2019977](https://github.com/html2rss/html2rss/commit/2019977b09fdc29c427b8b7e478857ca3f9f7027)), closes [#80](https://github.com/html2rss/html2rss/issues/80)
* require at least ruby version 2.5 ([#85](https://github.com/html2rss/html2rss/issues/85)) ([0ff6ee3](https://github.com/html2rss/html2rss/commit/0ff6ee355a87331f8afbfbdac1496cdfa36f3e5f))
* support ruby 2.7 ([#75](https://github.com/html2rss/html2rss/issues/75)) ([56ddbbe](https://github.com/html2rss/html2rss/commit/56ddbbe7c921e26057511754cf058fdd69fc9e0c))



## [0.8.2](https://github.com/html2rss/html2rss/compare/v0.8.1...v0.8.2) (2019-11-09)


### Features

* improve url handling by sanitizing and normalizing urls ([#70](https://github.com/html2rss/html2rss/issues/70)) ([02cd551](https://github.com/html2rss/html2rss/commit/02cd551f4411b050bbb6e4ed942d7b3d707cd86a))



## [0.8.1](https://github.com/html2rss/html2rss/compare/v0.8.0...v0.8.1) (2019-11-08)


### Features

* **config:** improve generation of channel.title from channel.url ([#68](https://github.com/html2rss/html2rss/issues/68)) ([bc8ecbb](https://github.com/html2rss/html2rss/commit/bc8ecbb9623ce08a6cd067da1cb5fd0a996a9d40))
* **parse_uri:** squish url to not fail on url with padding spaces ([#67](https://github.com/html2rss/html2rss/issues/67)) ([e349449](https://github.com/html2rss/html2rss/commit/e34944995e669c0f8dd6a1e78acb31bd3db9fcf6))
* auto generate nicer channel's title and description ([#63](https://github.com/html2rss/html2rss/issues/63)) ([6db28f6](https://github.com/html2rss/html2rss/commit/6db28f67a99b893fb09d7f8d337027a5a48dbe85))
* change default ttl to 360 ([#65](https://github.com/html2rss/html2rss/issues/65)) ([605c8db](https://github.com/html2rss/html2rss/commit/605c8db4f74329128bd45961e2c1e5fa344924a5))



# [0.8.0](https://github.com/html2rss/html2rss/compare/v0.7.0...v0.8.0) (2019-11-02)


### Features

* **post_processors:** add markdown to html ([#54](https://github.com/html2rss/html2rss/issues/54)) ([cdf77b8](https://github.com/html2rss/html2rss/commit/cdf77b8696eebed7a5cffda7cfd75ddc64db364b))
* **post_processors:** support annotated tokens ([#62](https://github.com/html2rss/html2rss/issues/62)) ([b57bd7b](https://github.com/html2rss/html2rss/commit/b57bd7b4cd22c8c51e8b2f526187b5997d77b25c)), closes [#56](https://github.com/html2rss/html2rss/issues/56)



# [0.7.0](https://github.com/html2rss/html2rss/compare/v0.6.0...v0.7.0) (2019-10-28)


### Features

* **post_processors:** add gsub ([#53](https://github.com/html2rss/html2rss/issues/53)) ([de268ae](https://github.com/html2rss/html2rss/commit/de268ae64f2f946103523c66919806b50c6d031a))
* support enclosure on items ([#52](https://github.com/html2rss/html2rss/issues/52)) ([80a30a1](https://github.com/html2rss/html2rss/commit/80a30a1944e9a256fc9b5497589b9e20a098c444)), closes [#50](https://github.com/html2rss/html2rss/issues/50)
* **postprocessor:** always wrap img tag in an a tag in sanitze html ([#51](https://github.com/html2rss/html2rss/issues/51)) ([6c7fb88](https://github.com/html2rss/html2rss/commit/6c7fb88c9c87fb977645b21a7b13e70367b10608))
* handle json array response ([#49](https://github.com/html2rss/html2rss/issues/49)) ([288c2af](https://github.com/html2rss/html2rss/commit/288c2af09909d5c54109f8ce6a566914dd188b0b))
* use zeitwerk for autoloading ([#47](https://github.com/html2rss/html2rss/issues/47)) ([bce523d](https://github.com/html2rss/html2rss/commit/bce523d64a58c52490a3326c3f85beba2e46088f))



# [0.6.0](https://github.com/html2rss/html2rss/compare/v0.5.2...v0.6.0) (2019-10-05)


### Bug Fixes

* **specs:** simplecov does not exclude files from spec/ ([#44](https://github.com/html2rss/html2rss/issues/44)) ([b0ca780](https://github.com/html2rss/html2rss/commit/b0ca780ebb69185ef7e534e1d36bd606073dc471))


### Features

* memoize ItemExtractor lookups ([#45](https://github.com/html2rss/html2rss/issues/45)) ([e88321c](https://github.com/html2rss/html2rss/commit/e88321c52b40c3f1581a576ae50e7f3416df4772))
* support setting of request headers in feed config ([#41](https://github.com/html2rss/html2rss/issues/41)) ([a7aca11](https://github.com/html2rss/html2rss/commit/a7aca11a708c4f3a3a5f9f6511c0c1e86ec63595)), closes [#38](https://github.com/html2rss/html2rss/issues/38)
* **ci:** run rubocop on ci ([#40](https://github.com/html2rss/html2rss/issues/40)) ([f4ec8d1](https://github.com/html2rss/html2rss/commit/f4ec8d15681c8a232dbad6a933f7877aec33cc4f))



## [0.5.2](https://github.com/html2rss/html2rss/compare/v0.5.1...v0.5.2) (2019-09-19)



## [0.5.1](https://github.com/html2rss/html2rss/compare/v0.5.0...v0.5.1) (2019-09-19)


### Bug Fixes

* rss contains additional categories ([#39](https://github.com/html2rss/html2rss/issues/39)) ([ed164ef](https://github.com/html2rss/html2rss/commit/ed164efdf5e2775f30130d0949d96ecee4f9cea0))



# [0.5.0](https://github.com/html2rss/html2rss/compare/v0.4.1...v0.5.0) (2019-09-18)


### Features

* support JSON ([#37](https://github.com/html2rss/html2rss/issues/37)) ([d258f73](https://github.com/html2rss/html2rss/commit/d258f73f30587e48f5854013fa0e67c88bb23a52))



## [0.4.1](https://github.com/html2rss/html2rss/compare/v0.4.0...v0.4.1) (2019-09-18)


### Bug Fixes

* building absolute url fails when a fragment is present ([#35](https://github.com/html2rss/html2rss/issues/35)) ([c1b6dc7](https://github.com/html2rss/html2rss/commit/c1b6dc7d72f3b93b64c81a455cfd24909de841a9))


### Features

* **postprocessors:** add html to markdown ([#34](https://github.com/html2rss/html2rss/issues/34)) ([6a4a462](https://github.com/html2rss/html2rss/commit/6a4a46269d0d185923f1e817141ac7901ce74784))



# [0.4.0](https://github.com/html2rss/html2rss/compare/v0.3.3...v0.4.0) (2019-09-07)


### Bug Fixes

* **template:** breaks when any method returns nil ([#32](https://github.com/html2rss/html2rss/issues/32)) ([0709958](https://github.com/html2rss/html2rss/commit/0709958a2bf3e5df6dbd7709b2f7734c7e9b3978))


### Features

* **parse_time:** support setting of a time_zone ([#31](https://github.com/html2rss/html2rss/issues/31)) ([cecbe5e](https://github.com/html2rss/html2rss/commit/cecbe5eb7b8586f036169480cd009c8be69b4f22)), closes [#19](https://github.com/html2rss/html2rss/issues/19)
* **postprocessor:** add referrer-policy on img tag in sanitze html ([#24](https://github.com/html2rss/html2rss/issues/24)) ([a3b1d18](https://github.com/html2rss/html2rss/commit/a3b1d18cc0eb4ff9c359d591357ed631e44c8dd8))
* **rubocop:** add rubocop-rspec and (auto-)fix issues ([#22](https://github.com/html2rss/html2rss/issues/22)) ([dd539f6](https://github.com/html2rss/html2rss/commit/dd539f66fa31a5735090663b0611e8ba56c7c34f))
* **rubocop:** enable more performance cops and relax config ([#21](https://github.com/html2rss/html2rss/issues/21)) ([67132bb](https://github.com/html2rss/html2rss/commit/67132bba2ac13ca7ed694e965fb8770a1f635de2))
* **sanitize_html:** rewrite relative urls to absolute in a and img elements ([#30](https://github.com/html2rss/html2rss/issues/30)) ([caf4e80](https://github.com/html2rss/html2rss/commit/caf4e80f342d32ec193868ebeacc5db989947594))
* **sanitze_html:** strip more attributes ([#28](https://github.com/html2rss/html2rss/issues/28)) ([9daa42e](https://github.com/html2rss/html2rss/commit/9daa42e774850c766299b5d85bf6e98d40cb9f6d)), closes [#26](https://github.com/html2rss/html2rss/issues/26)



## [0.3.3](https://github.com/html2rss/html2rss/compare/v0.3.2...v0.3.3) (2019-07-01)


### Features

* enable usage of multiple post processors ([#17](https://github.com/html2rss/html2rss/issues/17)) ([8a9f7b4](https://github.com/html2rss/html2rss/commit/8a9f7b439b266c92756d9198c8689cd4ba9813e8))



## [0.3.2](https://github.com/html2rss/html2rss/compare/v0.3.1...v0.3.2) (2019-07-01)



## [0.3.1](https://github.com/html2rss/html2rss/compare/v0.3.0...v0.3.1) (2019-06-23)


### Features

* handle string and symbol keys in config hashes ([#15](https://github.com/html2rss/html2rss/issues/15)) ([93ad824](https://github.com/html2rss/html2rss/commit/93ad82488cfb0fc497c443d4b11dc12b8eeb50e2))
* support attributes without selector, fallback to root element then ([#16](https://github.com/html2rss/html2rss/issues/16)) ([d99ae3d](https://github.com/html2rss/html2rss/commit/d99ae3d3d91ffc0a8549fd0ab6926e136126489b))



# [0.3.0](https://github.com/html2rss/html2rss/compare/v0.2.2...v0.3.0) (2019-06-20)


### Features

* add rubocop and update development deps ([#13](https://github.com/html2rss/html2rss/issues/13)) ([6e06329](https://github.com/html2rss/html2rss/commit/6e063296d05f5cbe7ee8699e11ae7c812c519814))
* change Config constructor arguments ([#14](https://github.com/html2rss/html2rss/issues/14)) ([21f8746](https://github.com/html2rss/html2rss/commit/21f8746e74d2a7c74611fb3c4ca24d5505915f73))



## [0.2.2](https://github.com/html2rss/html2rss/compare/v0.2.0...v0.2.2) (2019-01-31)


### Bug Fixes

* generates invalid feeds ([00309e7](https://github.com/html2rss/html2rss/commit/00309e7ba9a35ef0272b72b75c4410c47413a2dc))



# [0.2.0](https://github.com/html2rss/html2rss/compare/v0.1.0...v0.2.0) (2018-11-13)


### Features

* **category:** support item categories ([#10](https://github.com/html2rss/html2rss/issues/10)) ([4572bcb](https://github.com/html2rss/html2rss/commit/4572bcb33fc73a2d0cfe27afa2ba51310f71780f)), closes [#2](https://github.com/html2rss/html2rss/issues/2)



# [0.1.0](https://github.com/html2rss/html2rss/compare/v0.0.1...v0.1.0) (2018-11-04)


### Bug Fixes

* **config:** feed generation fails ([7dd5586](https://github.com/html2rss/html2rss/commit/7dd55869f79b1de76c004bf0e82d13b16b5b3f0d))
* **parse_uri:** handle non-absolute paths ([9215025](https://github.com/html2rss/html2rss/commit/921502574e4436d65a30e1d34b9b31f238336247))
* handling of url query breaks processing ([ace289e](https://github.com/html2rss/html2rss/commit/ace289e911b69cb92433cac6f1ca0403715d8286))
* only set supported attributes on rss item ([dae0d8e](https://github.com/html2rss/html2rss/commit/dae0d8e75541e810275e789a23971a61e60a2154))


### Features

* add logo [skip ci] ([857a55f](https://github.com/html2rss/html2rss/commit/857a55fd8c932930d96c47c5abe57f0507356df1))
* require updated to be present ([e1bedae](https://github.com/html2rss/html2rss/commit/e1bedaecc91e874fe24e96000612abb9cd11e9fe))
* **item_extractor:** add static and current_time ([25043dc](https://github.com/html2rss/html2rss/commit/25043dcbd8f0f4901202f4a2f66b355ac48825a8))
* **item_extractor:** handle absolute urls ([f96be00](https://github.com/html2rss/html2rss/commit/f96be00857bdcded02d52dd62ec22b9b52c803ed))
* **item_extractor:** text strips strings ([f598285](https://github.com/html2rss/html2rss/commit/f59828593dca663bdbe8699392594e2d18658f8f))
* **post_processing:** add configurable post_processing ([#5](https://github.com/html2rss/html2rss/issues/5)) ([4cf6cac](https://github.com/html2rss/html2rss/commit/4cf6cacac00bd3c0c53d584ca11274ba24b03ef7)), closes [#1](https://github.com/html2rss/html2rss/issues/1)
* **post_processor:** add substring ([6f2a32a](https://github.com/html2rss/html2rss/commit/6f2a32a6304ef9956577711173de681daf93f55f))
* **postprocessors:** add Template ([#6](https://github.com/html2rss/html2rss/issues/6)) ([f1db542](https://github.com/html2rss/html2rss/commit/f1db542e8c1e9e09a066a3cd6c8514a6ca0aa871)), closes [#4](https://github.com/html2rss/html2rss/issues/4)
* **sanitize_html:** add target="_blank" to anchors ([975a73b](https://github.com/html2rss/html2rss/commit/975a73bfd396ba5942bc0ea80eebd14cc37ad776))
* do not fail on invalid item, just skip it ([3b83d71](https://github.com/html2rss/html2rss/commit/3b83d715619abbc33b124de1945d17cb0dc7edb0))



## [0.0.1](https://github.com/html2rss/html2rss/compare/219cac849460eae3262108d886c60b9b08385a3d...v0.0.1) (2018-06-03)


### Bug Fixes

* gem's version and readme-typos ([eab39d9](https://github.com/html2rss/html2rss/commit/eab39d981efda19d4ed66d7427d240b083eb2ae4))


### Features

* **html2rss:** add initial version of the html2rss gem ([219cac8](https://github.com/html2rss/html2rss/commit/219cac849460eae3262108d886c60b9b08385a3d))



