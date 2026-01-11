import axios from 'axios';
import type { AxiosError, InternalAxiosRequestConfig } from 'axios';
import { message } from '../lib/antd-static';

// Create axios instance with default config
const apiClient = axios.create({
  baseURL: import.meta.env.VITE_API_BASE_URL || 'http://localhost:8000',
  timeout: 10000,
  headers: {
    'Content-Type': 'application/json',
  },
});

// Request interceptor - attach JWT token
apiClient.interceptors.request.use(
  (config: InternalAxiosRequestConfig) => {
    const token = localStorage.getItem('access_token');
    if (token && config.headers) {
      config.headers.Authorization = `Bearer ${token}`;
    }
    return config;
  },
  (error: AxiosError) => {
    return Promise.reject(error);
  }
);

// Response interceptor - handle common errors
apiClient.interceptors.response.use(
  (response) => {
    return response;
  },
  (error: AxiosError) => {
    // Handle 401 Unauthorized - redirect to login
    if (error.response?.status === 401) {
      message.warning('인증이 만료되었습니다. 다시 로그인해주세요.');
      localStorage.removeItem('access_token');
      localStorage.removeItem('user');
      window.location.href = '/';
    }
    // Handle 403 Forbidden
    else if (error.response?.status === 403) {
      message.error('접근 권한이 없습니다.');
      console.error('Access forbidden:', error);
    }
    // Handle 500 Internal Server Error
    else if (error.response?.status === 500) {
      message.error('서버 오류가 발생했습니다. 잠시 후 다시 시도해주세요.');
      console.error('Server error:', error);
    }
    // Handle network errors
    else if (error.code === 'ECONNABORTED' || error.message === 'Network Error') {
      message.error('네트워크 연결을 확인해주세요.');
      console.error('Network error:', error);
    }
    // Handle timeout errors
    else if (error.code === 'ETIMEDOUT') {
      message.error('요청 시간이 초과되었습니다. 다시 시도해주세요.');
      console.error('Request timeout:', error);
    }
    // Handle other client errors (4xx)
    else if (error.response?.status && error.response.status >= 400 && error.response.status < 500) {
      const errorMessage = (error.response.data as any)?.detail || '요청 처리 중 오류가 발생했습니다.';
      message.error(errorMessage);
      console.error('Client error:', error);
    }

    return Promise.reject(error);
  }
);

export default apiClient;
