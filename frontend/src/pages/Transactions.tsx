import React, { useState, useEffect } from 'react';
import { Typography, Table, Tag, message } from 'antd';
import type { ColumnsType, TablePaginationConfig } from 'antd/es/table';
import type { SorterResult, FilterValue } from 'antd/es/table/interface';
import LoadingSkeleton from '../components/common/LoadingSkeleton';
import EmptyState from '../components/common/EmptyState';
import FilterPanel from '../components/transactions/FilterPanel';
import type { FilterValues } from '../components/transactions/FilterPanel';
import SummarySection from '../components/transactions/SummarySection';
import {
  fetchTransactions,
  fetchCategories,
  fetchInstitutions,
} from '../api/services';
import type {
  TransactionAPIResponse,
  CategoryAPIResponse,
  InstitutionAPIResponse,
  TransactionFilters,
} from '../api/services';
import { categoryColors } from '../theme.config';

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
  });

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
      }));
    } catch (error) {
      console.error('Failed to load transactions:', error);
      message.error('거래 내역을 불러오는데 실패했습니다.');
    } finally {
      setLoading(false);
    }
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
   * Get category color for display
   */
  const getCategoryColor = (categoryName: string): string => {
    return categoryColors[categoryName] || categoryColors['기타'];
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
      render: (category: string) => (
        <span>
          <span
            style={{
              display: 'inline-block',
              width: 8,
              height: 8,
              borderRadius: '50%',
              backgroundColor: getCategoryColor(category),
              marginRight: 8,
            }}
          />
          {category}
        </span>
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
  ];

  /**
   * Calculate total amount from current transactions
   */
  const calculateTotalAmount = (): number => {
    return transactions.reduce((sum, t) => sum + t.amount, 0);
  };

  return (
    <div>
      <Title level={2}>지출 내역</Title>

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
          totalAmount={calculateTotalAmount()}
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
    </div>
  );
};

export default Transactions;
