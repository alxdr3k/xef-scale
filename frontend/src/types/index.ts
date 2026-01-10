// Transaction type matching the backend DTO
export interface Transaction {
  id?: number;
  month: string; // mm format
  date: string; // yyyy.mm.dd format
  category: string; // 분류 (식비/편의점/교통/보험/기타)
  item: string; // 내역 (merchant/transaction description)
  amount: number; // 금액
  source: string; // 지출 위치 (bank/card name)
}

// User type for authentication (matches backend UserInfo schema)
export interface User {
  id: string;
  email: string;
  name: string | null;
  picture: string | null;
}

// Auth response from backend
export interface AuthResponse {
  access_token: string;
  refresh_token: string;
  token_type: string;
  user: User;
}

// Parsing session status
export type ParsingStatus = 'pending' | 'processing' | 'completed' | 'failed';

export interface ParsingSession {
  id: number;
  file_id: number;
  parser_type: string;
  started_at: string;
  completed_at: string | null;
  total_rows_in_file: number;
  rows_saved: number;
  rows_skipped: number;
  rows_duplicate: number;
  status: string;
  error_message: string | null;
  validation_status: string | null;
  validation_notes: string | null;
  // Joined fields from processed_files and financial_institutions
  file_name: string | null;
  file_hash: string | null;
  institution_name: string | null;
  institution_type: string | null;
}

// Skipped transaction in parsing session
export interface SkippedTransaction {
  id: number;
  session_id: number;
  row_number: number;
  skip_reason: string;
  transaction_date: string | null;
  merchant_name: string | null;
  amount: number | null;
  original_amount: number | null;
  skip_details: string | null;
  column_data: Record<string, any> | null;
}

// API response with pagination
export interface PaginatedResponse<T> {
  data: T[];
  total: number;
  page: number;
  limit: number;
  totalPages: number;
}

// Parsing session list response
export interface ParsingSessionListResponse {
  sessions: ParsingSession[];
  total: number;
  page: number;
  page_size: number;
}

// Transaction summary by category
export interface CategorySummary {
  category: string;
  total_amount: number;
  transaction_count: number;
  percentage: number;
}

// Financial institutions
export interface Institution {
  id: number;
  name: string;
  code: string;
}

// Categories
export interface Category {
  id: number;
  name: string;
  description: string | null;
}

// Transaction query parameters
export interface TransactionQueryParams {
  year?: number;
  month?: number;
  page?: number;
  limit?: number;
  sort?: 'date' | 'amount' | '-date' | '-amount';
  search?: string;
}
