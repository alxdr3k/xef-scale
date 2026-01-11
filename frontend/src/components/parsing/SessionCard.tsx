import React from 'react';
import { Card, Badge, Button, Space, Typography } from 'antd';
import {
  CheckCircleOutlined,
  WarningOutlined,
  CloseCircleOutlined,
  FileTextOutlined,
  ExclamationCircleOutlined,
} from '@ant-design/icons';
import dayjs from 'dayjs';
import relativeTime from 'dayjs/plugin/relativeTime';
import 'dayjs/locale/ko';
import type { ParsingSession } from '../../types';
import { institutionColors } from '../../theme.config';

dayjs.extend(relativeTime);
dayjs.locale('ko');

const { Text } = Typography;

interface SessionCardProps {
  session: ParsingSession;
  onDetail: () => void;
  onReviewDuplicates?: () => void;
}

/**
 * Card component to display a single parsing session summary
 * Shows file info, institution, status, and processing statistics
 */
const SessionCard: React.FC<SessionCardProps> = ({ session, onDetail, onReviewDuplicates }) => {
  const getStatusIcon = () => {
    if (session.error_message) {
      return <CloseCircleOutlined style={{ color: '#f5222d', fontSize: 24 }} />;
    }
    if (session.status === 'pending_confirmation') {
      return <ExclamationCircleOutlined style={{ color: '#faad14', fontSize: 24 }} />;
    }
    if (session.rows_skipped > 0) {
      return <WarningOutlined style={{ color: '#faad14', fontSize: 24 }} />;
    }
    return <CheckCircleOutlined style={{ color: '#52c41a', fontSize: 24 }} />;
  };

  const getInstitutionColor = (institutionName: string | null): string => {
    if (!institutionName) return '#d9d9d9';
    return institutionColors[institutionName] || '#d9d9d9';
  };

  const getRelativeTime = (dateString: string): string => {
    return dayjs(dateString).fromNow();
  };

  const getSummaryText = (): string => {
    const parts: string[] = [];
    if (session.rows_saved > 0) {
      parts.push(`${session.rows_saved}건 저장`);
    }
    if (session.rows_skipped > 0) {
      parts.push(`${session.rows_skipped}건 스킵`);
    }
    if (session.rows_duplicate > 0) {
      parts.push(`${session.rows_duplicate}건 중복`);
    }
    return parts.length > 0 ? parts.join(', ') : '처리 내역 없음';
  };

  return (
    <Card
      hoverable
      style={{ marginBottom: 16 }}
      styles={{
        body: { padding: 16 },
      }}
    >
      <div style={{ display: 'flex', alignItems: 'center', gap: 16 }}>
        {/* Status Icon */}
        <div style={{ flexShrink: 0 }}>
          {getStatusIcon()}
        </div>

        {/* Main Content */}
        <div style={{ flex: 1, minWidth: 0 }}>
          <Space direction="vertical" size={4} style={{ width: '100%' }}>
            {/* File Name */}
            <div style={{ display: 'flex', alignItems: 'center', gap: 8 }}>
              <FileTextOutlined />
              <Text strong style={{ fontSize: 16 }}>
                {session.file_name || '알 수 없는 파일'}
              </Text>
            </div>

            {/* Institution Badge & Time */}
            <div style={{ display: 'flex', alignItems: 'center', gap: 12, flexWrap: 'wrap' }}>
              <Badge
                color={getInstitutionColor(session.institution_name)}
                text={session.institution_name || '알 수 없음'}
              />
              <Text type="secondary" style={{ fontSize: 13 }}>
                {getRelativeTime(session.started_at)}
              </Text>
            </div>

            {/* Summary Statistics */}
            <Text type="secondary" style={{ fontSize: 13 }}>
              {getSummaryText()}
            </Text>

            {/* Error Message */}
            {session.error_message && (
              <Text type="danger" style={{ fontSize: 12 }}>
                오류: {session.error_message}
              </Text>
            )}
          </Space>
        </div>

        {/* Action Buttons */}
        <div style={{ flexShrink: 0 }}>
          <Space>
            {session.status === 'pending_confirmation' && onReviewDuplicates && (
              <Button
                type="primary"
                icon={<ExclamationCircleOutlined />}
                onClick={onReviewDuplicates}
              >
                중복 확인
              </Button>
            )}
            <Button type="default" onClick={onDetail}>
              상세
            </Button>
          </Space>
        </div>
      </div>
    </Card>
  );
};

export default SessionCard;
