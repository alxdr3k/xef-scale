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
  WorkspaceInvitation,
  WorkspaceInvitationListResponse,
  InvitationCreateRequest,
  InvitationPreview,
  InvitationAcceptResponse,
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

/**
 * Create invitation link for workspace
 * @param workspaceId - Workspace ID
 * @param data - Invitation creation request (role, expires_in_days, max_uses)
 * @returns Created invitation
 */
export const createInvitation = async (
  workspaceId: number,
  data: InvitationCreateRequest
): Promise<WorkspaceInvitation> => {
  const response = await apiClient.post<WorkspaceInvitation>(
    `/api/workspaces/${workspaceId}/invitations`,
    data
  );
  return response.data;
};

/**
 * Get all invitations for a workspace
 * @param workspaceId - Workspace ID
 * @returns List of invitations
 */
export const getInvitations = async (workspaceId: number): Promise<WorkspaceInvitation[]> => {
  const response = await apiClient.get<WorkspaceInvitationListResponse>(
    `/api/workspaces/${workspaceId}/invitations`
  );
  return response.data.invitations;
};

/**
 * Revoke invitation link
 * @param workspaceId - Workspace ID
 * @param invitationId - Invitation ID to revoke
 */
export const revokeInvitation = async (workspaceId: number, invitationId: number): Promise<void> => {
  await apiClient.delete(`/api/workspaces/${workspaceId}/invitations/${invitationId}`);
};

/**
 * Get invitation details by token (for preview before joining)
 * @param token - Invitation token from URL
 * @returns Invitation details including workspace info
 */
export const getInvitationByToken = async (token: string): Promise<InvitationPreview> => {
  // Since backend doesn't have a dedicated preview endpoint, we'll construct
  // the preview from the invitation data. The validation happens on accept.
  // For now, we'll need to attempt accept and handle errors gracefully.
  // This function will be used in conjunction with accept_invitation.

  // Note: Backend doesn't expose a GET /invitations/{token} endpoint for preview.
  // The accept endpoint validates everything, so we'll need to show invitation
  // based on the token validation response during accept.
  throw new Error('getInvitationByToken not implemented - use acceptInvitation directly');
};

/**
 * Accept invitation and join workspace
 * @param token - Invitation token from URL
 * @returns Workspace info and assigned role
 */
export const acceptInvitation = async (token: string): Promise<InvitationAcceptResponse> => {
  const response = await apiClient.post<InvitationAcceptResponse>(
    `/api/invitations/${token}/accept`
  );
  return response.data;
};
