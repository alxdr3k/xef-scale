# Changelog

## [0.4.0](https://github.com/alxdr3k/xef-scale/compare/0.3.2...0.4.0) (2026-04-28)


### ⚠ BREAKING CHANGES

* **parser:** ShinhanTextParser class is removed, use ShinhanCardParser instead

### Features

* add a calendar dashboard as the daily entry point ([3794256](https://github.com/alxdr3k/xef-scale/commit/37942565d608e578b5282ecdd1c54f5e6590ffa9))
* add AI text parsing engine (Phase B2) ([cf861a6](https://github.com/alxdr3k/xef-scale/commit/cf861a6d9fbc80772affc4b2adfc2c9bb2c958a8))
* add B0 AI parsing benchmark (25 Korean financial SMS) ([f813d95](https://github.com/alxdr3k/xef-scale/commit/f813d952c05a465b47ceb307c1e18ddc3b4f74c0))
* add budget tracking with progress bar and threshold alerts ([5b88e46](https://github.com/alxdr3k/xef-scale/commit/5b88e46178a659eafd65e6e48cbee7dff46e5534))
* add installment fields to transactions ([08e016f](https://github.com/alxdr3k/xef-scale/commit/08e016fd02161fd47a93b211f8d7faa7e1a3ecd3))
* add installment parsing and real-time updates ([e7767a2](https://github.com/alxdr3k/xef-scale/commit/e7767a25cb7a62f3f85eb8ab58ddfb1bb66eb06d))
* add mobile bottom nav and dashboard hero card ([4f3b20a](https://github.com/alxdr3k/xef-scale/commit/4f3b20aff17057d13719c5410ae67561d46cc47e))
* add onboarding overlay and institution guide in settings ([65c5dc1](https://github.com/alxdr3k/xef-scale/commit/65c5dc155542d377a3b91e35cd8edec64a49b6c9))
* add read-only REST API with API key auth and MCP config ([0e1175e](https://github.com/alxdr3k/xef-scale/commit/0e1175e3d9aa7beef00e05442a4d0e5edf3ae99c))
* add recurring payment detection and dashboard tab ([90d93bd](https://github.com/alxdr3k/xef-scale/commit/90d93bdcd3c2efc944f4c3cb5961bfc4d599d702))
* add text paste UI for AI parsing (Phase B4) ([45403fd](https://github.com/alxdr3k/xef-scale/commit/45403fdcd295180417d51ee415ae4e638d394762))
* add Transaction Write API (Phase B1) ([d9d250d](https://github.com/alxdr3k/xef-scale/commit/d9d250dec07e07afaf49a85a2641f5dff364282c))
* add Turbo Streams real-time updates ([c9611be](https://github.com/alxdr3k/xef-scale/commit/c9611be6a65ae6b99eb2b024e8b98a5282a2b998))
* **allowances:** add bulk unmark allowance action ([7060636](https://github.com/alxdr3k/xef-scale/commit/706063667ab57cc2ebf21e5403996bff77b3ce3c))
* attribute transactions with source_type and parse_confidence ([1d9c32a](https://github.com/alxdr3k/xef-scale/commit/1d9c32a359a8094aca0bd629e00b462298157333))
* **auth:** add styled Devise views matching app design ([79ee79c](https://github.com/alxdr3k/xef-scale/commit/79ee79c52418e027caa41d70e4379e14db9f830f))
* **auth:** add styled Devise views matching app design ([2ac14b3](https://github.com/alxdr3k/xef-scale/commit/2ac14b31c6acb085db307bfcd19c2e23f363b167))
* auto-join workspace after sign-in via invitation link ([debe73d](https://github.com/alxdr3k/xef-scale/commit/debe73d3e75bae48b259ce11af40f96b7de211d8))
* auto-submit upload form when non-image files are selected ([c00e362](https://github.com/alxdr3k/xef-scale/commit/c00e36227410f45155db5ccf8ab1a83c3ed86ca4))
* **bulk-select:** add row-click selection with shift-click range support ([fc79dd9](https://github.com/alxdr3k/xef-scale/commit/fc79dd9ce8b1aea52ae57d5161d96d183cae45f3))
* **category:** add description-based category auto-mapping ([3a358cc](https://github.com/alxdr3k/xef-scale/commit/3a358ccc34cfea9cb8340c70a97e20b0a9147e14))
* **category:** add description-based category auto-mapping ([28b3de1](https://github.com/alxdr3k/xef-scale/commit/28b3de123a8118c8071f0772183974f0caf209f8))
* **comments:** add Comment model, controller, and routes ([2b5c4cb](https://github.com/alxdr3k/xef-scale/commit/2b5c4cbde184842074df9c6b6574a795dda2dedc))
* **comments:** add comment panel UI and badge ([a2a29fa](https://github.com/alxdr3k/xef-scale/commit/a2a29fadaf21f6c77a528e8a0667556b531886f2))
* **dashboard:** add calendar action strip and Turbo Frame day panel ([1c4dea0](https://github.com/alxdr3k/xef-scale/commit/1c4dea00e559c9b2ee3ec53694902ece4b7f0fea))
* **db:** add comments table and merge description into notes ([560eea0](https://github.com/alxdr3k/xef-scale/commit/560eea0d3673167250b522911a05a5ac41715cec))
* drop Excel/PDF/CSV/HTML upload, image screenshots only ([2cb4372](https://github.com/alxdr3k/xef-scale/commit/2cb43721322496e864ded147162856286b6b3117))
* drop statement password storage via data migration ([cc30bea](https://github.com/alxdr3k/xef-scale/commit/cc30bea0f4a8cd3503fe469dd90701d6df9516a0))
* **duplicates:** add drag-and-drop, inline editing, and CSRF refactor ([4371d56](https://github.com/alxdr3k/xef-scale/commit/4371d567ca0300a1a0c4616b7f79e2d2cd646e4f))
* gate AI features behind workspace consent and per-feature toggles ([eca793e](https://github.com/alxdr3k/xef-scale/commit/eca793e7a9b115716de076818177ff98c7451aa5))
* GPT 리뷰 반영 — UI 개선, Calendar action strip, E2E 전면 갱신 ([757ae7e](https://github.com/alxdr3k/xef-scale/commit/757ae7efe8f5fe752c5e516b55c1a3eef9889db4))
* implement Phase B - AI text parsing, Write API, text paste UI ([#62](https://github.com/alxdr3k/xef-scale/issues/62)) ([aafe270](https://github.com/alxdr3k/xef-scale/commit/aafe2702c05c85156146be43a9c50e43f5764605))
* **mapping:** add match_type and amount fields to category mappings ([3e79047](https://github.com/alxdr3k/xef-scale/commit/3e790476c4102d0a2edb289fbff0581e4fe09ed3))
* notify all workspace members on parsing completion ([2ce3931](https://github.com/alxdr3k/xef-scale/commit/2ce39317af306d11d395815208c1671059f35aba))
* **parser:** add benefit tracking and signed amount to Hana Card parser ([69087ab](https://github.com/alxdr3k/xef-scale/commit/69087abec2954aa0167c761538ede0da7f1b6187))
* **parser:** add Hana Card encrypted HTML parser ([60532ce](https://github.com/alxdr3k/xef-scale/commit/60532ce034a519fc7d40fd09d3d9c6a75202003a))
* **parser:** add installment parsing for Hana Card statements ([713c747](https://github.com/alxdr3k/xef-scale/commit/713c7470f6edf96f94390ba4686be2ad17ab774e))
* **parser:** add MG Bank (새마을금고) parser support ([bf78ec5](https://github.com/alxdr3k/xef-scale/commit/bf78ec538a846da0a67d9afa8b65ded9381095a3))
* **parser:** add password support and excluded merchant filtering ([cb9c394](https://github.com/alxdr3k/xef-scale/commit/cb9c3942d355552e921c98520fc69981d73ea769))
* **parser:** add Samsung Card parser and cancellation support ([fca463b](https://github.com/alxdr3k/xef-scale/commit/fca463bbf9d2fef2132cda611384cbd86e5b2649))
* **parser:** add Samsung Card statement parser ([db43e9f](https://github.com/alxdr3k/xef-scale/commit/db43e9fd321dd469e9e16a2f240388f92a44d9d4))
* **parser:** add text paste parsing for Shinhan Card statements ([f403374](https://github.com/alxdr3k/xef-scale/commit/f403374229913d9bf0f6778e4893c1acfd878f50))
* **parser:** relax duplicate detection to date+amount only ([68e3d67](https://github.com/alxdr3k/xef-scale/commit/68e3d67371f1ee41edfb3b9c98d438ae23467670))
* **parsing-sessions:** add notes feature to upload history ([b494405](https://github.com/alxdr3k/xef-scale/commit/b494405b5d75e23972d9e7ab7374ba65231004ee))
* Phase A — 가족 공유 UX, REST API, 예산/반복결제 ([e9383b8](https://github.com/alxdr3k/xef-scale/commit/e9383b8aed223250cd5f723a411ed2759cc7dc79))
* rank duplicate matches by confidence instead of treating every date+amount collision the same ([cb403fa](https://github.com/alxdr3k/xef-scale/commit/cb403fa5c394a1c41a9f9acb69776ecd2cbde49f))
* **reviews:** improve bulk-select with inline-edit compatibility ([5a53a95](https://github.com/alxdr3k/xef-scale/commit/5a53a9506be1b88f6aff33ff6b3c25dd955f48ef))
* **settings:** add exclude card withdrawals option ([9673f74](https://github.com/alxdr3k/xef-scale/commit/9673f747bede5e84bac58e32b51a95eaf834ba8a))
* store SMS cancellation transactions as negative amounts ([3a647d1](https://github.com/alxdr3k/xef-scale/commit/3a647d118d4daa5837ac45ff72e042ab7b4db6b7))
* store SMS cancellation transactions as negative amounts ([e70cf54](https://github.com/alxdr3k/xef-scale/commit/e70cf54c8d84bab84132735d3c9076c8e64545dc))
* surface a diff-style summary after a parsing session is committed ([843b9da](https://github.com/alxdr3k/xef-scale/commit/843b9da796ad06230d1b38e8414933ff9aaa4ace))
* **transactions:** add bulk actions with floating action bar ([1e667bd](https://github.com/alxdr3k/xef-scale/commit/1e667bd85bb7709ada4ebc0aaf5151f3dbe2f436))
* **transactions:** add duplicate detection modal ([cc13dd9](https://github.com/alxdr3k/xef-scale/commit/cc13dd965a7b56490f450e9513d6bed967de9848))
* **transactions:** add inline cell editing for transaction fields ([07be572](https://github.com/alxdr3k/xef-scale/commit/07be572bdf5d17aa67df23681260402e7607c59b))
* **ui:** add category mapping rules management UI ([23813d0](https://github.com/alxdr3k/xef-scale/commit/23813d03e5fabe344b4b21bf5e7e5a48367233a8))
* **ui:** add date update hint for installment transactions in review ([f959a2d](https://github.com/alxdr3k/xef-scale/commit/f959a2d9a93850144c9cfb6b6cb74864f022ea92))
* **ui:** add installment popover for payment type editing ([be2f7d4](https://github.com/alxdr3k/xef-scale/commit/be2f7d40d71711c5498e7fec1305a78ea85f52de))
* **ui:** add payment type cell partial ([1f63d00](https://github.com/alxdr3k/xef-scale/commit/1f63d0080724265259771835fb5bc59f1bc82550))
* **ui:** add preset color palette for category color picker ([43de0f3](https://github.com/alxdr3k/xef-scale/commit/43de0f32b9212ebc2ef540141d3ec94c2d9f4960))
* **ui:** add source popover to institution cell ([df4ebac](https://github.com/alxdr3k/xef-scale/commit/df4ebac49276231a11901f0b5a0045409971f7d6))
* **ui:** broadcast new category to all dropdowns ([935ebc4](https://github.com/alxdr3k/xef-scale/commit/935ebc429dc512b9825fde7890df140f8822fe39))
* **ui:** display installment badge on transaction rows ([b9881ee](https://github.com/alxdr3k/xef-scale/commit/b9881eedfaf795cf726539df966b81e8f6b370d8))
* **ui:** improve parsing session list and duplicate card ([ed70988](https://github.com/alxdr3k/xef-scale/commit/ed709884d73fc66d25cf3a3247fafcd752beb722))
* **ui:** replace delete buttons with note panel and improve inline editing ([2db31c6](https://github.com/alxdr3k/xef-scale/commit/2db31c6f5f615201fd7c459b0c07c1365e7da41b))
* **ui:** replace floating action bar with Gmail-style selection toolbar ([bd99de4](https://github.com/alxdr3k/xef-scale/commit/bd99de47c7949fdbc8a6aa931611bdf8c613146c))
* **ui:** show notes badge in category transactions panel ([7d260ba](https://github.com/alxdr3k/xef-scale/commit/7d260ba84a3a50e1b397fb3203fb37490986b577))
* **upload:** add Gemini Vision OCR for image file parsing ([b49da06](https://github.com/alxdr3k/xef-scale/commit/b49da06157f670064e809a2f424adcd2d6ee1d82))
* **upload:** add multi-file upload and bulk discard ([efa2ea5](https://github.com/alxdr3k/xef-scale/commit/efa2ea5fe0bd5c539e7cb6f175449e5361baae0c))
* UX redesign - stacked cards, auto-commit, mobile history ([7ac9613](https://github.com/alxdr3k/xef-scale/commit/7ac9613a5dbbeae405ab39f8529f1406b00dfd8d))
* UX redesign - stacked cards, auto-commit, mobile history ([cbe80ba](https://github.com/alxdr3k/xef-scale/commit/cbe80ba3349650c7c3dccefb8dd32566902fcdd2))
* **ux:** replace '거래' with '결제' across all UI text ([5d95890](https://github.com/alxdr3k/xef-scale/commit/5d958907b7e1343354647ee02598bd512f21a778))
* **ux:** replace '거래' with '결제' across all UI text ([085b3e0](https://github.com/alxdr3k/xef-scale/commit/085b3e05518b0982c44955d9c301aa59dd5ecadc))


### Bug Fixes

* add queue database config for test environment ([1f801f0](https://github.com/alxdr3k/xef-scale/commit/1f801f0808bf16013f5bd6bd6620f626fc0a6100))
* add return after unauthorized render and validate API params ([a855069](https://github.com/alxdr3k/xef-scale/commit/a855069bf5c5dec3f0911c07c1869cc1d38b6b5a))
* address review and security audit findings ([5c432d7](https://github.com/alxdr3k/xef-scale/commit/5c432d73153bdb3474c145973293da9657a68fd8))
* address security review findings on PR [#62](https://github.com/alxdr3k/xef-scale/issues/62) ([b67eab6](https://github.com/alxdr3k/xef-scale/commit/b67eab614c0f35b03ff6e8b3d24171cfc89655ff))
* apply index filters to CSV export so the file matches the screen ([de257b2](https://github.com/alxdr3k/xef-scale/commit/de257b23fb140e8735633feb83d80a63395aa555))
* **auth:** address Codex review — form_with, app_name helper, accessibility ([c97fe85](https://github.com/alxdr3k/xef-scale/commit/c97fe85feccf8c15a7a8c9285063e05f92e6c8be))
* **calendar:** add distinct filters for review/duplicate badges and fix E2E helper ([e5541f5](https://github.com/alxdr3k/xef-scale/commit/e5541f59b9adc4593bcfbebf51ae6d1bb7244321))
* **calendar:** add turbo_frame _top to eager-rendered monthly link ([071fbf1](https://github.com/alxdr3k/xef-scale/commit/071fbf1c465a2d2f54d9cb7728929c33a89f6583))
* **calendar:** address P2 codex review issues ([22921db](https://github.com/alxdr3k/xef-scale/commit/22921db4a5f7301a77a49bdd4df94e53f1841450))
* **calendar:** address second round P2 codex review issues ([5d26495](https://github.com/alxdr3k/xef-scale/commit/5d264959ceea93725f6f79bccf96f0e1ee72b439))
* **calendar:** break frame nav for monthly link and align filter date basis ([5cc9f42](https://github.com/alxdr3k/xef-scale/commit/5cc9f42b86cfb5f0b4b1ff583706dcb52978865d))
* **calendar:** scope review/duplicate badge links to active month ([2190a68](https://github.com/alxdr3k/xef-scale/commit/2190a6840073ce76a7e6a249b02a8b0e426b097f))
* CI failures — add schema for new tables, fix RuboCop violations ([2254b99](https://github.com/alxdr3k/xef-scale/commit/2254b99bed210b21370436d2279bb8f44301f908))
* **ci+migration:** build assets in e2e, fix FK delete order, purge processed_file on destroy ([e451931](https://github.com/alxdr3k/xef-scale/commit/e451931c298c5177ca1ae0ca2b78512a5a6a04c9))
* **ci:** add git user config and fix shell logic in deploy jobs ([1c21322](https://github.com/alxdr3k/xef-scale/commit/1c21322dc5150caed3766242b38ffb0d3b4cab79))
* **ci:** fix deploy-stg git commit failure (exit code 128) ([1fdfa3a](https://github.com/alxdr3k/xef-scale/commit/1fdfa3afc8f3599065af65b38ee98b984cd85117))
* close AI consent gap, switch home to calendar, and clarify duplicate review ([f982448](https://github.com/alxdr3k/xef-scale/commit/f982448e848f85b10301268fe9dde4a41f032315))
* close AI consent gap, switch home to calendar, and clarify duplicate review ([3ae558c](https://github.com/alxdr3k/xef-scale/commit/3ae558c13366be4baee9640d24ff7172b24380ff))
* close data integrity gaps around import, commit, and uploads ([5f98d9a](https://github.com/alxdr3k/xef-scale/commit/5f98d9aa36f25194fb5372bb509302bc3a782f55))
* close data integrity gaps around import, commit, and uploads ([5160766](https://github.com/alxdr3k/xef-scale/commit/51607664bc2baffc2debe2b27ffcd1fc378228c8))
* **codex-loop:** comprehensive baseline accuracy and robustness improvements ([#101](https://github.com/alxdr3k/xef-scale/issues/101)) ([e14e848](https://github.com/alxdr3k/xef-scale/commit/e14e8483901f26a3bcced7a15923ee919bf1c492))
* **codex-loop:** emit all unseen feedback and use pass reaction ([#99](https://github.com/alxdr3k/xef-scale/issues/99)) ([9fc7ef9](https://github.com/alxdr3k/xef-scale/commit/9fc7ef91d40bdc5a90ff4e0e4d7d5438c8794687))
* compute daily-average denominator from the selected month ([250348c](https://github.com/alxdr3k/xef-scale/commit/250348c48bca67f517d7eb1852a4633b6b04cacf))
* **controller:** add installment params to transaction_params ([09cc157](https://github.com/alxdr3k/xef-scale/commit/09cc1578430e76c626c331ff632f4282ac7bad51))
* defer duplicate decision side effects to commit and undo on rollback ([51e4684](https://github.com/alxdr3k/xef-scale/commit/51e46847234aa8dbff3f92772daf9109ea4221ae))
* **e2e:** align selectors with current Hotwire UI ([95c88e2](https://github.com/alxdr3k/xef-scale/commit/95c88e2e3228a56065ae192db5792893c9c1dfc8))
* **e2e:** redirect legacy login helper through test_login bypass ([ffea2f3](https://github.com/alxdr3k/xef-scale/commit/ffea2f3579e1c419df8b73e4e94465f37d15bc96))
* **e2e:** update test assertions to use 결제 terminology ([#108](https://github.com/alxdr3k/xef-scale/issues/108)) ([6dc64b2](https://github.com/alxdr3k/xef-scale/commit/6dc64b20ba824411baa0c72b6db8ed0f5756447d))
* harden import pipeline, review UX, upload errors, and e2e CI ([d64af6a](https://github.com/alxdr3k/xef-scale/commit/d64af6a10b6c9b49f70e93e1b6fd6466ed5cef13))
* increase KT amount variance in recurring detector test ([0bf02b6](https://github.com/alxdr3k/xef-scale/commit/0bf02b616deb7da141ead20925a7b70f54d0219a))
* **jobs:** harden parsing pipeline reliability and idempotency ([90c0209](https://github.com/alxdr3k/xef-scale/commit/90c020910a44a41eec2b953e23fc598ce59dbf9b))
* **mapping:** align find_or_initialize_by with new unique index ([fa44bee](https://github.com/alxdr3k/xef-scale/commit/fa44beeb04bfee6cab0ea123261d73df1c3b731f))
* migrate pagy extras/items to limit for v9 compatibility ([6606017](https://github.com/alxdr3k/xef-scale/commit/66060172740f0e8d8ce8e34568fe8f7aef6f2dac))
* **migration:** purge all FK dependents before deleting duplicate transactions ([a3f4bf8](https://github.com/alxdr3k/xef-scale/commit/a3f4bf87276efaab409bcc11dfa128d68acebcd4))
* mobile bottom nav hidden behind iOS Safari bar ([858cb6d](https://github.com/alxdr3k/xef-scale/commit/858cb6d06fc96fb8acebdd88508d5200880b9a68))
* mobile bottom nav not showing on iOS Safari ([8925a6e](https://github.com/alxdr3k/xef-scale/commit/8925a6e6ad19bc2cc72e42ab5cb9ce65338a9f50))
* **notification:** add nil safety for processed_file access ([d4fa22e](https://github.com/alxdr3k/xef-scale/commit/d4fa22ee15f063b3f69fb3d418501800ec2b05aa))
* parse Gemini Vision OBJECT schema and send API key via header ([4ab5ca6](https://github.com/alxdr3k/xef-scale/commit/4ab5ca6472e2418c87ebfee258a13202b35dc8f1))
* **parser:** catch non-StandardError exceptions in FileParsingJob ([5c621b7](https://github.com/alxdr3k/xef-scale/commit/5c621b7618bd89b1c2cf4322955ec6909e852b41))
* **parser:** handle OCR errors in Shinhan text parser ([ec872dc](https://github.com/alxdr3k/xef-scale/commit/ec872dc8ae97fd8d5f1eb2779839e002dcf4b55e))
* **parser:** route HTML files by extension to Hana Card parser ([08858c4](https://github.com/alxdr3k/xef-scale/commit/08858c46f6656bba112df6b1a94cc77cea309057))
* **parser:** use payment date for installment month 2+ in Samsung Card ([2d4b172](https://github.com/alxdr3k/xef-scale/commit/2d4b17266f8a200b6f50b877a7714dd1600c8997))
* **parsing_sessions:** scope has_duplicates filter by new_transaction date ([f1d6a2f](https://github.com/alxdr3k/xef-scale/commit/f1d6a2f626e8ef7debb706e7dfc460bdadfa66fe))
* **parsing:** filter card withdrawals and fix duplicate detection ([3f7c920](https://github.com/alxdr3k/xef-scale/commit/3f7c920c5b891fef31eedf8fd255bcd850fec4a5))
* real-time status updates via Turbo Stream ([a21f9b6](https://github.com/alxdr3k/xef-scale/commit/a21f9b6fe96a3b3d25bfccb7ee1a188c966940b4))
* real-time status updates via Turbo Stream ([27bf79a](https://github.com/alxdr3k/xef-scale/commit/27bf79a210c07e75c8801ad8bea403a26f8d5ebe))
* refuse review mutations on finalized parsing sessions ([ec7aadd](https://github.com/alxdr3k/xef-scale/commit/ec7aadddc4bc85f5d677abd503e3525d5b20f04e))
* register missing Stimulus controllers (input-tabs, onboarding, edit-modal) ([9f45a69](https://github.com/alxdr3k/xef-scale/commit/9f45a699a1f3074da40bc13ba78fcb981480b501))
* register missing Stimulus controllers + trigger STG deploy ([b451255](https://github.com/alxdr3k/xef-scale/commit/b4512558d74e5d52c663ef3d16a41b703eac9e72))
* resolve multi-review blockers — parsing, duplicates, uploads ([28e9eab](https://github.com/alxdr3k/xef-scale/commit/28e9eab8de2844885f9c82156fe70cc885062503))
* resolve pre-existing CI errors (lint, brakeman, bundler-audit) ([#50](https://github.com/alxdr3k/xef-scale/issues/50)) ([5ffd13f](https://github.com/alxdr3k/xef-scale/commit/5ffd13f367046121fad43332dafb6f1a5e56a51c))
* **retry:** make text-paste retry idempotent by destroying source session ([94ce895](https://github.com/alxdr3k/xef-scale/commit/94ce8957b7e9fed3b611ad63e54fe991ce12a994))
* **retry:** persist and restore institution_identifier on file retry ([79f0824](https://github.com/alxdr3k/xef-scale/commit/79f082435d573dae7c29dfa545aa170fe40cdb6a))
* **retry:** serialize concurrent text retries and handle enqueue failure ([9981376](https://github.com/alxdr3k/xef-scale/commit/998137604b8e18032ede1defea22d22f8bf23774))
* **reviews:** fix negative amount validation, commit count copy, and budget alerts ([f71a432](https://github.com/alxdr3k/xef-scale/commit/f71a43217807525e4aee25f98e83e28ea9ea3b40))
* **review:** sync review table header with row cells; remove institution from duplicate modal ([f1f1d36](https://github.com/alxdr3k/xef-scale/commit/f1f1d364c3ef7d1403ba1beec95f0fbf647255dd))
* **review:** tighten source metadata UX and semantics ([8a394e8](https://github.com/alxdr3k/xef-scale/commit/8a394e83465839ee84d6f3e0c017c4316cd5875c))
* rollback excluded pending transactions instead of soft delete ([a040ba1](https://github.com/alxdr3k/xef-scale/commit/a040ba10bc1d2583214fe89152ffad6def5c6bcc))
* rollback excluded pending transactions instead of soft delete ([4e95aad](https://github.com/alxdr3k/xef-scale/commit/4e95aad8bbb6855cda7d8f01896537ac0cf821fa))
* sanitize year and month params in dashboard and workspace views ([f22a8b0](https://github.com/alxdr3k/xef-scale/commit/f22a8b0cb4d71269bb32b18b6047ed8283f8ec7a))
* **search:** qualify column names in transaction search scope ([f0d692f](https://github.com/alxdr3k/xef-scale/commit/f0d692fb39dd88f2462a42a116df12fe8e4ab379))
* **security:** CSV injection 방어, commit race condition 수정, job discard 정책 추가 ([9cf73ee](https://github.com/alxdr3k/xef-scale/commit/9cf73ee1603b62d38e853eb129824c0932bda490))
* **security:** CSV injection 방어, commit race condition, job discard 정책 ([34346c1](https://github.com/alxdr3k/xef-scale/commit/34346c15e57c429cdfcdac02293eebdf59203e12))
* **seeds:** clamp e2e seed dates to stay in the current month ([fd40c8a](https://github.com/alxdr3k/xef-scale/commit/fd40c8a4da0c519f54b5338b89df0529475701f5))
* serialize invitation consumption with a row lock ([501a2cd](https://github.com/alxdr3k/xef-scale/commit/501a2cded1ebd6b89d2723c276a3c2cb446f903d))
* sniff uploaded file magic bytes before handing to Gemini Vision ([d8379fb](https://github.com/alxdr3k/xef-scale/commit/d8379fbdd6b8f35b448fac1e004ef9c967a827a0))
* **source-popover:** stop click propagation from popover panel to row bulk-select ([3aef5d6](https://github.com/alxdr3k/xef-scale/commit/3aef5d6422b6ab5611b26b6ee00a224f331789a5))
* **source-popover:** use proper Stimulus action to stop popover click propagation ([866c95b](https://github.com/alxdr3k/xef-scale/commit/866c95bb2f3d0fd2e71f096a28cc0a59ac6c62bd))
* SpaceInsideArrayLiteralBrackets in recurring_payment_detector ([1e76899](https://github.com/alxdr3k/xef-scale/commit/1e76899cc20b3e4666160baa575d5a803b66c572))
* surface failures from quick_update_category instead of always succeeding ([710a985](https://github.com/alxdr3k/xef-scale/commit/710a9856cf4c7024f6902d9bba57ab863137a9d2))
* test failures — remove secret_key_base from fixture, fix next→return ([dc85b15](https://github.com/alxdr3k/xef-scale/commit/dc85b15d664776b4cb9f7241b936b65ad1b97be4))
* **test:** align parse_amount test with actual behavior ([64d3459](https://github.com/alxdr3k/xef-scale/commit/64d3459aff82e261b43a5a4438a689453751dbaa))
* **ui:** add group/row class to review transaction row ([7f41214](https://github.com/alxdr3k/xef-scale/commit/7f41214b33e7259401054d95c8f4ff71e3c0e686))
* **ui:** enable link navigation in source popover ([4140aa9](https://github.com/alxdr3k/xef-scale/commit/4140aa9be8e79553a733ff3b62c37e9d27cd93f6))
* **ui:** enable notes and category features on review page ([3625744](https://github.com/alxdr3k/xef-scale/commit/3625744528283c0ec0759ced17032b399bc50e91))
* **ui:** flip category dropdown upward when near viewport bottom ([ef9e8a8](https://github.com/alxdr3k/xef-scale/commit/ef9e8a8af0fee2f21173608133ceeeb42e431a8e))
* **ui:** improve merchant cell inline-edit and icon visibility ([0c4ad64](https://github.com/alxdr3k/xef-scale/commit/0c4ad6438066a33204ddad9f91da04403ea0127b))
* **ui:** prevent layout shift on scrollbar appearance ([2c7836d](https://github.com/alxdr3k/xef-scale/commit/2c7836dab9261048de530cc6f0b194d1f9f0299d))
* **ui:** rename nav label to 가져오기 and update duplicate modal button labels ([ad9f27a](https://github.com/alxdr3k/xef-scale/commit/ad9f27aa7751de9aa8a68fa4fc231fca25b15384))
* **ui:** update notification list on mark-all-read ([afef964](https://github.com/alxdr3k/xef-scale/commit/afef96450150572ad15a4aa3ae7c83aaf26005da))
* update gems to patch security vulnerabilities ([1491056](https://github.com/alxdr3k/xef-scale/commit/14910567f89a2eac34774b0467e43f42bf15fceb))
* update workspace create test to expect dashboard redirect ([df9c288](https://github.com/alxdr3k/xef-scale/commit/df9c288ed38b68f806f985520aa512b56242d2b0))
* **uploads:** cap flash message length and wrap retry in transaction ([a83cde0](https://github.com/alxdr3k/xef-scale/commit/a83cde0bb3f0dcecb7b0e57231c91f884ebef8f9))
* **uploads:** show per-file error messages and add retry/delete for failed sessions ([f13b1d5](https://github.com/alxdr3k/xef-scale/commit/f13b1d55746f4eb8ddacb617877b2aa073b76027))
* **ux:** update JS controllers to use '결제' terminology ([9e7aa22](https://github.com/alxdr3k/xef-scale/commit/9e7aa222fbdf97c10f8f1414f6d8741ffb397550))


### Performance Improvements

* **db:** add composite index for date+amount duplicate query ([67457ea](https://github.com/alxdr3k/xef-scale/commit/67457ea225b208174fb7681ce9b0b5f85a57e925))


### Code Refactoring

* **parser:** merge Shinhan text parser into card parser ([d9df878](https://github.com/alxdr3k/xef-scale/commit/d9df878b92404181cf3c89069678b1ad8c0f7367))

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
