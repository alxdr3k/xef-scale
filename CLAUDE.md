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

## Key Models

1. **User** - Devise authentication + Google OAuth
2. **Workspace** - Multi-tenant support for shared expense tracking
3. **WorkspaceMembership** - Roles: owner, co_owner, member_write, member_read
4. **WorkspaceInvitation** - Invite links for workspace sharing
5. **Category** - Expense categories (식비, 교통, etc.)
6. **FinancialInstitution** - Bank/card definitions
7. **Transaction** - Core expense records
8. **AllowanceTransaction** - Private allowance tracking
9. **ProcessedFile** - File upload tracking
10. **ParsingSession** - Batch parsing metadata
11. **DuplicateConfirmation** - Duplicate transaction handling

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
