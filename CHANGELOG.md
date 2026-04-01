# Changelog

## [0.3.2](https://github.com/alxdr3k/xef-scale/compare/0.3.1...0.3.2) (2026-01-25)


### Bug Fixes

* db:migrate and CI improvements ([5e7f80d](https://github.com/alxdr3k/xef-scale/commit/5e7f80da791cef4506284878a2b69cc6b6673ccf))
* use db:migrate instead of db:prepare in entrypoint ([e9ad004](https://github.com/alxdr3k/xef-scale/commit/e9ad0045bcddb619f774a9ff229c4996548da055))

## [0.3.1](https://github.com/alxdr3k/xef-scale/compare/0.3.0...0.3.1) (2026-01-25)


### Bug Fixes

* add python3 for Excel parsing ([#11](https://github.com/alxdr3k/xef-scale/issues/11)) ([5291a8d](https://github.com/alxdr3k/xef-scale/commit/5291a8de8006f5d8ecd265d1330eb17c8623e992))

## [0.3.0](https://github.com/alxdr3k/xef-scale/compare/0.2.0...0.3.0) (2026-01-24)


### Features

* add SSH key setup for deploy workflows ([47bfdfb](https://github.com/alxdr3k/xef-scale/commit/47bfdfb2e65e436cfb1459f3aa2671b0c438c934))
* switch to Cloudflare Tunnel for deployments ([e654ecb](https://github.com/alxdr3k/xef-scale/commit/e654ecb644b00f8d653ef6bb0eead64d9362ed6f))


### Bug Fixes

* add --id and --secret flags to cloudflared ([8515f65](https://github.com/alxdr3k/xef-scale/commit/8515f6514a55a76f0fcdb426c22f7b946c3b553a))
* use SSH ProxyCommand for cloudflared ([d0876d4](https://github.com/alxdr3k/xef-scale/commit/d0876d4661989c25664e5e731582234179ac5fc3))
* use SSH ProxyCommand in release.yml ([3ee79ec](https://github.com/alxdr3k/xef-scale/commit/3ee79ec9cf645032680c7ef31458f13718678c55))

## [0.2.0](https://github.com/alxdr3k/xef-scale/compare/0.1.1...0.2.0) (2026-01-23)


### Features

* add CD deploy workflows (stg auto, prd with approval) ([c93c952](https://github.com/alxdr3k/xef-scale/commit/c93c952bf99a46413ad2156a802c6c76b35fd948))
* **review:** add duplicate confirmation UI to review page ([5100531](https://github.com/alxdr3k/xef-scale/commit/5100531c3c63a2c4b72b58b36593b84c415b0d59))

## [0.1.1](https://github.com/alxdr3k/expense-tracker/compare/0.1.0...0.1.1) (2026-01-23)


### Bug Fixes

* add yarn.lock for Docker build ([898276b](https://github.com/alxdr3k/expense-tracker/commit/898276b44a0c514989560c19c6de97fedce13c8e))

## 0.1.0 (2026-01-23)


### Features

* add ActiveRecord models with validations and associations ([65e51c9](https://github.com/alxdr3k/expense-tracker/commit/65e51c9ceca082042d804d260050b23977a8bd82))
* add auto-filter Stimulus controller for instant search ([280fbcd](https://github.com/alxdr3k/expense-tracker/commit/280fbcd271bc7d6c91e6f004cf3e6667eaee37c6))
* add category click feature to monthly dashboard ([316ce7d](https://github.com/alxdr3k/expense-tracker/commit/316ce7d39850339dee77df403ee48abbad6a3ce8))
* add CategoryMapping model for merchant-to-category mapping ([97f6f47](https://github.com/alxdr3k/expense-tracker/commit/97f6f47c58562453e2fec4647ba2d2bfba5d51c8))
* add controllers for expense tracking application ([0f8aeac](https://github.com/alxdr3k/expense-tracker/commit/0f8aeac5b23e71de3e0cd5882d674b5592804000))
* add database schema and migrations ([5d95e46](https://github.com/alxdr3k/expense-tracker/commit/5d95e46305b555e42188572f4c86d56536923eb2))
* add database schema for transaction review workflow ([e7b0c73](https://github.com/alxdr3k/expense-tracker/commit/e7b0c73212b548f8d0c2bbfc2dfb5e3bce1c6f9e))
* add DatabaseBackupService for SQLite backup/restore ([b755c05](https://github.com/alxdr3k/expense-tracker/commit/b755c05263f0ca0366f351fad9eea41913279d79))
* add discard action for pending review sessions ([d272df4](https://github.com/alxdr3k/expense-tracker/commit/d272df4c952e90de35ffba20773fcd9d6bc767c5))
* add FileParsingJob for async file processing ([2141de8](https://github.com/alxdr3k/expense-tracker/commit/2141de844788f13e69db32676f84255085450505))
* add Gemini AI service for automatic category suggestion ([f22573b](https://github.com/alxdr3k/expense-tracker/commit/f22573bf86558d3f7c74d481043fc7af3cc382be))
* add import rake task for bulk transaction import from txt files ([c8224f1](https://github.com/alxdr3k/expense-tracker/commit/c8224f1363fec76ac0ed7de7757263464e058d3b))
* add inline category selector to transactions list ([de44d71](https://github.com/alxdr3k/expense-tracker/commit/de44d71966005cb094dff8e073242033b76505eb))
* add inline edit modal for transactions ([8be6110](https://github.com/alxdr3k/expense-tracker/commit/8be6110586c1eb9ad9633ef552e2674820a73da3))
* add month picker component for quick date navigation ([9cfc532](https://github.com/alxdr3k/expense-tracker/commit/9cfc53274a3e19cb5a183ba7862159a819e2f617))
* add Python-based Excel parser for reliable .xls support ([903970f](https://github.com/alxdr3k/expense-tracker/commit/903970fd1154812b068fbf71da9334e228b0a025))
* add review page and notification UI ([988a4a9](https://github.com/alxdr3k/expense-tracker/commit/988a4a9fa03e3b47a6c57caa322a1c49f2b6f499))
* add ReviewsController and NotificationsController ([beb7267](https://github.com/alxdr3k/expense-tracker/commit/beb7267350ebbe2766fa4866c084e73199256dfb))
* add Ruby-based financial statement parsers ([1f33a4e](https://github.com/alxdr3k/expense-tracker/commit/1f33a4e5efe40c09e9068d35efc4095c74baf0ac))
* add slideover component for category creation ([c0fa56a](https://github.com/alxdr3k/expense-tracker/commit/c0fa56a6e49789986f2c6993177c722d5798ff1b))
* add Stimulus controllers for review UI ([e27ad33](https://github.com/alxdr3k/expense-tracker/commit/e27ad3303cf82bea73033592f83b245ae272f3a8))
* add transaction review logic to models ([4fa2e69](https://github.com/alxdr3k/expense-tracker/commit/4fa2e693b86a9fa53ebce2cc30e07bcbaa75ad24))
* add Turbo Stream views for CRUD operations ([dba5e0c](https://github.com/alxdr3k/expense-tracker/commit/dba5e0cd4db65d0f30a2450015710415468c6a3b))
* add views and frontend assets ([b79f476](https://github.com/alxdr3k/expense-tracker/commit/b79f476a2fc02f6021114b3d729b742815fc68e3))
* add year picker to yearly dashboard ([06d1558](https://github.com/alxdr3k/expense-tracker/commit/06d1558910e8a66f1f64391de8776371200ced58))
* add yearly dashboard with Chart.js visualization ([caa44a8](https://github.com/alxdr3k/expense-tracker/commit/caa44a87c42d7d917c77a8f4ddd102a8e4d91fbb))
* auto-create category mappings when manually categorizing transactions ([611ee7b](https://github.com/alxdr3k/expense-tracker/commit/611ee7bed3d657befa1fd3ff1cf751d7a83291ae))
* enhance dashboard with category chart colors and month picker ([5ca573e](https://github.com/alxdr3k/expense-tracker/commit/5ca573e37559cd3d3cfbcd8a4b780ce3ff92df6e))
* improve allowances page with unmark button and month picker ([15f310e](https://github.com/alxdr3k/expense-tracker/commit/15f310eeee274f8530f8ca3b99a8491e14809117))
* improve review page with description column and column reorder ([b4833a7](https://github.com/alxdr3k/expense-tracker/commit/b4833a70afac104929b390ce67a609abae9b278c))
* improve transaction modal UX for add/edit ([ede7a4d](https://github.com/alxdr3k/expense-tracker/commit/ede7a4db8f9480560ef9f08293f81dceb201f133))
* initialize Rails 8.1 application with base configuration ([77cfc5e](https://github.com/alxdr3k/expense-tracker/commit/77cfc5e727e65ff190ee7aeb933d3a4aa5ef3900))
* modernize flash notifications with toast UX ([a7117f2](https://github.com/alxdr3k/expense-tracker/commit/a7117f21730f902d34ddc5306c0bb8bfa648c258))
* update FileParsingJob to create pending_review transactions ([8df0f67](https://github.com/alxdr3k/expense-tracker/commit/8df0f676d17ccf2ed5841f1a84f3fc28aad844c2))
* update transactions page UI and column order ([2a9c569](https://github.com/alxdr3k/expense-tracker/commit/2a9c5691d94bec80aea06a065062a7c50a6bbe86))


### Bug Fixes

* apply button styles directly to button elements ([d7c57e2](https://github.com/alxdr3k/expense-tracker/commit/d7c57e29ed96478186266eb4006e4a92a70df271))
* change commit button color to indigo for visibility ([5a48c20](https://github.com/alxdr3k/expense-tracker/commit/5a48c203e5d9c906be846d805649ec0455f35d3f))
* **ci:** resolve all CI failures ([63c0b22](https://github.com/alxdr3k/expense-tracker/commit/63c0b225ea291e37b6c9413849c5f4f22d2515e8))
* **ci:** use actions/checkout@v4 instead of non-existent v6 ([a014aa0](https://github.com/alxdr3k/expense-tracker/commit/a014aa0a836962f283293723dccde2ab61820f79))
* immediate removal from allowance list on unmark ([b9bce48](https://github.com/alxdr3k/expense-tracker/commit/b9bce4895827b43ceb012c5f81c3a11997bbb76a))
* improve UI/UX for Turbo and better navigation ([a7f4261](https://github.com/alxdr3k/expense-tracker/commit/a7f42616c6eee4406532018ae7435f9d24d17511))
* resolve category feature bugs ([1573a6f](https://github.com/alxdr3k/expense-tracker/commit/1573a6f0a1e452a0a905ec40e6aa42b2c51f6dcb))
* resolve remaining category feature bugs ([aae6b37](https://github.com/alxdr3k/expense-tracker/commit/aae6b3717689142155cb86d20e89a279ab4b687b))
* resolve transaction CRUD and turbo stream issues ([256872e](https://github.com/alxdr3k/expense-tracker/commit/256872e997d5917cdf7df2ca6d89718fe7dd48c6))
* sync Gemfile.lock and update outdated tests ([e2f61b5](https://github.com/alxdr3k/expense-tracker/commit/e2f61b5a6748ab90a976153b56e5560a843d2ded))
* update Stimulus manifest with new controllers ([ecea323](https://github.com/alxdr3k/expense-tracker/commit/ecea323a0bbd2e9a641959f51fe3671ad7e74cad))
* use green button for commit action and rebuild CSS ([970b503](https://github.com/alxdr3k/expense-tracker/commit/970b503c4915339b60b754e3e939c970b83570c8))
