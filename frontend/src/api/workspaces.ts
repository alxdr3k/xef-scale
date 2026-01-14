/**
 * Workspace API service
 * Handles fetching and managing workspaces
 */

import apiClient from './client';
import type { Workspace, WorkspaceListResponse } from '../types';

/**
 * Get all workspaces for the current user
 * @returns List of workspaces with user's role and permissions
 */
export const getWorkspaces = async (): Promise<Workspace[]> => {
  const response = await apiClient.get<WorkspaceListResponse>('/api/workspaces');
  return response.data.data;
};
