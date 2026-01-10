/**
 * Authentication API service
 * Handles Google OAuth, token refresh, logout, and user info retrieval
 */

import apiClient from './client';
import type { User, AuthResponse } from '../types';

/**
 * Google authentication request payload
 */
export interface GoogleAuthRequest {
  credential: string;
}

/**
 * Authenticate with Google ID token
 * @param credential - Google ID token from Google Sign-In
 * @returns Authentication response with tokens and user info
 */
export const googleLogin = async (credential: string): Promise<AuthResponse> => {
  const response = await apiClient.post<AuthResponse>('/api/auth/google', {
    credential,
  });
  return response.data;
};

/**
 * Get current authenticated user information
 * @returns Current user info from JWT token
 */
export const getCurrentUser = async (): Promise<User> => {
  const response = await apiClient.get<User>('/api/auth/me');
  return response.data;
};

/**
 * Logout current user
 * Note: JWT tokens are stateless, so client must delete tokens locally
 */
export const logout = async (): Promise<void> => {
  await apiClient.post('/api/auth/logout');
};

/**
 * Refresh access token using refresh token
 * @param refreshToken - Refresh token from previous authentication
 * @returns New access and refresh tokens
 */
export const refreshAccessToken = async (refreshToken: string): Promise<AuthResponse> => {
  const response = await apiClient.post<AuthResponse>('/api/auth/refresh', {
    refresh_token: refreshToken,
  });
  return response.data;
};
