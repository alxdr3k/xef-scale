# xef-scale

A Rails 8 expense tracking application for Korean financial statements. Users add transactions by entering them directly, pasting financial SMS/text, uploading screenshots of card statements, or writing through the API. Text and image inputs are parsed with Gemini (Flash for text, Vision for images).

## Features

- **Workspace Management**: Create and manage multiple workspaces for organizing expenses
- **Transaction Management**: Track, filter, and categorize expenses
- **Four input paths** (the full input surface):
  - **Direct entry**: Create a transaction manually via the web UI
  - **Text paste**: Paste card/bank SMS and Gemini Flash extracts transactions
  - **Screenshot upload**: Upload card statement screenshots (JPG/PNG/WEBP/HEIC) and Gemini Vision extracts transactions
  - **API write**: Create committed transactions with an API key that has the `write` scope
- **Allowance Tracking**: Mark transactions as allowance for personal budget tracking
- **Member Collaboration**: Invite team members with different permission levels
- **Export**: Export transactions to CSV format

## Technology Stack

- **Ruby** 3.3+
- **Rails** 8.1.x
- **SQLite3** (database)
- **Tailwind CSS** 4.x (styling)
- **Hotwire** (Turbo + Stimulus)
- **Devise** + OmniAuth (authentication with Google OAuth2)
- **Pagy** 9.x (pagination)
- **Gemini** (Flash for text, Vision for screenshots) via direct HTTP

## Requirements

- Ruby 3.3.10+
- Bun (for JavaScript/CSS bundling)
- SQLite3
- `GEMINI_API_KEY` environment variable

## Setup

1. Clone the repository:
   ```bash
   git clone <repository-url>
   cd xef-scale
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
     export GEMINI_API_KEY="your-gemini-api-key"
     ```

5. Start the server:
   ```bash
   bin/dev
   ```

## Running Tests

```bash
bin/rails db:test:prepare test
```

See [docs/current/TESTING.md](docs/current/TESTING.md) for the full validation matrix.

## Project Structure

```
app/
├── controllers/       # Request handlers
├── models/           # ActiveRecord models
├── views/            # ERB templates
├── helpers/          # View helpers
├── jobs/             # Background jobs (text/image parsing)
└── services/         # Business logic
    ├── ai_text_parser.rb             # Gemini Flash text parser
    ├── image_statement_parser.rb     # Screenshot parser wrapper
    ├── gemini_vision_parser_service.rb # Gemini Vision API client
    ├── gemini_category_service.rb    # Gemini-based category suggestions
    ├── database_backup_service.rb    # SQLite backup helper
    └── recurring_payment_detector.rb # Subscription/recurring-charge detection

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
- **ProcessedFile**: Uploaded statement screenshots (image files only)
- **ParsingSession**: Parsing job tracking (source: text paste or image upload)
- **WorkspaceInvitation**: Team member invitations

## Input paths

Four entry points. Text and image paths share the same parse → review → commit pipeline; direct entry and API write skip it.

1. **Direct entry** → form in the transactions UI creates a committed transaction immediately (no review session)
2. **Text paste** → `AiTextParser` (Gemini Flash) → `pending_review` transactions
3. **Screenshot upload (JPG/PNG/WEBP/HEIC)** → `ImageStatementParser` → `GeminiVisionParserService` (Gemini Vision) → `pending_review` transactions
4. **API write** → `POST /api/v1/transactions` with a `write` scoped API key creates a committed transaction immediately

For the parsing paths (2 and 3):

5. Auto-categorization runs via `CategoryMapping` + `Category` keyword match; only the screenshot path sends remaining uncategorized merchants to `GeminiCategoryService`
6. Duplicate detection creates `DuplicateConfirmation` records for review
7. User reviews the session and commits — pending duplicates must be resolved first

Excel, PDF, CSV, and HTML statements are **not** supported. Only direct entry, SMS/text paste, image screenshots, and API write are in scope.

## Documentation

For implementation context (current state, runtime flow, data model, AI pipeline, testing, operations), see [docs/README.md](docs/README.md). AI coding agents should start with [AGENTS.md](AGENTS.md); Claude-specific operating rules live in [CLAUDE.md](CLAUDE.md).

## License

This project is proprietary software.
