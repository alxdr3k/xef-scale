import React, { useState } from 'react';
import { Modal, Input, Typography, Space } from 'antd';
import { EditOutlined } from '@ant-design/icons';
import type { TransactionAPIResponse } from '../../api/services';

const { TextArea } = Input;
const { Text } = Typography;

interface NotesCellProps {
  transaction: TransactionAPIResponse;
  onUpdate: (transactionId: number, notes: string | null) => Promise<void>;
}

/**
 * NotesCell component for displaying and editing transaction notes
 * Shows notes with ellipsis and edit icon
 * Opens modal for editing notes
 */
const NotesCell: React.FC<NotesCellProps> = ({ transaction, onUpdate }) => {
  const [isModalOpen, setIsModalOpen] = useState(false);
  const [editedNotes, setEditedNotes] = useState<string>(transaction.notes || '');
  const [saving, setSaving] = useState(false);

  const handleOpenModal = () => {
    setEditedNotes(transaction.notes || '');
    setIsModalOpen(true);
  };

  const handleCloseModal = () => {
    setIsModalOpen(false);
    setEditedNotes('');
  };

  const handleSave = async () => {
    try {
      setSaving(true);
      // Convert empty string to null
      const notesToSave = editedNotes.trim() === '' ? null : editedNotes;
      await onUpdate(transaction.id, notesToSave);
      setIsModalOpen(false);
    } catch (error) {
      // Error handled by parent component
    } finally {
      setSaving(false);
    }
  };

  return (
    <>
      <Space style={{ width: '100%', justifyContent: 'space-between' }}>
        <Text
          ellipsis
          style={{
            maxWidth: '150px',
            color: transaction.notes ? 'inherit' : '#999',
          }}
        >
          {transaction.notes || '메모 없음'}
        </Text>
        <EditOutlined
          style={{ cursor: 'pointer', color: '#1890ff' }}
          onClick={handleOpenModal}
        />
      </Space>

      <Modal
        title="메모 편집"
        open={isModalOpen}
        onOk={handleSave}
        onCancel={handleCloseModal}
        okText="저장"
        cancelText="취소"
        confirmLoading={saving}
        width={500}
      >
        <TextArea
          value={editedNotes}
          onChange={(e) => setEditedNotes(e.target.value)}
          placeholder="메모를 입력하세요..."
          rows={4}
          maxLength={500}
          showCount
        />
      </Modal>
    </>
  );
};

export default NotesCell;
