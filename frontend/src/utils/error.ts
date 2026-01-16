/**
 * Safely extract error message from API error response.
 * Handles various error formats including Pydantic validation errors.
 *
 * @param error - The error object (typically from axios catch)
 * @param fallbackMessage - Default message if extraction fails
 * @returns A string error message safe for display
 */
export function getErrorMessage(error: any, fallbackMessage: string = '오류가 발생했습니다'): string {
  const detail = error?.response?.data?.detail;

  if (typeof detail === 'string') {
    return detail;
  }

  if (Array.isArray(detail)) {
    // Handle Pydantic validation errors (array of {field, msg/message, type})
    return detail
      .map((e: any) => e.msg || e.message || JSON.stringify(e))
      .join(', ');
  }

  if (detail && typeof detail === 'object') {
    return detail.message || detail.msg || JSON.stringify(detail);
  }

  if (error?.message) {
    return error.message;
  }

  return fallbackMessage;
}
