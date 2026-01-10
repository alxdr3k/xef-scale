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

**Task Tool Subagents** (use `Task` tool with appropriate `subagent_type`):
- `Explore`: File/code search, codebase structure, feature investigation
- `Plan`: Implementation planning before code changes
- `project-manager`: Multi-component feature breakdown, cross-stack coordination
- `senior-backend-architect`: Backend/API development (Python/Node/Rust), unit testing
- `frontend-architect`: Frontend/React/UI implementation, E2E testing
- `database-architect`: Schema design, migrations, query optimization
- `ux-ui-design-specialist`: UX/UI decisions, design patterns, design review
- `Bash`: Shell operations, `general-purpose`: Research tasks

### MCP Tool Integration

**Shrimp Task Manager**: Primarily used by the `project-manager` agent for task planning (`plan_task`, `split_tasks`), execution tracking (`execute_task`, `verify_task`), and review (`analyze_task`, `reflect_task`). Direct shrimp MCP usage should be delegated to the project-manager agent in most cases.

**Context7**: Use for library documentation (`resolve-library-id`, `query-docs`) when referencing external libraries/frameworks

**CRITICAL**: Always run `mcp-cli info <server>/<tool>` BEFORE `mcp-cli call <server>/<tool>`

### Task Completion Protocol

**CRITICAL: After completing EACH Shrimp task**:
1. Create git commit IMMEDIATELY after task implementation
2. Commit message MUST reference the completed Shrimp task
3. Then update Shrimp status via `project-manager` agent (`execute_task` or `verify_task`)

**Workflow**:
- Simple task: Implement → Git commit → Report to user
- Shrimp task: Implement → **Git commit** → `project-manager` (update Shrimp) → Report to user
- Complex multi-task: For EACH subtask → Implement → **Git commit** → `project-manager` (update Shrimp) → Next subtask

**Never skip commits**: Every Shrimp task completion = One git commit before Shrimp status update

### Subagent Execution Strategy

**Dependency Chain**: Phase 1 (Discovery) → Phase 2 (Design) → Phase 3 (Implementation) → Phase 4 (Verification)

**✅ Parallel Execution**:
- Phase 1: `Explore` + `project-manager` + `context7` (discovery tasks)
- Phase 3: `database-architect` + `senior-backend-architect` + `frontend-architect` (if independent)
- Independent features/bugs across any specialized agents

**❌ Sequential Execution**:
- `Explore` → `Plan` → Implementation agents (must understand before implementing)
- `database-architect` → `senior-backend-architect` → `frontend-architect` (dependency chain)
- `ux-ui-design-specialist` → `frontend-architect` (design before UI)
- Implementation → `Bash` tests (code before testing)
- Task management: `project-manager` handles Shrimp flow (`plan_task` → `split_tasks` → `execute_task` → `verify_task`)

**Agent Priority**:
- Start with `Explore` for unfamiliar codebases
- Use `project-manager` for multi-component features and Shrimp task management
- Use `Plan` after exploration, before specialized agents
- `database-architect` before `senior-backend-architect` before `frontend-architect`
- Delegate Shrimp MCP operations to `project-manager` instead of direct usage

**Examples**:
1. Full-stack feature: `Explore` + `context7` (parallel) → `project-manager` (Shrimp planning) → `database-architect` → `senior-backend-architect` → `frontend-architect` → `Bash` tests → `project-manager` (Shrimp update)
2. Independent bugs: `Explore` (parallel for each) → specialized agents (parallel) → `Bash` tests (parallel)
3. Complex multi-phase project: `project-manager` creates Shrimp tasks → delegate to specialized agents → `project-manager` tracks/updates Shrimp progress

**Never** use Glob/Grep/Read when `Explore` agent is more appropriate.