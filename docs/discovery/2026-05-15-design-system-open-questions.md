# Design System Phase 1 사전 미해결 질문

- 일자: 2026-05-15
- 입력: `docs/discovery/2026-05-15-ui-redesign-plan.md 8장` (결정해야 할 미해결 질문 7개)
- 산출물: 각 질문에 대한 컨텍스트·옵션·권고·후속 액션. Phase 1 시작 전에 이 노트의 권고를 검토해 채택 여부를 확정한다.
- 권한: 디스커버리이며 권위가 아니다. 본 노트의 권고가 채택되면 해당 항목은 `docs/decisions/`의 ADR로 승격된다.
- 관련 ADR: ADR-0003 (Design system), ADR-0004 (Review Inbox IA), ADR-0006 (시맨틱 컬러), ADR-0008 (다크 모드)

---

## 0. 본 문서가 다루는 7가지 질문

| # | 질문 | 권고 요약 | 후속 ADR? |
|---|---|---|---|
| Q1 | **Tailwind 4 & `@theme` 도입 가능한가?** | **즉시 채택** — 이미 v4.1.18 | 불필요 (ADR-0003 안에 포함) |
| Q2 | **ViewComponent 도입할 것인가?** | **본 사이클 보류** — ERB partial 표준화 우선 | 향후 별도 ADR |
| Q3 | **Pretendard 폰트 자가 호스팅 vs CDN** | **자가 호스팅 (WOFF2 subset)** | ADR-0009 후보 |
| Q4 | **`UserSetting#theme` 마이그레이션 방식** | `User#settings["theme"]` vs `users.theme` 둘 다 후보. 디스커버리 preference는 `users.theme`이나 **저장 위치는 ADR-0010에서 확정** (ADR-0008은 값 도메인만 결정) | ADR-0010 후보 (ADR-0008 종속) |
| Q5 | **5탭 라우트 path 명명** | **기존 path 유지 + 별칭 추가** (breaking change 회피) | Phase 3 내부 결정 (ADR 불필요) |
| Q6 | **키보드 단축키 라이브러리** | **Stimulus 자체 구현** (외부 라이브러리 회피) | Phase 2 내부 결정 |
| Q7 | **일러스트 시스템** | **본 사이클 deferred — 빈 상태는 이모지 한정** | 향후 별도 디스커버리 |

---

## Q1. Tailwind 4 & `@theme` 도입 가능한가?

### 컨텍스트

ADR-0003은 시맨틱 토큰을 Tailwind CSS의 `@theme` 블록과 `light-dark()` 함수로 정의하는 것을 전제로 한다. Tailwind 4의 CSS-first config가 채택의 기반이며, 본 레포가 이 버전 위에 있는지 검증해야 한다.

### 사실 확인

```bash
$ grep tailwindcss package.json
"tailwindcss": "^4.1.18"

$ head app/assets/stylesheets/application.tailwind.css
@import "tailwindcss";

@layer base { ... }
@layer utilities { ... }
```

- `tailwindcss@^4.1.18` 이미 도입됨.
- 진입점 `application.tailwind.css`에서 `@import "tailwindcss"` 패턴 사용. v4의 CSS-first config 호환.
- 현재 `@layer base`, `@layer utilities`만 사용 — `@theme` 블록은 아직 없음.

### 옵션

| 옵션 | 장점 | 단점 |
|---|---|---|
| **A. 즉시 `@theme` 도입 (권고)** | v4 기능을 그대로 활용. 추가 마이그레이션 비용 0. | (없음) |
| B. CSS 변수만 사용 (`@theme` 없이 `:root` 정의) | `@theme` 학습 비용 회피 | Tailwind 자동 utility 생성 (`bg-surface` 등) 못 받음. ADR-0003의 토큰 → utility 자동 매핑 깨짐 |

### 권고

**A. 즉시 채택.** Phase 1에서 `application.tailwind.css`에 `@theme` 블록 추가. 추가 작업:

```css
@import "tailwindcss";

@theme {
  /* synthesis.md 4장 토큰 전체 */
}

@layer base { /* 기존 유지 */ }
```

### 후속 액션

- ADR-0003 안에 포함된 결정이므로 별도 ADR 불필요.
- Phase 1 PR에서 토큰 정의 + 기존 `@layer` 호환성 검증.

---

## Q2. ViewComponent 도입할 것인가?

### 컨텍스트

ADR-0003은 컴포넌트 사전(Product Language)을 ERB partial로 구현하기로 결정했고, ViewComponent 도입은 본 ADR 범위 밖이라 명시했다. 그러나 디자인 시스템 도입과 같이 가는 것이 자연스러운 시점이라는 주장도 가능하다.

### 사실 확인

```bash
$ grep view_component Gemfile
(없음)
```

- 현재 ViewComponent gem 미도입.
- 모든 컴포넌트가 ERB partial (`app/views/shared/*`, 도메인별 `_*.html.erb`).
- 기존 partial에 Ruby 로직(`if/else`, `each`)이 많이 들어 있음 — 단순 치환으로 ViewComponent로 옮기기 어려움.

### 옵션

| 옵션 | 장점 | 단점 |
|---|---|---|
| **A. 본 사이클 보류 (권고)** | Phase 1~2를 partial 표준화에만 집중 가능. 마이그레이션 비용 1단계로 제한. | 미래에 ViewComponent로 갈 때 partial → component 변환 일회용 작업 발생 |
| B. Phase 2와 동시 도입 | 토큰·partial·component를 한 번에 정착 | Phase 2 범위가 2~3배. 회귀 위험 ↑. 직군 학습 비용 동시 발생 |
| C. 영구 ERB partial 유지 | 추가 의존성 0 | 컴포넌트 격리·테스트·preview(Lookbook) 기능 포기 |

### 권고

**A. 본 사이클 보류.**

근거:
- ERB partial 표준화만으로도 ADR-0003의 일관성 목표(직군 어휘 통일, 거버넌스)는 달성 가능.
- ViewComponent의 가장 큰 이점(컴포넌트 단위 테스트, Lookbook preview)은 Phase 2 이후에야 의미가 큼.
- Strangler Fig 마이그레이션(ADR-0003)과 *동시에* 컴포넌트 시스템도 바꾸면 진단·롤백이 어려워짐. 한 번에 한 축씩.

도입 시점 기준 (향후 검토):
- xef-scale의 view layer 복잡도가 증가해 partial 안에 100줄 이상 ERB가 늘어날 때.
- 시각 회귀 테스트가 Phase 7에서 도입되면 ViewComponent + Lookbook 효용 ↑.
- 디자이너가 직접 컴포넌트 preview를 검토하는 워크플로우가 필요해질 때.

### 후속 액션

- 본 사이클 ADR 작성하지 않음.
- 향후 도입 검토 시 신규 ADR(예: ADR-00XX `Adopt ViewComponent for design system primitives`)로 처리.

---

## Q3. Pretendard 폰트 자가 호스팅 vs CDN

### 컨텍스트

ADR-0003의 토큰 정의에서 `--font-sans: "Pretendard Variable", "Pretendard", system-ui, ...` 로 명시. 본 레포에 폰트가 없으므로 호스팅 결정 필요.

### 사실 확인

```bash
$ find . -path ./node_modules -prune -o -name '*pretendard*' -print
(없음)

$ ls public/
400.html  404.html  406-unsupported-browser.html  422.html  500.html  icon.png  icon.svg  robots.txt
```

- Pretendard 자체는 SIL Open Font License 1.1 — 자유롭게 호스팅 가능.
- 공식 배포: GitHub `orioncactus/pretendard` (또는 npm `pretendard`).
- 변형:
  - **Pretendard Variable** (가변 폰트, 단일 파일 ~700KB WOFF2) — 모든 weight 지원.
  - **Pretendard Static** (weight별 분리 파일, 9 weights × 2 styles, 총 ~2MB) — 사용 weight만 골라 로딩 가능.
  - **Pretendard Subset** (한글 KS X 1001 + 기본 Latin) — 변형별 ~30% 크기.

### 옵션

| 옵션 | 장점 | 단점 |
|---|---|---|
| A. CDN (jsdelivr 등) | 0 작업. 다른 사이트 캐시 공유 가능. | 외부 의존성 (CDN 다운 시 폰트 fallback). CSP에 도메인 추가 필요. 다른 사이트 캐시 공유는 2024 브라우저 캐시 파티셔닝으로 사실상 무력화. |
| **B. 자가 호스팅 (Variable Subset, WOFF2) (권고)** | 외부 의존 0. CSP 단순. 단일 파일. ~200KB. | 폰트 파일 관리 책임. 업데이트 시 수동 갱신. |
| C. 자가 호스팅 Static (필요 weight만 로딩) | 사용 안 하는 weight 미로딩. | 디자인 시스템에서 다양한 weight 사용 시 파일 수 ↑. HTTP/2 multiplexing이 있어 큰 이슈 아님. |

### 권고

**B. 자가 호스팅 (Pretendard Variable Subset, WOFF2 단일).**

근거:
- ADR-0003에서 hero/title/section/body/meta 등 다양한 weight 사용 — Variable이 자연스러움.
- 200KB 정도면 첫 페인트에 무리 없음 (`font-display: swap`).
- 외부 CDN 의존 회피는 보안·CSP·오프라인 개발 모두에 유리.
- 호스팅 위치(`public/fonts/` vs `app/assets/fonts/`)는 빌드 파이프라인 호환성에 따라 아래 P-public/P-layout-preload/P-erb 옵션 중 선택. **본 디스커버리는 P-public을 Phase 1 default로 권고**한다.

### 후속 액션 (Phase 1)

**현재 CSS 빌드 파이프라인 사실** (2026-05-15 기준 `package.json`): `npm run build:css`는 `npx @tailwindcss/cli -i ./app/assets/stylesheets/application.tailwind.css -o ./app/assets/builds/application.css --minify`를 실행한다. **이 파이프라인은 ERB를 평가하지 않는다.** 따라서 입력 CSS를 `.css.erb`로 두고 `<%= asset_path %>`를 박는 접근은 **빌드 파이프라인 변경 없이는 불가**하며, 그대로 두면 빌드된 CSS에 미해석 ERB 토큰이 그대로 실린다.

본 레포는 Propshaft를 사용하므로 `app/assets/`에 둔 파일은 fingerprinted된 `/assets/...` 경로로 서비스된다. CSS에서 폰트를 정적 경로(`/fonts/...`)로 하드코딩하면 production에서 404가 나고 시스템 폰트로 폴백된다. 세 옵션 중 하나를 명시 채택해야 한다:

**옵션 P-public (가장 단순, 권장)** — 정적 경로(`/fonts/...`):

1. `public/fonts/PretendardVariable-Subset.woff2` 저장 (fingerprint 없음, 캐시 무효화는 파일명 버전 접미사로: 예 `PretendardVariable-Subset.v1.woff2`).
2. CSS에서 `src: url("/fonts/PretendardVariable-Subset.woff2") format("woff2-variations")` 사용 가능. 현재 Tailwind CLI 파이프라인을 그대로 유지.

**옵션 P-layout-preload** — `app/assets/fonts/`에 두고 layout에서 preload + ERB-rendered `@font-face`:

1. `app/assets/fonts/PretendardVariable-Subset.woff2` 저장 (Propshaft가 `/assets/...`로 fingerprint).
2. `application.html.erb`에 `<link rel="preload" as="font" href="<%= font_path("PretendardVariable-Subset.woff2") %>" crossorigin>` 추가 (네트워크 fetch 우선순위 확보).
3. **`@font-face` 매핑은 반드시 함께 발행해야 한다** — preload 단독으로는 `font-family: "Pretendard Variable"` 바인딩이 안 되어 폰트가 다운로드돼도 시스템 폰트로 폴백된다. layout 안에 inline `<style>`로 ERB 평가가 가능한 `@font-face`를 발행한다:
   ```erb
   <style>
     @font-face {
       font-family: "Pretendard Variable";
       font-weight: 100 900;
       font-style: normal;
       font-display: swap;
       src: url("<%= font_path("PretendardVariable-Subset.woff2") %>") format("woff2-variations");
     }
   </style>
   ```
4. CSS 빌드 파이프라인은 그대로 유지 (Tailwind CLI 입력은 `.css`).

**옵션 P-erb (빌드 파이프라인 변경 동반)** — `application.tailwind.css.erb`로:

1. `application.tailwind.css`를 `.css.erb`로 변경.
2. `npm run build:css`를 *ERB 사전 평가*하는 단계로 감싼다 (예: `bin/render-css.rb` 같은 wrapper). `@tailwindcss/cli`는 ERB를 평가하지 않으므로 *반드시* 빌드 파이프라인을 같이 변경해야 한다 — 그렇지 않으면 production CSS에 미해석 ERB가 실린다.
3. `<%= asset_path "..." %>` 사용 가능.

→ 본 디스커버리는 결정을 ADR-0009 후보에 위임한다. **빌드 파이프라인 변경 비용이 가장 적은 P-public이 우선 권고**. P-erb는 빌드 변경 부담 때문에 비권장.

공통:
- 라이선스 고지를 `public/licenses/pretendard.txt` 또는 README에 명시 (SIL OFL 1.1 준수).
- `font-display: swap`, `font-weight: 100 900`, `format("woff2-variations")`.

### 후속 ADR 후보

ADR-0009 `Self-host Pretendard Variable Subset`. Phase 1 PR과 같이 머지 권장.

---

## Q4. `UserSetting#theme` 마이그레이션 방식

### 컨텍스트

ADR-0008은 사용자 토글로 테마 강제(`auto/light/dark`)를 위해 `UserSetting#theme` 컬럼이 필요하다고 명시. 그러나 현재 `UserSetting` 모델 자체가 없다.

### 사실 확인

```bash
$ ls app/models/user*.rb
app/models/user.rb

$ grep -A 15 'create_table "user_settings"' db/schema.rb
(없음)

$ head app/controllers/user_settings_controller.rb
class UserSettingsController < ApplicationController
  def show
  def update
    update_excluded_merchants
    if current_user.save  # ← User 모델에 직접 저장
```

- `UserSetting` 모델·테이블 부재.
- `UserSettingsController#update`는 `current_user`에 직접 저장 — 기존 패턴은 **사용자 설정을 `User` 모델 컬럼/JSON에 직접 둔다**.
- `excluded_merchants` 같은 설정이 이미 user에 저장됨.

### 옵션

| 옵션 | 장점 | 단점 |
|---|---|---|
| **A. `users.theme` 컬럼 추가** | 마이그레이션 단순(컬럼 1개). 인덱스/check constraint 가능. | `users` 테이블이 커짐. 기존 `excluded_merchants` 같은 JSON 패턴과 어휘 분기. |
| **B. `User#settings["theme"]` (기존 JSON store)** | 기존 패턴(`serialize :settings, coder: JSON`) 일관 유지. 마이그레이션 불요. | 인덱스 어려움. JSON 키 typo 위험. enum 강제 어려움. |
| C. 별도 `user_settings` 테이블 신설 | 설정 분리, 향후 설정 확장에 유리 | 마이그레이션·연관 모델·컨트롤러 리팩터 필요. 기존 `excluded_merchants` 위치 결정도 같이 해야 함 |

### 디스커버리 preference (구속력 없음)

본 디스커버리는 **A(`users.theme` 컬럼)** 를 약하게 선호한다. 근거: enum/check constraint로 값 도메인을 DB 레벨에서 강제 가능, 인덱스 가능, ActiveRecord 통합 자연스러움.

다만 본 레포의 기존 패턴(`User#settings` JSON)도 일관성 있는 옵션이며, 둘 사이의 트레이드오프(스키마 명확성 vs 패턴 일관성)는 **본 디스커버리에서 최종 결정하지 않는다**. ADR-0008은 *값 도메인*만 결정했고, *저장 위치*는 다음 ADR에서 확정한다.

### 후속 액션 (Phase 5 시작 전)

1. **ADR-0010 작성** — 옵션 A/B/C 중 하나를 채택. Phase 5 구현 PR보다 먼저 머지.
2. ADR-0010 채택 후 Phase 5 구현 PR에서: 마이그레이션 또는 JSON 키 추가 → `User#theme` 접근자 → `app/views/user_settings/show.html.erb` SwitchRow → `<html data-theme="...">` 렌더 → Stimulus `theme_controller.js`.

### 후속 ADR 후보

ADR-0010 `User theme preference storage location`. ADR-0008(값 도메인 `auto/light/dark`)과 연결. 옵션 A/B/C 중 채택.

---

## Q5. 5탭 라우트 path 명명

### 컨텍스트

ADR-0004는 5탭 IA(홈/거래/검토함/카테고리/더보기)를 명시. 라우트 path를 신규로 잡을지, 기존 경로(예: `/dashboard`)를 유지할지 결정 필요.

### 사실 확인

```ruby
# config/routes.rb (발췌)
root "dashboards#calendar", as: :authenticated_root
get "dashboard", to: "dashboards#calendar", as: :dashboard

resources :workspaces, ... do
  resources :transactions
  resources :categories
  resources :parsing_sessions do
    member do
      get :review, to: "reviews#show"   # ← 검토는 nested action
      post :commit, to: "reviews#commit"
      ...
    end
  end
end
resources :allowances, only: [ :index ]
```

- 현재 `dashboard`는 *기본*이 `dashboards#calendar` — 캘린더가 홈인 셈.
- `reviews`는 별도 resource가 아닌 `parsing_sessions` 안의 nested action.
- `allowances`는 워크스페이스 밖의 글로벌 resource.

### 옵션

| 옵션 | 장점 | 단점 |
|---|---|---|
| A. 모든 path 신규 (`/home`, `/transactions`, `/reviews`, `/categories`, `/more`) | 어휘 일관 | breaking change. 북마크 깨짐. 외부 링크 무효 |
| **B. 기존 path 유지 + 신규 추가 (권고)** | 호환성. 점진 도입. | path 표면이 한동안 둘 공존 |
| C. 신규 path + 기존 → 신규 301 redirect | 어휘 일관. SEO 보존. | 워크스페이스 nested resource의 redirect 매핑 복잡 |

### 권고

**B. 기존 path 유지 + 신규 추가 + Phase 3에서 alias.**

세부:
- `홈` → `/dashboard` (기존 그대로, 컨텐츠만 ADR-0004의 홈 패턴으로 재구성)
- `거래` → `/workspaces/:id/transactions` (그대로)
- `검토함` → 신규 라우트 `/workspaces/:id/reviews` 인덱스 추가 (`reviews#index`). 기존 nested action(`parsing_sessions/:id/review`)은 한동안 유지하며 새 인덱스에서 세션 상세로 이동.
- `카테고리` → `/workspaces/:id/categories` (그대로). `category_mappings`는 sub-section.
- `더보기` → 신규 `/workspaces/:id/more` 또는 사용자 전역 `/more`. 워크스페이스 컨텍스트 강하므로 nested 선호.

### 후속 액션

- Phase 3 PR에서 `resources :reviews, only: [ :index ]` 신설 + `reviews#index` 컨트롤러 액션 추가. 기존 `parsing_sessions/:id/review` (`reviews#show`) member action은 그대로 유지.
- **`ReviewsController` 콜백 스코핑** (필수, 2개 콜백). 현재 컨트롤러는 다음 둘이 모든 액션에 적용된다:
  - `before_action :set_parsing_session` — `params[:parsing_session_id] || params[:id]` 요구. 인덱스에는 두 param 모두 없음 → `RecordNotFound`.
  - `before_action :require_workspace_write_access, except: [ :show ]` — 인덱스가 write-gated 상태 → `member_read` 멤버 차단.
  단일 컨트롤러 유지 시 (권장):
  ```ruby
  before_action :set_parsing_session, except: [ :index ]
  before_action :require_workspace_write_access, except: [ :show, :index ]
  ```
  또는 `ReviewsInboxController#index`로 분리(이 경우에도 인덱스는 read 권한만 요구). 자세한 가이드는 ADR-0004.
- **인덱스 쿼리는 `ParsingSession.needs_review` (= `completed.pending_review`) 사용**. `where(review_status: "pending_review")`만 쓰면 status가 `pending`/`processing`/`failed`인 세션도 섞임. ADR-0004의 쿼리 sketch 참조.
- `parsing_sessions/index` 경로는 한동안 유지하고, 새 IA에서 "검토함 > + 새로 가져오기" 시트로 흡수.
- ADR 불필요 — 구현 디테일. 단 path 변경이 발생하면 PR description에 명시.

---

## Q6. 키보드 단축키 라이브러리

### 컨텍스트

ADR-0003의 컴포넌트 사전(검토함)과 `ui-redesign-plan.md 3.3`에서 키보드 단축키 필요(`j/k/c/d/x/enter/cmd+enter`). 라이브러리 도입 여부 결정.

### 옵션

| 옵션 | 장점 | 단점 |
|---|---|---|
| A. `hotkeys.js` (or `tinykeys`) 라이브러리 | 단축키 조합 파서 무료. modifier 처리 잘됨. | 의존성 추가. 번들 크기 ~3KB. |
| **B. Stimulus controller 자체 구현 (권고)** | Hotwire 일관성. 의존성 0. xef-scale 도메인 단축키만 다루면 충분히 단순. | 단축키 조합 직접 파싱 |
| C. 단축키 미도입 (마우스/터치만) | 0 작업 | 검토함 키보드 워크플로우(ADR-0003) 불가 |

### 권고

**B. Stimulus controller 자체 구현.**

근거:
- xef-scale 단축키 세트는 `j/k/c/d/x/enter/cmd+enter` 7개 + 검토함 한정 — 라이브러리 학습 비용이 도입 비용보다 큼.
- Hotwire와 Stimulus 일관성 유지.
- 작은 controller 1개로 처리 가능.

스케치:
```js
// app/javascript/controllers/keyboard_shortcut_controller.js
export default class extends Controller {
  static targets = ["row"]
  static values = { scope: String }  // "review"

  connect() { this.boundHandler = this.handle.bind(this); document.addEventListener("keydown", this.boundHandler) }
  disconnect() { document.removeEventListener("keydown", this.boundHandler) }
  handle(e) {
    if (this.isTyping(e)) return
    if (e.key === "j") return this.next()
    if (e.key === "k") return this.prev()
    if (e.key === "c") return this.openCategoryPicker()
    if (e.key === "d") return this.discard()
    if (e.key === "x") return this.markDuplicate()
    if (e.key === "Enter") {
      if (e.metaKey || e.ctrlKey) return this.commit()    // cmd/ctrl+enter: 전체 반영
      return this.openCurrentRow()                          // plain enter: 현재 행 펼침/상세
    }
  }
  isTyping(e) { return ["INPUT","TEXTAREA","SELECT"].includes(e.target.tagName) || e.target.isContentEditable }
}
```

### 후속 액션

- Phase 2 PR에서 controller 신설.
- 단축키 도움말 모달(`?` 키)을 같은 controller로.
- ADR 불필요.

---

## Q7. 일러스트 시스템

### 컨텍스트

토스(3D 스티커 풍)·뱅샐(돼지 마스코트 + 파스텔 일러스트) 모두 회피 결정 (`synthesis.md 2.4`, `banksalad-ui-deconstruction.md 5.2`). 자체 일러스트 톤이 필요한가?

### 옵션

| 옵션 | 장점 | 단점 |
|---|---|---|
| A. 처음부터 일러스트 시스템 구축 (외주·생성) | 강한 정체성 | 비용·시간 大. 가계부 *도구* 정체성과 충돌 가능 |
| **B. 본 사이클 deferred — 빈 상태는 이모지만 (권고)** | Phase 1~6에 일러스트 부담 0. 이모지는 OS별 일관성 있음. | 시각적으로 더 *도구*다움 (장점이기도 함) |
| C. 단색 SVG 픽토그램만 도입 (마스코트 없음) | 가벼움 | 빈 상태 일러스트로는 약함 — 결국 이모지 수준 |

### 권고

**B. 본 사이클 deferred.**

근거:
- xef-scale은 가계부 *도구*다. 토스/뱅샐과 다르게 마스코트나 친근감보다 *신뢰·정확성*이 우선.
- 빈 상태(`EmptyState` 컴포넌트)에는 이모지(🪙, 📥, ✨, 📊 등) + 워크스페이스명 호명 + 1 CTA가 *충분*하다 (ADR-0003 컴포넌트 사전).
- 일러스트 도입은 *PRD가 정의된 후* 결정할 일. 가계부의 정서적 정체성을 미리 못 박지 않는다.

### 후속 액션

- Phase 1~6 동안 모든 빈 상태에 이모지만 사용.
- 일러스트 필요 결정이 나면 별도 디스커버리 노트.
- ADR 불필요 (deferred).

---

## 요약 — Phase 1 시작 전에 처리할 것

본 노트의 권고가 채택되면 Phase 1 첫 PR에서 다음을 함께 처리:

1. **Tailwind `@theme` 토큰 정의** (Q1) — `application.tailwind.css`에 추가.
2. **Pretendard Variable Subset 자가 호스팅** (Q3) — **P-public 옵션을 Phase 1 default로 채택**. `public/fonts/PretendardVariable-Subset.woff2` + CSS에서 `src: url("/fonts/PretendardVariable-Subset.woff2")`. `app/assets/fonts/` + ERB-rendered `@font-face`(P-layout-preload)는 디자인 시스템 PR과 함께 검증 후 적용. 라이선스 고지 함께.
3. **ADR-0009** (Pretendard 자가 호스팅) 작성.

Phase 5 시작 전:

4. **ADR-0010** (테마 저장 위치) 작성 — `User#settings["theme"]` vs `users.theme` 컬럼 vs `user_settings` 테이블 중 채택. 디스커버리 preference는 컬럼이지만 구속력 없음.
5. ADR-0010 채택 후 Phase 5 구현 PR에서 마이그레이션 또는 JSON 키 추가 + UI 토글 + Stimulus controller.

본 사이클에서 *하지 않을 것*:

- ViewComponent 도입 (Q2) — 향후 별도 ADR.
- 일러스트 시스템 구축 (Q7) — 향후 별도 디스커버리.
- 5탭 path 완전 신규 (Q5) — 기존 path 유지 + 검토함 인덱스만 신설.
- 키보드 단축키 외부 라이브러리 (Q6) — Stimulus 자체 구현.

---

## 참고

- `docs/discovery/2026-05-15-design-system-synthesis.md` (12장: 후속 액션)
- `docs/discovery/2026-05-15-ui-redesign-plan.md` (8장: 미해결 질문)
- `docs/decisions/ADR-0003` ~ `ADR-0008` (Accepted, 2026-05-15)
- 후속 ADR 후보: ADR-0009 (Pretendard 자가 호스팅), ADR-0010 (사용자 테마 저장 위치)
