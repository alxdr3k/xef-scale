/**
 * Allowance API service
 * Handles marking transactions as personal allowances
 */

import apiClient from './client';

/**
 * Allowance mark request payload
 */
export interface AllowanceMarkRequest {
  transaction_id: number;
  notes?: string | null;
}

/**
 * Allowance transaction response from backend
 */
export interface AllowanceTransactionResponse {
  allowance_id: number;
  transaction_id: number;
  user_id: number;
  workspace_id: number;
  notes: string | null;
  marked_at: string;
  // Transaction details
  date: string;
  category: string;
  merchant_name: string;
  amount: number;
  institution: string;
  category_id: number;
  institution_id: number;
}

/**
 * Mark a transaction as personal allowance
 * @param workspaceId - Workspace ID
 * @param transactionId - Transaction ID to mark
 * @param notes - Optional notes about the allowance
 * @returns Allowance transaction details
 */
export const markAsAllowance = async (
  workspaceId: number,
  transactionId: number,
  notes?: string | null
): Promise<AllowanceTransactionResponse> => {
  const response = await apiClient.post<AllowanceTransactionResponse>(
    `/api/workspaces/${workspaceId}/allowances`,
    {
      transaction_id: transactionId,
      notes,
    }
  );
  return response.data;
};

/**
 * Unmark a transaction as allowance (make it visible to workspace again)
 * @param workspaceId - Workspace ID
 * @param transactionId - Transaction ID to unmark
 */
export const unmarkAllowance = async (
  workspaceId: number,
  transactionId: number
): Promise<void> => {
  await apiClient.delete(`/api/workspaces/${workspaceId}/allowances/${transactionId}`);
};
