import React, { useState, useEffect } from 'react';
import { Typography, Pagination, Spin, Alert } from 'antd';
import { parsingApi } from '../api/parsing';
import SessionCard from '../components/parsing/SessionCard';
import SessionDetailModal from '../components/parsing/SessionDetailModal';
import DuplicateConfirmationModal from '../components/parsing/DuplicateConfirmationModal';
import EmptyState from '../components/common/EmptyState';
import type { ParsingSession } from '../types';

const { Title } = Typography;

/**
 * Parsing Sessions Page
 * Displays a paginated list of file parsing sessions with detailed view modal
 */
const ParsingSessions: React.FC = () => {
  const [sessions, setSessions] = useState<ParsingSession[]>([]);
  const [loading, setLoading] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const [currentPage, setCurrentPage] = useState(1);
  const [total, setTotal] = useState(0);
  const [pageSize] = useState(20);

  // Modal state
  const [modalVisible, setModalVisible] = useState(false);
  const [selectedSessionId, setSelectedSessionId] = useState<number | null>(null);

  // Duplicate confirmation modal state
  const [confirmationModalVisible, setConfirmationModalVisible] = useState(false);
  const [confirmationSessionId, setConfirmationSessionId] = useState<number | null>(null);

  useEffect(() => {
    fetchSessions();
  }, [currentPage]);

  const fetchSessions = async () => {
    setLoading(true);
    setError(null);

    try {
      const response = await parsingApi.getSessions(currentPage, pageSize);
      setSessions(response.sessions);
      setTotal(response.total);
    } catch (err: any) {
      console.error('Failed to fetch parsing sessions:', err);
      setError(err.response?.data?.detail || '파싱 세션 목록을 불러오는데 실패했습니다');
      setSessions([]);
      setTotal(0);
    } finally {
      setLoading(false);
    }
  };

  const handlePageChange = (page: number) => {
    setCurrentPage(page);
  };

  const handleOpenDetail = (sessionId: number) => {
    setSelectedSessionId(sessionId);
    setModalVisible(true);
  };

  const handleCloseModal = () => {
    setModalVisible(false);
    setSelectedSessionId(null);
  };

  const handleOpenConfirmation = (sessionId: number) => {
    setConfirmationSessionId(sessionId);
    setConfirmationModalVisible(true);
  };

  const handleCloseConfirmation = () => {
    setConfirmationModalVisible(false);
    setConfirmationSessionId(null);
  };

  const handleConfirmationComplete = () => {
    setConfirmationModalVisible(false);
    setConfirmationSessionId(null);
    fetchSessions(); // Refresh session list
  };

  return (
    <div style={{ maxWidth: 1200, margin: '0 auto', padding: '24px' }}>
      <Title level={2}>파싱 세션 현황</Title>

      {error && (
        <Alert
          message="오류"
          description={error}
          type="error"
          showIcon
          closable
          onClose={() => setError(null)}
          style={{ marginBottom: 16 }}
        />
      )}

      {loading ? (
        <div style={{ textAlign: 'center', padding: '60px 0' }}>
          <Spin size="large" tip="파싱 세션 목록을 불러오는 중..." />
        </div>
      ) : sessions.length === 0 ? (
        <EmptyState message="아직 파싱 이력이 없습니다" />
      ) : (
        <>
          {/* Session List */}
          <div style={{ marginBottom: 24 }}>
            {sessions.map((session) => (
              <SessionCard
                key={session.id}
                session={session}
                onDetail={() => handleOpenDetail(session.id)}
                onReviewDuplicates={
                  session.status === 'pending_confirmation'
                    ? () => handleOpenConfirmation(session.id)
                    : undefined
                }
              />
            ))}
          </div>

          {/* Pagination */}
          {total > pageSize && (
            <div style={{ display: 'flex', justifyContent: 'center' }}>
              <Pagination
                current={currentPage}
                total={total}
                pageSize={pageSize}
                onChange={handlePageChange}
                showSizeChanger={false}
                showTotal={(total) => `전체 ${total}개`}
              />
            </div>
          )}
        </>
      )}

      {/* Detail Modal */}
      <SessionDetailModal
        visible={modalVisible}
        sessionId={selectedSessionId}
        onClose={handleCloseModal}
      />

      {/* Duplicate Confirmation Modal */}
      {confirmationSessionId && (
        <DuplicateConfirmationModal
          sessionId={confirmationSessionId}
          visible={confirmationModalVisible}
          onClose={handleCloseConfirmation}
          onComplete={handleConfirmationComplete}
        />
      )}
    </div>
  );
};

export default ParsingSessions;
