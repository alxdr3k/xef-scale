"""
Centralized configuration for expense tracking system.
Contains directory paths, institution keywords, and category rules.
"""

# Directory configuration
DIRECTORIES = {
    'inbox': './inbox',
    'archive': './archive',
    'data': './data',
    'unknown': './unknown',
    'logs': './logs'
}

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
