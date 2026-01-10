import React from 'react';
import { Card, Row, Col, Select, Input } from 'antd';
import type { CategoryAPIResponse, InstitutionAPIResponse } from '../../api/services';

const { Search } = Input;
const { Option } = Select;

export interface FilterValues {
  year?: number;
  month?: number;
  category_id?: number;
  institution_id?: number;
  search?: string;
}

interface FilterPanelProps {
  filters: FilterValues;
  onChange: (filters: FilterValues) => void;
  categories: CategoryAPIResponse[];
  institutions: InstitutionAPIResponse[];
  loading?: boolean;
}

/**
 * Filter panel for transaction filtering
 * Provides year, month, category, institution, and search filters
 */
const FilterPanel: React.FC<FilterPanelProps> = ({
  filters,
  onChange,
  categories,
  institutions,
  loading = false,
}) => {
  // Generate year options (2020-2030)
  const yearOptions = Array.from({ length: 11 }, (_, i) => 2020 + i);

  // Month options (1-12)
  const monthOptions = [
    { value: 1, label: '1월' },
    { value: 2, label: '2월' },
    { value: 3, label: '3월' },
    { value: 4, label: '4월' },
    { value: 5, label: '5월' },
    { value: 6, label: '6월' },
    { value: 7, label: '7월' },
    { value: 8, label: '8월' },
    { value: 9, label: '9월' },
    { value: 10, label: '10월' },
    { value: 11, label: '11월' },
    { value: 12, label: '12월' },
  ];

  const handleFilterChange = (key: keyof FilterValues, value: any) => {
    onChange({
      ...filters,
      [key]: value === undefined ? undefined : value,
    });
  };

  return (
    <Card style={{ marginBottom: 24 }}>
      <Row gutter={[16, 16]}>
        <Col xs={24} sm={12} md={6} lg={4}>
          <div style={{ marginBottom: 8, fontWeight: 500 }}>연도</div>
          <Select
            style={{ width: '100%' }}
            placeholder="연도 선택"
            value={filters.year}
            onChange={(value) => handleFilterChange('year', value)}
            allowClear
            disabled={loading}
          >
            {yearOptions.map((year) => (
              <Option key={year} value={year}>
                {year}년
              </Option>
            ))}
          </Select>
        </Col>

        <Col xs={24} sm={12} md={6} lg={4}>
          <div style={{ marginBottom: 8, fontWeight: 500 }}>월</div>
          <Select
            style={{ width: '100%' }}
            placeholder="전체"
            value={filters.month}
            onChange={(value) => handleFilterChange('month', value)}
            allowClear
            disabled={loading}
          >
            {monthOptions.map((month) => (
              <Option key={month.value} value={month.value}>
                {month.label}
              </Option>
            ))}
          </Select>
        </Col>

        <Col xs={24} sm={12} md={6} lg={5}>
          <div style={{ marginBottom: 8, fontWeight: 500 }}>카테고리</div>
          <Select
            style={{ width: '100%' }}
            placeholder="전체"
            value={filters.category_id}
            onChange={(value) => handleFilterChange('category_id', value)}
            allowClear
            disabled={loading}
            showSearch
            filterOption={(input, option) =>
              String(option?.children || '')
                .toLowerCase()
                .includes(input.toLowerCase())
            }
          >
            {categories.map((category) => (
              <Option key={category.id} value={category.id}>
                {category.name}
              </Option>
            ))}
          </Select>
        </Col>

        <Col xs={24} sm={12} md={6} lg={5}>
          <div style={{ marginBottom: 8, fontWeight: 500 }}>금융기관</div>
          <Select
            style={{ width: '100%' }}
            placeholder="전체"
            value={filters.institution_id}
            onChange={(value) => handleFilterChange('institution_id', value)}
            allowClear
            disabled={loading}
            showSearch
            filterOption={(input, option) =>
              String(option?.children || '')
                .toLowerCase()
                .includes(input.toLowerCase())
            }
          >
            {institutions.map((institution) => (
              <Option key={institution.id} value={institution.id}>
                {institution.display_name}
              </Option>
            ))}
          </Select>
        </Col>

        <Col xs={24} sm={24} md={24} lg={6}>
          <div style={{ marginBottom: 8, fontWeight: 500 }}>거래처 검색</div>
          <Search
            placeholder="거래처명 입력"
            value={filters.search}
            onChange={(e) => handleFilterChange('search', e.target.value)}
            onSearch={(value) => handleFilterChange('search', value)}
            allowClear
            disabled={loading}
          />
        </Col>
      </Row>
    </Card>
  );
};

export default FilterPanel;
