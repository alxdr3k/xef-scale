# Expense Tracker Frontend

React + TypeScript + Ant Design frontend for the Expense Tracker application.

## Tech Stack

- **Framework**: React 18 + TypeScript
- **Build Tool**: Vite
- **UI Library**: Ant Design (antd)
- **Charts**: Recharts
- **Routing**: React Router v6
- **State Management**: React Context API
- **HTTP Client**: Axios
- **Date Handling**: dayjs

## Project Structure

```
frontend/
├── src/
│   ├── components/
│   │   ├── common/         # Reusable components
│   │   └── layout/         # Layout components
│   │       ├── PublicLayout.tsx
│   │       ├── AuthenticatedLayout.tsx
│   │       ├── Sidebar.tsx
│   │       └── TopBar.tsx
│   ├── pages/              # Page components
│   │   ├── LandingPage.tsx
│   │   ├── Dashboard.tsx
│   │   ├── Transactions.tsx
│   │   ├── ParsingSessions.tsx
│   │   └── Settings.tsx
│   ├── contexts/           # React contexts
│   │   └── AuthContext.tsx
│   ├── api/                # API client configuration
│   │   └── client.ts
│   ├── types/              # TypeScript type definitions
│   │   └── index.ts
│   ├── theme.config.ts     # Ant Design theme configuration
│   ├── App.tsx
│   └── main.tsx
├── package.json
└── tsconfig.json
```

## Getting Started

### Prerequisites

- Node.js 18+ and npm

### Installation

1. Install dependencies:
   ```bash
   npm install
   ```

2. Create environment file:
   ```bash
   cp .env.example .env
   ```

3. Update `.env` with your configuration:
   ```
   VITE_API_BASE_URL=http://localhost:8000
   VITE_GOOGLE_CLIENT_ID=your_google_client_id
   ```

### Development

Run the development server:
```bash
npm run dev
```

The app will be available at http://localhost:5173

### Build

Build for production:
```bash
npm run build
```

Preview production build:
```bash
npm run preview
```

## Features

### Design System

- **Color Palette**: Primary blue (#2196F3) with category-specific colors
- **Typography**: Pretendard font family with Korean language support
- **Responsive Design**: Mobile-first approach with Ant Design breakpoints
- **Theme**: Customizable Ant Design theme in `theme.config.ts`

### Authentication

- Google OAuth 2.0 integration
- JWT-based session management
- Auto-login with stored tokens
- Protected routes with automatic redirect

### Pages

1. **Landing Page** (`/`)
   - Public page with feature showcase
   - Google login button
   - Auto-redirect to `/transactions` if authenticated

2. **Dashboard** (`/dashboard`)
   - Overview of expenses (to be implemented)

3. **Transactions** (`/transactions`)
   - Transaction list with filtering and sorting (to be implemented)

4. **Parsing Sessions** (`/parsing-sessions`)
   - Parsing job status and history (to be implemented)

5. **Settings** (`/settings`)
   - User preferences (to be implemented)

## Development Guidelines

### Adding New Pages

1. Create page component in `src/pages/`
2. Add route in `App.tsx`
3. Add navigation item in `Sidebar.tsx` if needed

### API Integration

All API calls should use the configured axios client from `src/api/client.ts`. The client automatically:
- Adds JWT token to requests
- Handles 401 (unauthorized) responses
- Redirects to login on auth failures

Example:
```typescript
import apiClient from '../api/client';

const fetchTransactions = async () => {
  const response = await apiClient.get('/api/transactions');
  return response.data;
};
```

### Type Safety

All API types are defined in `src/types/index.ts`. Always use these types for type-safe API interactions.

## Next Steps

- [ ] Implement Google OAuth login flow
- [ ] Build transaction list with filters and pagination
- [ ] Add data visualization charts
- [ ] Implement parsing session details view
- [ ] Add user settings page
- [ ] Write E2E tests with Playwright or Cypress
