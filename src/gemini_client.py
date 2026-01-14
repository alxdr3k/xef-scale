"""
GeminiClient wrapper for Google Gemini API transaction categorization.

Provides AI-powered merchant categorization for Korean financial statements
with retry logic, validation, and cost tracking.
"""

import logging
import time
from datetime import datetime, timedelta
from typing import Dict, List, Optional

from google import genai


class GeminiClient:
    """
    Wrapper for Google Gemini API transaction categorization.

    Features:
    - Multi-model fallback strategy (5 models in priority order)
    - Prompt engineering for Korean merchant categorization
    - Retry logic with exponential backoff (3 attempts per model)
    - Rate limit handling with automatic model switching
    - Cooldown tracking to prevent repeated rate limit hits
    - Response validation against valid categories
    - Error handling with graceful fallback
    - Cost tracking and model usage statistics

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
        >>>
        >>> # Check model usage statistics
        >>> stats = client.get_model_stats()
        >>> print(stats)
        {'gemini-2.5-flash': {'success': 10, 'failed': 0, 'rate_limited': 2}, ...}
    """

    # Model priority list (try in order)
    MODELS = [
        'gemini-2.5-flash',      # Latest flash (fastest, try first)
        'gemini-2.5-pro',        # Latest pro (more capable)
        'gemini-3.0-flash',      # Newest flash
        'gemini-3.0-pro',        # Newest pro
        'gemini-2.0-flash'       # Current stable
    ]

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

        # Initialize client (new API)
        self.client = genai.Client(api_key=self.api_key)

        # Track model usage stats
        self.model_stats: Dict[str, Dict[str, int]] = {
            model: {'success': 0, 'failed': 0, 'rate_limited': 0}
            for model in self.MODELS
        }

        # Track when each model was last rate limited
        self.model_cooldowns: Dict[str, Optional[datetime]] = {
            model: None for model in self.MODELS
        }
        self.COOLDOWN_DURATION = 60  # seconds

        self.logger.info(f'GeminiClient initialized with {len(valid_categories)} valid categories')
        self.logger.info(f'Multi-model fallback enabled: {len(self.MODELS)} models available')

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

    def _is_model_on_cooldown(self, model_name: str) -> bool:
        """
        Check if model is in cooldown period after rate limit.

        Args:
            model_name: Name of the model to check

        Returns:
            True if model is on cooldown, False otherwise
        """
        cooldown_time = self.model_cooldowns.get(model_name)
        if not cooldown_time:
            return False

        elapsed = (datetime.now() - cooldown_time).total_seconds()
        if elapsed < self.COOLDOWN_DURATION:
            remaining = self.COOLDOWN_DURATION - elapsed
            self.logger.debug(f'{model_name} on cooldown ({remaining:.0f}s remaining)')
            return True

        return False

    def get_model_stats(self) -> Dict[str, Dict[str, int]]:
        """
        Return model usage statistics for monitoring.

        Returns:
            Dictionary mapping model names to their usage stats
            (success, failed, rate_limited counts)
        """
        return self.model_stats

    def _call_gemini_api(self, prompt: str, max_retries: int = 3) -> Optional[str]:
        """
        Call Gemini API with multi-model fallback.

        Multi-Model Fallback Strategy:
        - Tries models in priority order (MODELS list)
        - On rate limit (429), tries next model immediately
        - On other errors, retries same model with exponential backoff
        - Tracks cooldowns to prevent repeated rate limit hits
        - Returns None only after all models exhausted

        Retry Strategy (per model):
        - Attempt 1: Immediate call
        - Attempt 2: Wait 1 second, retry
        - Attempt 3: Wait 2 seconds, retry
        - After 3 failures or rate limit: Try next model

        Handles:
        - Network timeouts
        - Rate limit errors (429) - switches to next model
        - Invalid API keys
        - Empty responses
        - Any unexpected exceptions

        Args:
            prompt: Prompt to send to Gemini
            max_retries: Maximum number of retry attempts per model (default: 3)

        Returns:
            Raw response text (stripped) or None if all models exhausted

        Examples:
            >>> client = GeminiClient(api_key='key', valid_categories=['식비'])
            >>> response = client._call_gemini_api('Categorize: 스타벅스')
            >>> print(response)
            '식비'

        Notes:
            - Logs all API calls for cost tracking
            - Exponential backoff: 2^(attempt-1) seconds per model
            - Model statistics tracked for monitoring
            - Cooldown tracking prevents repeated rate limit attempts
        """
        for model_name in self.MODELS:
            # Skip models on cooldown
            if self._is_model_on_cooldown(model_name):
                self.logger.info(f'⏸ Skipping {model_name} (cooling down)')
                continue

            self.logger.info(f'Attempting model: {model_name}')

            for attempt in range(1, max_retries + 1):
                try:
                    self.logger.debug(f'{model_name} - attempt {attempt}/{max_retries}')

                    # New API pattern
                    response = self.client.models.generate_content(
                        model=model_name,
                        contents=prompt
                    )

                    if response and response.text:
                        # Success! Update stats and return
                        self.model_stats[model_name]['success'] += 1
                        self.logger.info(f'✓ {model_name} succeeded (attempt {attempt})')
                        return response.text.strip()
                    else:
                        self.logger.warning(f'{model_name} returned empty response')

                except Exception as e:
                    error_type = type(e).__name__
                    error_msg = str(e)

                    # Check if this is a rate limit error
                    is_rate_limit = (
                        error_type == 'ResourceExhausted' or
                        '429' in error_msg or
                        'quota' in error_msg.lower() or
                        'rate limit' in error_msg.lower()
                    )

                    if is_rate_limit:
                        # Set cooldown for this model
                        self.model_cooldowns[model_name] = datetime.now()
                        self.model_stats[model_name]['rate_limited'] += 1
                        self.logger.warning(
                            f'✗ {model_name} rate limited (attempt {attempt}). '
                            f'Cooldown: {self.COOLDOWN_DURATION}s. Trying next model...'
                        )
                        break  # Exit retry loop, try next model
                    else:
                        # Non-rate-limit error - log and retry same model
                        self.model_stats[model_name]['failed'] += 1
                        self.logger.error(
                            f'{model_name} error (attempt {attempt}/{max_retries}): '
                            f'{error_type} - {error_msg}'
                        )

                        if attempt < max_retries:
                            backoff_time = 2 ** (attempt - 1)
                            self.logger.debug(f'Retrying {model_name} in {backoff_time}s...')
                            time.sleep(backoff_time)
                        else:
                            # All retries exhausted for this model, try next
                            self.logger.error(f'{model_name} failed after {max_retries} attempts')
                            break

        # All models exhausted
        self.logger.error(f'All {len(self.MODELS)} models exhausted or rate limited')
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
