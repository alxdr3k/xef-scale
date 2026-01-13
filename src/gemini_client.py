"""
GeminiClient wrapper for Google Gemini API transaction categorization.

Provides AI-powered merchant categorization for Korean financial statements
with retry logic, validation, and cost tracking.
"""

import logging
import time
from typing import List, Optional

import google.generativeai as genai


class GeminiClient:
    """
    Wrapper for Google Gemini API transaction categorization.

    Features:
    - Prompt engineering for Korean merchant categorization
    - Retry logic with exponential backoff (3 attempts)
    - Response validation against valid categories
    - Error handling with graceful fallback
    - Cost tracking via logging

    Gemini 1.5 Flash Pricing:
    - Input: $0.00001875 per 1K tokens (~$0.00002 per request)
    - Output: $0.0000375 per 1K tokens
    - Fast response times (1-2s average)
    - Sufficient accuracy for categorization tasks

    Example Usage:
        >>> from src.gemini_client import GeminiClient
        >>>
        >>> valid_categories = ['식비', '교통', '기타']
        >>> client = GeminiClient(api_key='your_key', valid_categories=valid_categories)
        >>>
        >>> category = client.categorize_merchant('스타벅스 강남점')
        >>> print(category)
        '식비'
        >>>
        >>> # Handles errors gracefully
        >>> category = client.categorize_merchant('')
        >>> print(category)
        None
    """

    def __init__(self, api_key: str, valid_categories: List[str]):
        """
        Initialize Gemini client.

        Args:
            api_key: Google Gemini API key (get from https://aistudio.google.com/app/apikey)
            valid_categories: List of valid category names for validation (23 categories)

        Raises:
            ValueError: If api_key is empty or valid_categories is empty

        Notes:
            - Configures genai module globally with provided API key
            - Initializes Gemini 1.5 Flash model (fast, cost-effective)
            - Converts categories to set for O(1) lookup performance
        """
        if not api_key:
            raise ValueError('API key cannot be empty')

        if not valid_categories:
            raise ValueError('Valid categories list cannot be empty')

        self.api_key = api_key
        self.valid_categories = set(valid_categories)  # O(1) lookup
        self.logger = logging.getLogger(__name__)

        # Configure API
        genai.configure(api_key=self.api_key)

        # Initialize Gemini 1.5 Flash model (fast, cost-effective)
        self.model = genai.GenerativeModel('gemini-1.5-flash')

        self.logger.info(f'GeminiClient initialized with {len(valid_categories)} valid categories')

    def categorize_merchant(self, merchant_name: str) -> Optional[str]:
        """
        Categorize merchant using Gemini API.

        Workflow:
        1. Validate merchant name (skip if empty)
        2. Build prompt with all valid categories
        3. Call Gemini API with retry logic
        4. Validate response against valid categories
        5. Return validated category or None on error

        Args:
            merchant_name: Korean merchant name from transaction (e.g., '스타벅스', 'GS주유소')

        Returns:
            Valid category name or None on error

        Examples:
            >>> client = GeminiClient(api_key='key', valid_categories=['식비', '교통', '기타'])
            >>>
            >>> # Successful categorization
            >>> client.categorize_merchant('스타벅스')
            '식비'
            >>>
            >>> # Empty merchant name
            >>> client.categorize_merchant('')
            None
            >>>
            >>> # Invalid response from Gemini
            >>> client.categorize_merchant('Unknown Merchant')
            None  # Logs warning about invalid response

        Notes:
            - Returns None if merchant name is empty (no API call made)
            - Returns None if Gemini API fails after retries
            - Returns None if response is not in valid categories
            - Logs all operations for debugging and cost tracking
        """
        # Edge case: empty merchant name
        if not merchant_name or not merchant_name.strip():
            self.logger.debug('Empty merchant name, skipping Gemini API call')
            return None

        # Build prompt
        prompt = self._build_prompt(merchant_name)

        # Call Gemini API with retry
        raw_response = self._call_gemini_api(prompt)

        if not raw_response:
            return None

        # Validate response
        validated_category = self._validate_category(raw_response)

        if validated_category:
            self.logger.debug(f'Gemini categorized "{merchant_name}" → {validated_category}')
        else:
            self.logger.warning(
                f'Invalid Gemini response "{raw_response}" for "{merchant_name}". '
                f'Not in valid categories.'
            )

        return validated_category

    def _build_prompt(self, merchant_name: str) -> str:
        """
        Build optimized prompt for Gemini categorization.

        Prompt Engineering Strategy:
        - Clear role definition: "You are a transaction categorizer"
        - Korean language instructions for better context understanding
        - Complete list of all 23 valid categories
        - Request for single-word response (easy parsing)
        - No explanations requested (reduces token cost)

        Args:
            merchant_name: Merchant name to categorize

        Returns:
            Formatted prompt string in Korean

        Examples:
            >>> client = GeminiClient(api_key='key', valid_categories=['식비', '교통'])
            >>> prompt = client._build_prompt('스타벅스')
            >>> print(prompt)
            당신은 거래 내역을 분류하는 AI입니다.

            가맹점 이름: "스타벅스"

            다음 카테고리 중 가장 적합한 하나만 선택하세요:
            - 교통
            - 식비

            응답은 정확한 카테고리 이름만 반환하세요...

        Notes:
            - Categories are sorted for consistency across requests
            - Korean instructions improve accuracy for Korean merchant names
            - Single-line response format simplifies parsing
        """
        # Sort categories for consistency
        categories_list = '\n'.join(f'- {cat}' for cat in sorted(self.valid_categories))

        prompt = f"""당신은 거래 내역을 분류하는 AI입니다.

가맹점 이름: "{merchant_name}"

다음 카테고리 중 가장 적합한 하나만 선택하세요:
{categories_list}

응답은 정확한 카테고리 이름만 반환하세요. 설명이나 추가 텍스트 없이 카테고리 이름만 작성하세요."""

        return prompt

    def _call_gemini_api(self, prompt: str, max_retries: int = 3) -> Optional[str]:
        """
        Call Gemini API with exponential backoff retry.

        Retry Strategy:
        - Attempt 1: Immediate call
        - Attempt 2: Wait 1 second, retry
        - Attempt 3: Wait 2 seconds, retry
        - After 3 failures: Give up and return None

        Handles:
        - Network timeouts
        - Rate limit errors (429)
        - Invalid API keys
        - Empty responses
        - Any unexpected exceptions

        Args:
            prompt: Prompt to send to Gemini
            max_retries: Maximum number of retry attempts (default: 3)

        Returns:
            Raw response text (stripped) or None on error

        Examples:
            >>> client = GeminiClient(api_key='key', valid_categories=['식비'])
            >>> response = client._call_gemini_api('Categorize: 스타벅스')
            >>> print(response)
            '식비'

        Notes:
            - Logs all API calls for cost tracking
            - Exponential backoff: 2^(attempt-1) seconds
            - Catches all exceptions to prevent crashes
            - Returns None after exhausting retries
        """
        for attempt in range(1, max_retries + 1):
            try:
                self.logger.info(f'Gemini API call (attempt {attempt}/{max_retries})')

                response = self.model.generate_content(prompt)

                if response and response.text:
                    return response.text.strip()
                else:
                    self.logger.warning(f'Empty response from Gemini API (attempt {attempt})')

            except Exception as e:
                self.logger.error(
                    f'Gemini API error (attempt {attempt}/{max_retries}): {type(e).__name__} - {e}'
                )

                # Exponential backoff: 1s, 2s, 4s
                if attempt < max_retries:
                    backoff_time = 2 ** (attempt - 1)
                    self.logger.debug(f'Retrying in {backoff_time}s...')
                    time.sleep(backoff_time)

        # All retries failed
        self.logger.error(f'Gemini API failed after {max_retries} attempts')
        return None

    def _validate_category(self, category: str) -> Optional[str]:
        """
        Validate Gemini response against valid categories.

        Validation Strategy:
        1. Clean response (strip whitespace)
        2. Check exact match (primary method)
        3. Check case-insensitive match (fallback for edge cases)
        4. Return None if no match

        Args:
            category: Raw category string from Gemini

        Returns:
            Validated category (exact match from valid_categories) or None if invalid

        Examples:
            >>> client = GeminiClient(api_key='key', valid_categories=['식비', '교통'])
            >>>
            >>> # Exact match
            >>> client._validate_category('식비')
            '식비'
            >>>
            >>> # With whitespace
            >>> client._validate_category('  식비  ')
            '식비'
            >>>
            >>> # Invalid category
            >>> client._validate_category('알수없음')
            None
            >>>
            >>> # Empty response
            >>> client._validate_category('')
            None

        Notes:
            - O(1) lookup performance (set membership test)
            - Case-insensitive fallback handles edge cases
            - Returns canonical category name from valid_categories
        """
        if not category:
            return None

        # Clean up response (strip whitespace, normalize)
        cleaned = category.strip()

        # Check if category is valid (exact match)
        if cleaned in self.valid_categories:
            return cleaned

        # Case-insensitive check (shouldn't be needed for Korean, but safe)
        for valid_cat in self.valid_categories:
            if cleaned.lower() == valid_cat.lower():
                return valid_cat

        return None
