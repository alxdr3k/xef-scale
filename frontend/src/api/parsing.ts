import apiClient from './client';
import type { ParsingSession, ParsingSessionListResponse, SkippedTransaction } from '../types';

/**
 * API service for parsing sessions
 */

export const parsingApi = {
  /**
   * Get paginated list of parsing sessions
   */
  async getSessions(page: number = 1, pageSize: number = 20): Promise<ParsingSessionListResponse> {
    const response = await apiClient.get<ParsingSessionListResponse>('/api/parsing-sessions', {
      params: {
        page,
        page_size: pageSize,
      },
    });
    return response.data;
  },

  /**
   * Get single parsing session by ID
   */
  async getSessionById(sessionId: number): Promise<ParsingSession> {
    const response = await apiClient.get<ParsingSession>(`/api/parsing-sessions/${sessionId}`);
    return response.data;
  },

  /**
   * Get skipped transactions for a parsing session
   */
  async getSkippedTransactions(sessionId: number): Promise<SkippedTransaction[]> {
    const response = await apiClient.get<SkippedTransaction[]>(`/api/parsing-sessions/${sessionId}/skipped`);
    return response.data;
  },
};
