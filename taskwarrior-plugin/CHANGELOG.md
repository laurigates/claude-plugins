# Changelog

## [1.9.1](https://github.com/laurigates/claude-plugins/compare/taskwarrior-plugin-v1.9.0...taskwarrior-plugin-v1.9.1) (2026-06-25)


### Bug Fixes

* **taskwarrior-plugin:** task-add captures UUID via working command ([#1819](https://github.com/laurigates/claude-plugins/issues/1819)) ([3f7ca1b](https://github.com/laurigates/claude-plugins/commit/3f7ca1b1d022c42d4b27ba67624f0ee14d58ac84))

## [1.9.0](https://github.com/laurigates/claude-plugins/compare/taskwarrior-plugin-v1.8.0...taskwarrior-plugin-v1.9.0) (2026-06-25)


### Features

* **taskwarrior-plugin:** on-add hook auto-links ghid from trailing #N ([#1816](https://github.com/laurigates/claude-plugins/issues/1816)) ([fb2b14c](https://github.com/laurigates/claude-plugins/commit/fb2b14c8a8d96318290baed2f2aed5c121f13c61))

## [1.8.0](https://github.com/laurigates/claude-plugins/compare/taskwarrior-plugin-v1.7.0...taskwarrior-plugin-v1.8.0) (2026-06-25)


### Features

* **taskwarrior-plugin:** on-modify native hook enforces claim invariant + auto-expires stale claims ([#1814](https://github.com/laurigates/claude-plugins/issues/1814)) ([052089a](https://github.com/laurigates/claude-plugins/commit/052089af0c0ff182c417d11827b2fcedeb0bdce5))

## [1.7.0](https://github.com/laurigates/claude-plugins/compare/taskwarrior-plugin-v1.6.0...taskwarrior-plugin-v1.7.0) (2026-06-24)


### Features

* **taskwarrior-plugin:** surface stale linked-task drift at session start ([#1794](https://github.com/laurigates/claude-plugins/issues/1794)) ([d51f874](https://github.com/laurigates/claude-plugins/commit/d51f8746d212795f05959e8d71d3dfe18d934407))

## [1.6.0](https://github.com/laurigates/claude-plugins/compare/taskwarrior-plugin-v1.5.0...taskwarrior-plugin-v1.6.0) (2026-06-20)


### Features

* **taskwarrior-plugin:** reconcile issue/PR drift, adopt native scheduling, dedup shared logic ([#1720](https://github.com/laurigates/claude-plugins/issues/1720)) ([78fc1bf](https://github.com/laurigates/claude-plugins/commit/78fc1bf378a7aeb52e58074f6199e1eef02dce21))

## [1.5.0](https://github.com/laurigates/claude-plugins/compare/taskwarrior-plugin-v1.4.0...taskwarrior-plugin-v1.5.0) (2026-06-02)


### Features

* **taskwarrior-plugin:** emit stable UUID from task-add to prevent numeric-ID-shift footgun ([#1478](https://github.com/laurigates/claude-plugins/issues/1478)) ([4e40758](https://github.com/laurigates/claude-plugins/commit/4e40758d7f1deaa72c6d29f294ee5bfe74db0297))

## [1.4.0](https://github.com/laurigates/claude-plugins/compare/taskwarrior-plugin-v1.3.2...taskwarrior-plugin-v1.4.0) (2026-05-24)


### Features

* **hooks-plugin:** add SessionStart drift-nudge architecture ([#1401](https://github.com/laurigates/claude-plugins/issues/1401)) ([47815e2](https://github.com/laurigates/claude-plugins/commit/47815e2035923e9c714142597cd6ed4ad43e9f7e))

## [1.3.2](https://github.com/laurigates/claude-plugins/compare/taskwarrior-plugin-v1.3.1...taskwarrior-plugin-v1.3.2) (2026-05-22)


### Documentation

* **taskwarrior-plugin:** document bulk-close patterns in task-done ([#1370](https://github.com/laurigates/claude-plugins/issues/1370)) ([39321ac](https://github.com/laurigates/claude-plugins/commit/39321ac6d2fefcf21e28ba777ae6de0ca62faecb))

## [1.3.1](https://github.com/laurigates/claude-plugins/compare/taskwarrior-plugin-v1.3.0...taskwarrior-plugin-v1.3.1) (2026-05-14)


### Code Refactoring

* **taskwarrior-plugin:** further tighten descriptions under 180 chars ([629fad9](https://github.com/laurigates/claude-plugins/commit/629fad936158464f7435c603ecdf4a0312e3784a))
* **taskwarrior-plugin:** tighten skill descriptions (continuation) ([d7ae5ad](https://github.com/laurigates/claude-plugins/commit/d7ae5ad40dce72db789e058834a1ba25cceb8a10))
* **taskwarrior-plugin:** tighten skill descriptions for listing budget ([f574fe0](https://github.com/laurigates/claude-plugins/commit/f574fe0495428f4ca8b47bdf099304249e6612b6))

## [1.3.0](https://github.com/laurigates/claude-plugins/compare/taskwarrior-plugin-v1.2.5...taskwarrior-plugin-v1.3.0) (2026-05-10)


### Features

* **taskwarrior-plugin:** add agent identity claims via task-claim/task-release ([#1296](https://github.com/laurigates/claude-plugins/issues/1296)) ([e1d0df2](https://github.com/laurigates/claude-plugins/commit/e1d0df2adeac0d2704884fc9c7ebc1968b8c85fb))

## [1.2.5](https://github.com/laurigates/claude-plugins/compare/taskwarrior-plugin-v1.2.4...taskwarrior-plugin-v1.2.5) (2026-05-09)


### Documentation

* **taskwarrior-plugin:** add task-tracking lifecycle doc (resolves [#1293](https://github.com/laurigates/claude-plugins/issues/1293) conflicts) ([#1294](https://github.com/laurigates/claude-plugins/issues/1294)) ([53feabc](https://github.com/laurigates/claude-plugins/commit/53feabcf605aea12544c248fa3e09ca0f94b9e2a))

## [1.2.4](https://github.com/laurigates/claude-plugins/compare/taskwarrior-plugin-v1.2.3...taskwarrior-plugin-v1.2.4) (2026-05-09)


### Documentation

* trim oversized SKILL.md descriptions across 41 plugins ([#1265](https://github.com/laurigates/claude-plugins/issues/1265)) ([e13d9f4](https://github.com/laurigates/claude-plugins/commit/e13d9f46a010559082c6d5eb61b0cb891843bf97))

## [1.2.3](https://github.com/laurigates/claude-plugins/compare/taskwarrior-plugin-v1.2.2...taskwarrior-plugin-v1.2.3) (2026-05-06)


### Bug Fixes

* **taskwarrior-plugin:** document hyphen tag-parser quirk and switch to underscores ([#1248](https://github.com/laurigates/claude-plugins/issues/1248)) ([5b3ba02](https://github.com/laurigates/claude-plugins/commit/5b3ba024caf0e2baa1ea9331adc81598427f47e9))

## [1.2.2](https://github.com/laurigates/claude-plugins/compare/taskwarrior-plugin-v1.2.1...taskwarrior-plugin-v1.2.2) (2026-04-29)


### Bug Fixes

* **taskwarrior-plugin:** use task --version and git remote in Context probes ([#1210](https://github.com/laurigates/claude-plugins/issues/1210)) ([294bd08](https://github.com/laurigates/claude-plugins/commit/294bd08a59dda24c1a0d0afe13731b157b0d7e8a))

## [1.2.1](https://github.com/laurigates/claude-plugins/compare/taskwarrior-plugin-v1.2.0...taskwarrior-plugin-v1.2.1) (2026-04-25)


### Documentation

* **taskwarrior-plugin:** standardise When to Use tables ([#1175](https://github.com/laurigates/claude-plugins/issues/1175)) ([835035f](https://github.com/laurigates/claude-plugins/commit/835035fe38d7fff9c6da04fa6702c1790c2a0fc8)), closes [#1156](https://github.com/laurigates/claude-plugins/issues/1156)

## [1.2.0](https://github.com/laurigates/claude-plugins/compare/taskwarrior-plugin-v1.1.0...taskwarrior-plugin-v1.2.0) (2026-04-25)


### Features

* **taskwarrior-plugin:** scope queries to current project by default ([#1149](https://github.com/laurigates/claude-plugins/issues/1149)) ([bbf2ab9](https://github.com/laurigates/claude-plugins/commit/bbf2ab9eb82761501daefc84d0a14eb6264f8583))

## [1.1.0](https://github.com/laurigates/claude-plugins/compare/taskwarrior-plugin-v1.0.0...taskwarrior-plugin-v1.1.0) (2026-04-24)


### Features

* **taskwarrior-plugin:** add coordination layer for multi-agent work ([#1134](https://github.com/laurigates/claude-plugins/issues/1134)) ([ab5e111](https://github.com/laurigates/claude-plugins/commit/ab5e1116272068e7d36692c815e411e84f48bf83))
