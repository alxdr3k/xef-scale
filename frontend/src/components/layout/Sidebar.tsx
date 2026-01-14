import React from 'react';
import { Menu } from 'antd';
import { useNavigate, useLocation } from 'react-router-dom';
import {
  DashboardOutlined,
  TransactionOutlined,
  FileTextOutlined,
  WalletOutlined,
  SettingOutlined,
} from '@ant-design/icons';

interface SidebarProps {
  onMenuClick?: () => void;
}

const Sidebar: React.FC<SidebarProps> = ({ onMenuClick }) => {
  const navigate = useNavigate();
  const location = useLocation();

  const menuItems = [
    {
      key: '/dashboard',
      icon: <DashboardOutlined />,
      label: '대시보드',
    },
    {
      key: '/transactions',
      icon: <TransactionOutlined />,
      label: '지출 내역',
    },
    {
      key: '/parsing-sessions',
      icon: <FileTextOutlined />,
      label: '파싱 현황',
    },
    {
      key: '/allowances',
      icon: <WalletOutlined />,
      label: '용돈 내역',
    },
    {
      key: '/settings',
      icon: <SettingOutlined />,
      label: '설정',
    },
  ];

  const handleMenuClick = (key: string) => {
    navigate(key);
    // Close mobile drawer after navigation
    if (onMenuClick) {
      onMenuClick();
    }
  };

  return (
    <Menu
      theme="dark"
      mode="inline"
      selectedKeys={[location.pathname]}
      items={menuItems}
      onClick={({ key }) => handleMenuClick(key)}
    />
  );
};

export default Sidebar;
