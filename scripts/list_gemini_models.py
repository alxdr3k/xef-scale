#!/usr/bin/env python3
from google import genai
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).parent.parent))
from src.config import GEMINI_API_KEY

client = genai.Client(api_key=GEMINI_API_KEY)
models = client.models.list()
print('Available Gemini models that support generateContent:')
for m in models:
    if hasattr(m, 'supported_generation_methods') and 'generateContent' in m.supported_generation_methods:
        print(f'  - {m.name}')
    elif hasattr(m, 'name'):
        # Some models might not have supported_generation_methods attribute
        print(f'  - {m.name}')
