import React from 'react';
import { Typography, Row, Col, Card } from 'antd';
import {
  FileTextOutlined,
  UnorderedListOutlined,
  DollarOutlined,
  ClockCircleOutlined,
} from '@ant-design/icons';
import { useNavigate } from 'react-router-dom';
import { useAuth } from '../contexts/AuthContext';
import StatCard from '../components/common/StatCard';

const { Title, Paragraph } = Typography;

/**
 * Dashboard page
 * Displays welcome message, summary statistics, and quick links
 */
const Dashboard: React.FC = () => {
  const navigate = useNavigate();
  const { user } = useAuth();

  const quickLinks = [
    {
      title: '지출 내역 조회',
      description: '월별 지출 내역을 확인하고 분석하세요',
      icon: <UnorderedListOutlined style={{ fontSize: 32 }} />,
      path: '/transactions',
      color: '#2196F3',
    },
    {
      title: '파싱 이력',
      description: '파일 파싱 세션 이력을 확인하세요',
      icon: <FileTextOutlined style={{ fontSize: 32 }} />,
      path: '/parsing-sessions',
      color: '#52c41a',
    },
  ];

  return (
    <div>
      {/* Welcome section */}
      <div style={{ marginBottom: 32 }}>
        <Title level={2}>안녕하세요, {user?.name || '사용자'}님!</Title>
        <Paragraph type="secondary">
          지출 추적 시스템에 오신 것을 환영합니다. 아래에서 빠르게 원하는 기능으로
          이동할 수 있습니다.
        </Paragraph>
      </div>

      {/* Summary statistics (placeholder for future implementation) */}
      <Row gutter={[16, 16]} style={{ marginBottom: 32 }}>
        <Col xs={24} sm={12} lg={6}>
          <StatCard
            title="이번 달 지출"
            value="0"
            suffix="원"
            icon={<DollarOutlined />}
            variant="default"
          />
        </Col>
        <Col xs={24} sm={12} lg={6}>
          <StatCard
            title="총 거래 건수"
            value="0"
            suffix="건"
            icon={<UnorderedListOutlined />}
            variant="success"
          />
        </Col>
        <Col xs={24} sm={12} lg={6}>
          <StatCard
            title="파싱 세션"
            value="0"
            suffix="개"
            icon={<FileTextOutlined />}
            variant="warning"
          />
        </Col>
        <Col xs={24} sm={12} lg={6}>
          <StatCard
            title="최근 업데이트"
            value="-"
            icon={<ClockCircleOutlined />}
            variant="default"
          />
        </Col>
      </Row>

      {/* Quick links */}
      <Title level={4} style={{ marginBottom: 16 }}>
        빠른 링크
      </Title>
      <Row gutter={[16, 16]}>
        {quickLinks.map((link) => (
          <Col xs={24} sm={12} lg={8} key={link.path}>
            <Card
              hoverable
              onClick={() => navigate(link.path)}
              style={{
                borderRadius: 8,
                borderLeft: `4px solid ${link.color}`,
              }}
            >
              <div style={{ display: 'flex', alignItems: 'center', gap: 16 }}>
                <div style={{ color: link.color }}>{link.icon}</div>
                <div>
                  <Title level={5} style={{ marginBottom: 4 }}>
                    {link.title}
                  </Title>
                  <Paragraph
                    type="secondary"
                    style={{ marginBottom: 0, fontSize: 13 }}
                  >
                    {link.description}
                  </Paragraph>
                </div>
              </div>
            </Card>
          </Col>
        ))}
      </Row>

      {/* Placeholder message */}
      <div
        style={{
          marginTop: 48,
          padding: 24,
          background: '#f5f5f5',
          borderRadius: 8,
          textAlign: 'center',
        }}
      >
        <Paragraph type="secondary">
          더 많은 통계와 차트는 추후 구현될 예정입니다.
        </Paragraph>
      </div>
    </div>
  );
};

export default Dashboard;
