import React from 'react';
import { Typography } from 'antd';

const { Title } = Typography;

const Dashboard: React.FC = () => {
  return (
    <div>
      <Title level={2}>대시보드</Title>
      <p>대시보드 페이지 (구현 예정)</p>
    </div>
  );
};

export default Dashboard;
