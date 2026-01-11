import React, { useState } from 'react';
import { Layout, Drawer } from 'antd';
import { Outlet } from 'react-router-dom';
import Sidebar from './Sidebar';
import TopBar from './TopBar';

const { Header, Content, Sider, Footer } = Layout;

const AuthenticatedLayout: React.FC = () => {
  const [mobileDrawerOpen, setMobileDrawerOpen] = useState(false);

  const toggleMobileDrawer = () => {
    setMobileDrawerOpen(!mobileDrawerOpen);
  };

  return (
    <Layout style={{ minHeight: '100vh' }}>
      {/* Desktop Sidebar */}
      <Sider
        breakpoint="lg"
        collapsedWidth="0"
        onBreakpoint={(broken) => {
          // Close mobile drawer when switching to desktop
          if (!broken) {
            setMobileDrawerOpen(false);
          }
        }}
        style={{
          overflow: 'auto',
          height: '100vh',
          position: 'fixed',
          left: 0,
          top: 0,
          bottom: 0,
        }}
        className="desktop-sider"
      >
        <div
          style={{
            height: 32,
            margin: 16,
            textAlign: 'center',
            color: '#fff',
            fontSize: '18px',
            fontWeight: 'bold',
          }}
        >
          지출 추적기
        </div>
        <Sidebar />
      </Sider>

      {/* Mobile Drawer */}
      <Drawer
        placement="left"
        onClose={() => setMobileDrawerOpen(false)}
        open={mobileDrawerOpen}
        styles={{ body: { padding: 0, background: '#001529' } }}
        size="default"
        className="mobile-drawer"
      >
        <div
          style={{
            height: 32,
            margin: 16,
            textAlign: 'center',
            color: '#fff',
            fontSize: '18px',
            fontWeight: 'bold',
          }}
        >
          지출 추적기
        </div>
        <Sidebar onMenuClick={() => setMobileDrawerOpen(false)} />
      </Drawer>

      <Layout
        style={{
          marginLeft: 0,
        }}
        className="main-layout"
      >
        <Header
          style={{
            padding: '0 24px',
            background: '#fff',
            boxShadow: '0 2px 8px rgba(0, 0, 0, 0.06)',
            position: 'sticky',
            top: 0,
            zIndex: 999,
          }}
        >
          <TopBar onMenuClick={toggleMobileDrawer} />
        </Header>
        <Content style={{ margin: '24px 16px 0', overflow: 'initial' }}>
          <div
            style={{
              padding: 24,
              minHeight: 360,
              background: '#fff',
              borderRadius: 8,
            }}
          >
            <Outlet />
          </div>
        </Content>
        <Footer style={{ textAlign: 'center', background: '#f5f5f5' }}>
          Expense Tracker ©{new Date().getFullYear()}
        </Footer>
      </Layout>

      <style>{`
        @media (min-width: 992px) {
          .main-layout {
            margin-left: 200px !important;
          }
          .mobile-drawer {
            display: none;
          }
        }

        @media (max-width: 991px) {
          .desktop-sider {
            display: none !important;
          }
        }
      `}</style>
    </Layout>
  );
};

export default AuthenticatedLayout;
