/**
 * Allowance API service
 * Handles marking transactions as personal allowances
 */

import apiClient from './client';
import type { AllowanceTransactionResponse, AllowanceSummary, PaginatedResponse } from '../types';

/**
 * Allowance mark request payload
 */
export interface AllowanceMarkRequest {
  transaction_id: number;
  notes?: string | null;
}

/**
 * Allowance filters for fetching allowance transactions
 */
export interface AllowanceFilters {
  year?: number;
  month?: number;
  category_id?: number;
  institution_id?: number;
  page?: number;
  limit?: number;
  sort?: 'date_desc' | 'date_asc' | 'amount_desc' | 'amount_asc';
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

/**
 * Fetch paginated allowance transactions with filters
 * @param workspaceId - Workspace ID
 * @param filters - Filter parameters
 * @returns Paginated allowance transactions
 */
export const getAllowances = async (
  workspaceId: number,
  filters: AllowanceFilters = {}
): Promise<PaginatedResponse<AllowanceTransactionResponse>> => {
  const response = await apiClient.get<PaginatedResponse<AllowanceTransactionResponse>>(
    `/api/workspaces/${workspaceId}/allowances`,
    {
      params: {
        ...filters,
      },
    }
  );
  return response.data;
};

/**
 * Fetch allowance summary statistics
 * @param workspaceId - Workspace ID
 * @returns Summary statistics for allowances
 */
export const getAllowanceSummary = async (
  workspaceId: number
): Promise<AllowanceSummary> => {
  const response = await apiClient.get<AllowanceSummary>(
    `/api/workspaces/${workspaceId}/allowances/summary`
  );
  return response.data;
};
