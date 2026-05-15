# ADR-0010: Pretendard Variable을 dynamic-subset으로 자가 호스팅한다

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

선행 디스커버리 [`docs/discovery/2026-05-15-design-system-open-questions.md Q3`](../discovery/2026-05-15-design-system-open-questions.md)이 세 옵션(A: CDN / B: 자가 호스팅 Variable Subset / C: 자가 호스팅 Static)을 비교했고, 본 ADR에서 호스팅 위치(P-public/P-layout-preload/P-erb)와 폰트 변형(전체 vs Subset vs Dynamic Subset)을 최종 확정한다.

## 사실 확인 (2026-05-15)

- `package.json` 기준 CSS 빌드는 `npx @tailwindcss/cli -i ./app/assets/stylesheets/application.tailwind.css -o ./app/assets/builds/application.css --minify`. ERB를 평가하지 않는다. 다만 Tailwind 4 CLI는 CSS `@import "./relative.css"`를 빌드 시점에 인라인 해석한다 — 본 ADR이 이 기능을 활용한다.
- 본 레포는 Propshaft를 사용한다 — `app/assets/` 하위 파일은 `/assets/...`로 fingerprinted, `public/` 하위 파일은 정적 경로 그대로.
- Pretendard `v1.3.9` 공식 release (`github.com/orioncactus/pretendard/releases/download/v1.3.9/Pretendard-1.3.9.zip`)와 npm `pretendard@1.3.9` 패키지가 제공하는 옵션:
  - `web/variable/woff2/PretendardVariable.woff2` — 단일 **2.0MB** (Hangul 11,172자 + Latin/CJK 기호, 모든 weight).
  - `web/static/woff2/Pretendard-{Weight}.woff2` × 9 weights — 각 ~770KB (총 ~7MB, 전체 글리프).
  - `web/static/woff2-subset/Pretendard-{Weight}.subset.woff2` × 9 weights — 각 ~270KB (KS X 1001 subset, 총 ~2.4MB, Variable 아님).
  - **`web/variable/woff2-dynamic-subset/PretendardVariable.subset.{0..91}.woff2` — 92개 분할 파일** + 동봉된 `pretendardvariable-dynamic-subset.css`가 각 파일별 `@font-face`에 `unicode-range`를 지정. 브라우저는 페이지에서 실제 사용된 코드 포인트가 포함된 subset만 fetch한다.
- **Q3 권고가 언급한 "Variable Subset ~200KB 단일 파일"은 실재하지 않는다** — orioncactus 공식 release/패키지 어디에도 단일 Variable Subset WOFF2가 없다. 디스커버리 노트가 static-subset(weight당 ~270KB)을 Variable로 잘못 기억했거나, third-party 호스팅과 혼동한 것으로 보인다.
- 로컬에서 `fontTools.subset`로 Variable에 KS X 1001 한글 + Latin 기본만 남겨도 ~1.7MB가 하한 — Hangul 음절 자체가 큰 글리프 데이터를 차지하기 때문이며, 단일 Variable로 200KB대 달성은 한글을 대거 드롭하지 않는 한 불가능하다.
- 한국 프로덕션 사이트(Toss, Banksalad, 네이버 등)의 일반 관행은 **dynamic-subset**으로, 첫 페인트에 보이는 글자에 필요한 1~3개 subset(~50-150KB)만 fetch한다.

## Decision

xef-scale은 다음 4가지를 동시에 채택한다.

1. **자가 호스팅** — CDN 의존을 회피한다 (Q3 옵션 B). CSP·외부 의존 0 측면에서 우위. 브라우저 캐시 파티셔닝(2024~) 이후 CDN의 캐시 공유 이점이 사실상 사라졌다.
2. **호스팅 위치는 `public/fonts/pretendard-1.3.9/`** (Q3의 P-public 옵션). `app/assets/fonts/` + ERB-rendered `@font-face`(P-layout-preload) 또는 `application.tailwind.css.erb`(P-erb)는 빌드 파이프라인 변경을 동반하므로 거부. CSS에서 `url("/fonts/pretendard-1.3.9/...")` 정적 경로로 참조한다.
3. **Dynamic Subset (92 파일)을 채택한다.** orioncactus가 공식으로 푸시하는 방식이며 한국 프로덕션 관행과 일치한다. 첫 페인트에 보이는 한글이 속한 1~3개 subset(~50-150KB)만 fetch — Variable의 weight 자유도(45~920)를 그대로 유지하면서 단일 파일(2MB) 대비 클라이언트 전송 비용을 ~10~30배 절감한다.
4. **CSS는 별도 파일 `app/assets/stylesheets/pretendard-dynamic-subset.css`에 92개 `@font-face` 블록을 두고 `application.tailwind.css`에서 `@import`** 한다. Tailwind 4 CLI가 빌드 시점에 인라인하므로 런타임에서는 단일 `application.css`로 서빙된다. 캐시 무효화는 폰트 파일 디렉토리명에 버전을 포함 (`pretendard-1.3.9/`), 폰트 업그레이드 시 새 디렉토리에 파일을 두고 CSS의 URL prefix를 갱신.

구현:

```
public/fonts/pretendard-1.3.9/PretendardVariable.subset.{0..91}.woff2  # 92 파일, 합계 ~2.1MB
public/licenses/pretendard-OFL-1.1.txt                                  # SIL OFL 1.1 고지
app/assets/stylesheets/pretendard-dynamic-subset.css                    # 92개 @font-face, unicode-range
app/assets/stylesheets/application.tailwind.css                         # @import 위 CSS + @theme
```

```css
/* application.tailwind.css */
@import "tailwindcss";
@import "./pretendard-dynamic-subset.css";

@theme { /* ... */ }
```

```css
/* pretendard-dynamic-subset.css (일부) */
@font-face {
  font-family: 'Pretendard Variable';
  font-style: normal;
  font-display: swap;
  font-weight: 45 920;
  src: url(/fonts/pretendard-1.3.9/PretendardVariable.subset.0.woff2) format('woff2-variations');
  unicode-range: U+f9ca-fa0b, U+ff03-ff05, U+ff07, /* ... */;
}
/* ... 91 more @font-face blocks ... */
```

## Consequences

**긍정**
- 첫 페인트 폰트 전송량 ~50-150KB (단일 2MB 대비 ~10~30배 절감). 모바일 LTE에서 FOUT 시간 최소화.
- 외부 의존 0. CSP에 폰트 도메인 추가 불필요.
- 빌드 파이프라인 무변경. Tailwind CLI가 `@import`를 그대로 처리.
- 가변 폰트의 weight 자유도(45~920) 유지 — 디자인 시스템의 hero/title/section/body/meta 다양한 weight 사용에 자연스럽다.
- 한국 프로덕션 관행과 일치 — 운영/디버깅 시 익숙한 패턴.
- 폰트 라이선스 고지(`public/licenses/`)가 명시적으로 레포에 존재.

**부정**
- `public/fonts/pretendard-1.3.9/` 디렉토리에 92개 파일이 추가됨. 디스크 footprint(~2.1MB)는 단일 파일과 거의 동일하나 파일 수가 늘어난다 (HTTP/2 멀티플렉싱으로 fetch 오버헤드는 작음).
- 빌드된 `application.css`에 92개 `@font-face` 블록이 인라인되어 CSS 크기 ~50KB 증가. minify 후에도 unicode-range 메타데이터 자체가 크기 때문. 그러나 폰트 파일 전송 절감 대비 합리적인 trade-off.
- 폰트 업데이트 시 디렉토리 + CSS 양쪽을 함께 갱신해야 한다 (현재는 npm 패키지 → 디렉토리 복사 + sed로 경로 치환하는 수동 절차).
- Propshaft fingerprint를 거치지 않으므로 long-cache(`Cache-Control: max-age=...`)는 Rails / Nginx / CDN 설정 단계에서 처리해야 한다 — 92개 파일이라 더 중요하다.

**운영·테스트·문서 영향**
- `docs/discovery/2026-05-15-design-system-open-questions.md Q3`의 "ADR-0009 후보" 표기를 본 ADR(0010)로 정정한다 (ADR-0009는 vision dogfood로 선행 채택됨).
- `docs/code-map.md`에 `public/fonts/pretendard-1.3.9/`, `public/licenses/`, `app/assets/stylesheets/pretendard-dynamic-subset.css` 추가 (다음 partial 도입 PR에서 함께 갱신 권고).
- 폰트 버전 업그레이드 절차는 본 ADR의 "업데이트 절차" 섹션 참조.

## 업데이트 절차 (예: 1.3.9 → 1.3.10)

```bash
# 1. npm 패키지 받기
npm pack pretendard@1.3.10

# 2. 새 디렉토리에 subset 파일 복사
tar -xzf pretendard-1.3.10.tgz \
  package/dist/web/variable/woff2-dynamic-subset/ \
  package/dist/web/variable/pretendardvariable-dynamic-subset.css
mkdir -p public/fonts/pretendard-1.3.10
cp package/dist/web/variable/woff2-dynamic-subset/*.woff2 \
   public/fonts/pretendard-1.3.10/

# 3. CSS의 URL prefix 갱신
sed 's|./woff2-dynamic-subset/|/fonts/pretendard-1.3.10/|g' \
  package/dist/web/variable/pretendardvariable-dynamic-subset.css \
  > app/assets/stylesheets/pretendard-dynamic-subset.css

# 4. 빌드 검증 + 옛 디렉토리 정리
npm run build:css
git rm -r public/fonts/pretendard-1.3.9/
```

## Phase 1 follow-up: `<link rel="preload">` 검토 (2026-05-15)

후속 PR(`shared/_screen_shell` 도입 + `application.html.erb` shell 전환)에서 폰트 preload 추가 여부를 검토했다. **결론: 추가하지 않는다.** 근거:

1. **dynamic-subset 구조 자체가 이미 fetch 최소화** — 92개 `@font-face` 가 `unicode-range` 로 분기되어 있어 브라우저는 페이지 DOM 에 등장한 코드 포인트가 포함된 subset(보통 1~3개, ~50-150KB)만 fetch 한다. preload 의 본래 목적인 "필요한 자원 조기 발견"은 dynamic-subset CSS 가 `application.css` 에 인라인되어 `<head>` 의 stylesheet 링크 단계에서 이미 달성된다.
2. **preload 대상 subset 식별이 자명하지 않다** — subset 0 은 fullwidth/특수 한글, subset 91 은 기본 ASCII + ~30개 최빈 한글(가/고/기/다/로/리/사/스/시/이/인/지/하), subset 90 은 그 다음 최빈 한글(간/개/거/게/결/...). 페이지마다 노출되는 한글이 다르므로 "거의 모든 페이지가 받는 subset"을 1~2개로 안전하게 좁히기 어렵다. 잘못 preload 하면 사용되지 않는 파일을 강제로 받는 손해가 발생한다.
3. **측정 데이터 없음** — Web Vitals(LCP/CLS/FOUT) 실측이 없는 상태에서의 preload 추가는 premature optimization 이다. 본 ADR 의 "재검토 트리거 1. 모바일 LCP 회귀"가 발동되면 측정 데이터 기반으로 1~2개 subset(예: 페이지 hit ratio 가 높은 subset)을 preload 하는 변경을 별도 PR 로 도입한다.
4. **HTTP/2 멀티플렉싱** — 본 레포 배포 환경(Thruster + HTTP/2)에서는 CSS 발견 → 폰트 fetch 직렬 의존이 HTTP/1 시절만큼 비싸지 않다. preload 의 이득(parallel fetch)이 작아진다.

향후 measurement-driven 으로 도입할 때의 패턴 (참고):

```erb
<%# 측정 결과 subset 91 이 사실상 모든 페이지에서 fetch 된다고 확인된 경우 %>
<link rel="preload" as="font" type="font/woff2"
      href="/fonts/pretendard-1.3.9/PretendardVariable.subset.91.woff2"
      crossorigin>
```

- `crossorigin` 속성은 필수 — 폰트 요청은 CORS 자격으로 fetch 되므로 preload 도 동일한 자격으로 발행해야 캐시 매칭이 된다.
- 1개 subset 만 preload — 여러 개를 한꺼번에 발행하면 첫 페인트 네트워크 대역폭을 잠식.

본 PR 은 위 패턴을 **도입하지 않고**, 본 섹션을 변경 이력으로 남긴다.

## 재검토 트리거

다음 중 하나라도 발생하면 본 ADR을 supersede 하는 새 ADR로 폰트 호스팅 전략을 재평가한다.

1. **모바일 LCP 회귀** — Web Vitals에서 LCP가 측정 가능하게 악화되고 폰트 다운로드가 주요 원인으로 식별된다. dynamic-subset의 첫 페인트 fetch도 누적되면 영향이 있을 수 있다.
2. **번들 크기 압박** — `public/` 총 크기가 배포 시스템 제약에 근접한다 (현재 ~2.1MB는 충분히 여유).
3. **다국어 확장** — 일본어/중국어 등 추가 스크립트를 동시 지원해야 하는 시점이 오면, `pretendard-jp` 같은 별도 패밀리 추가 또는 fontTools.subset 빌드 단계 도입을 재고한다.
4. **CSS 인라인 비용이 문제될 때** — 92개 `@font-face`가 인라인된 CSS 크기가 첫 페인트에 영향을 준다고 측정되면, CSS를 분리해 `<link>`로 별도 로드하거나 lazy CSS 패턴을 고려.

후속 옵션 (재검토 시):
- **fontTools.subset 빌드 단계 도입** — KS X 1001 + 사용 빈도 한글로 한정해 단일 Variable subset(~500KB-1MB)로 줄임. 빌드 파이프라인에 Python 의존성 추가.
- **별도 한글 fontfamily 분리** — Latin은 system-ui로 두고 한글만 자가 호스팅.

## Alternatives considered

1. **A. CDN (jsdelivr 등)** — 거부. CSP에 외부 도메인 추가 필요. 브라우저 캐시 파티셔닝(2024~)으로 사이트 간 캐시 공유가 사실상 무력화되어 자가 호스팅 대비 이점이 사라졌다. 외부 의존이 발생.
2. **C. Static (weight별 분리 파일)** — 거부. 디자인 시스템이 hero/title/section/body 등 다수 weight를 사용하므로 동시 다운로드 파일 수가 증가. Variable의 weight 자유도를 잃는다.
3. **단일 Variable WOFF2 (2.0MB)** — 거부 (본 ADR의 이전 버전이 채택했으나 dynamic-subset으로 전환). 단순하지만 첫 방문 시 2MB를 모두 받아야 하며 모바일 LTE에서 1~3초 FOUT이 보인다. dynamic-subset이 운영 복잡성 약간 증가 대비 클라이언트 전송 비용을 ~10~30배 절감한다.
4. **P-layout-preload (`app/assets/fonts/` + Propshaft fingerprint + ERB-rendered `@font-face`)** — 거부. preload만 추가하면 폰트가 다운로드돼도 `font-family` 바인딩이 없어 시스템 폰트로 폴백되므로 `@font-face` 발행을 layout inline `<style>`로 옮겨야 한다. 92개 `@font-face`를 layout inline으로 발행하면 매 페이지 응답마다 ~50KB HTML이 추가된다 — P-public + CSS 캐시가 훨씬 효율적.
5. **P-erb (`application.tailwind.css.erb` + ERB 사전 평가 wrapper)** — 거부. `@tailwindcss/cli`는 ERB를 평가하지 않아 빌드 파이프라인을 별도 래퍼로 감싸야 한다. dynamic-subset에서는 ERB 도움 자체가 불필요 (정적 디렉토리 경로 + Tailwind `@import` 인라인으로 충분).
6. **Local fontTools subset (~1.7MB)** — 거부 (Phase 1 한정). 빌드에 Python + fontTools 종속성을 추가해야 하며 단일 파일 ~200KB 목표 달성 실패. 재검토 시 후속 옵션으로 보류.

## Supersedes

없음.

## Superseded by

없음.

## References

- 디스커버리: [`docs/discovery/2026-05-15-design-system-open-questions.md Q3`](../discovery/2026-05-15-design-system-open-questions.md)
- 관련 ADR: [ADR-0003](ADR-0003-design-system-and-product-language.md) (디자인 시스템 채택), [ADR-0008](ADR-0008-light-first-with-dark-pair.md) (light-dark 페어)
- 라이선스: [`public/licenses/pretendard-OFL-1.1.txt`](../../public/licenses/pretendard-OFL-1.1.txt) (SIL OFL 1.1)
- 폰트 원본: npm `pretendard@1.3.9` (https://github.com/orioncactus/pretendard)
- 동적 subset CSS 원본: orioncactus의 `dist/web/variable/pretendardvariable-dynamic-subset.css` (URL prefix만 `./woff2-dynamic-subset/` → `/fonts/pretendard-1.3.9/`로 치환)
