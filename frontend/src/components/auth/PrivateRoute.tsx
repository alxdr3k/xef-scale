import React from 'react';
import { Navigate, useLocation } from 'react-router-dom';
import { useAuth } from '../../contexts/AuthContext';
import LoadingSkeleton from '../common/LoadingSkeleton';

interface PrivateRouteProps {
  children: React.ReactElement;
}

/**
 * PrivateRoute component
 * Protects routes that require authentication
 * - Shows loading skeleton while checking authentication
 * - Redirects to landing page if not authenticated
 * - Preserves the original location for post-login redirect
 */
const PrivateRoute: React.FC<PrivateRouteProps> = ({ children }) => {
  const { isAuthenticated, isLoading } = useAuth();
  const location = useLocation();

  // Show loading skeleton while checking authentication (prevents flash of content)
  if (isLoading) {
    return (
      <div style={{ padding: '24px' }}>
        <LoadingSkeleton type="card" rows={4} />
      </div>
    );
  }

  // Redirect to landing page if not authenticated
  // Preserve the original location for post-login redirect
  if (!isAuthenticated) {
    return <Navigate to="/" state={{ from: location.pathname }} replace />;
  }

  // Render protected content
  return children;
};

export default PrivateRoute;
