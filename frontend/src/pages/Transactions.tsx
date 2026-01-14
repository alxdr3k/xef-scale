import React, { useState, useEffect } from 'react';
import { Typography, Table, Tag, Button, Space, Modal, Input, Alert, Tooltip } from 'antd';
import { EditOutlined, DeleteOutlined, PlusOutlined, LockOutlined, EyeInvisibleOutlined } from '@ant-design/icons';
import { message, modal } from '../lib/antd-static';
import type { ColumnsType, TablePaginationConfig } from 'antd/es/table';
import type { SorterResult, FilterValue } from 'antd/es/table/interface';
import LoadingSkeleton from '../components/common/LoadingSkeleton';
import EmptyState from '../components/common/EmptyState';
import FilterPanel from '../components/transactions/FilterPanel';
import type { FilterValues } from '../components/transactions/FilterPanel';
import SummarySection from '../components/transactions/SummarySection';
import TransactionFormModal from '../components/transactions/TransactionFormModal';
import NotesCell from '../components/transactions/NotesCell';
import CategoryCell from '../components/transactions/CategoryCell';
import { useWorkspace } from '../contexts/WorkspaceContext';
import {
  fetchTransactions,
  fetchCategories,
  fetchInstitutions,
  deleteTransaction,
  updateTransactionNotes,
  updateTransactionCategory,
} from '../api/services';
import type {
  TransactionAPIResponse,
  CategoryAPIResponse,
  InstitutionAPIResponse,
  TransactionFilters,
} from '../api/services';
import { markAsAllowance } from '../api/allowances';

const { Title } = Typography;
const { TextArea } = Input;

/**
 * Transactions page component
 * Displays transaction list with filtering, sorting, and pagination
 */
const Transactions: React.FC = () => {
  // Workspace context
  const { currentWorkspace, loading: workspaceLoading } = useWorkspace();

  // State management
  const [transactions, setTransactions] = useState<TransactionAPIResponse[]>([]);
  const [categories, setCategories] = useState<CategoryAPIResponse[]>([]);
  const [institutions, setInstitutions] = useState<InstitutionAPIResponse[]>([]);
  const [loading, setLoading] = useState(false);
  const [categoriesLoading, setCategoriesLoading] = useState(true);
  const [institutionsLoading, setInstitutionsLoading] = useState(true);
  const [pagination, setPagination] = useState({
    current: 1,
    pageSize: 50,
    total: 0,
    totalPages: 0,
    totalAmount: 0,
  });

  // Modal state
  const [modalVisible, setModalVisible] = useState(false);
  const [modalMode, setModalMode] = useState<'create' | 'edit'>('create');
  const [selectedTransaction, setSelectedTransaction] = useState<TransactionAPIResponse | null>(null);

  // Allowance modal state
  const [allowanceModalVisible, setAllowanceModalVisible] = useState(false);
  const [allowanceTransaction, setAllowanceTransaction] = useState<TransactionAPIResponse | null>(null);
  const [allowanceNotes, setAllowanceNotes] = useState<string>('');
  const [allowanceLoading, setAllowanceLoading] = useState(false);

  // Filter state - default to current year
  const currentYear = new Date().getFullYear();
  const [filters, setFilters] = useState<FilterValues>({
    year: currentYear,
  });

  // Sort state
  const [sort, setSort] = useState<'date_desc' | 'date_asc' | 'amount_desc' | 'amount_asc'>('date_desc');

  // Permission checks
  const canWrite = currentWorkspace
    ? ['OWNER', 'CO_OWNER', 'MEMBER_WRITE'].includes(currentWorkspace.role)
    : false;

  // Load categories and institutions when workspace changes
  useEffect(() => {
    if (currentWorkspace) {
      loadCategories();
      loadInstitutions();
    }
  }, [currentWorkspace]);

  // Load transactions when filters or pagination changes
  useEffect(() => {
    if (currentWorkspace) {
      loadTransactions();
    }
  }, [currentWorkspace, filters, pagination.current, pagination.pageSize, sort]);

  /**
   * Load categories from API
   */
  const loadCategories = async () => {
    if (!currentWorkspace) return;

    try {
      setCategoriesLoading(true);
      const data = await fetchCategories(currentWorkspace.id);
      setCategories(data);
    } catch (error) {
      console.error('Failed to load categories:', error);
      message.error('카테고리 목록을 불러오는데 실패했습니다.');
    } finally {
      setCategoriesLoading(false);
    }
  };

  /**
   * Load institutions from API
   */
  const loadInstitutions = async () => {
    if (!currentWorkspace) return;

    try {
      setInstitutionsLoading(true);
      const data = await fetchInstitutions(currentWorkspace.id);
      setInstitutions(data);
    } catch (error) {
      console.error('Failed to load institutions:', error);
      message.error('금융기관 목록을 불러오는데 실패했습니다.');
    } finally {
      setInstitutionsLoading(false);
    }
  };

  /**
   * Load transactions from API with current filters
   */
  const loadTransactions = async () => {
    if (!currentWorkspace) return;

    try {
      setLoading(true);
      const params: TransactionFilters = {
        workspace_id: currentWorkspace.id,
        ...filters,
        page: pagination.current,
        limit: pagination.pageSize,
        sort,
      };

      const response = await fetchTransactions(params);
      setTransactions(response.data);
      setPagination((prev) => ({
        ...prev,
        total: response.total,
        totalPages: response.totalPages,
        totalAmount: response.total_amount || 0,
      }));
    } catch (error) {
      console.error('Failed to load transactions:', error);
      message.error('거래 내역을 불러오는데 실패했습니다.');
    } finally {
      setLoading(false);
    }
  };

  /**
   * Handle create transaction
   */
  const handleCreate = () => {
    setModalMode('create');
    setSelectedTransaction(null);
    setModalVisible(true);
  };

  /**
   * Handle edit transaction
   */
  const handleEdit = (transaction: TransactionAPIResponse) => {
    setModalMode('edit');
    setSelectedTransaction(transaction);
    setModalVisible(true);
  };

  /**
   * Handle delete transaction
   */
  const handleDelete = (transaction: TransactionAPIResponse) => {
    if (transaction.file_id !== null) {
      message.error('파일에서 가져온 거래는 삭제할 수 없습니다');
      return;
    }

    modal.confirm({
      title: '거래 삭제',
      content: `"${transaction.merchant_name}" 거래를 삭제하시겠습니까?`,
      okText: '삭제',
      okType: 'danger',
      cancelText: '취소',
      onOk: async () => {
        try {
          await deleteTransaction(transaction.id);
          message.success('거래가 삭제되었습니다');
          loadTransactions();
        } catch (error: any) {
          message.error(error.response?.data?.detail || '거래 삭제에 실패했습니다');
        }
      },
    });
  };

  /**
   * Handle notes update
   */
  const handleNotesUpdate = async (transactionId: number, notes: string | null) => {
    try {
      await updateTransactionNotes(transactionId, notes);
      message.success('메모가 저장되었습니다');
      loadTransactions();
    } catch (error: any) {
      message.error(error.response?.data?.detail || '메모 저장에 실패했습니다');
    }
  };

  /**
   * Handle category update
   */
  const handleCategoryUpdate = async (transactionId: number, category: string) => {
    try {
      await updateTransactionCategory(transactionId, category);
      message.success('카테고리가 변경되었습니다');
      loadTransactions();
    } catch (error: any) {
      message.error(error.response?.data?.detail || '카테고리 변경에 실패했습니다');
    }
  };

  /**
   * Handle modal close
   */
  const handleModalClose = () => {
    setModalVisible(false);
    setSelectedTransaction(null);
  };

  /**
   * Handle modal success
   */
  const handleModalSuccess = () => {
    loadTransactions();
  };

  /**
   * Handle mark as allowance button click
   */
  const handleMarkAsAllowance = (transaction: TransactionAPIResponse) => {
    setAllowanceTransaction(transaction);
    setAllowanceNotes('');
    setAllowanceModalVisible(true);
  };

  /**
   * Handle allowance modal confirm
   */
  const handleAllowanceConfirm = async () => {
    if (!currentWorkspace || !allowanceTransaction) return;

    try {
      setAllowanceLoading(true);
      await markAsAllowance(
        currentWorkspace.id,
        allowanceTransaction.id,
        allowanceNotes || null
      );
      message.success('거래가 용돈으로 표시되었습니다');
      setAllowanceModalVisible(false);
      setAllowanceTransaction(null);
      setAllowanceNotes('');
      // Refresh transactions list to remove the marked transaction
      loadTransactions();
    } catch (error: any) {
      console.error('Failed to mark as allowance:', error);
      message.error(error.response?.data?.detail || '용돈 표시에 실패했습니다');
    } finally {
      setAllowanceLoading(false);
    }
  };

  /**
   * Handle allowance modal cancel
   */
  const handleAllowanceCancel = () => {
    setAllowanceModalVisible(false);
    setAllowanceTransaction(null);
    setAllowanceNotes('');
  };

  /**
   * Handle filter changes
   */
  const handleFilterChange = (newFilters: FilterValues) => {
    setFilters(newFilters);
    // Reset to first page when filters change
    setPagination((prev) => ({
      ...prev,
      current: 1,
    }));
  };

  /**
   * Handle table changes (pagination, sorting)
   */
  const handleTableChange = (
    newPagination: TablePaginationConfig,
    _filters: Record<string, FilterValue | null>,
    sorter: SorterResult<TransactionAPIResponse> | SorterResult<TransactionAPIResponse>[]
  ) => {
    // Update pagination
    setPagination((prev) => ({
      ...prev,
      current: newPagination.current || 1,
      pageSize: newPagination.pageSize || 50,
    }));

    // Update sort if sorter is provided
    if (!Array.isArray(sorter) && sorter.field) {
      const field = sorter.field as string;
      const order = sorter.order;

      if (field === 'date') {
        setSort(order === 'ascend' ? 'date_asc' : 'date_desc');
      } else if (field === 'amount') {
        setSort(order === 'ascend' ? 'amount_asc' : 'amount_desc');
      }
    }
  };

  /**
   * Table columns definition
   */
  const columns: ColumnsType<TransactionAPIResponse> = [
    {
      title: '날짜',
      dataIndex: 'date',
      key: 'date',
      width: 120,
      sorter: true,
      defaultSortOrder: 'descend',
      render: (date: string) => date,
    },
    {
      title: '카테고리',
      dataIndex: 'category',
      key: 'category',
      width: 150,
      render: (_: string, record: TransactionAPIResponse) => (
        <CategoryCell
          transaction={record}
          categories={categories}
          onUpdate={handleCategoryUpdate}
        />
      ),
      responsive: ['md'],
    },
    {
      title: '거래처',
      dataIndex: 'merchant_name',
      key: 'merchant_name',
      ellipsis: true,
      render: (text: string) => text,
    },
    {
      title: '메모',
      dataIndex: 'notes',
      key: 'notes',
      width: 200,
      ellipsis: true,
      render: (_: string | null, record: TransactionAPIResponse) => (
        <NotesCell transaction={record} onUpdate={handleNotesUpdate} />
      ),
    },
    {
      title: '금액',
      dataIndex: 'amount',
      key: 'amount',
      width: 150,
      align: 'right',
      sorter: true,
      render: (amount: number) => (
        <span style={{ fontWeight: 600 }}>
          ₩{amount.toLocaleString('ko-KR')}
        </span>
      ),
    },
    {
      title: '출처',
      dataIndex: 'institution',
      key: 'institution',
      width: 120,
      render: (institution: string) => (
        <Tag color="blue">{institution}</Tag>
      ),
      responsive: ['lg'],
    },
    {
      title: '용돈',
      key: 'allowance',
      width: 120,
      align: 'center',
      render: (_, record: TransactionAPIResponse) => {
        if (!canWrite) {
          return null;
        }

        return (
          <Tooltip title="이 거래를 개인 용돈으로 표시합니다. 다른 멤버에게는 보이지 않습니다.">
            <Button
              type="link"
              size="small"
              icon={<EyeInvisibleOutlined />}
              onClick={() => handleMarkAsAllowance(record)}
            >
              용돈 표시
            </Button>
          </Tooltip>
        );
      },
      responsive: ['lg'],
    },
    {
      title: '작업',
      key: 'actions',
      width: 120,
      fixed: 'right',
      render: (_, record: TransactionAPIResponse) => {
        if (record.file_id !== null) {
          return (
            <Tag icon={<LockOutlined />} color="default">
              읽기 전용
            </Tag>
          );
        }

        if (!canWrite) {
          return (
            <Tooltip title="편집 권한이 필요합니다">
              <Tag color="default">권한 없음</Tag>
            </Tooltip>
          );
        }

        return (
          <Space size="small">
            <Button
              type="link"
              size="small"
              icon={<EditOutlined />}
              onClick={() => handleEdit(record)}
            >
              수정
            </Button>
            <Button
              type="link"
              size="small"
              danger
              icon={<DeleteOutlined />}
              onClick={() => handleDelete(record)}
            >
              삭제
            </Button>
          </Space>
        );
      },
    },
  ];

  // Loading state while workspace initializes
  if (workspaceLoading) {
    return <LoadingSkeleton type="table" rows={5} />;
  }

  // No workspace selected
  if (!currentWorkspace) {
    return <EmptyState message="워크스페이스를 선택해주세요." />;
  }

  return (
    <div>
      <div style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'center', marginBottom: 16 }}>
        <div>
          <Title level={2}>지출 내역</Title>
          <div style={{ color: '#8c8c8c', fontSize: '14px', marginTop: '-8px' }}>
            워크스페이스: {currentWorkspace.name}
          </div>
        </div>
        <Tooltip title={!canWrite ? '편집 권한이 필요합니다' : ''}>
          <Button
            type="primary"
            icon={<PlusOutlined />}
            onClick={handleCreate}
            size="large"
            disabled={!canWrite}
          >
            새 거래 추가
          </Button>
        </Tooltip>
      </div>

      {/* Permission alert for read-only users */}
      {!canWrite && (
        <Alert
          message="읽기 전용 권한"
          description="읽기 전용 권한입니다. 거래를 수정하거나 추가할 수 없습니다."
          type="info"
          showIcon
          style={{ marginBottom: 16 }}
        />
      )}

      {/* Filter Panel */}
      <FilterPanel
        filters={filters}
        onChange={handleFilterChange}
        categories={categories}
        institutions={institutions}
        loading={loading || categoriesLoading || institutionsLoading}
      />

      {/* Summary Section */}
      {!loading && transactions.length > 0 && (
        <SummarySection
          totalAmount={pagination.totalAmount}
          totalCount={pagination.total}
        />
      )}

      {/* Transactions Table */}
      {loading ? (
        <LoadingSkeleton type="table" rows={5} />
      ) : transactions.length === 0 ? (
        <EmptyState message="조회된 거래 내역이 없습니다." />
      ) : (
        <Table
          columns={columns}
          dataSource={transactions}
          rowKey="id"
          pagination={{
            current: pagination.current,
            pageSize: pagination.pageSize,
            total: pagination.total,
            showSizeChanger: true,
            showTotal: (total, range) =>
              `${range[0]}-${range[1]} / 총 ${total}건`,
            pageSizeOptions: ['10', '25', '50', '100'],
          }}
          onChange={handleTableChange}
          scroll={{ x: 'max-content' }}
          loading={loading}
        />
      )}

      {/* Transaction Form Modal */}
      <TransactionFormModal
        visible={modalVisible}
        mode={modalMode}
        transaction={selectedTransaction}
        categories={categories}
        institutions={institutions}
        onClose={handleModalClose}
        onSuccess={handleModalSuccess}
      />

      {/* Allowance Mark Modal */}
      <Modal
        title="용돈으로 표시"
        open={allowanceModalVisible}
        onOk={handleAllowanceConfirm}
        onCancel={handleAllowanceCancel}
        okText="확인"
        cancelText="취소"
        confirmLoading={allowanceLoading}
      >
        <div>
          <Alert
            message="주의"
            description="이 거래를 용돈으로 표시하시겠습니까? 다른 멤버에게는 이 거래가 보이지 않습니다."
            type="warning"
            showIcon
            style={{ marginBottom: 16 }}
          />
          {allowanceTransaction && (
            <div style={{ marginBottom: 16 }}>
              <div><strong>거래처:</strong> {allowanceTransaction.merchant_name}</div>
              <div><strong>금액:</strong> ₩{allowanceTransaction.amount.toLocaleString('ko-KR')}</div>
              <div><strong>날짜:</strong> {allowanceTransaction.date}</div>
            </div>
          )}
          <div>
            <div style={{ marginBottom: 8 }}>메모 (선택사항)</div>
            <TextArea
              rows={3}
              placeholder="용돈에 대한 메모를 입력하세요 (선택사항)"
              value={allowanceNotes}
              onChange={(e) => setAllowanceNotes(e.target.value)}
            />
          </div>
        </div>
      </Modal>
    </div>
  );
};

export default Transactions;
