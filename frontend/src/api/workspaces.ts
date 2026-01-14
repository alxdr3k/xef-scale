/**
 * Workspace API service
 * Handles fetching and managing workspaces
 */

import apiClient from './client';
import type {
  Workspace,
  WorkspaceListResponse,
  WorkspaceMember,
  WorkspaceMemberListResponse,
  WorkspaceUpdateRequest,
  MemberRoleUpdateRequest,
} from '../types';

/**
 * Get all workspaces for the current user
 * @returns List of workspaces with user's role and permissions
 */
export const getWorkspaces = async (): Promise<Workspace[]> => {
  const response = await apiClient.get<WorkspaceListResponse>('/api/workspaces');
  return response.data.data;
};

/**
 * Update workspace information
 * @param workspaceId - Workspace ID
 * @param data - Update data (name, description)
 * @returns Updated workspace
 */
export const updateWorkspace = async (
  workspaceId: number,
  data: WorkspaceUpdateRequest
): Promise<Workspace> => {
  const response = await apiClient.put<Workspace>(`/api/workspaces/${workspaceId}`, data);
  return response.data;
};

/**
 * Get all members of a workspace
 * @param workspaceId - Workspace ID
 * @returns List of workspace members
 */
export const getWorkspaceMembers = async (workspaceId: number): Promise<WorkspaceMember[]> => {
  const response = await apiClient.get<WorkspaceMemberListResponse>(
    `/api/workspaces/${workspaceId}/members`
  );
  return response.data.members;
};

/**
 * Update member role
 * @param workspaceId - Workspace ID
 * @param userId - User ID to update
 * @param role - New role
 * @returns Updated member information
 */
export const updateMemberRole = async (
  workspaceId: number,
  userId: number,
  role: string
): Promise<WorkspaceMember> => {
  const response = await apiClient.patch<WorkspaceMember>(
    `/api/workspaces/${workspaceId}/members/${userId}/role`,
    { role }
  );
  return response.data;
};

/**
 * Remove member from workspace
 * @param workspaceId - Workspace ID
 * @param userId - User ID to remove
 */
export const removeMember = async (workspaceId: number, userId: number): Promise<void> => {
  await apiClient.delete(`/api/workspaces/${workspaceId}/members/${userId}`);
};

/**
 * Leave workspace (remove yourself)
 * @param workspaceId - Workspace ID
 * @param userId - Current user ID
 */
export const leaveWorkspace = async (workspaceId: number, userId: number): Promise<void> => {
  await apiClient.delete(`/api/workspaces/${workspaceId}/members/${userId}`);
};

/**
 * Delete workspace (OWNER only)
 * @param workspaceId - Workspace ID
 */
export const deleteWorkspace = async (workspaceId: number): Promise<void> => {
  await apiClient.delete(`/api/workspaces/${workspaceId}`);
};
