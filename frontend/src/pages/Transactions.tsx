import React, { useState, useEffect } from 'react';
import { Typography, Table, Tag, Button, Space } from 'antd';
import { EditOutlined, DeleteOutlined, PlusOutlined, LockOutlined } from '@ant-design/icons';
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

const { Title } = Typography;

/**
 * Transactions page component
 * Displays transaction list with filtering, sorting, and pagination
 */
const Transactions: React.FC = () => {
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

  // Filter state - default to current year
  const currentYear = new Date().getFullYear();
  const [filters, setFilters] = useState<FilterValues>({
    year: currentYear,
  });

  // Sort state
  const [sort, setSort] = useState<'date_desc' | 'date_asc' | 'amount_desc' | 'amount_asc'>('date_desc');

  // Load categories and institutions on mount
  useEffect(() => {
    loadCategories();
    loadInstitutions();
  }, []);

  // Load transactions when filters or pagination changes
  useEffect(() => {
    loadTransactions();
  }, [filters, pagination.current, pagination.pageSize, sort]);

  /**
   * Load categories from API
   */
  const loadCategories = async () => {
    try {
      setCategoriesLoading(true);
      const data = await fetchCategories();
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
    try {
      setInstitutionsLoading(true);
      const data = await fetchInstitutions();
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
    try {
      setLoading(true);
      const params: TransactionFilters = {
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
      render: (institution: string, record: TransactionAPIResponse) => (
        <Space orientation="vertical" size={0}>
          <Tag color="blue">{institution}</Tag>
          {record.file_id !== null && (
            <Tag color="default" style={{ fontSize: 11 }}>
              파일
            </Tag>
          )}
        </Space>
      ),
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

  return (
    <div>
      <div style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'center', marginBottom: 16 }}>
        <Title level={2}>지출 내역</Title>
        <Button
          type="primary"
          icon={<PlusOutlined />}
          onClick={handleCreate}
          size="large"
        >
          새 거래 추가
        </Button>
      </div>

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
    </div>
  );
};

export default Transactions;
