# ADR-0010: Pretendard Variable을 `public/fonts/`로 자가 호스팅한다

## Status

Accepted

## Date

2026-05-15

## Context

[ADR-0003](ADR-0003-design-system-and-product-language.md)이 채택한 디자인 토큰의 타이포 토큰은 다음과 같다:

```css
--font-sans: "Pretendard Variable", "Pretendard", system-ui, -apple-system, sans-serif;
```

본 레포에는 폰트가 없으므로 어디서 어떻게 서비스할지 결정이 필요하다. Pretendard는 SIL Open Font License 1.1로 자유롭게 자가 호스팅 가능하다.

선행 디스커버리 [`docs/discovery/2026-05-15-design-system-open-questions.md Q3`](../discovery/2026-05-15-design-system-open-questions.md)이 세 옵션(A: CDN / B: 자가 호스팅 Variable Subset / C: 자가 호스팅 Static)을 비교했고, 본 ADR에서 호스팅 위치(P-public/P-layout-preload/P-erb)와 폰트 변형(Variable 전체 vs Subset)을 최종 확정한다.

## 사실 확인 (2026-05-15)

- `package.json` 기준 CSS 빌드는 `npx @tailwindcss/cli -i ./app/assets/stylesheets/application.tailwind.css -o ./app/assets/builds/application.css --minify`. ERB를 평가하지 않는다.
- 본 레포는 Propshaft를 사용한다 — `app/assets/` 하위 파일은 `/assets/...`로 fingerprinted, `public/` 하위 파일은 정적 경로 그대로.
- npm `pretendard@1.3.9` 패키지가 제공하는 단일 파일 옵션은 두 가지:
  - `dist/web/variable/woff2/PretendardVariable.woff2` — 단일 파일 약 **2.0MB** (Hangul 11,172자 + Latin/CJK 기호 포함).
  - `dist/web/variable/woff2-dynamic-subset/PretendardVariable.subset.{0..104}.woff2` — 105개 분할 파일, 각 평균 ~20KB. `unicode-range` 기반 dynamic loading.
- Q3 권고가 언급한 "Variable Subset ~200KB 단일 파일"은 GitHub의 `orioncactus/pretendard` 레포에는 존재하지만 npm `pretendard` 패키지에는 포함되지 않는다 (별도 `packages/pretendard-subset/`). 본 환경에서는 외부 네트워크 접근이 차단되어 있어 GitHub raw / jsdelivr 직접 다운로드도 불가하다.
- 로컬에서 `fontTools.subset`로 KS X 1001 한글 + Latin 기본을 잘라보면 ~1.7MB로 줄어들 뿐, Hangul 음절 ~2,350개 자체가 음절당 ~700 bytes로 시작점이 크다. **200KB는 한글을 빼지 않는 한 도달 불가**.

## Decision

xef-scale은 다음 4가지를 동시에 채택한다.

1. **자가 호스팅** — CDN 의존을 회피한다 (Q3 옵션 B). CSP·오프라인 개발·외부 의존 0 측면에서 우위.
2. **호스팅 위치는 `public/fonts/`** (Q3의 P-public 옵션). `app/assets/fonts/` + ERB-rendered `@font-face`(P-layout-preload) 또는 `application.tailwind.css.erb`(P-erb)는 빌드 파이프라인 변경을 동반하므로 거부. 현재 Tailwind CLI 입력 CSS에서 `url("/fonts/...")` 정적 경로로 참조한다.
3. **Phase 1은 Pretendard Variable 전체 파일(약 2.0MB)을 단일 WOFF2로 출시한다.** Q3 권고가 명시한 "~200KB Variable Subset"은 본 환경(외부 네트워크 차단) + Hangul 음절 수 자체의 크기 하한 때문에 달성 불가. `font-display: swap`으로 첫 페인트는 차단되지 않으며, 브라우저 캐시 + HTTP/2 멀티플렉싱으로 재방문 비용은 0에 수렴한다.
4. **캐시 무효화는 파일명 버전 접미사**로 처리한다. 파일명은 `PretendardVariable.v1.3.9.woff2` 형식 (npm 패키지 버전 일치). 폰트 업데이트 시 새 버전 접미사로 파일을 추가하고 CSS의 `src` URL을 함께 갱신한다 — fingerprint가 없는 정적 경로의 한계를 명시적 버전 관리로 보완.

구현:

```
public/fonts/PretendardVariable.v1.3.9.woff2     # 2.0MB, npm pretendard@1.3.9
public/licenses/pretendard-OFL-1.1.txt           # SIL OFL 1.1 고지
app/assets/stylesheets/application.tailwind.css  # @font-face + @theme 블록
```

```css
@font-face {
  font-family: "Pretendard Variable";
  font-weight: 45 920;
  font-style: normal;
  font-display: swap;
  src: url("/fonts/PretendardVariable.v1.3.9.woff2") format("woff2-variations");
}
```

## Consequences

**긍정**
- 외부 의존 0. CSP에 폰트 도메인 추가 불필요.
- 빌드 파이프라인 무변경. 기존 `npm run build:css` 그대로 동작.
- 폰트 라이선스 고지(`public/licenses/`)가 명시적으로 레포에 존재.
- 가변 폰트이므로 weight 100~900 전 범위를 단일 파일로 커버 — 디자인 시스템의 hero/title/section/body/meta 다양한 weight 사용에 자연스럽다.

**부정**
- 첫 방문 시 다운로드 용량 2.0MB. `font-display: swap`이 첫 페인트를 시스템 폰트로 띄우므로 LCP 영향은 제한적이나, 모바일 저속 네트워크에서 FOUT 시간이 길어질 수 있다.
- Q3 권고("~200KB Variable Subset")에서 약 10배 deviation. 다만 본 환경의 가용 자원과 한글 폰트의 크기 하한을 고려한 현실 적합 선택.
- 폰트 업데이트 시 파일명 버전 접미사를 수동으로 올려야 한다 (fingerprint 부재의 trade-off).
- Propshaft fingerprint를 거치지 않으므로 long-cache(`Cache-Control: max-age=...`)는 별도로 Rails / Nginx / CDN 설정 단계에서 처리해야 한다.

**운영·테스트·문서 영향**
- `docs/discovery/2026-05-15-design-system-open-questions.md Q3`의 "ADR-0009 후보" 표기를 본 ADR(0010)로 정정한다 (ADR-0009는 vision dogfood로 선행 채택됨).
- `docs/code-map.md`에 `public/fonts/`, `public/licenses/` 추가 (다음 partial 도입 PR에서 함께 갱신 권고).
- Phase 1 후속 PR에서 `application.html.erb`에 `<link rel="preload" as="font" href="/fonts/PretendardVariable.v1.3.9.woff2" type="font/woff2" crossorigin>` 추가를 검토. 본 PR은 partial/shell 전환을 포함하지 않으므로 preload 도입도 후속 PR로 미룬다.

## 재검토 트리거

다음 중 하나라도 발생하면 본 ADR을 supersede 하는 새 ADR로 폰트 호스팅 전략을 재평가한다.

1. **모바일 LCP 회귀** — Phase 1 출시 후 Web Vitals에서 LCP가 측정 가능하게 악화되고 폰트 다운로드가 주요 원인으로 식별된다.
2. **번들 크기 압박** — `public/` 총 크기가 배포 시스템 제약(예: Cloudflare Pages 25MB 단일 파일 제한)에 근접한다. (현재 2MB는 충분히 여유)
3. **다국어 확장** — 일본어/중국어 등 추가 스크립트를 동시 지원해야 하는 시점이 오면, dynamic-subset 또는 별도 폰트 패밀리 분할이 더 효율적이다.
4. **외부 네트워크 정책 변경** — CI/dev 환경에서 GitHub raw/jsdelivr 접근이 열리면, orioncactus가 배포하는 ~200KB Variable Subset 단일 파일 채택을 재고할 수 있다.

후속 옵션 (재검토 시):
- **dynamic-subset (105 파일)** — npm 패키지에 이미 포함, `pretendardvariable-dynamic-subset.css`의 `@font-face` + `unicode-range` 패턴 그대로 채택 가능. 첫 페인트에 보이는 글자만 로딩.
- **`fontTools.subset` 빌드 단계 도입** — KS X 1001 + 사용 빈도 한글로 한정해 ~500KB로 줄임. `bin/dev` 또는 release CI에 subset 단계 추가.

## Alternatives considered

1. **A. CDN (jsdelivr 등)** — 거부. CSP에 외부 도메인 추가 필요. 브라우저 캐시 파티셔닝(2024~)으로 사이트 간 캐시 공유가 사실상 무력화되어 자가 호스팅 대비 이점이 사라졌다. 외부 의존이 발생.
2. **C. Static (weight별 분리 파일)** — 거부. 디자인 시스템이 hero/title/section/body 등 다수 weight를 사용하므로 동시 다운로드 파일 수가 증가. HTTP/2 멀티플렉싱으로 영향은 작지만, 단일 Variable 파일이 더 단순하다.
3. **P-layout-preload (`app/assets/fonts/` + Propshaft fingerprint + ERB-rendered `@font-face`)** — 거부 (Phase 1 한정). preload만 추가하면 폰트가 다운로드돼도 `font-family` 바인딩이 없어 시스템 폰트로 폴백되므로 `@font-face` 발행을 layout inline `<style>`로 옮겨야 한다 — 동일 폰트 정의가 두 곳(`application.tailwind.css` + layout)에 분산된다. Phase 1은 빌드/라우팅을 건드리지 않는 것이 목표이므로 P-public이 더 단순.
4. **P-erb (`application.tailwind.css.erb` + ERB 사전 평가 wrapper)** — 거부. `@tailwindcss/cli`는 ERB를 평가하지 않아 빌드 파이프라인을 별도 래퍼로 감싸야 한다. 비용 대비 이득이 없다.
5. **Local fontTools subset (~1.7MB)** — 거부 (Phase 1 한정). 빌드에 Python + fontTools 종속성을 추가해야 하며 200KB 목표 달성 실패 (한글 음절 수 하한). 재검토 시 후속 옵션으로 보류.

## Supersedes

없음.

## Superseded by

없음.

## References

- 디스커버리: [`docs/discovery/2026-05-15-design-system-open-questions.md Q3`](../discovery/2026-05-15-design-system-open-questions.md)
- 관련 ADR: [ADR-0003](ADR-0003-design-system-and-product-language.md) (디자인 시스템 채택), [ADR-0008](ADR-0008-light-first-with-dark-pair.md) (light-dark 페어)
- 라이선스: [`public/licenses/pretendard-OFL-1.1.txt`](../../public/licenses/pretendard-OFL-1.1.txt) (SIL OFL 1.1)
- 폰트 원본: npm `pretendard@1.3.9` (https://github.com/orioncactus/pretendard)
