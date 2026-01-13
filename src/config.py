"""
Centralized configuration for expense tracking system.
Contains directory paths, institution keywords, and category rules.
"""

import os
from dotenv import load_dotenv

load_dotenv()

# Gemini API Configuration
GEMINI_API_KEY = os.getenv('GEMINI_API_KEY', '')

if not GEMINI_API_KEY:
    import logging
    logging.warning('GEMINI_API_KEY not set in .env - Gemini categorization disabled')

# Directory configuration
DIRECTORIES = {
    'inbox': './inbox',
    'archive': './archive',
    'data': './data',
    'unknown': './unknown',
    'logs': './logs'
}

# Archive configuration
ARCHIVE_RETENTION_DAYS = 30  # Keep archived files for 30 days, then auto-delete
ARCHIVE_CLEANUP_ENABLED = True  # Set to False to disable automatic cleanup

# Institution identification keywords
INSTITUTION_KEYWORDS = {
    'TOSS': ['토스뱅크', 'Toss'],
    'KAKAO': ['kakao', '카카오뱅크'],
    'SHINHAN': ['신한카드'],
    'HANA': ['하나카드']
}

# Category matching rules
CATEGORY_RULES = {
    '식비': ['식당', '음식'],
    '교통': ['주유'],
    '통신': ['KT', 'SKT']
}
