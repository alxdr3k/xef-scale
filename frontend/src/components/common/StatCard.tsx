import React from 'react';
import { Card, Statistic, Row, Col } from 'antd';
import { ArrowUpOutlined, ArrowDownOutlined } from '@ant-design/icons';
import type { ReactNode } from 'react';

export type StatCardVariant = 'default' | 'success' | 'warning' | 'danger';

interface StatCardProps {
  title: string;
  value: number | string;
  prefix?: ReactNode;
  suffix?: string;
  icon?: ReactNode;
  trend?: number; // Percentage change, e.g., 12.5 for +12.5%
  variant?: StatCardVariant;
  loading?: boolean;
}

const variantColors: Record<StatCardVariant, string> = {
  default: '#2196F3',
  success: '#52c41a',
  warning: '#faad14',
  danger: '#f5222d',
};

/**
 * Dashboard statistics card component
 * Displays a key metric with optional icon and trend indicator
 */
const StatCard: React.FC<StatCardProps> = ({
  title,
  value,
  prefix,
  suffix,
  icon,
  trend,
  variant = 'default',
  loading = false,
}) => {
  const valueColor = variantColors[variant];

  const renderTrend = () => {
    if (trend === undefined || trend === null) return null;

    const isPositive = trend >= 0;
    const trendColor = isPositive ? '#52c41a' : '#f5222d';
    const TrendIcon = isPositive ? ArrowUpOutlined : ArrowDownOutlined;

    return (
      <span style={{ fontSize: 14, color: trendColor, marginLeft: 8 }}>
        <TrendIcon /> {Math.abs(trend).toFixed(1)}%
      </span>
    );
  };

  return (
    <Card
      bordered={false}
      loading={loading}
      style={{
        borderRadius: 8,
        boxShadow: '0 2px 8px rgba(0, 0, 0, 0.06)',
      }}
    >
      <Row gutter={16} align="middle">
        {icon && (
          <Col>
            <div
              style={{
                fontSize: 32,
                color: valueColor,
                display: 'flex',
                alignItems: 'center',
              }}
            >
              {icon}
            </div>
          </Col>
        )}
        <Col flex={1}>
          <Statistic
            title={
              <span>
                {title}
                {renderTrend()}
              </span>
            }
            value={value}
            prefix={prefix}
            suffix={suffix}
            valueStyle={{ color: valueColor, fontSize: 24, fontWeight: 600 }}
          />
        </Col>
      </Row>
    </Card>
  );
};

export default StatCard;
