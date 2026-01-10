import React from 'react';
import { Layout } from 'antd';
import { Outlet } from 'react-router-dom';

const { Header, Content, Footer } = Layout;

const PublicLayout: React.FC = () => {
  return (
    <Layout style={{ minHeight: '100vh' }}>
      <Header style={{
        display: 'flex',
        alignItems: 'center',
        background: '#fff',
        boxShadow: '0 2px 8px rgba(0, 0, 0, 0.06)'
      }}>
        <div style={{
          fontSize: '20px',
          fontWeight: 'bold',
          color: '#2196F3'
        }}>
          지출 추적기
        </div>
      </Header>
      <Content style={{ padding: '0 50px' }}>
        <Outlet />
      </Content>
      <Footer style={{ textAlign: 'center', background: '#f5f5f5' }}>
        Expense Tracker ©{new Date().getFullYear()} Created with Ant Design
      </Footer>
    </Layout>
  );
};

export default PublicLayout;
