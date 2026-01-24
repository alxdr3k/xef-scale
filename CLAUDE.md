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

## 참조 안내

- 모델: `app/models/`
- DB 스키마: `db/schema.rb`
- API 라우트: `config/routes.rb`
- 환경변수: Doppler `xef-scale` 프로젝트 (`.env.example` 참조)

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

## 배포

k8s 클러스터에 배포 (ops 레포의 Kustomize 사용)

| 환경 | 도메인 | Namespace |
|------|--------|-----------|
| stg | stg-scale.xeflabs.com | apps-stg |
| prd | scale.xeflabs.com | apps-prd |

```bash
kubectl apply -k ~/ws/xeflabs/ops/apps/xef-scale/overlays/{stg,prd}
```

환경변수: `.env.example` 참조, Doppler `xef-scale` 프로젝트에서 관리

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
