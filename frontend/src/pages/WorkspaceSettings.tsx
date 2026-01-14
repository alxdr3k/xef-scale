import React, { useState, useEffect } from 'react';
import {
  Typography,
  Tabs,
  Card,
  Form,
  Input,
  Button,
  Table,
  Select,
  Modal,
  message,
  Space,
  Tag,
  Popconfirm,
  Alert,
  Divider,
} from 'antd';
import type { TableColumnsType } from 'antd';
import {
  WarningOutlined,
  UserOutlined,
  TeamOutlined,
  DeleteOutlined,
  LogoutOutlined,
} from '@ant-design/icons';
import { useNavigate } from 'react-router-dom';
import { useWorkspace } from '../contexts/WorkspaceContext';
import { useAuth } from '../contexts/AuthContext';
import {
  updateWorkspace,
  getWorkspaceMembers,
  updateMemberRole,
  removeMember,
  leaveWorkspace,
  deleteWorkspace,
} from '../api/workspaces';
import type { WorkspaceMember, WorkspaceRole } from '../types';

const { Title, Text, Paragraph } = Typography;
const { TextArea } = Input;

const WorkspaceSettings: React.FC = () => {
  const navigate = useNavigate();
  const { currentWorkspace, refreshWorkspaces } = useWorkspace();
  const { user } = useAuth();
  const [form] = Form.useForm();

  // State
  const [loading, setLoading] = useState(false);
  const [members, setMembers] = useState<WorkspaceMember[]>([]);
  const [loadingMembers, setLoadingMembers] = useState(false);
  const [updatingMemberId, setUpdatingMemberId] = useState<number | null>(null);
  const [deleteConfirmText, setDeleteConfirmText] = useState('');
  const [isDeleteModalVisible, setIsDeleteModalVisible] = useState(false);

  // Load workspace members
  const loadMembers = async () => {
    if (!currentWorkspace) return;

    setLoadingMembers(true);
    try {
      const fetchedMembers = await getWorkspaceMembers(currentWorkspace.id);
      setMembers(fetchedMembers);
    } catch (error: any) {
      message.error('멤버 목록을 불러오는데 실패했습니다');
      console.error('Failed to load members:', error);
    } finally {
      setLoadingMembers(false);
    }
  };

  useEffect(() => {
    if (currentWorkspace) {
      // Set form initial values
      form.setFieldsValue({
        name: currentWorkspace.name,
        description: currentWorkspace.description || '',
      });

      // Load members
      loadMembers();
    }
  }, [currentWorkspace]);

  // Permission checks
  const canEdit = currentWorkspace?.role === 'OWNER' || currentWorkspace?.role === 'CO_OWNER';
  const isOwner = currentWorkspace?.role === 'OWNER';
  const canManageMembers = canEdit;
  const currentUserId = user ? parseInt(user.id) : null;

  // Check if user can modify a specific member's role
  const canModifyMember = (member: WorkspaceMember): boolean => {
    if (!currentUserId || !canManageMembers) return false;
    if (member.user_id === currentUserId) return false; // Cannot modify self

    if (isOwner) return true; // OWNER can modify anyone

    // CO_OWNER can only modify MEMBER_WRITE and MEMBER_READ
    if (currentWorkspace?.role === 'CO_OWNER') {
      return member.role === 'MEMBER_WRITE' || member.role === 'MEMBER_READ';
    }

    return false;
  };

  // Check if user can remove a specific member
  const canRemoveMember = (member: WorkspaceMember): boolean => {
    if (!currentUserId || !canManageMembers) return false;

    if (isOwner) {
      // OWNER cannot remove themselves if they're the last OWNER
      if (member.user_id === currentUserId) {
        const ownerCount = members.filter((m) => m.role === 'OWNER').length;
        return ownerCount > 1;
      }
      return true;
    }

    // CO_OWNER can only remove MEMBER_WRITE and MEMBER_READ
    if (currentWorkspace?.role === 'CO_OWNER') {
      return member.role === 'MEMBER_WRITE' || member.role === 'MEMBER_READ';
    }

    return false;
  };

  // Handle workspace info update
  const handleUpdateWorkspace = async (values: any) => {
    if (!currentWorkspace) return;

    setLoading(true);
    try {
      await updateWorkspace(currentWorkspace.id, {
        name: values.name,
        description: values.description,
      });
      message.success('워크스페이스 정보가 업데이트되었습니다');
      await refreshWorkspaces();
    } catch (error: any) {
      message.error('업데이트에 실패했습니다');
      console.error('Failed to update workspace:', error);
    } finally {
      setLoading(false);
    }
  };

  // Handle member role update
  const handleRoleUpdate = async (userId: number, newRole: WorkspaceRole) => {
    if (!currentWorkspace) return;

    setUpdatingMemberId(userId);
    try {
      await updateMemberRole(currentWorkspace.id, userId, newRole);
      message.success('멤버 역할이 업데이트되었습니다');
      await loadMembers();
    } catch (error: any) {
      const errorMessage = error.response?.data?.detail || '역할 업데이트에 실패했습니다';
      message.error(errorMessage);
      console.error('Failed to update member role:', error);
    } finally {
      setUpdatingMemberId(null);
    }
  };

  // Handle member removal
  const handleRemoveMember = async (userId: number, memberName: string) => {
    if (!currentWorkspace) return;

    try {
      await removeMember(currentWorkspace.id, userId);
      message.success(`${memberName}님이 제거되었습니다`);
      await loadMembers();
    } catch (error: any) {
      const errorMessage = error.response?.data?.detail || '멤버 제거에 실패했습니다';
      message.error(errorMessage);
      console.error('Failed to remove member:', error);
    }
  };

  // Handle leave workspace
  const handleLeaveWorkspace = async () => {
    if (!currentWorkspace || !currentUserId) return;

    try {
      await leaveWorkspace(currentWorkspace.id, currentUserId);
      message.success('워크스페이스에서 나갔습니다');
      await refreshWorkspaces();
      navigate('/dashboard');
    } catch (error: any) {
      const errorMessage = error.response?.data?.detail || '워크스페이스 나가기에 실패했습니다';
      message.error(errorMessage);
      console.error('Failed to leave workspace:', error);
    }
  };

  // Handle delete workspace
  const handleDeleteWorkspace = async () => {
    if (!currentWorkspace) return;
    if (deleteConfirmText !== 'DELETE') {
      message.error('DELETE를 정확히 입력해주세요');
      return;
    }

    try {
      await deleteWorkspace(currentWorkspace.id);
      message.success('워크스페이스가 삭제되었습니다');
      await refreshWorkspaces();
      navigate('/dashboard');
      setIsDeleteModalVisible(false);
    } catch (error: any) {
      const errorMessage = error.response?.data?.detail || '워크스페이스 삭제에 실패했습니다';
      message.error(errorMessage);
      console.error('Failed to delete workspace:', error);
    }
  };

  // Role display helpers
  const getRoleColor = (role: WorkspaceRole): string => {
    switch (role) {
      case 'OWNER':
        return 'red';
      case 'CO_OWNER':
        return 'orange';
      case 'MEMBER_WRITE':
        return 'blue';
      case 'MEMBER_READ':
        return 'default';
      default:
        return 'default';
    }
  };

  const getRoleLabel = (role: WorkspaceRole): string => {
    switch (role) {
      case 'OWNER':
        return '소유자';
      case 'CO_OWNER':
        return '공동 소유자';
      case 'MEMBER_WRITE':
        return '편집 권한';
      case 'MEMBER_READ':
        return '읽기 전용';
      default:
        return role;
    }
  };

  // Table columns for members
  const memberColumns: TableColumnsType<WorkspaceMember> = [
    {
      title: '이름',
      dataIndex: 'name',
      key: 'name',
      render: (name: string, record: WorkspaceMember) => (
        <Space>
          <UserOutlined />
          <span>
            {name}
            {record.user_id === currentUserId && (
              <Tag color="blue" style={{ marginLeft: 8 }}>
                나
              </Tag>
            )}
          </span>
        </Space>
      ),
    },
    {
      title: '이메일',
      dataIndex: 'email',
      key: 'email',
    },
    {
      title: '역할',
      dataIndex: 'role',
      key: 'role',
      render: (role: WorkspaceRole, record: WorkspaceMember) => {
        if (canModifyMember(record)) {
          return (
            <Select
              value={role}
              onChange={(newRole) => handleRoleUpdate(record.user_id, newRole as WorkspaceRole)}
              loading={updatingMemberId === record.user_id}
              disabled={updatingMemberId === record.user_id}
              style={{ width: 140 }}
            >
              <Select.Option value="OWNER">소유자</Select.Option>
              <Select.Option value="CO_OWNER">공동 소유자</Select.Option>
              <Select.Option value="MEMBER_WRITE">편집 권한</Select.Option>
              <Select.Option value="MEMBER_READ">읽기 전용</Select.Option>
            </Select>
          );
        }
        return <Tag color={getRoleColor(role)}>{getRoleLabel(role)}</Tag>;
      },
    },
    {
      title: '가입일',
      dataIndex: 'joined_at',
      key: 'joined_at',
      render: (date: string) => new Date(date).toLocaleDateString('ko-KR'),
    },
    {
      title: '작업',
      key: 'action',
      render: (_: any, record: WorkspaceMember) => {
        if (canRemoveMember(record)) {
          const isSelf = record.user_id === currentUserId;
          return (
            <Popconfirm
              title={isSelf ? '워크스페이스에서 나가시겠습니까?' : `${record.name}님을 제거하시겠습니까?`}
              description={
                isSelf
                  ? '이 워크스페이스의 모든 접근 권한을 잃게 됩니다.'
                  : '이 작업은 되돌릴 수 없습니다.'
              }
              onConfirm={() => handleRemoveMember(record.user_id, record.name)}
              okText="확인"
              cancelText="취소"
            >
              <Button type="link" danger icon={isSelf ? <LogoutOutlined /> : <DeleteOutlined />}>
                {isSelf ? '나가기' : '제거'}
              </Button>
            </Popconfirm>
          );
        }
        return null;
      },
    },
  ];

  if (!currentWorkspace) {
    return (
      <div>
        <Title level={2}>워크스페이스 설정</Title>
        <Alert message="워크스페이스를 선택해주세요" type="warning" />
      </div>
    );
  }

  // Tab items
  const tabItems = [
    {
      key: 'info',
      label: (
        <span>
          <UserOutlined />
          워크스페이스 정보
        </span>
      ),
      children: (
        <Card>
          <Form form={form} layout="vertical" onFinish={handleUpdateWorkspace}>
            <Form.Item
              label="워크스페이스 이름"
              name="name"
              rules={[
                { required: true, message: '이름을 입력해주세요' },
                { max: 100, message: '최대 100자까지 입력 가능합니다' },
              ]}
            >
              <Input placeholder="우리 팀의 지출 관리" disabled={!canEdit} />
            </Form.Item>

            <Form.Item
              label="설명"
              name="description"
              rules={[{ max: 500, message: '최대 500자까지 입력 가능합니다' }]}
            >
              <TextArea
                rows={4}
                placeholder="워크스페이스에 대한 설명을 입력하세요"
                disabled={!canEdit}
              />
            </Form.Item>

            <Form.Item label="화폐">
              <Input value={currentWorkspace.currency} disabled />
            </Form.Item>

            <Form.Item label="시간대">
              <Input value={currentWorkspace.timezone} disabled />
            </Form.Item>

            {canEdit && (
              <Form.Item>
                <Button type="primary" htmlType="submit" loading={loading}>
                  저장
                </Button>
              </Form.Item>
            )}

            {!canEdit && (
              <Alert
                message="읽기 전용"
                description="워크스페이스 정보를 수정하려면 소유자 또는 공동 소유자 권한이 필요합니다."
                type="info"
              />
            )}
          </Form>
        </Card>
      ),
    },
    {
      key: 'members',
      label: (
        <span>
          <TeamOutlined />
          멤버 관리 <Tag color="blue">{members.length}</Tag>
        </span>
      ),
      children: (
        <Card>
          {!canManageMembers && (
            <Alert
              message="읽기 전용"
              description="멤버를 관리하려면 공동 소유자 이상의 권한이 필요합니다."
              type="info"
              style={{ marginBottom: 16 }}
            />
          )}

          {canManageMembers && currentWorkspace.role === 'CO_OWNER' && (
            <Alert
              message="제한된 권한"
              description="공동 소유자는 일반 멤버(편집 권한, 읽기 전용)만 관리할 수 있습니다. 소유자 및 다른 공동 소유자는 관리할 수 없습니다."
              type="warning"
              style={{ marginBottom: 16 }}
            />
          )}

          <Table
            columns={memberColumns}
            dataSource={members}
            loading={loadingMembers}
            rowKey="user_id"
            pagination={false}
          />
        </Card>
      ),
    },
    {
      key: 'invitations',
      label: '초대 링크',
      children: (
        <Card>
          <Alert
            message="구현 예정"
            description="초대 링크 관리는 다음 단계에서 구현됩니다 (Phase 7.2)"
            type="info"
          />
        </Card>
      ),
    },
    {
      key: 'danger',
      label: (
        <span style={{ color: '#ff4d4f' }}>
          <WarningOutlined />
          위험 영역
        </span>
      ),
      children: (
        <Card>
          <Space direction="vertical" style={{ width: '100%' }} size="large">
            {/* Leave Workspace Section */}
            {currentWorkspace.role !== 'OWNER' ||
            members.filter((m) => m.role === 'OWNER').length > 1 ? (
              <div>
                <Title level={4}>워크스페이스 나가기</Title>
                <Paragraph>
                  이 워크스페이스에서 나가면 모든 접근 권한을 잃게 됩니다. 다시 참여하려면 다른 멤버의
                  초대가 필요합니다.
                </Paragraph>
                <Popconfirm
                  title="정말 이 워크스페이스를 떠나시겠습니까?"
                  description="이 작업은 되돌릴 수 없습니다."
                  onConfirm={handleLeaveWorkspace}
                  okText="나가기"
                  cancelText="취소"
                  okButtonProps={{ danger: true }}
                >
                  <Button danger icon={<LogoutOutlined />}>
                    워크스페이스 나가기
                  </Button>
                </Popconfirm>
              </div>
            ) : (
              <Alert
                message="워크스페이스를 떠날 수 없습니다"
                description="당신은 이 워크스페이스의 유일한 소유자입니다. 워크스페이스를 떠나기 전에 다른 멤버를 소유자로 승격시켜주세요."
                type="warning"
              />
            )}

            <Divider />

            {/* Delete Workspace Section */}
            {isOwner ? (
              <div>
                <Title level={4} style={{ color: '#ff4d4f' }}>
                  워크스페이스 삭제
                </Title>
                <Alert
                  message="경고: 이 작업은 되돌릴 수 없습니다"
                  description="워크스페이스와 모든 거래 내역, 파싱 세션, 멤버 정보가 영구적으로 삭제됩니다."
                  type="error"
                  style={{ marginBottom: 16 }}
                />
                <Paragraph>워크스페이스를 영구적으로 삭제하려면 아래 버튼을 클릭하세요.</Paragraph>
                <Button danger icon={<DeleteOutlined />} onClick={() => setIsDeleteModalVisible(true)}>
                  워크스페이스 삭제
                </Button>

                <Modal
                  title={
                    <span style={{ color: '#ff4d4f' }}>
                      <WarningOutlined /> 워크스페이스 삭제 확인
                    </span>
                  }
                  open={isDeleteModalVisible}
                  onOk={handleDeleteWorkspace}
                  onCancel={() => {
                    setIsDeleteModalVisible(false);
                    setDeleteConfirmText('');
                  }}
                  okText="삭제"
                  cancelText="취소"
                  okButtonProps={{ danger: true, disabled: deleteConfirmText !== 'DELETE' }}
                >
                  <Alert
                    message="이 작업은 되돌릴 수 없습니다"
                    description="모든 데이터가 영구적으로 삭제됩니다."
                    type="error"
                    style={{ marginBottom: 16 }}
                  />
                  <Paragraph>
                    워크스페이스 <strong>{currentWorkspace.name}</strong>을(를) 삭제하려면 아래에{' '}
                    <strong>DELETE</strong>를 입력하세요.
                  </Paragraph>
                  <Input
                    placeholder="DELETE를 입력하세요"
                    value={deleteConfirmText}
                    onChange={(e) => setDeleteConfirmText(e.target.value)}
                  />
                </Modal>
              </div>
            ) : (
              <Alert
                message="워크스페이스를 삭제할 수 없습니다"
                description="워크스페이스를 삭제하려면 소유자 권한이 필요합니다."
                type="info"
              />
            )}
          </Space>
        </Card>
      ),
    },
  ];

  return (
    <div>
      <Title level={2}>워크스페이스 설정</Title>
      <Paragraph type="secondary">현재 워크스페이스: {currentWorkspace.name}</Paragraph>
      <Tabs defaultActiveKey="info" items={tabItems} />
    </div>
  );
};

export default WorkspaceSettings;
