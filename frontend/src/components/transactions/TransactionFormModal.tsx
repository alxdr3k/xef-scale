import React, { useState, useEffect } from 'react';
import {
  Modal,
  Form,
  Input,
  InputNumber,
  Select,
  DatePicker,
  Button,
  Space,
  Row,
  Col,
  Divider,
} from 'antd';
import { message } from '../../lib/antd-static';
import { DownOutlined, UpOutlined } from '@ant-design/icons';
import dayjs from 'dayjs';
import type {
  TransactionAPIResponse,
  CategoryAPIResponse,
  InstitutionAPIResponse,
} from '../../api/services';
import type { TransactionCreateRequest, TransactionUpdateRequest } from '../../types';
import { createTransaction, updateTransaction } from '../../api/services';
import { getErrorMessage } from '../../utils/error';

const { TextArea } = Input;

interface TransactionFormModalProps {
  visible: boolean;
  mode: 'create' | 'edit';
  transaction?: TransactionAPIResponse | null;
  categories: CategoryAPIResponse[];
  institutions: InstitutionAPIResponse[];
  onClose: () => void;
  onSuccess: () => void;
}

/**
 * Modal component for creating and editing transactions
 * Supports both create mode (empty form) and edit mode (pre-filled)
 */
const TransactionFormModal: React.FC<TransactionFormModalProps> = ({
  visible,
  mode,
  transaction,
  categories,
  institutions,
  onClose,
  onSuccess,
}) => {
  const [form] = Form.useForm();
  const [loading, setLoading] = useState(false);
  const [hasInstallments, setHasInstallments] = useState(false);

  useEffect(() => {
    if (visible) {
      if (mode === 'edit' && transaction) {
        // Parse date string to dayjs object
        const dateObj = dayjs(transaction.date, 'YYYY.MM.DD');

        // Set form values from transaction
        form.setFieldsValue({
          date: dateObj,
          amount: transaction.amount,
          merchant_name: transaction.merchant_name,
          category_id: transaction.category_id,
          institution_id: transaction.institution_id,
          installment_months: transaction.installment_months,
          installment_current: transaction.installment_current,
          original_amount: transaction.original_amount,
          notes: '', // Notes are not stored in current schema
        });

        // Show installment section if transaction has installments
        if (transaction.installment_months) {
          setHasInstallments(true);
        }
      } else if (mode === 'create') {
        // Initialize with default values for create mode
        form.setFieldsValue({
          date: dayjs(), // Today's date
          amount: undefined,
          merchant_name: '',
          category_id: undefined,
          institution_id: undefined,
          installment_months: undefined,
          installment_current: undefined,
          original_amount: undefined,
          notes: '',
        });
        setHasInstallments(false);
      }
    }
  }, [visible, mode, transaction, form]);

  const handleSubmit = async () => {
    try {
      const values = await form.validateFields();
      setLoading(true);

      // Convert dayjs date to YYYY.MM.DD format
      const formattedDate = values.date.format('YYYY.MM.DD');

      // Find category and institution names by ID
      const category = categories.find((c) => c.id === values.category_id);
      const institution = institutions.find((i) => i.id === values.institution_id);

      if (!category || !institution) {
        message.error('카테고리 또는 금융기관을 찾을 수 없습니다');
        return;
      }

      // Prepare request payload
      const basePayload = {
        date: formattedDate,
        category: category.name,
        merchant_name: values.merchant_name,
        amount: values.amount,
        institution: institution.name,
        notes: values.notes || null,
      };

      // Add installment fields if section is expanded
      const installmentFields = hasInstallments
        ? {
            installment_months: values.installment_months || null,
            installment_current: values.installment_current || null,
            original_amount: values.original_amount || null,
          }
        : {
            installment_months: null,
            installment_current: null,
            original_amount: null,
          };

      if (mode === 'create') {
        const payload: TransactionCreateRequest = {
          ...basePayload,
          ...installmentFields,
        };
        await createTransaction(payload);
        message.success('거래가 추가되었습니다');
      } else if (mode === 'edit' && transaction) {
        const payload: TransactionUpdateRequest = {
          ...basePayload,
          ...installmentFields,
        };
        await updateTransaction(transaction.id, payload);
        message.success('거래가 수정되었습니다');
      }

      // Reset form and close modal
      form.resetFields();
      setHasInstallments(false);
      onSuccess();
      onClose();
    } catch (error: any) {
      console.error('Failed to save transaction:', error);

      // Handle specific error codes
      if (error.response?.status === 403) {
        message.error('파일에서 가져온 거래는 수정할 수 없습니다');
      } else if (error.response?.status === 400) {
        const errorDetail = getErrorMessage(error, '');
        if (errorDetail.includes('duplicate') || errorDetail.includes('중복')) {
          message.error('동일한 거래가 이미 존재합니다');
        } else {
          message.error(errorDetail || '입력 값을 확인해주세요');
        }
      } else {
        const actionText = mode === 'create' ? '추가' : '수정';
        message.error(`거래 ${actionText}에 실패했습니다`);
      }
    } finally {
      setLoading(false);
    }
  };

  const handleCancel = () => {
    form.resetFields();
    setHasInstallments(false);
    onClose();
  };

  const toggleInstallments = () => {
    setHasInstallments(!hasInstallments);
    // Clear installment fields when collapsing
    if (hasInstallments) {
      form.setFieldsValue({
        installment_months: undefined,
        installment_current: undefined,
        original_amount: undefined,
      });
    }
  };

  return (
    <Modal
      title={mode === 'create' ? '거래 추가' : '거래 수정'}
      open={visible}
      onCancel={handleCancel}
      footer={null}
      width={600}
      centered
      destroyOnHidden
    >
      <Form
        form={form}
        layout="vertical"
        onFinish={handleSubmit}
        autoComplete="off"
      >
        <Row gutter={16}>
          {/* Date field */}
          <Col span={12}>
            <Form.Item
              label="날짜"
              name="date"
              rules={[{ required: true, message: '날짜를 입력해주세요' }]}
            >
              <DatePicker
                format="YYYY.MM.DD"
                style={{ width: '100%' }}
                placeholder="날짜 선택"
              />
            </Form.Item>
          </Col>

          {/* Amount field */}
          <Col span={12}>
            <Form.Item
              label="금액"
              name="amount"
              rules={[
                { required: true, message: '금액을 입력해주세요' },
                {
                  type: 'number',
                  min: 1,
                  message: '금액은 양수여야 합니다',
                },
              ]}
            >
              <InputNumber
                style={{ width: '100%' }}
                formatter={(value) =>
                  `₩ ${value}`.replace(/\B(?=(\d{3})+(?!\d))/g, ',')
                }
                parser={(value) => value!.replace(/₩\s?|(,*)/g, '') as any}
                placeholder="금액 입력"
              />
            </Form.Item>
          </Col>
        </Row>

        {/* Merchant name field */}
        <Form.Item
          label="거래처"
          name="merchant_name"
          rules={[
            { required: true, message: '거래처를 입력해주세요' },
            { min: 1, max: 200, message: '거래처는 1-200자 이내여야 합니다' },
          ]}
        >
          <Input placeholder="거래처 입력 (예: 스타벅스, 쿠팡)" maxLength={200} />
        </Form.Item>

        <Row gutter={16}>
          {/* Category field */}
          <Col span={12}>
            <Form.Item
              label="카테고리"
              name="category_id"
              rules={[{ required: true, message: '카테고리를 선택해주세요' }]}
            >
              <Select
                placeholder="카테고리 선택"
                showSearch
                optionFilterProp="children"
                filterOption={(input, option) =>
                  (option?.label ?? '').toLowerCase().includes(input.toLowerCase())
                }
                options={categories.map((cat) => ({
                  value: cat.id,
                  label: cat.name,
                }))}
              />
            </Form.Item>
          </Col>

          {/* Institution field */}
          <Col span={12}>
            <Form.Item
              label="금융기관"
              name="institution_id"
              rules={[{ required: true, message: '금융기관을 선택해주세요' }]}
            >
              <Select
                placeholder="금융기관 선택"
                showSearch
                optionFilterProp="children"
                filterOption={(input, option) =>
                  (option?.label ?? '').toLowerCase().includes(input.toLowerCase())
                }
                options={institutions.map((inst) => ({
                  value: inst.id,
                  label: inst.display_name,
                }))}
              />
            </Form.Item>
          </Col>
        </Row>

        {/* Installments toggle button */}
        <Button
          type="dashed"
          onClick={toggleInstallments}
          style={{ width: '100%', marginBottom: 16 }}
          icon={hasInstallments ? <UpOutlined /> : <DownOutlined />}
        >
          {hasInstallments ? '할부 정보 숨기기' : '할부 정보 추가'}
        </Button>

        {/* Installment fields (collapsible) */}
        {hasInstallments && (
          <div style={{ marginBottom: 16 }}>
            <Row gutter={16}>
              <Col span={8}>
                <Form.Item
                  label="할부 개월"
                  name="installment_months"
                  rules={[
                    {
                      type: 'number',
                      min: 1,
                      max: 60,
                      message: '1-60개월 이내',
                    },
                  ]}
                >
                  <InputNumber
                    style={{ width: '100%' }}
                    placeholder="개월"
                    min={1}
                    max={60}
                  />
                </Form.Item>
              </Col>

              <Col span={8}>
                <Form.Item
                  label="현재 회차"
                  name="installment_current"
                  rules={[
                    {
                      type: 'number',
                      min: 1,
                      message: '1 이상',
                    },
                    ({ getFieldValue }) => ({
                      validator(_, value) {
                        const months = getFieldValue('installment_months');
                        if (!value || !months || value <= months) {
                          return Promise.resolve();
                        }
                        return Promise.reject(
                          new Error('현재 회차는 할부 개월 이하여야 합니다')
                        );
                      },
                    }),
                  ]}
                >
                  <InputNumber
                    style={{ width: '100%' }}
                    placeholder="회차"
                    min={1}
                  />
                </Form.Item>
              </Col>

              <Col span={8}>
                <Form.Item
                  label="원금액"
                  name="original_amount"
                  rules={[
                    {
                      type: 'number',
                      min: 1,
                      message: '양수여야 합니다',
                    },
                  ]}
                >
                  <InputNumber
                    style={{ width: '100%' }}
                    formatter={(value) =>
                      `₩ ${value}`.replace(/\B(?=(\d{3})+(?!\d))/g, ',')
                    }
                    parser={(value) => value!.replace(/₩\s?|(,*)/g, '') as any}
                    placeholder="원금액"
                  />
                </Form.Item>
              </Col>
            </Row>
          </div>
        )}

        {/* Notes field */}
        <Form.Item
          label="메모"
          name="notes"
          rules={[{ max: 500, message: '메모는 500자 이내여야 합니다' }]}
        >
          <TextArea
            rows={3}
            placeholder="메모 입력 (선택사항)"
            maxLength={500}
            showCount
          />
        </Form.Item>

        <Divider />

        {/* Footer buttons */}
        <Space style={{ width: '100%', justifyContent: 'flex-end' }}>
          <Button onClick={handleCancel} disabled={loading}>
            취소
          </Button>
          <Button type="primary" htmlType="submit" loading={loading}>
            {mode === 'create' ? '추가' : '수정'}
          </Button>
        </Space>
      </Form>
    </Modal>
  );
};

export default TransactionFormModal;
