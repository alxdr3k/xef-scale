import React from 'react';
import { Avatar, Dropdown, Space } from 'antd';
import { UserOutlined, LogoutOutlined } from '@ant-design/icons';
import type { MenuProps } from 'antd';
import { useAuth } from '../../contexts/AuthContext';

const TopBar: React.FC = () => {
  const { user, logout } = useAuth();

  const handleLogout = async () => {
    await logout();
  };

  const menuItems: MenuProps['items'] = [
    {
      key: 'profile',
      icon: <UserOutlined />,
      label: user?.display_name || user?.email,
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
    <div style={{
      display: 'flex',
      justifyContent: 'space-between',
      alignItems: 'center',
      width: '100%'
    }}>
      <div style={{
        fontSize: '20px',
        fontWeight: 'bold',
        color: '#2196F3'
      }}>
        지출 추적기
      </div>
      <Dropdown menu={{ items: menuItems }} placement="bottomRight">
        <Space style={{ cursor: 'pointer' }}>
          <Avatar
            src={user?.profile_image_url}
            icon={<UserOutlined />}
            style={{ backgroundColor: '#2196F3' }}
          />
          <span>{user?.display_name || '사용자'}</span>
        </Space>
      </Dropdown>
    </div>
  );
};

export default TopBar;
