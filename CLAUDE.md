# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

**Expense Tracker (지출 추적 앱)** - A local file-watching system that automatically parses financial statements from Korean banks and credit cards to track expenses.

### Core Concept
Instead of email automation or web scraping, users manually download statements (Excel/PDF) from their bank apps/websites and drop them into a watched folder (`inbox`). The system:
1. Detects new files using a file watcher (`watchdog` library)
2. Identifies the financial institution through content-based routing (header keywords)
3. Parses the data using institution-specific parsers
4. Stores transactions in a unified format (CSV/SQLite)
5. Archives the processed files

## Supported Financial Institutions

- 신한카드 (Shinhan Card)
- 하나카드 (Hana Card)
- 토스뱅크 (Toss Bank)
- 토스페이 (Toss Pay)
- 카카오뱅크 (Kakao Bank)
- 카카오페이 (Kakao Pay)

Note: Each institution provides data through open APIs. You should research and document API specifications in the project's documentation directory when implementing.

## Data Schema

Final transaction format (Transaction DTO):
- **월** (month): mm format
- **날짜** (date): yyyy.mm.dd format
- **분류** (category): Auto-categorized based on merchant name (식비/편의점/교통/보험/기타 등)
- **내역** (item): Merchant/transaction description
- **금액** (amount): Integer amount
- **지출 위치** (source): Bank/card name (e.g., "신한카드", "하나카드")

## Architecture

### Key Components

1. **File Watcher** (`watchdog.observers.Observer`)
   - Monitors `./inbox` directory for new files
   - Triggers processing on file creation events
   - Ignores temporary files (.crdownload, hidden files)

2. **Router/Identifier**
   - Content-based routing: Analyzes file headers/content to identify institution
   - Supports both extension-based (`.xlsx`, `.csv`, `.pdf`) and content-based identification
   - Keywords for identification:
     - 토스뱅크: "토스뱅크", "Toss", "수신자", "거래유형"
     - 카카오뱅크: "kakao", "카카오뱅크", "거래일시", "거래구분"
     - 신한/하나카드: "이용일자", "승인번호", "가맹점명"

3. **Parser Strategy Pattern**
   - `StatementParser` (Abstract base class): Defines `parse()` interface
   - Institution-specific parsers inherit from base:
     - `HanaCardParser`: Uses `pandas` for structured CSV/Excel
     - `ShinhanCardParser`: Uses regex for unstructured text/PDF
     - `TossParser`, `KakaoParser`: Similar structured approaches

4. **CategoryMatcher**
   - Helper class for auto-categorizing transactions based on merchant names
   - Uses keyword matching (e.g., "마라탕", "식당" → "식비")
   - Should be trained/expanded over time with user's actual merchants

5. **Data Loader**
   - Appends parsed data to `./data/master_ledger.csv` (or SQLite DB)
   - Moves processed files to `./archive` directory

### Directory Structure

```
expense-tracker/
├── inbox/           # Drop zone for downloaded statements
├── archive/         # Processed files moved here
├── data/           # master_ledger.csv or database
└── shrimp_data/    # MCP task manager data (from .mcp.json)
```

## Parsing Strategy by Institution

### CSV/Excel Files (Structured)
- **하나카드, 토스뱅크, 카카오뱅크**: Use `pandas.read_excel()` or `pandas.read_csv()`
- Skip metadata rows (top 3-4 rows typically contain account info)
- Extract columns: date, merchant name, amount
- Normalize date format to `yyyy.mm.dd`

### PDF/Text Files (Unstructured)
- **신한카드**: Often comes as PDF or complex text
- Use `pdfplumber` for table extraction or OCR
- Regex patterns to extract:
  - Date: `\d{2}\.\d{2}\.\d{2}` (convert to `20YY.MM.DD`)
  - Merchant: Follow date line, strip prefixes like "본인357"
  - Amount: Number patterns with comma separators
- Context-aware parsing: track state (current_date, current_item) across lines

## Development Guidelines

### When Adding New Institution Parser

1. Create new parser class inheriting from `StatementParser`
2. Implement `parse(input_data) -> List[Transaction]` method
3. Add identification keywords to router's `identify_bank_by_columns()` method
4. Test with actual statement samples from that institution
5. Handle edge cases: multiple metadata rows, different date formats, currency symbols

### Category Matching Strategy

- Start with basic keyword mapping in `CategoryMatcher.get_category()`
- Initial categories: 식비, 편의점/마트/잡화, 교통/자동차, 주거/통신, 보험, 기타
- Expand merchant dictionary over time based on user's actual spending patterns
- Consider: Allow manual corrections that feed back into the matcher

### Error Handling

- Gracefully skip unparseable rows (log but don't crash)
- Validate date formats before processing
- Handle amount parsing edge cases (commas, decimals, negative values)
- If institution cannot be identified, move to a `./unknown` folder for manual review

## Technology Stack

**Note**: This project is intended to be implemented 100% with AI agents, so choose the most suitable tech stack for that context.

Current implementation basis (from PRD):
- **Language**: Python
- **File Watching**: `watchdog` library
- **Data Processing**: `pandas` for structured data
- **Text Extraction**: `pdfplumber` for PDFs, `re` for regex parsing
- **Storage**: CSV (master_ledger.csv) or SQLite database
- **MCP Integration**: shrimp-task-manager for task management (see `.mcp.json`)

## Important Considerations

### Security & Privacy
- No credential storage required - users download files manually
- All processing happens locally
- No network calls to bank APIs (manual download approach)

### Format Change Resilience
- Bank statement formats may change - parsers need maintenance
- Use flexible regex and column detection where possible
- Log parsing failures for debugging

### Manual Intervention
- Users must periodically (e.g., monthly) download statements from each institution
- This is not fully automated but provides better security and compatibility

## Language Note

This project documentation and requirements are primarily in Korean. Transaction descriptions, merchant names, and categories will be in Korean. When working with data samples or examples, expect Korean text in the merchant names and descriptions.

## Claude Code Workflow Instructions

**CRITICAL**: When working on tasks in this repository, ALWAYS use specialized subagents via the Task tool. Direct tool usage should be minimized.

### Mandatory Subagent Usage

1. **For all exploration and search tasks**: Use `Task` tool with `subagent_type=Explore`
   - Finding files, searching code, understanding codebase structure
   - Investigating how features work or where code is located
   - Analyzing patterns and relationships in the code

2. **For implementation tasks**: Use `Task` tool with `subagent_type=Plan` first
   - Any code changes or new features
   - Bug fixes that affect multiple files
   - Refactoring or architectural changes

3. **For specialized tasks**: Use appropriate subagent types
   - Bash operations: `subagent_type=Bash`
   - General research: `subagent_type=general-purpose`

4. **For project management and task breakdown**: Use `Task` tool with `subagent_type=project-manager`
   - Breaking down complex features into implementable tasks
   - Coordinating work across frontend/backend/database/infrastructure
   - Creating structured implementation plans
   - Managing software projects with multiple components

5. **For backend development**: Use `Task` tool with `subagent_type=senior-backend-architect`
   - Backend architecture design and implementation (Python, Node.js, Rust)
   - Comprehensive unit testing strategies
   - API design and backend system development
   - Cross-team collaboration (frontend-backend integration)

6. **For frontend development**: Use `Task` tool with `subagent_type=frontend-architect`
   - Frontend architecture and React/UI component implementation
   - API integration and real-time data handling
   - E2E testing and frontend testing strategies
   - Cross-platform and responsive design implementation

7. **For UX/UI design**: Use `Task` tool with `subagent_type=ux-ui-design-specialist`
   - UX/UI design decisions and modern design patterns
   - Visual design implementation review
   - User experience optimization
   - Frontend-design collaboration guidance

8. **For database work**: Use `Task` tool with `subagent_type=database-architect`
   - Database schema design and refactoring
   - Migration script creation and review
   - Query optimization and performance tuning
   - Database scaling strategies and technology selection

### MCP Tool Integration

**MANDATORY**: Use MCP tools for enhanced project management and documentation:

1. **Shrimp Task Manager** (`shrimp-task-manager` MCP server)
   - **ALWAYS** use when planning and breaking down tasks
   - Use `plan_task` to create structured implementation plans
   - Use `split_tasks` to break complex tasks into subtasks
   - Use `execute_task` and `verify_task` for task execution tracking
   - Use `analyze_task` and `reflect_task` for post-implementation review
   - Commands: Check schema with `mcp-cli info shrimp-task-manager/<tool>` before calling

2. **Context7 Documentation** (`context7` MCP server)
   - **ALWAYS** use when referencing external libraries or frameworks
   - Use `resolve-library-id` to identify the correct library
   - Use `query-docs` to fetch up-to-date documentation and examples
   - Essential for: Rust crates, API references, framework documentation
   - Commands: Check schema with `mcp-cli info context7/<tool>` before calling

**Remember**: ALWAYS call `mcp-cli info <server>/<tool>` BEFORE `mcp-cli call <server>/<tool>` to verify the correct schema.

### Workflow Pattern

```
User Request → Assess Task Type → Launch Appropriate Subagent → Review Results → Report to User
                    ↓
    ┌───────────────┼───────────────┐
    │               │               │
Project Mgmt   Backend/FE/DB    Design/UX
    │               │               │
    ├─ project-manager              ├─ ux-ui-design-specialist
    ├─ senior-backend-architect     │
    ├─ frontend-architect           │
    └─ database-architect           │
                    │
          Use Shrimp MCP for task planning
          Use Context7 MCP for library docs
```

**Agent Selection Guide**:
- Complex multi-component features → `project-manager`
- Backend/API development → `senior-backend-architect`
- Frontend/UI implementation → `frontend-architect`
- Database schema/queries → `database-architect`
- UX/design decisions → `ux-ui-design-specialist`
- Codebase exploration → `Explore`
- Implementation planning → `Plan`

**Never** directly use Glob/Grep/Read for exploration when a subagent would be more appropriate. This ensures efficient context usage and thorough analysis.