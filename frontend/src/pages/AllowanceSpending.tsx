import React, { useState, useEffect } from 'react';
import {
  Typography,
  Table,
  Tag,
  Button,
  Modal,
  Alert,
  Card,
  Row,
  Col,
  Statistic,
  Progress,
  Tooltip,
} from 'antd';
import {
  WalletOutlined,
  PieChartOutlined,
  LineChartOutlined,
  FileTextOutlined,
  ArrowUpOutlined,
  ArrowDownOutlined,
  UndoOutlined,
} from '@ant-design/icons';
import { message } from '../lib/antd-static';
import type { ColumnsType, TablePaginationConfig } from 'antd/es/table';
import type { SorterResult, FilterValue } from 'antd/es/table/interface';
import LoadingSkeleton from '../components/common/LoadingSkeleton';
import EmptyState from '../components/common/EmptyState';
import FilterPanel from '../components/transactions/FilterPanel';
import type { FilterValues } from '../components/transactions/FilterPanel';
import NotesCell from '../components/transactions/NotesCell';
import CategoryCell from '../components/transactions/CategoryCell';
import { useWorkspace } from '../contexts/WorkspaceContext';
import {
  fetchCategories,
  fetchInstitutions,
  updateTransactionNotes,
  updateTransactionCategory,
} from '../api/services';
import type {
  CategoryAPIResponse,
  InstitutionAPIResponse,
} from '../api/services';
import {
  getAllowances,
  getAllowanceSummary,
  unmarkAllowance,
} from '../api/allowances';
import type { AllowanceFilters } from '../api/allowances';
import type { AllowanceTransactionResponse, AllowanceSummary } from '../types';

const { Title, Text } = Typography;

/**
 * AllowanceSpending page component
 * Displays personal allowance spending with statistics and transaction list
 */
const AllowanceSpending: React.FC = () => {
  // Workspace context
  const { currentWorkspace, loading: workspaceLoading } = useWorkspace();

  // State management
  const [transactions, setTransactions] = useState<AllowanceTransactionResponse[]>([]);
  const [summary, setSummary] = useState<AllowanceSummary | null>(null);
  const [categories, setCategories] = useState<CategoryAPIResponse[]>([]);
  const [institutions, setInstitutions] = useState<InstitutionAPIResponse[]>([]);
  const [loading, setLoading] = useState(false);
  const [summaryLoading, setSummaryLoading] = useState(false);
  const [categoriesLoading, setCategoriesLoading] = useState(true);
  const [institutionsLoading, setInstitutionsLoading] = useState(true);
  const [pagination, setPagination] = useState({
    current: 1,
    pageSize: 50,
    total: 0,
    totalPages: 0,
    totalAmount: 0,
  });

  // Filter state - default to current year
  const currentYear = new Date().getFullYear();
  const [filters, setFilters] = useState<FilterValues>({
    year: currentYear,
  });

  // Sort state
  const [sort, setSort] = useState<'date_desc' | 'date_asc' | 'amount_desc' | 'amount_asc'>('date_desc');

  // Restore modal state
  const [restoreModalVisible, setRestoreModalVisible] = useState(false);
  const [restoreTransaction, setRestoreTransaction] = useState<AllowanceTransactionResponse | null>(null);
  const [restoreLoading, setRestoreLoading] = useState(false);

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

  // Load transactions and summary when filters or pagination changes
  useEffect(() => {
    if (currentWorkspace) {
      loadTransactions();
      loadSummary();
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
   * Load allowance transactions from API with current filters
   */
  const loadTransactions = async () => {
    if (!currentWorkspace) return;

    try {
      setLoading(true);
      const params: AllowanceFilters = {
        ...filters,
        page: pagination.current,
        limit: pagination.pageSize,
        sort,
      };

      const response = await getAllowances(currentWorkspace.id, params);
      setTransactions(response.data);
      setPagination((prev) => ({
        ...prev,
        total: response.total,
        totalPages: response.totalPages,
        totalAmount: response.total_amount || 0,
      }));
    } catch (error) {
      console.error('Failed to load allowance transactions:', error);
      message.error('용돈 내역을 불러오는데 실패했습니다.');
    } finally {
      setLoading(false);
    }
  };

  /**
   * Load summary statistics from API
   */
  const loadSummary = async () => {
    if (!currentWorkspace) return;

    try {
      setSummaryLoading(true);
      const data = await getAllowanceSummary(currentWorkspace.id);
      setSummary(data);
    } catch (error) {
      console.error('Failed to load allowance summary:', error);
      // Don't show error message for summary - non-critical
    } finally {
      setSummaryLoading(false);
    }
  };

  /**
   * Handle restore to shared spending button click
   */
  const handleRestoreClick = (transaction: AllowanceTransactionResponse) => {
    setRestoreTransaction(transaction);
    setRestoreModalVisible(true);
  };

  /**
   * Handle restore confirmation
   */
  const handleRestoreConfirm = async () => {
    if (!currentWorkspace || !restoreTransaction) return;

    try {
      setRestoreLoading(true);
      await unmarkAllowance(currentWorkspace.id, restoreTransaction.transaction_id);
      message.success('거래가 공유 지출로 복원되었습니다');
      setRestoreModalVisible(false);
      setRestoreTransaction(null);
      // Refresh list and summary
      loadTransactions();
      loadSummary();
    } catch (error: any) {
      console.error('Failed to restore transaction:', error);
      message.error(error.response?.data?.detail || '거래 복원에 실패했습니다');
    } finally {
      setRestoreLoading(false);
    }
  };

  /**
   * Handle restore modal cancel
   */
  const handleRestoreCancel = () => {
    setRestoreModalVisible(false);
    setRestoreTransaction(null);
  };

  /**
   * Handle notes update (convert to transaction_id for backend)
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
   * Handle category update (convert to transaction_id for backend)
   */
  const handleCategoryUpdate = async (transactionId: number, category: string) => {
    try {
      await updateTransactionCategory(transactionId, category);
      message.success('카테고리가 변경되었습니다');
      loadTransactions();
      loadSummary(); // Refresh summary as category changed
    } catch (error: any) {
      message.error(error.response?.data?.detail || '카테고리 변경에 실패했습니다');
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
    sorter: SorterResult<AllowanceTransactionResponse> | SorterResult<AllowanceTransactionResponse>[]
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
   * Format currency
   */
  const formatCurrency = (amount: number): string => {
    return `₩${amount.toLocaleString('ko-KR')}`;
  };

  /**
   * Render statistics cards
   */
  const renderStatistics = () => {
    if (summaryLoading || !summary) {
      return (
        <Card style={{ marginBottom: 16 }}>
          <LoadingSkeleton type="card" />
        </Card>
      );
    }

    const changePercent = summary.month_over_month_change;
    const isIncrease = changePercent > 0;
    const changeIcon = isIncrease ? <ArrowUpOutlined /> : <ArrowDownOutlined />;
    const changeColor = isIncrease ? '#cf1322' : '#3f8600';

    return (
      <Row gutter={[16, 16]} style={{ marginBottom: 16 }}>
        {/* Card 1: Current month spending */}
        <Col xs={24} sm={12} md={6}>
          <Card>
            <Statistic
              title="이번 달 용돈 지출"
              value={summary.current_month_total}
              formatter={(value) => formatCurrency(value as number)}
              prefix={<WalletOutlined style={{ color: '#1890ff' }} />}
            />
            {changePercent !== 0 && (
              <div style={{ marginTop: 8, fontSize: 14 }}>
                <span style={{ color: changeColor }}>
                  {changeIcon} {Math.abs(changePercent).toFixed(1)}%
                </span>
                <Text type="secondary" style={{ marginLeft: 4 }}>
                  지난달 대비
                </Text>
              </div>
            )}
          </Card>
        </Col>

        {/* Card 2: Category breakdown */}
        <Col xs={24} sm={12} md={6}>
          <Card>
            <div style={{ marginBottom: 16 }}>
              <PieChartOutlined style={{ fontSize: 24, color: '#52c41a', marginRight: 8 }} />
              <Text strong>카테고리별 지출</Text>
            </div>
            {summary.categories_breakdown.length > 0 ? (
              <div>
                {summary.categories_breakdown.slice(0, 3).map((cat, index) => (
                  <div key={index} style={{ marginBottom: 8 }}>
                    <div style={{ display: 'flex', justifyContent: 'space-between', marginBottom: 4 }}>
                      <Text>{cat.category}</Text>
                      <Text strong>{formatCurrency(cat.amount)}</Text>
                    </div>
                    <Progress
                      percent={cat.percentage}
                      size="small"
                      showInfo={false}
                      strokeColor="#52c41a"
                    />
                    <Text type="secondary" style={{ fontSize: 12 }}>
                      {cat.percentage.toFixed(1)}% ({cat.count}건)
                    </Text>
                  </div>
                ))}
              </div>
            ) : (
              <Text type="secondary">데이터 없음</Text>
            )}
          </Card>
        </Col>

        {/* Card 3: Monthly average */}
        <Col xs={24} sm={12} md={6}>
          <Card>
            <Statistic
              title="월별 평균 지출"
              value={summary.monthly_average}
              formatter={(value) => formatCurrency(value as number)}
              prefix={
                <LineChartOutlined
                  style={{
                    color: summary.average_trend === 'up' ? '#cf1322' : '#3f8600',
                  }}
                />
              }
            />
            <div style={{ marginTop: 8, fontSize: 14 }}>
              {summary.average_trend === 'up' && (
                <Text type="danger">
                  <ArrowUpOutlined /> 증가 추세
                </Text>
              )}
              {summary.average_trend === 'down' && (
                <Text type="success">
                  <ArrowDownOutlined /> 감소 추세
                </Text>
              )}
              {summary.average_trend === 'stable' && (
                <Text type="secondary">안정 추세</Text>
              )}
            </div>
          </Card>
        </Col>

        {/* Card 4: Total transaction count */}
        <Col xs={24} sm={12} md={6}>
          <Card>
            <Statistic
              title="이번 달 거래 건수"
              value={summary.total_count}
              suffix="건"
              prefix={<FileTextOutlined style={{ color: '#722ed1' }} />}
            />
          </Card>
        </Col>
      </Row>
    );
  };

  /**
   * Table columns definition
   */
  const columns: ColumnsType<AllowanceTransactionResponse> = [
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
      render: (_: string, record: AllowanceTransactionResponse) => {
        // Create a compatible object for CategoryCell
        const transactionForCell = {
          id: record.transaction_id,
          category: record.category,
          category_id: record.category_id,
        } as any;
        return (
          <CategoryCell
            transaction={transactionForCell}
            categories={categories}
            onUpdate={handleCategoryUpdate}
          />
        );
      },
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
      render: (_: string | null, record: AllowanceTransactionResponse) => {
        // Create a compatible object for NotesCell
        const transactionForCell = {
          id: record.transaction_id,
          notes: record.notes,
        } as any;
        return <NotesCell transaction={transactionForCell} onUpdate={handleNotesUpdate} />;
      },
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
          {formatCurrency(amount)}
        </span>
      ),
    },
    {
      title: '출처',
      dataIndex: 'institution',
      key: 'institution',
      width: 120,
      render: (institution: string) => <Tag color="blue">{institution}</Tag>,
      responsive: ['lg'],
    },
    {
      title: '작업',
      key: 'actions',
      width: 150,
      fixed: 'right',
      render: (_, record: AllowanceTransactionResponse) => {
        if (!canWrite) {
          return (
            <Tooltip title="편집 권한이 필요합니다">
              <Tag color="default">권한 없음</Tag>
            </Tooltip>
          );
        }

        return (
          <Tooltip title="이 거래를 공유 지출로 복원합니다">
            <Button
              type="link"
              size="small"
              icon={<UndoOutlined />}
              onClick={() => handleRestoreClick(record)}
            >
              복원
            </Button>
          </Tooltip>
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
      <div style={{ marginBottom: 16 }}>
        <Title level={2}>내 용돈 지출</Title>
        <Text type="secondary" style={{ fontSize: '16px' }}>
          나만 볼 수 있는 개인 지출 내역입니다
        </Text>
        <div style={{ color: '#8c8c8c', fontSize: '14px', marginTop: 4 }}>
          워크스페이스: {currentWorkspace.name}
        </div>
      </div>

      {/* Info alert */}
      <Alert
        message="개인 지출 내역"
        description="이 페이지의 거래는 다른 워크스페이스 멤버에게 보이지 않습니다."
        type="info"
        showIcon
        style={{ marginBottom: 16 }}
      />

      {/* Statistics Section */}
      {renderStatistics()}

      {/* Filter Panel */}
      <FilterPanel
        filters={filters}
        onChange={handleFilterChange}
        categories={categories}
        institutions={institutions}
        loading={loading || categoriesLoading || institutionsLoading}
      />

      {/* Transactions Table */}
      {loading ? (
        <LoadingSkeleton type="table" rows={5} />
      ) : transactions.length === 0 ? (
        <EmptyState message="아직 용돈으로 표시된 거래가 없습니다." />
      ) : (
        <Table
          columns={columns}
          dataSource={transactions}
          rowKey="allowance_id"
          pagination={{
            current: pagination.current,
            pageSize: pagination.pageSize,
            total: pagination.total,
            showSizeChanger: true,
            showTotal: (total, range) =>
              `${range[0]}-${range[1]} / 총 ${total}건`,
            pageSizeOptions: ['50', '100', '200'],
          }}
          onChange={handleTableChange}
          scroll={{ x: 'max-content' }}
          loading={loading}
        />
      )}

      {/* Restore Modal */}
      <Modal
        title="공유 지출로 복원"
        open={restoreModalVisible}
        onOk={handleRestoreConfirm}
        onCancel={handleRestoreCancel}
        okText="복원"
        cancelText="취소"
        confirmLoading={restoreLoading}
      >
        <div>
          <Alert
            message="주의"
            description="이 거래를 공유 지출로 복원하시겠습니까? 다른 멤버에게도 보이게 됩니다."
            type="warning"
            showIcon
            style={{ marginBottom: 16 }}
          />
          {restoreTransaction && (
            <div>
              <div><strong>거래처:</strong> {restoreTransaction.merchant_name}</div>
              <div><strong>금액:</strong> {formatCurrency(restoreTransaction.amount)}</div>
              <div><strong>날짜:</strong> {restoreTransaction.date}</div>
            </div>
          )}
        </div>
      </Modal>
    </div>
  );
};

export default AllowanceSpending;
