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

// Transaction creation request (POST /api/transactions)
export interface TransactionCreateRequest {
  date: string; // yyyy.mm.dd format
  category: string; // Category name in Korean
  merchant_name: string;
  amount: number; // Must be positive integer
  institution: string; // Institution name in Korean
  installment_months?: number | null;
  installment_current?: number | null;
  original_amount?: number | null;
  notes?: string | null;
}

// Transaction update request (PUT /api/transactions/:id)
export interface TransactionUpdateRequest {
  date?: string;
  category?: string;
  merchant_name?: string;
  amount?: number;
  institution?: string;
  installment_months?: number | null;
  installment_current?: number | null;
  original_amount?: number | null;
  notes?: string | null;
}

// Transaction delete response (DELETE /api/transactions/:id)
export interface TransactionDeleteResponse {
  id: number;
  message: string;
  deleted_at: string; // ISO timestamp
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
  rows_pending?: number; // Pending duplicate confirmations count
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
  total_amount?: number; // Sum of all filtered transactions
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

// Duplicate confirmation status
export type ConfirmationStatus = 'pending' | 'confirmed_insert' | 'confirmed_skip' | 'confirmed_merge' | 'expired';

// Duplicate confirmation action
export type ConfirmationAction = 'insert' | 'skip' | 'merge';

// Duplicate confirmation for a transaction
export interface DuplicateConfirmation {
  id: number;
  session_id: number;
  new_transaction: Transaction;
  new_transaction_index: number;
  existing_transaction: Transaction;
  confidence_score: number;
  match_fields: string[];
  difference_summary?: string;
  status: ConfirmationStatus;
  created_at: string;
  expires_at: string;
}

// Bulk confirmation response
export interface BulkConfirmationResponse {
  processed_count: number;
  session_id: number;
}

// Workspace role types
export type WorkspaceRole = 'OWNER' | 'CO_OWNER' | 'MEMBER_WRITE' | 'MEMBER_READ';

// Workspace interface
export interface Workspace {
  id: number;
  name: string;
  description: string | null;
  created_by_user_id: number;
  currency: string;
  timezone: string;
  is_active: boolean;
  created_at: string;
  updated_at: string;
  role: WorkspaceRole;
  member_count: number;
}

// Workspace list response
export interface WorkspaceListResponse {
  data: Workspace[];
}

// Workspace member interface
export interface WorkspaceMember {
  user_id: number;
  name: string;
  email: string;
  profile_picture_url: string | null;
  role: WorkspaceRole;
  joined_at: string;
}

// Workspace member list response
export interface WorkspaceMemberListResponse {
  members: WorkspaceMember[];
}

// Workspace update request
export interface WorkspaceUpdateRequest {
  name?: string;
  description?: string;
}

// Member role update request
export interface MemberRoleUpdateRequest {
  role: WorkspaceRole;
}

// Workspace invitation interface
export interface WorkspaceInvitation {
  id: number;
  workspace_id: number;
  token: string;
  role: WorkspaceRole;
  created_by_user_id: number;
  created_by_name?: string;
  expires_at: string;
  max_uses: number | null;
  current_uses: number;
  is_active: boolean;
  revoked_at: string | null;
  created_at: string;
}

// Invitation creation request
export interface InvitationCreateRequest {
  role: WorkspaceRole;
  expires_in_days: number;
  max_uses?: number | null;
}

// Invitation list response
export interface WorkspaceInvitationListResponse {
  invitations: WorkspaceInvitation[];
}
