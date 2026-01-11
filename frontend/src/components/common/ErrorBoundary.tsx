import { Component } from 'react';
import type { ErrorInfo, ReactNode } from 'react';
import { Result, Button } from 'antd';

interface Props {
  children: ReactNode;
}

interface State {
  hasError: boolean;
  error: Error | null;
  errorInfo: ErrorInfo | null;
}

/**
 * ErrorBoundary Component
 *
 * Catches JavaScript errors anywhere in the child component tree,
 * logs those errors, and displays a fallback UI instead of crashing the app.
 *
 * Usage:
 * <ErrorBoundary>
 *   <App />
 * </ErrorBoundary>
 */
class ErrorBoundary extends Component<Props, State> {
  constructor(props: Props) {
    super(props);
    this.state = {
      hasError: false,
      error: null,
      errorInfo: null,
    };
  }

  static getDerivedStateFromError(error: Error): State {
    // Update state so the next render will show the fallback UI
    return {
      hasError: true,
      error,
      errorInfo: null,
    };
  }

  componentDidCatch(error: Error, errorInfo: ErrorInfo): void {
    // Log error details to console for debugging
    console.error('ErrorBoundary caught an error:', error);
    console.error('Component stack trace:', errorInfo.componentStack);

    // Update state with error info
    this.setState({
      error,
      errorInfo,
    });

    // TODO: Send error to monitoring service (e.g., Sentry)
    // logErrorToService(error, errorInfo);
  }

  handleReload = (): void => {
    // Clear error state and reload the page
    window.location.reload();
  };

  render(): ReactNode {
    if (this.state.hasError) {
      return (
        <div
          style={{
            display: 'flex',
            justifyContent: 'center',
            alignItems: 'center',
            minHeight: '100vh',
            padding: '20px',
            backgroundColor: '#f5f5f5',
          }}
        >
          <Result
            status="500"
            title="문제가 발생했습니다"
            subTitle="예상치 못한 오류가 발생했습니다. 페이지를 새로고침하거나 잠시 후 다시 시도해주세요."
            extra={
              <Button type="primary" onClick={this.handleReload}>
                페이지 새로고침
              </Button>
            }
          >
            {import.meta.env.DEV && this.state.error && (
              <div
                style={{
                  marginTop: 24,
                  padding: 16,
                  backgroundColor: '#fff',
                  borderRadius: 8,
                  textAlign: 'left',
                  maxWidth: 600,
                  margin: '24px auto 0',
                }}
              >
                <details style={{ whiteSpace: 'pre-wrap', fontSize: 12 }}>
                  <summary style={{ cursor: 'pointer', fontWeight: 'bold', marginBottom: 8 }}>
                    에러 상세 정보 (개발 모드)
                  </summary>
                  <div style={{ marginTop: 8 }}>
                    <strong>Error:</strong> {this.state.error.toString()}
                  </div>
                  {this.state.errorInfo && (
                    <div style={{ marginTop: 8 }}>
                      <strong>Component Stack:</strong>
                      <pre style={{ marginTop: 4, fontSize: 11 }}>
                        {this.state.errorInfo.componentStack}
                      </pre>
                    </div>
                  )}
                </details>
              </div>
            )}
          </Result>
        </div>
      );
    }

    return this.props.children;
  }
}

export default ErrorBoundary;
