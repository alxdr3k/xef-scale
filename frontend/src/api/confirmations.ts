import apiClient from './client';
import type { DuplicateConfirmation, ConfirmationAction, BulkConfirmationResponse } from '../types';

/**
 * API service for duplicate transaction confirmations
 */

export const confirmationsApi = {
  /**
   * Get all pending confirmations with optional status filter
   */
  async getAllPendingConfirmations(statusFilter: string = 'pending'): Promise<DuplicateConfirmation[]> {
    const response = await apiClient.get<DuplicateConfirmation[]>('/api/confirmations', {
      params: {
        status: statusFilter,
      },
    });
    return response.data;
  },

  /**
   * Get confirmations by parsing session ID
   */
  async getConfirmationsBySession(sessionId: number): Promise<DuplicateConfirmation[]> {
    const response = await apiClient.get<DuplicateConfirmation[]>(`/api/confirmations/session/${sessionId}`);
    return response.data;
  },

  /**
   * Apply single decision to a confirmation
   */
  async confirmDuplicate(
    confirmationId: number,
    action: ConfirmationAction
  ): Promise<DuplicateConfirmation> {
    const response = await apiClient.post<DuplicateConfirmation>(
      `/api/confirmations/${confirmationId}/confirm`,
      { action }
    );
    return response.data;
  },

  /**
   * Bulk confirm all pending confirmations in a session
   */
  async bulkConfirmSession(
    sessionId: number,
    action: ConfirmationAction
  ): Promise<BulkConfirmationResponse> {
    const response = await apiClient.post<BulkConfirmationResponse>(
      `/api/confirmations/session/${sessionId}/bulk-confirm`,
      { action }
    );
    return response.data;
  },
};
