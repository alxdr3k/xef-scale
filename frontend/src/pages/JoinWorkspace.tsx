import React, { useState, useEffect } from 'react';
import { useParams, useNavigate } from 'react-router-dom';
import { Card, Button, Spin, Alert, Typography, Descriptions, Tag, Space } from 'antd';
import {
  CheckCircleOutlined,
  CloseCircleOutlined,
  TeamOutlined,
} from '@ant-design/icons';
import { acceptInvitation } from '../api/workspaces';
import { useAuth } from '../contexts/AuthContext';
import { getErrorMessage } from '../utils/error';
import type { InvitationAcceptResponse } from '../types';

const { Title, Paragraph } = Typography;

interface JoinState {
  loading: boolean;
  error: string | null;
  success: boolean;
  workspaceInfo: InvitationAcceptResponse | null;
}

/**
 * JoinWorkspace Page
 *
 * Allows users to accept workspace invitations via token link.
 * Route: /join/:token
 *
 * Features:
 * - Validates invitation token
 * - Shows workspace preview if available
 * - Handles authentication redirect
 * - Accepts invitation and joins workspace
 * - Redirects to workspace after successful join
 */
const JoinWorkspace: React.FC = () => {
  const { token } = useParams<{ token: string }>();
  const navigate = useNavigate();
  const { isAuthenticated, isLoading: authLoading } = useAuth();

  const [state, setState] = useState<JoinState>({
    loading: false,
    error: null,
    success: false,
    workspaceInfo: null,
  });

  // Check authentication on mount
  useEffect(() => {
    if (!authLoading && !isAuthenticated) {
      // User not logged in - redirect to login with return URL
      const returnUrl = `/join/${token}`;
      navigate(`/?redirect=${encodeURIComponent(returnUrl)}`, { replace: true });
    }
  }, [isAuthenticated, authLoading, token, navigate]);

  const handleAcceptInvitation = async () => {
    if (!token) {
      setState(prev => ({
        ...prev,
        error: '초대 링크가 유효하지 않습니다.',
      }));
      return;
    }

    setState(prev => ({ ...prev, loading: true, error: null }));

    try {
      const result = await acceptInvitation(token);

      setState(prev => ({
        ...prev,
        loading: false,
        success: true,
        workspaceInfo: result,
      }));

      // Redirect to transactions page after 2 seconds
      setTimeout(() => {
        navigate('/transactions', { replace: true });
        // Optionally reload to refresh workspace list
        window.location.reload();
      }, 2000);
    } catch (error: any) {
      console.error('Failed to accept invitation:', error);

      let errorMessage = '초대 링크를 처리하는 중 오류가 발생했습니다.';

      // Parse error from backend
      const detail = error.response?.data?.detail;
      const detailStr = typeof detail === 'string' ? detail : getErrorMessage(error, '');

      // Map backend error messages to Korean
      if (detailStr.includes('not found')) {
        errorMessage = '유효하지 않은 초대 링크입니다.';
      } else if (detailStr.includes('expired')) {
        errorMessage = '이 초대 링크는 만료되었습니다.';
      } else if (detailStr.includes('revoked')) {
        errorMessage = '이 초대 링크는 취소되었습니다.';
      } else if (detailStr.includes('maximum uses')) {
        errorMessage = '이 초대 링크는 사용 횟수를 모두 소진했습니다.';
      } else if (detailStr.includes('already a member')) {
        errorMessage = '이미 이 워크스페이스의 멤버입니다.';
      } else if (detailStr) {
        errorMessage = detailStr;
      } else if (error.response?.status === 401) {
        errorMessage = '로그인이 필요합니다.';
      } else if (error.response?.status === 403) {
        errorMessage = '접근 권한이 없습니다.';
      }

      setState(prev => ({
        ...prev,
        loading: false,
        error: errorMessage,
      }));
    }
  };

  // Show loading while checking auth
  if (authLoading) {
    return (
      <div style={{ display: 'flex', justifyContent: 'center', alignItems: 'center', minHeight: '100vh' }}>
        <Spin size="large" tip="인증 확인 중..." />
      </div>
    );
  }

  // Don't render if not authenticated (will redirect)
  if (!isAuthenticated) {
    return null;
  }

  // Success state
  if (state.success && state.workspaceInfo) {
    return (
      <div style={{ display: 'flex', justifyContent: 'center', alignItems: 'center', minHeight: '100vh', padding: '24px' }}>
        <Card style={{ maxWidth: 600, width: '100%' }}>
          <div style={{ textAlign: 'center' }}>
            <CheckCircleOutlined style={{ fontSize: 64, color: '#52c41a', marginBottom: 24 }} />
            <Title level={2}>워크스페이스 참여 완료</Title>
            <Paragraph>
              <strong>{state.workspaceInfo.workspace_name}</strong> 워크스페이스에 성공적으로 참여했습니다.
            </Paragraph>
            <Descriptions bordered column={1} style={{ marginTop: 24, textAlign: 'left' }}>
              <Descriptions.Item label="워크스페이스">{state.workspaceInfo.workspace_name}</Descriptions.Item>
              <Descriptions.Item label="역할">
                <Tag color="blue">{state.workspaceInfo.role}</Tag>
              </Descriptions.Item>
            </Descriptions>
            <Paragraph style={{ marginTop: 24, color: '#888' }}>
              잠시 후 자동으로 이동됩니다...
            </Paragraph>
          </div>
        </Card>
      </div>
    );
  }

  // Error state
  if (state.error) {
    return (
      <div style={{ display: 'flex', justifyContent: 'center', alignItems: 'center', minHeight: '100vh', padding: '24px' }}>
        <Card style={{ maxWidth: 600, width: '100%' }}>
          <div style={{ textAlign: 'center' }}>
            <CloseCircleOutlined style={{ fontSize: 64, color: '#ff4d4f', marginBottom: 24 }} />
            <Title level={2}>초대 링크 오류</Title>
            <Alert
              message="초대 링크를 사용할 수 없습니다"
              description={state.error}
              type="error"
              showIcon
              style={{ marginTop: 24, textAlign: 'left' }}
            />
            <Space style={{ marginTop: 32 }}>
              <Button onClick={() => navigate('/transactions')}>
                거래 내역으로 이동
              </Button>
              <Button onClick={() => navigate('/workspace-settings')}>
                워크스페이스 설정
              </Button>
            </Space>
          </div>
        </Card>
      </div>
    );
  }

  // Initial state - show join button
  return (
    <div style={{ display: 'flex', justifyContent: 'center', alignItems: 'center', minHeight: '100vh', padding: '24px' }}>
      <Card style={{ maxWidth: 600, width: '100%' }}>
        <div style={{ textAlign: 'center' }}>
          <TeamOutlined style={{ fontSize: 64, color: '#1890ff', marginBottom: 24 }} />
          <Title level={2}>워크스페이스 초대</Title>
          <Paragraph>
            워크스페이스에 초대되었습니다. 아래 버튼을 클릭하여 참여하세요.
          </Paragraph>

          <Alert
            message="초대 링크 정보"
            description={
              <>
                <Paragraph>
                  초대를 수락하면 워크스페이스의 거래 내역을 확인하고 관리할 수 있습니다.
                </Paragraph>
                <Paragraph style={{ marginBottom: 0 }}>
                  역할에 따라 권한이 다를 수 있습니다.
                </Paragraph>
              </>
            }
            type="info"
            showIcon
            style={{ marginTop: 24, textAlign: 'left' }}
          />

          <Button
            type="primary"
            size="large"
            onClick={handleAcceptInvitation}
            loading={state.loading}
            style={{ marginTop: 32, width: '100%' }}
          >
            워크스페이스 참여
          </Button>

          <Paragraph style={{ marginTop: 16, color: '#888' }}>
            초대를 수락하지 않으려면 이 페이지를 닫으세요.
          </Paragraph>
        </div>
      </Card>
    </div>
  );
};

export default JoinWorkspace;
