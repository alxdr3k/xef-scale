import React, { useEffect, useState } from 'react';
import { Modal, Descriptions, Badge, Table, Collapse, Typography, Alert, Spin } from 'antd';
import type { ColumnsType } from 'antd/es/table';
import dayjs from 'dayjs';
import { parsingApi } from '../../api/parsing';
import type { ParsingSession, SkippedTransaction } from '../../types';
import { institutionColors } from '../../theme.config';

const { Text } = Typography;

interface SessionDetailModalProps {
  visible: boolean;
  sessionId: number | null;
  onClose: () => void;
}

/**
 * Modal component to display detailed information about a parsing session
 * including file info, processing results, and skipped transactions
 */
const SessionDetailModal: React.FC<SessionDetailModalProps> = ({
  visible,
  sessionId,
  onClose,
}) => {
  const [session, setSession] = useState<ParsingSession | null>(null);
  const [skippedTransactions, setSkippedTransactions] = useState<SkippedTransaction[]>([]);
  const [loading, setLoading] = useState(false);
  const [error, setError] = useState<string | null>(null);

  useEffect(() => {
    if (visible && sessionId) {
      fetchSessionDetail();
    }
  }, [visible, sessionId]);

  const fetchSessionDetail = async () => {
    if (!sessionId) return;

    setLoading(true);
    setError(null);

    try {
      // Fetch session detail and skipped transactions in parallel
      const [sessionData, skippedData] = await Promise.all([
        parsingApi.getSessionById(sessionId),
        parsingApi.getSkippedTransactions(sessionId),
      ]);

      setSession(sessionData);
      setSkippedTransactions(skippedData);
    } catch (err: any) {
      console.error('Failed to fetch session detail:', err);
      setError(err.response?.data?.detail || '세션 정보를 불러오는데 실패했습니다');
    } finally {
      setLoading(false);
    }
  };

  const handleClose = () => {
    setSession(null);
    setSkippedTransactions([]);
    setError(null);
    onClose();
  };

  const getValidationBadge = (status: string | null) => {
    if (!status) return <Badge status="default" text="검증 안됨" />;

    switch (status.toLowerCase()) {
      case 'pass':
      case 'success':
        return <Badge status="success" text="성공" />;
      case 'warning':
        return <Badge status="warning" text="경고" />;
      case 'fail':
      case 'error':
        return <Badge status="error" text="실패" />;
      default:
        return <Badge status="default" text={status} />;
    }
  };

  const getInstitutionColor = (institutionName: string | null): string => {
    if (!institutionName) return '#d9d9d9';
    return institutionColors[institutionName] || '#d9d9d9';
  };

  const skippedColumns: ColumnsType<SkippedTransaction> = [
    {
      title: '행 번호',
      dataIndex: 'row_number',
      key: 'row_number',
      width: 80,
    },
    {
      title: '날짜',
      dataIndex: 'transaction_date',
      key: 'transaction_date',
      width: 120,
      render: (date: string | null) => date || '-',
    },
    {
      title: '거래처명',
      dataIndex: 'merchant_name',
      key: 'merchant_name',
      ellipsis: true,
      render: (name: string | null) => name || '-',
    },
    {
      title: '금액',
      dataIndex: 'amount',
      key: 'amount',
      width: 120,
      align: 'right',
      render: (amount: number | null) =>
        amount !== null ? `${amount.toLocaleString()}원` : '-',
    },
    {
      title: '스킵 이유',
      dataIndex: 'skip_reason',
      key: 'skip_reason',
      width: 150,
      render: (reason: string) => {
        const reasonMap: Record<string, string> = {
          'zero_amount': '금액 0원',
          'invalid_date': '날짜 오류',
          'missing_merchant': '거래처명 없음',
          'parsing_error': '파싱 오류',
        };
        return reasonMap[reason] || reason;
      },
    },
    {
      title: '상세',
      dataIndex: 'skip_details',
      key: 'skip_details',
      ellipsis: true,
      render: (details: string | null) => details || '-',
    },
  ];

  return (
    <Modal
      title="파싱 세션 상세 정보"
      open={visible}
      onCancel={handleClose}
      footer={null}
      width={900}
      destroyOnClose
    >
      {loading ? (
        <div style={{ textAlign: 'center', padding: '40px 0' }}>
          <Spin size="large" />
        </div>
      ) : error ? (
        <Alert message="오류" description={error} type="error" showIcon />
      ) : session ? (
        <>
          <Descriptions bordered column={2} size="small">
            <Descriptions.Item label="파일명" span={2}>
              <Text strong>{session.file_name || '알 수 없음'}</Text>
            </Descriptions.Item>
            <Descriptions.Item label="금융기관">
              <Badge
                color={getInstitutionColor(session.institution_name)}
                text={session.institution_name || '알 수 없음'}
              />
            </Descriptions.Item>
            <Descriptions.Item label="파서 타입">
              {session.parser_type}
            </Descriptions.Item>
            <Descriptions.Item label="처리 시작">
              {dayjs(session.started_at).format('YYYY.MM.DD HH:mm:ss')}
            </Descriptions.Item>
            <Descriptions.Item label="처리 완료">
              {session.completed_at
                ? dayjs(session.completed_at).format('YYYY.MM.DD HH:mm:ss')
                : '진행 중'}
            </Descriptions.Item>
            <Descriptions.Item label="전체 행 수">
              {session.total_rows_in_file.toLocaleString()}건
            </Descriptions.Item>
            <Descriptions.Item label="저장된 행">
              <Text type="success">{session.rows_saved.toLocaleString()}건</Text>
            </Descriptions.Item>
            <Descriptions.Item label="스킵된 행">
              <Text type="warning">{session.rows_skipped.toLocaleString()}건</Text>
            </Descriptions.Item>
            <Descriptions.Item label="중복된 행">
              <Text type="secondary">{session.rows_duplicate.toLocaleString()}건</Text>
            </Descriptions.Item>
            <Descriptions.Item label="검증 상태">
              {getValidationBadge(session.validation_status)}
            </Descriptions.Item>
            <Descriptions.Item label="파일 상태">
              {session.status}
            </Descriptions.Item>
          </Descriptions>

          {session.validation_notes && (
            <Alert
              message="검증 참고사항"
              description={session.validation_notes}
              type="info"
              showIcon
              style={{ marginTop: 16 }}
            />
          )}

          {session.error_message && (
            <Alert
              message="오류 메시지"
              description={session.error_message}
              type="error"
              showIcon
              style={{ marginTop: 16 }}
            />
          )}

          {skippedTransactions.length > 0 && (
            <Collapse
              style={{ marginTop: 16 }}
              items={[
                {
                  key: '1',
                  label: `스킵된 거래 목록 (${skippedTransactions.length}건)`,
                  children: (
                    <Table
                      columns={skippedColumns}
                      dataSource={skippedTransactions}
                      rowKey="id"
                      size="small"
                      pagination={false}
                      scroll={{ y: 300 }}
                    />
                  ),
                },
              ]}
            />
          )}
        </>
      ) : null}
    </Modal>
  );
};

export default SessionDetailModal;
