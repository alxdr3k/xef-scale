import React from 'react';
import { Typography, Space, Card, Row, Col, Tag, Divider, message } from 'antd';
import {
  FileSearchOutlined,
  PieChartOutlined,
  ThunderboltOutlined,
} from '@ant-design/icons';
import { GoogleLogin } from '@react-oauth/google';
import type { CredentialResponse } from '@react-oauth/google';
import { useAuth } from '../contexts/AuthContext';
import { useNavigate } from 'react-router-dom';

const { Title, Paragraph, Text } = Typography;

const LandingPage: React.FC = () => {
  const { isAuthenticated, login } = useAuth();
  const navigate = useNavigate();

  // Redirect to transactions if already logged in
  React.useEffect(() => {
    if (isAuthenticated) {
      navigate('/transactions');
    }
  }, [isAuthenticated, navigate]);

  const handleGoogleSuccess = async (credentialResponse: CredentialResponse) => {
    try {
      if (!credentialResponse.credential) {
        message.error('Google 인증 정보를 받지 못했습니다');
        return;
      }

      await login(credentialResponse.credential);
      message.success('로그인 성공!');
      navigate('/transactions');
    } catch (error) {
      console.error('Google login error:', error);
      message.error('Google 로그인에 실패했습니다. 다시 시도해주세요.');
    }
  };

  const handleGoogleError = () => {
    message.error('Google 로그인에 실패했습니다');
  };

  const features = [
    {
      icon: <FileSearchOutlined />,
      title: '파일 자동 파싱',
      description:
        '신한카드, 하나카드, 토스뱅크, 카카오뱅크 등 주요 금융기관의 명세서를 자동으로 파싱합니다.',
      color: '#2196F3',
    },
    {
      icon: <ThunderboltOutlined />,
      title: '지능형 분류',
      description:
        'AI 기반 카테고리 자동 분류로 식비, 교통비, 쇼핑 등 지출 유형을 자동으로 구분합니다.',
      color: '#52c41a',
    },
    {
      icon: <PieChartOutlined />,
      title: '실시간 분석',
      description:
        '카테고리별 지출 현황과 추세를 시각화하여 한눈에 확인할 수 있습니다.',
      color: '#faad14',
    },
  ];

  const supportedBanks = [
    { name: '신한카드', color: '#0046ff' },
    { name: '하나카드', color: '#008485' },
    { name: '토스뱅크', color: '#0064ff' },
    { name: '토스페이', color: '#0064ff' },
    { name: '카카오뱅크', color: '#ffeb00' },
    { name: '카카오페이', color: '#ffeb00' },
  ];

  return (
    <div
      style={{
        minHeight: '100vh',
        background: 'linear-gradient(135deg, #667eea 0%, #764ba2 100%)',
      }}
    >
      <div
        style={{
          padding: '80px 24px',
          maxWidth: '1200px',
          margin: '0 auto',
        }}
      >
        {/* Hero Section */}
        <div
          style={{
            textAlign: 'center',
            marginBottom: '80px',
            color: '#fff',
          }}
        >
          <Title
            level={1}
            style={{
              color: '#fff',
              fontSize: '48px',
              marginBottom: '24px',
              fontWeight: 700,
            }}
          >
            지출 추적을 더 쉽게
          </Title>
          <Paragraph
            style={{
              fontSize: '20px',
              color: 'rgba(255, 255, 255, 0.9)',
              margin: '0 0 48px',
              maxWidth: '600px',
              marginLeft: 'auto',
              marginRight: 'auto',
            }}
          >
            한국 금융기관 명세서를 자동으로 파싱하고 분석하세요
          </Paragraph>
          <div style={{ display: 'flex', justifyContent: 'center' }}>
            <GoogleLogin
              onSuccess={handleGoogleSuccess}
              onError={handleGoogleError}
              size="large"
              text="continue_with"
              shape="rectangular"
              theme="filled_blue"
              width="300"
            />
          </div>
        </div>

        {/* Features Section */}
        <Row gutter={[24, 24]} style={{ marginBottom: '80px' }}>
          {features.map((feature, index) => (
            <Col xs={24} md={8} key={index}>
              <Card
                hoverable
                style={{
                  height: '100%',
                  borderRadius: 16,
                  border: 'none',
                  boxShadow: '0 4px 16px rgba(0, 0, 0, 0.1)',
                }}
              >
                <Space direction="vertical" size="large" style={{ width: '100%' }}>
                  <div
                    style={{
                      fontSize: '48px',
                      color: feature.color,
                      textAlign: 'center',
                    }}
                  >
                    {feature.icon}
                  </div>
                  <Title level={4} style={{ textAlign: 'center', marginBottom: 8 }}>
                    {feature.title}
                  </Title>
                  <Paragraph
                    style={{
                      textAlign: 'center',
                      color: '#666',
                      marginBottom: 0,
                    }}
                  >
                    {feature.description}
                  </Paragraph>
                </Space>
              </Card>
            </Col>
          ))}
        </Row>

        {/* Supported Banks Section */}
        <div
          style={{
            background: '#fff',
            borderRadius: 16,
            padding: '48px 24px',
            textAlign: 'center',
            boxShadow: '0 4px 16px rgba(0, 0, 0, 0.1)',
          }}
        >
          <Title level={3} style={{ marginBottom: 32 }}>
            지원하는 금융기관
          </Title>
          <Space size={[16, 16]} wrap style={{ justifyContent: 'center' }}>
            {supportedBanks.map((bank) => (
              <Tag
                key={bank.name}
                style={{
                  padding: '8px 24px',
                  fontSize: '16px',
                  borderRadius: 24,
                  border: `2px solid ${bank.color}`,
                  color: bank.color,
                  background: 'transparent',
                  fontWeight: 500,
                }}
              >
                {bank.name}
              </Tag>
            ))}
          </Space>
          <Divider />
          <Text type="secondary" style={{ fontSize: 14 }}>
            더 많은 금융기관이 계속 추가될 예정입니다
          </Text>
        </div>

        {/* Footer */}
        <div
          style={{
            textAlign: 'center',
            marginTop: '80px',
            color: 'rgba(255, 255, 255, 0.8)',
          }}
        >
          <div style={{ marginBottom: '8px' }}>
            <Text style={{ color: 'rgba(255, 255, 255, 0.8)', fontSize: 14 }}>
              © {new Date().getFullYear()} 지출 추적기
            </Text>
          </div>
          <div>
            <Text style={{ color: 'rgba(255, 255, 255, 0.7)', fontSize: 13 }}>
              안전한 로컬 지출 관리
            </Text>
          </div>
        </div>
      </div>

      <style>{`
        @media (max-width: 768px) {
          h1 {
            font-size: 32px !important;
          }
          .ant-typography {
            font-size: 16px !important;
          }
        }
      `}</style>
    </div>
  );
};

export default LandingPage;
