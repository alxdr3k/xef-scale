import { BrowserRouter as Router, Routes, Route, Navigate } from 'react-router-dom';
import { ConfigProvider, App as AntdApp } from 'antd';
import koKR from 'antd/locale/ko_KR';
import { AuthProvider, useAuth } from './contexts/AuthContext';
import { WorkspaceProvider } from './contexts/WorkspaceContext';
import { theme } from './theme.config';
import StaticApp from './components/common/StaticApp';

// Layouts
import PublicLayout from './components/layout/PublicLayout';
import AuthenticatedLayout from './components/layout/AuthenticatedLayout';

// Pages
import LandingPage from './pages/LandingPage';
import Dashboard from './pages/Dashboard';
import Transactions from './pages/Transactions';
import ParsingSessions from './pages/ParsingSessions';
import Settings from './pages/Settings';
import AllowanceSpending from './pages/AllowanceSpending';
import WorkspaceSettings from './pages/WorkspaceSettings';

// Auth components
import PrivateRoute from './components/auth/PrivateRoute';

/**
 * AppRoutes component
 * Handles all application routing with authentication protection
 */
function AppRoutes() {
  const { isAuthenticated } = useAuth();

  return (
    <Router>
      <Routes>
        {/* Public routes */}
        <Route element={<PublicLayout />}>
          <Route
            path="/"
            element={
              isAuthenticated ? (
                <Navigate to="/dashboard" replace />
              ) : (
                <LandingPage />
              )
            }
          />
        </Route>

        {/* Protected routes */}
        <Route
          element={
            <PrivateRoute>
              <AuthenticatedLayout />
            </PrivateRoute>
          }
        >
          <Route path="/dashboard" element={<Dashboard />} />
          <Route path="/transactions" element={<Transactions />} />
          <Route path="/parsing-sessions" element={<ParsingSessions />} />
          <Route path="/allowances" element={<AllowanceSpending />} />
          <Route path="/settings" element={<Settings />} />
          <Route path="/workspace-settings" element={<WorkspaceSettings />} />
        </Route>

        {/* Fallback route - redirect based on authentication state */}
        <Route
          path="*"
          element={<Navigate to={isAuthenticated ? '/dashboard' : '/'} replace />}
        />
      </Routes>
    </Router>
  );
}

function App() {
  return (
    <ConfigProvider theme={theme} locale={koKR}>
      <AntdApp>
        <StaticApp />
        <AuthProvider>
          <WorkspaceProvider>
            <AppRoutes />
          </WorkspaceProvider>
        </AuthProvider>
      </AntdApp>
    </ConfigProvider>
  );
}

export default App;
