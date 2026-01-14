import React from 'react';
import { Card, Typography, Empty } from 'antd';
import { WalletOutlined } from '@ant-design/icons';

const { Title, Paragraph } = Typography;

/**
 * Allowances Page (Placeholder)
 *
 * This is a placeholder component for the Allowances feature.
 * It will be fully implemented in Phase 9.
 *
 * Planned features:
 * - View allowance transaction history
 * - Filter by date range, sender, amount
 * - Create new allowance records
 * - Export allowance data
 */
const Allowances: React.FC = () => {
  return (
    <div>
      <Title level={2}>
        <WalletOutlined style={{ marginRight: 8 }} />
        용돈 내역
      </Title>
      <Paragraph>
        가족이나 친구로부터 받은 용돈을 기록하고 관리합니다.
      </Paragraph>

      <Card>
        <Empty
          image={Empty.PRESENTED_IMAGE_SIMPLE}
          description={
            <div>
              <Paragraph style={{ marginTop: 16 }}>
                용돈 관리 기능은 곧 제공될 예정입니다.
              </Paragraph>
              <Paragraph type="secondary">
                Phase 9에서 다음 기능이 추가됩니다:
              </Paragraph>
              <ul style={{ textAlign: 'left', display: 'inline-block' }}>
                <li>용돈 거래 내역 조회</li>
                <li>날짜, 보낸 사람, 금액별 필터링</li>
                <li>새 용돈 기록 생성</li>
                <li>용돈 데이터 내보내기</li>
              </ul>
            </div>
          }
        />
      </Card>
    </div>
  );
};

export default Allowances;
