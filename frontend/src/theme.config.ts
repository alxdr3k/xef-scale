import type { ThemeConfig } from 'antd';

// Design tokens based on expense tracker requirements
export const theme: ThemeConfig = {
  token: {
    // Color palette
    colorPrimary: '#2196F3', // Primary blue
    colorSuccess: '#52c41a',
    colorWarning: '#faad14',
    colorError: '#f5222d',
    colorInfo: '#1890ff',

    // Typography
    fontFamily: '-apple-system, BlinkMacSystemFont, "Pretendard", "Segoe UI", "Roboto", "Helvetica Neue", Arial, sans-serif',
    fontSize: 14,
    fontSizeHeading1: 38,
    fontSizeHeading2: 30,
    fontSizeHeading3: 24,
    fontSizeHeading4: 20,
    fontSizeHeading5: 16,

    // Spacing
    borderRadius: 8,

    // Layout
    colorBgContainer: '#ffffff',
    colorBgLayout: '#f5f5f5',
  },
  components: {
    Layout: {
      headerBg: '#ffffff',
      headerHeight: 64,
      siderBg: '#001529',
    },
    Button: {
      primaryShadow: '0 2px 0 rgba(33, 150, 243, 0.1)',
    },
    Table: {
      headerBg: '#fafafa',
      headerColor: 'rgba(0, 0, 0, 0.88)',
    },
  },
};

// Category colors for expense categorization
export const categoryColors: Record<string, string> = {
  '식비': '#ff6b6b',
  '편의점/마트/잡화': '#4ecdc4',
  '교통/자동차': '#95e1d3',
  '주거/통신': '#f38181',
  '보험': '#aa96da',
  '기타': '#fcbad3',
};

// Financial institution colors
export const institutionColors: Record<string, string> = {
  '신한카드': '#0046ff',
  '하나카드': '#008485',
  '토스뱅크': '#0064ff',
  '토스페이': '#0064ff',
  '카카오뱅크': '#ffeb00',
  '카카오페이': '#ffeb00',
};
