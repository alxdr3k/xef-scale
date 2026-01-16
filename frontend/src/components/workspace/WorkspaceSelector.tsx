import React from 'react';
import { Select, Badge, Spin, Space, Tag } from 'antd';
import { UserOutlined } from '@ant-design/icons';
import { useWorkspace } from '../../contexts/WorkspaceContext';
import type { WorkspaceRole } from '../../types';

const { Option } = Select;

/**
 * Role badge configuration for workspace roles
 */
const roleConfig: Record<WorkspaceRole, { color: string; label: string }> = {
  OWNER: { color: '#faad14', label: '소유자' },
  CO_OWNER: { color: '#1890ff', label: '공동소유자' },
  MEMBER_WRITE: { color: '#52c41a', label: '편집 가능' },
  MEMBER_READ: { color: '#8c8c8c', label: '읽기 전용' },
};

/**
 * WorkspaceSelector Component
 *
 * Dropdown component for switching between workspaces.
 * Displays workspace name, role badge, and member count.
 * Designed for placement in the Navbar/TopBar.
 */
const WorkspaceSelector: React.FC = () => {
  const { currentWorkspace, workspaces, loading, switchWorkspace } = useWorkspace();

  const handleChange = (workspaceId: number) => {
    switchWorkspace(workspaceId);
  };

  // Show loading state
  if (loading) {
    return (
      <div style={{ display: 'flex', alignItems: 'center', minWidth: 200 }}>
        <Spin size="small" />
        <span style={{ marginLeft: 8, color: '#8c8c8c' }}>워크스페이스 로딩 중...</span>
      </div>
    );
  }

  // Handle empty workspace list
  if (!workspaces || workspaces.length === 0) {
    return (
      <div style={{ padding: '8px 12px', color: '#8c8c8c', fontSize: 14 }}>
        사용 가능한 워크스페이스가 없습니다
      </div>
    );
  }

  return (
    <Select
      value={currentWorkspace?.id}
      onChange={handleChange}
      style={{ minWidth: 200 }}
      dropdownStyle={{ minWidth: 280 }}
      placeholder="워크스페이스 선택"
      size="middle"
    >
      {workspaces.map((workspace) => (
        <Option key={workspace.id} value={workspace.id}>
          <Space
            style={{
              display: 'flex',
              justifyContent: 'space-between',
              alignItems: 'center',
              width: '100%',
            }}
          >
            <div style={{ display: 'flex', alignItems: 'center', gap: 8, flex: 1 }}>
              <span
                style={{
                  fontWeight: workspace.id === currentWorkspace?.id ? 600 : 400,
                  flex: 1,
                  overflow: 'hidden',
                  textOverflow: 'ellipsis',
                  whiteSpace: 'nowrap',
                }}
              >
                {workspace.name}
              </span>
            </div>
            <Space size={4} style={{ flexShrink: 0 }}>
              <Tag
                color={roleConfig[workspace.role].color}
                style={{
                  margin: 0,
                  fontSize: 11,
                  padding: '0 6px',
                  lineHeight: '18px',
                }}
              >
                {roleConfig[workspace.role].label}
              </Tag>
              <Badge
                count={workspace.member_count}
                showZero
                style={{
                  backgroundColor: '#f0f0f0',
                  color: '#595959',
                  fontSize: 11,
                  minWidth: 18,
                  height: 18,
                  lineHeight: '18px',
                  padding: '0 4px',
                  boxShadow: 'none',
                }}
                overflowCount={99}
              >
                <UserOutlined style={{ fontSize: 12, color: '#8c8c8c' }} />
              </Badge>
            </Space>
          </Space>
        </Option>
      ))}
    </Select>
  );
};

export default WorkspaceSelector;
