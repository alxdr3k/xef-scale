import React, { useState, useEffect } from 'react';
import {
  Modal,
  Card,
  Button,
  Space,
  Badge,
  Divider,
  Typography,
  Spin,
  message,
  Row,
  Col,
} from 'antd';
import {
  CheckCircleOutlined,
  CloseCircleOutlined,
  ExclamationCircleOutlined,
} from '@ant-design/icons';
import { confirmationsApi } from '../../api/confirmations';
import type { DuplicateConfirmation, ConfirmationAction } from '../../types';

const { Text, Title } = Typography;

interface DuplicateConfirmationModalProps {
  sessionId: number;
  visible: boolean;
  onClose: () => void;
  onComplete: () => void;
}

/**
 * Modal component for reviewing and confirming duplicate transactions
 * Shows side-by-side comparison of new vs existing transactions
 */
const DuplicateConfirmationModal: React.FC<DuplicateConfirmationModalProps> = ({
  sessionId,
  visible,
  onClose,
  onComplete,
}) => {
  const [confirmations, setConfirmations] = useState<DuplicateConfirmation[]>([]);
  const [currentIndex, setCurrentIndex] = useState(0);
  const [loading, setLoading] = useState(false);
  const [processing, setProcessing] = useState(false);

  useEffect(() => {
    if (visible && sessionId) {
      fetchConfirmations();
    }
  }, [visible, sessionId]);

  const fetchConfirmations = async () => {
    setLoading(true);
    try {
      const data = await confirmationsApi.getConfirmationsBySession(sessionId);
      const pendingConfirmations = data.filter((c) => c.status === 'pending');
      setConfirmations(pendingConfirmations);
      setCurrentIndex(0);

      if (pendingConfirmations.length === 0) {
        message.info('모든 중복 확인이 완료되었습니다');
        onComplete();
      }
    } catch (error: any) {
      console.error('Failed to fetch confirmations:', error);
      message.error(error.response?.data?.detail || '중복 확인 목록을 불러오는데 실패했습니다');
    } finally {
      setLoading(false);
    }
  };

  const handleConfirm = async (action: ConfirmationAction) => {
    const currentConfirmation = confirmations[currentIndex];
    if (!currentConfirmation) return;

    setProcessing(true);
    try {
      await confirmationsApi.confirmDuplicate(currentConfirmation.id, action);

      const actionText = action === 'skip' ? '스킵' : action === 'insert' ? '추가' : '병합';
      message.success(`거래 ${actionText} 완료`);

      // Move to next confirmation or complete
      if (currentIndex + 1 < confirmations.length) {
        setCurrentIndex(currentIndex + 1);
      } else {
        message.success('모든 중복 확인이 완료되었습니다');
        onComplete();
      }
    } catch (error: any) {
      console.error('Failed to confirm duplicate:', error);
      message.error(error.response?.data?.detail || '확인 처리에 실패했습니다');
    } finally {
      setProcessing(false);
    }
  };

  const handleBulkAction = async (action: ConfirmationAction) => {
    Modal.confirm({
      title: '나머지 모두 일괄 처리',
      content: `나머지 ${confirmations.length - currentIndex}건을 모두 ${action === 'skip' ? '스킵' : '추가'}하시겠습니까?`,
      okText: '확인',
      cancelText: '취소',
      onOk: async () => {
        setProcessing(true);
        try {
          const response = await confirmationsApi.bulkConfirmSession(sessionId, action);
          message.success(`${response.processed_count}건 일괄 처리 완료`);
          onComplete();
        } catch (error: any) {
          console.error('Failed to bulk confirm:', error);
          message.error(error.response?.data?.detail || '일괄 처리에 실패했습니다');
        } finally {
          setProcessing(false);
        }
      },
    });
  };

  const getConfidenceColor = (score: number): string => {
    if (score >= 95) return '#52c41a'; // green
    if (score >= 80) return '#faad14'; // yellow
    return '#ff4d4f'; // red
  };

  const getConfidenceText = (score: number): string => {
    if (score === 100) return '완전 일치';
    if (score >= 95) return '높은 중복 가능성';
    if (score >= 80) return '중복 가능성 있음';
    return '유사한 거래';
  };

  const renderTransactionComparison = () => {
    if (confirmations.length === 0) return null;

    const current = confirmations[currentIndex];
    if (!current) return null;

    const { new_transaction, existing_transaction, confidence_score, match_fields } = current;

    const compareField = (field: keyof typeof new_transaction, label: string) => {
      const newValue = new_transaction[field];
      const existingValue = existing_transaction[field];
      const isMatch = match_fields.includes(field);

      return (
        <Row key={field} style={{ marginBottom: 12 }}>
          <Col span={6}>
            <Text strong>{label}:</Text>
          </Col>
          <Col span={8}>
            <Text>{String(newValue)}</Text>
          </Col>
          <Col span={8}>
            <Text>{String(existingValue)}</Text>
          </Col>
          <Col span={2} style={{ textAlign: 'center' }}>
            {isMatch ? (
              <CheckCircleOutlined style={{ color: '#52c41a' }} />
            ) : (
              <CloseCircleOutlined style={{ color: '#ff4d4f' }} />
            )}
          </Col>
        </Row>
      );
    };

    return (
      <Space direction="vertical" size="large" style={{ width: '100%' }}>
        {/* Header */}
        <div>
          <Title level={5}>
            거래 {currentIndex + 1} / {confirmations.length}
          </Title>
          <Badge
            color={getConfidenceColor(confidence_score)}
            text={`유사도: ${confidence_score}% - ${getConfidenceText(confidence_score)}`}
          />
        </div>

        {/* Comparison Table */}
        <Card>
          <Row style={{ marginBottom: 12 }}>
            <Col span={6}></Col>
            <Col span={8}>
              <Text strong type="secondary">새 거래 (파일)</Text>
            </Col>
            <Col span={8}>
              <Text strong type="secondary">기존 거래 (DB)</Text>
            </Col>
            <Col span={2} style={{ textAlign: 'center' }}>
              <Text strong type="secondary">일치</Text>
            </Col>
          </Row>
          <Divider style={{ margin: '12px 0' }} />
          {compareField('date', '날짜')}
          {compareField('item', '내역')}
          {compareField('amount', '금액')}
          {compareField('source', '지출처')}
          {compareField('category', '분류')}
        </Card>

        {/* Difference Summary */}
        {current.difference_summary && (
          <Card size="small">
            <Text type="secondary" style={{ fontSize: 12 }}>
              <ExclamationCircleOutlined style={{ marginRight: 4 }} />
              차이점: {current.difference_summary}
            </Text>
          </Card>
        )}

        {/* Individual Actions */}
        <Space style={{ width: '100%', justifyContent: 'center' }}>
          <Button
            size="large"
            onClick={() => handleConfirm('skip')}
            loading={processing}
            disabled={processing}
          >
            스킵 (중복으로 처리)
          </Button>
          <Button
            type="primary"
            size="large"
            onClick={() => handleConfirm('insert')}
            loading={processing}
            disabled={processing}
          >
            추가 (새 거래로 저장)
          </Button>
        </Space>

        {/* Bulk Actions */}
        {confirmations.length - currentIndex > 1 && (
          <>
            <Divider />
            <Space style={{ width: '100%', justifyContent: 'center' }}>
              <Button
                type="default"
                onClick={() => handleBulkAction('skip')}
                disabled={processing}
              >
                나머지 모두 스킵
              </Button>
              <Button
                type="default"
                onClick={() => handleBulkAction('insert')}
                disabled={processing}
              >
                나머지 모두 추가
              </Button>
            </Space>
          </>
        )}
      </Space>
    );
  };

  return (
    <Modal
      title="중복 거래 확인"
      open={visible}
      onCancel={onClose}
      footer={null}
      width={800}
      centered
      destroyOnClose
    >
      {loading ? (
        <div style={{ textAlign: 'center', padding: '60px 0' }}>
          <Spin size="large" tip="중복 확인 목록을 불러오는 중..." />
        </div>
      ) : confirmations.length === 0 ? (
        <div style={{ textAlign: 'center', padding: '40px 0' }}>
          <Text type="secondary">확인할 중복 거래가 없습니다</Text>
        </div>
      ) : (
        renderTransactionComparison()
      )}
    </Modal>
  );
};

export default DuplicateConfirmationModal;
