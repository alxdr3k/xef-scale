import React from 'react';
import { Avatar, Dropdown, Space, Button } from 'antd';
import {
  UserOutlined,
  LogoutOutlined,
  MenuOutlined,
} from '@ant-design/icons';
import type { MenuProps } from 'antd';
import { useNavigate } from 'react-router-dom';
import { useAuth } from '../../contexts/AuthContext';
import { WorkspaceSelector } from '../workspace';

interface TopBarProps {
  onMenuClick?: () => void;
}

const TopBar: React.FC<TopBarProps> = ({ onMenuClick }) => {
  const { user, logout } = useAuth();
  const navigate = useNavigate();

  const handleLogout = async () => {
    await logout();
    // Redirect to landing page after logout
    navigate('/', { replace: true });
  };

  const menuItems: MenuProps['items'] = [
    {
      key: 'profile',
      icon: <UserOutlined />,
      label: user?.name || user?.email,
      disabled: true,
    },
    {
      type: 'divider',
    },
    {
      key: 'logout',
      icon: <LogoutOutlined />,
      label: '로그아웃',
      onClick: handleLogout,
    },
  ];

  return (
    <div
      style={{
        display: 'flex',
        justifyContent: 'space-between',
        alignItems: 'center',
        width: '100%',
      }}
    >
      <div style={{ display: 'flex', alignItems: 'center', gap: 16 }}>
        {/* Mobile hamburger menu button */}
        <Button
          type="text"
          icon={<MenuOutlined />}
          onClick={onMenuClick}
          className="mobile-menu-button"
          style={{ fontSize: 20 }}
        />
        <div
          style={{
            fontSize: '20px',
            fontWeight: 'bold',
            color: '#2196F3',
          }}
          className="desktop-title"
        >
          지출 추적기
        </div>
      </div>
      <Space size="middle" style={{ display: 'flex', alignItems: 'center' }}>
        {/* Workspace Selector - shown when authenticated */}
        <div className="workspace-selector-container">
          <WorkspaceSelector />
        </div>
        {/* User Profile Dropdown */}
        <Dropdown menu={{ items: menuItems }} placement="bottomRight">
          <Space style={{ cursor: 'pointer' }}>
            <Avatar
              src={user?.picture || undefined}
              icon={<UserOutlined />}
              style={{ backgroundColor: '#2196F3' }}
            />
            <span className="user-name">{user?.name || '사용자'}</span>
          </Space>
        </Dropdown>
      </Space>

      <style>{`
        @media (min-width: 992px) {
          .mobile-menu-button {
            display: none !important;
          }
        }

        @media (max-width: 991px) {
          .desktop-title {
            display: none !important;
          }
        }

        @media (max-width: 768px) {
          .workspace-selector-container {
            display: none !important;
          }
        }

        @media (max-width: 576px) {
          .user-name {
            display: none !important;
          }
        }
      `}</style>
    </div>
  );
};

export default TopBar;
