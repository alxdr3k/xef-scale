import React from 'react';
import { Layout } from 'antd';
import { Outlet } from 'react-router-dom';
import Sidebar from './Sidebar';
import TopBar from './TopBar';

const { Header, Content, Sider, Footer } = Layout;

const AuthenticatedLayout: React.FC = () => {
  return (
    <Layout style={{ minHeight: '100vh' }}>
      <Sider
        breakpoint="lg"
        collapsedWidth="0"
        style={{
          overflow: 'auto',
          height: '100vh',
          position: 'fixed',
          left: 0,
          top: 0,
          bottom: 0,
        }}
      >
        <div style={{
          height: 32,
          margin: 16,
          textAlign: 'center',
          color: '#fff',
          fontSize: '18px',
          fontWeight: 'bold'
        }}>
          ET
        </div>
        <Sidebar />
      </Sider>
      <Layout style={{ marginLeft: 200 }}>
        <Header style={{
          padding: '0 24px',
          background: '#fff',
          boxShadow: '0 2px 8px rgba(0, 0, 0, 0.06)',
          position: 'sticky',
          top: 0,
          zIndex: 1
        }}>
          <TopBar />
        </Header>
        <Content style={{ margin: '24px 16px 0', overflow: 'initial' }}>
          <div style={{
            padding: 24,
            minHeight: 360,
            background: '#fff',
            borderRadius: 8
          }}>
            <Outlet />
          </div>
        </Content>
        <Footer style={{ textAlign: 'center', background: '#f5f5f5' }}>
          Expense Tracker ©{new Date().getFullYear()} Created with Ant Design
        </Footer>
      </Layout>
    </Layout>
  );
};

export default AuthenticatedLayout;
