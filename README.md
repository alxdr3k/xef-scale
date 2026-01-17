# Expense Tracker (지출 추적 앱)

A Rails 8 application for tracking expenses by automatically parsing financial statements from Korean banks and credit cards.

## Features

- **Workspace Management**: Create and manage multiple workspaces for organizing expenses
- **Transaction Management**: Track, filter, and categorize expenses
- **File Parsing**: Automatically parse statements from Korean financial institutions:
  - 신한카드 (Shinhan Card)
  - 하나카드 (Hana Card)
  - 토스뱅크 (Toss Bank)
  - 카카오뱅크 (Kakao Bank)
- **Allowance Tracking**: Mark transactions as allowance for personal budget tracking
- **Member Collaboration**: Invite team members with different permission levels
- **Export**: Export transactions to CSV format

## Technology Stack

- **Ruby** 3.3+
- **Rails** 8.1.2
- **SQLite3** (database)
- **Tailwind CSS** 4.x (styling)
- **Hotwire** (Turbo + Stimulus)
- **Devise** + OmniAuth (authentication with Google OAuth2)
- **Pagy** 6.x (pagination)

## Requirements

- Ruby 3.3.10+
- Bun (for JavaScript/CSS bundling)
- SQLite3

## Setup

1. Clone the repository:
   ```bash
   git clone <repository-url>
   cd expense-tracker
   ```

2. Install dependencies:
   ```bash
   bundle install
   bun install
   ```

3. Setup database:
   ```bash
   rails db:create db:migrate db:seed
   ```

4. Configure Google OAuth (for authentication):
   - Create credentials at [Google Cloud Console](https://console.cloud.google.com/)
   - Set environment variables:
     ```bash
     export GOOGLE_CLIENT_ID="your-client-id"
     export GOOGLE_CLIENT_SECRET="your-client-secret"
     ```

5. Start the server:
   ```bash
   bin/dev
   ```

## Running Tests

```bash
bundle exec rails test
```

Test coverage: ~80% (line coverage)

## Project Structure

```
app/
├── controllers/       # Request handlers
├── models/           # ActiveRecord models
├── views/            # ERB templates
├── helpers/          # View helpers
├── jobs/             # Background jobs (file parsing)
└── services/         # Business logic
    └── parsers/      # Institution-specific parsers

test/
├── controllers/      # Controller tests
├── models/          # Model tests
├── services/        # Service tests
└── fixtures/        # Test data
```

## Key Models

- **User**: Authentication via Devise/Google OAuth
- **Workspace**: Container for transactions and members
- **Transaction**: Individual expense records
- **Category**: Transaction categorization with keyword matching
- **ProcessedFile**: Uploaded financial statement files
- **ParsingSession**: File parsing job tracking
- **WorkspaceInvitation**: Team member invitations

## File Parsing

1. Upload a statement file (Excel, CSV, or PDF)
2. System identifies the financial institution
3. Parser extracts transaction data
4. Duplicate detection prevents redundant entries
5. Transactions are auto-categorized based on merchant keywords

## License

This project is proprietary software.
