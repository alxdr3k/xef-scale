import React from 'react';
import { Card, Row, Col, Statistic } from 'antd';

interface SummarySectionProps {
  totalAmount: number;
  totalCount: number;
}

/**
 * Summary section displaying total transactions and amount
 * Shows key metrics at the top of the transactions page
 */
const SummarySection: React.FC<SummarySectionProps> = ({
  totalAmount,
  totalCount,
}) => {
  // Format currency with Korean Won symbol
  const formatCurrency = (amount: number): string => {
    return `₩${amount.toLocaleString('ko-KR')}`;
  };

  return (
    <Card style={{ marginBottom: 16 }}>
      <Row gutter={16}>
        <Col xs={24} sm={12}>
          <Statistic
            title="총 거래 건수"
            value={totalCount}
            suffix="건"
          />
        </Col>
        <Col xs={24} sm={12}>
          <Statistic
            title="총 지출 금액"
            value={totalAmount}
            formatter={(value) => formatCurrency(value as number)}
          />
        </Col>
      </Row>
    </Card>
  );
};

export default SummarySection;
