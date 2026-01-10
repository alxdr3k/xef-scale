import React from 'react';
import { Button, Typography, Space, Card, Row, Col } from 'antd';
import { GoogleOutlined, CheckCircleOutlined } from '@ant-design/icons';
import { useAuth } from '../contexts/AuthContext';
import { useNavigate } from 'react-router-dom';

const { Title, Paragraph } = Typography;

const LandingPage: React.FC = () => {
  const { isAuthenticated } = useAuth();
  const navigate = useNavigate();

  // Redirect to transactions if already logged in
  React.useEffect(() => {
    if (isAuthenticated) {
      navigate('/transactions');
    }
  }, [isAuthenticated, navigate]);

  const handleGoogleLogin = () => {
    // TODO: Implement Google OAuth login flow
    console.log('Google login clicked');
  };

  const features = [
    {
      title: '파일 자동 파싱',
      description: '신한카드, 하나카드, 토스뱅크, 카카오뱅크 등 주요 금융기관의 명세서를 자동으로 파싱합니다.',
    },
    {
      title: '지출 분석',
      description: '카테고리별 지출 현황을 시각화하여 한눈에 확인할 수 있습니다.',
    },
    {
      title: '다중 금융기관 지원',
      description: '여러 은행과 카드사의 데이터를 하나로 통합하여 관리합니다.',
    },
  ];

  return (
    <div style={{ padding: '50px 0', maxWidth: '1200px', margin: '0 auto' }}>
      {/* Hero Section */}
      <div style={{ textAlign: 'center', marginBottom: '60px' }}>
        <Title level={1}>지출 추적을 더 쉽게</Title>
        <Paragraph style={{ fontSize: '18px', color: '#666', margin: '20px 0 40px' }}>
          금융기관 명세서를 자동으로 파싱하고 지출을 분석하세요
        </Paragraph>
        <Button
          type="primary"
          size="large"
          icon={<GoogleOutlined />}
          onClick={handleGoogleLogin}
          style={{ height: '48px', fontSize: '16px', padding: '0 40px' }}
        >
          Google로 시작하기
        </Button>
      </div>

      {/* Features Section */}
      <Row gutter={[24, 24]}>
        {features.map((feature, index) => (
          <Col xs={24} md={8} key={index}>
            <Card
              hoverable
              style={{ height: '100%' }}
            >
              <Space direction="vertical" size="middle">
                <CheckCircleOutlined style={{ fontSize: '32px', color: '#2196F3' }} />
                <Title level={4}>{feature.title}</Title>
                <Paragraph>{feature.description}</Paragraph>
              </Space>
            </Card>
          </Col>
        ))}
      </Row>
    </div>
  );
};

export default LandingPage;
