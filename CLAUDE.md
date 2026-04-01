# CLAUDE.md

This file provides guidance to Claude Code when working with code in this repository.

## Project Overview

**Expense Tracker (지출 추적 앱)** - A Rails 8 application for tracking personal expenses from Korean financial institutions.

### Core Concept
Users manually download financial statements (Excel/PDF) from their bank apps/websites and upload them through the web interface. The system:
1. Identifies the financial institution through content-based routing
2. Parses the data using institution-specific parsers
3. Stores transactions in a unified format (SQLite)
4. Provides filtering, categorization, and analytics

## Technology Stack

### Backend
- **Ruby**: 3.3+
- **Rails**: 8.0+
- **Database**: SQLite3
- **Authentication**: Devise + OmniAuth Google OAuth2
- **Authorization**: Pundit (RBAC)
- **Background Jobs**: Solid Queue (Rails 8 default)
- **File Parsing**: Roo (Excel), CSV (built-in), pdf-reader (PDF)

### Frontend
- **Hotwire**: Turbo + Stimulus
- **CSS**: Tailwind CSS 3
- **Icons**: Heroicons

## Supported Financial Institutions

- 신한카드 (Shinhan Card)
- 하나카드 (Hana Card)
- 토스뱅크 (Toss Bank)
- 토스페이 (Toss Pay)
- 카카오뱅크 (Kakao Bank)
- 카카오페이 (Kakao Pay)

## Data Schema

Final transaction format:
- **월** (month): mm format
- **날짜** (date): yyyy.mm.dd format
- **분류** (category): Auto-categorized based on merchant name
- **내역** (item): Merchant/transaction description
- **금액** (amount): Integer amount
- **지출 위치** (source): Bank/card name

## 아키텍처

### 파싱 흐름

```
파일 업로드 → ParserRouter → Institution Parser → Transaction 저장
     │              │                │
     │              │                └── 금융기관별 파싱 로직
     │              └── 파일 내용 기반 금융기관 식별
     └── Excel/CSV/PDF
```

### 핵심 서비스

| 서비스 | 위치 | 역할 |
|--------|------|------|
| `ParserRouter` | `app/services/parser_router.rb` | 파일 → 적합한 Parser 라우팅 |
| `ShinhanCardParser` | `app/services/parsers/shinhan_card_parser.rb` | 신한카드 명세서 파싱 |
| `HanaCardParser` | `app/services/parsers/hana_card_parser.rb` | 하나카드 명세서 파싱 |
| `TossBankParser` | `app/services/parsers/toss_bank_parser.rb` | 토스뱅크 내역 파싱 |
| `KakaoBankParser` | `app/services/parsers/kakao_bank_parser.rb` | 카카오뱅크 내역 파싱 |

### 데이터 모델

```
User ──< Workspace ──< Transaction
              │
              └──< ProcessedFile (업로드 이력)
```

## 참조 안내

- 모델: `app/models/`
- DB 스키마: `db/schema.rb`
- API 라우트: `config/routes.rb`
- 환경변수: Doppler `xef-scale` 프로젝트

## Development Commands

```bash
# Start development server
bin/dev

# Run tests
rails test
rails test:system

# Database operations
rails db:migrate
rails db:seed
rails db:reset
```

## Directory Structure

```
expense-tracker/
├── app/
│   ├── controllers/
│   ├── models/
│   ├── policies/        # Pundit authorization
│   ├── services/        # Parser services
│   ├── jobs/            # Solid Queue background jobs
│   └── views/
├── config/
│   ├── routes.rb
│   └── initializers/
├── db/
│   ├── migrate/
│   └── seeds.rb
└── test/
```

## Language Note

This project uses Korean for transaction descriptions, merchant names, and categories. UI can be internationalized via Rails I18n.

## Git 규칙

- PR merge 시 **squash 금지**, 반드시 **merge commit** 사용 (커밋 히스토리 보존)
- Conventional Commits 형식 사용

## CI/CD 워크플로우 (필수 준수)

**절대 직접 빌드/배포하지 마세요.** 모든 빌드와 배포는 GitHub Actions를 통해 자동화되어 있습니다.

### 금지 사항

- `docker build` 직접 실행 금지
- `docker push` 직접 실행 금지
- ghcr.io에 이미지 직접 푸시 금지

### 올바른 배포 프로세스

1. 코드 변경 후 Conventional Commits 형식으로 커밋
2. dev 브랜치에 푸시
3. main으로 PR 생성 및 머지
4. release-please가 자동으로 Release PR 생성
5. Release PR 머지 → 자동으로 Docker 이미지 빌드 및 ghcr.io 푸시
6. ops 레포의 kustomization.yaml에서 이미지 태그 업데이트
7. kubectl apply로 배포 (또는 CD workflow)

### Dockerfile 수정 시

Dockerfile을 수정했다면:
- 직접 빌드하지 말고 커밋 후 CI/CD를 통해 빌드
- 로컬 테스트가 필요하면 `bin/dev`로 개발 서버 실행

### Claude Code 관련 파일 수정 시

`.claude/`, `CLAUDE.md` 등 Claude Code 관련 파일 수정 시:
- `chore` 타입 사용 (예: `chore: update claude code commands`)

## 배포

k8s 클러스터에 배포 (ops 레포의 Kustomize 사용)

| 환경 | 도메인 | Namespace |
|------|--------|-----------|
| stg | stg-scale.xeflabs.com | apps-stg |
| prd | scale.xeflabs.com | apps-prd |

```bash
kubectl apply -k ~/ws/xeflabs/ops/apps/xef-scale/overlays/{stg,prd}
```

환경변수: Doppler `xef-scale` 프로젝트에서 관리

## 라이브러리 문서 조회 (context7)

다음 경우에만 context7으로 문서 확인:
- 에러/경고 발생 시 (특히 deprecation)
- 최신 버전 기능 사용 시
- 불확실하거나 기억이 모호할 때

### 주요 라이브러리
- rails (8.x), turbo-rails, stimulus-rails
- devise, omniauth, omniauth-google-oauth2
- pundit (authorization)
- solid_queue, solid_cache
- roo (Excel), pdf-reader (PDF)
- tailwindcss
