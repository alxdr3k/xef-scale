/**
 * API service functions for making requests to the backend
 * Provides typed interfaces for all API endpoints
 */

import apiClient from './client';
import type {
  PaginatedResponse,
  TransactionCreateRequest,
  TransactionUpdateRequest,
  TransactionDeleteResponse
} from '../types';

/**
 * Transaction API query parameters
 */
export interface TransactionFilters {
  year?: number;
  month?: number;
  category_id?: number;
  institution_id?: number;
  search?: string;
  sort?: 'date_desc' | 'date_asc' | 'amount_desc' | 'amount_asc';
  page?: number;
  limit?: number;
}

/**
 * Transaction response matching backend schema
 */
export interface TransactionAPIResponse {
  id: number;
  date: string; // yyyy.mm.dd format
  category: string;
  merchant_name: string;
  amount: number;
  institution: string;
  installment_months?: number | null;
  installment_current?: number | null;
  original_amount?: number | null;
  transaction_year: number;
  transaction_month: number;
  category_id: number;
  institution_id: number;
  file_id?: number | null;
  row_number_in_file?: number | null;
  created_at: string;
  notes?: string | null;
}

/**
 * Category response from backend
 */
export interface CategoryAPIResponse {
  id: number;
  name: string;
  created_at: string;
  updated_at: string;
}

/**
 * Institution response from backend
 */
export interface InstitutionAPIResponse {
  id: number;
  name: string;
  institution_type: string;
  display_name: string;
  is_active: boolean;
  created_at: string;
  updated_at: string;
}

/**
 * Monthly summary response from backend
 */
export interface MonthlySummaryResponse {
  year: number;
  month: number;
  total_amount: number;
  transaction_count: number;
  by_category: Array<{
    category_id: number;
    category_name: string;
    amount: number;
    count: number;
  }>;
}

/**
 * Fetch paginated transactions with filters
 */
export const fetchTransactions = async (
  filters: TransactionFilters = {}
): Promise<PaginatedResponse<TransactionAPIResponse>> => {
  const response = await apiClient.get<PaginatedResponse<TransactionAPIResponse>>(
    '/api/transactions',
    {
      params: {
        year: filters.year,
        month: filters.month,
        category_id: filters.category_id,
        institution_id: filters.institution_id,
        search: filters.search,
        sort: filters.sort || 'date_desc',
        page: filters.page || 1,
        limit: filters.limit || 50,
      },
    }
  );
  return response.data;
};

/**
 * Fetch single transaction by ID
 */
export const fetchTransactionById = async (
  id: number
): Promise<TransactionAPIResponse> => {
  const response = await apiClient.get<TransactionAPIResponse>(
    `/api/transactions/${id}`
  );
  return response.data;
};

/**
 * Create a new manual transaction
 */
export const createTransaction = async (
  request: TransactionCreateRequest
): Promise<TransactionAPIResponse> => {
  const response = await apiClient.post<TransactionAPIResponse>(
    '/api/transactions',
    request
  );
  return response.data;
};

/**
 * Update an existing manual transaction
 */
export const updateTransaction = async (
  id: number,
  request: TransactionUpdateRequest
): Promise<TransactionAPIResponse> => {
  const response = await apiClient.put<TransactionAPIResponse>(
    `/api/transactions/${id}`,
    request
  );
  return response.data;
};

/**
 * Delete a manual transaction (soft delete)
 */
export const deleteTransaction = async (
  id: number
): Promise<TransactionDeleteResponse> => {
  const response = await apiClient.delete<TransactionDeleteResponse>(
    `/api/transactions/${id}`
  );
  return response.data;
};

/**
 * Fetch monthly summary
 */
export const fetchMonthlySummary = async (
  year: number,
  month: number
): Promise<MonthlySummaryResponse> => {
  const response = await apiClient.get<MonthlySummaryResponse>(
    '/api/transactions/summary/monthly',
    {
      params: { year, month },
    }
  );
  return response.data;
};

/**
 * Fetch all categories
 */
export const fetchCategories = async (): Promise<CategoryAPIResponse[]> => {
  const response = await apiClient.get<CategoryAPIResponse[]>('/api/categories');
  return response.data;
};

/**
 * Fetch all institutions
 */
export const fetchInstitutions = async (): Promise<InstitutionAPIResponse[]> => {
  const response = await apiClient.get<InstitutionAPIResponse[]>('/api/institutions');
  return response.data;
};

/**
 * Update transaction notes
 */
export const updateTransactionNotes = async (
  id: number,
  notes: string | null
): Promise<TransactionAPIResponse> => {
  const response = await apiClient.patch<TransactionAPIResponse>(
    `/api/transactions/${id}/notes`,
    { notes }
  );
  return response.data;
};

/**
 * Update transaction category
 */
export const updateTransactionCategory = async (
  id: number,
  category: string
): Promise<TransactionAPIResponse> => {
  const response = await apiClient.patch<TransactionAPIResponse>(
    `/api/transactions/${id}/category`,
    { category }
  );
  return response.data;
};
