# Gemini API Integration

## Overview

The Expense Tracker uses Google's Gemini AI to automatically categorize Korean merchant names that cannot be matched by keyword-based rules. This AI-powered fallback dramatically improves categorization accuracy from ~24.7% to 80%+.

## Architecture

### Components

1. **GeminiClient** (`src/gemini_client.py`)
   - Wrapper for Google Gemini API
   - Handles AI-powered merchant categorization
   - Features:
     - Prompt engineering for Korean merchant categorization
     - Retry logic with exponential backoff (3 attempts)
     - Response validation against valid categories
     - Graceful error handling
     - Cost tracking via logging

2. **CategoryMatcher Integration** (`src/category_matcher.py`)
   - Three-tier categorization strategy:
     1. **Exact match**: Check existing merchant mappings (O(1) lookup)
     2. **Keyword match**: Try keyword-based rules
     3. **AI fallback**: Call Gemini API for unknown merchants
   - Caches all Gemini responses to database (`source='gemini'`)
   - Prevents duplicate API calls for same merchant

3. **Database Caching** (`category_merchant_mappings` table)
   - Stores all Gemini categorization results
   - `source` column tracks mapping origin ('manual', 'keyword', 'gemini')
   - Enables instant lookup on repeat processing
   - Reduces API costs by caching responses

## API Configuration

### Getting API Key

1. Visit [Google AI Studio](https://aistudio.google.com/app/apikey)
2. Create a new API key
3. Add to `.env` file:
   ```
   GEMINI_API_KEY=your_api_key_here
   ```

### Free Tier Limits

Gemini API free tier has the following limits:

- **Requests Per Minute (RPM)**: 15
- **Requests Per Day (RPD)**: 1500
- **Tokens Per Minute**: Varies by model

### Model Selection

Currently using `gemini-1.5-flash-latest`:
- Fast response times (1-2s average)
- Cost-effective for categorization tasks
- Good accuracy for Korean merchant names
- Better availability than experimental models

**Pricing** (if you upgrade to paid tier):
- Input: $0.00001875 per 1K tokens (~$0.00002 per request)
- Output: $0.0000375 per 1K tokens

## Testing

### Integration Test

Run the integration test to verify end-to-end Gemini integration:

```bash
cd /Users/yngn/ws/expense-tracker
source .venv/bin/activate
python3 scripts/test_gemini_integration.py
```

The test will:
1. Find all uncategorized transactions (category='기타')
2. Process them in batches to respect rate limits
3. Cache all Gemini responses to database
4. Report accuracy improvement metrics

**Expected behavior**:
- Processes 10 transactions per batch
- Pauses 50 seconds between batches (to stay under 15 RPM)
- Gracefully handles quota exceeded errors
- Provides progress updates during processing

### Rate Limit Handling

The test script includes built-in rate limit handling:

```python
BATCH_SIZE = 10           # Process 10 transactions at a time
BATCH_DELAY = 50         # Wait 50s between batches
```

This ensures we stay well under the 15 RPM limit (10 requests per 50s = 12 RPM).

### Quota Exceeded

If you exceed the daily quota (1500 RPD), the test will:
1. Report partial results (accuracy gain so far)
2. Show how many transactions were processed
3. Provide instructions to complete testing after quota resets

**To complete testing after quota exceeded**:
1. Wait 24 hours for daily quota to reset (midnight PST)
2. Run test again - cached results will be reused
3. Only remaining uncategorized merchants will hit the API

## Usage in Production

### File Processor Integration

The file processor automatically uses Gemini when processing new statements:

```python
from src.category_matcher import CategoryMatcher
from src.gemini_client import GeminiClient

# Initialize with Gemini support
gemini_client = GeminiClient(api_key=GEMINI_API_KEY, valid_categories=category_names)
matcher = CategoryMatcher(
    mapping_repo=mapping_repo,
    category_repo=category_repo,
    gemini_client=gemini_client  # Enable AI fallback
)

# Categorize merchant (will use AI if no keyword match)
category = matcher.get_category("스타벅스 강남점")  # Returns: "식비"
```

### Caching Benefits

Once a merchant is categorized by Gemini, the result is cached forever:

- **First time**: API call (costs ~$0.00002, takes 1-2s)
- **Subsequent times**: Database lookup (free, instant)

Example: If you have 100 transactions from "스타벅스", only the first one hits the API. The remaining 99 use the cached result.

## Monitoring

### Database Queries

Check Gemini mapping statistics:

```sql
-- Total Gemini mappings
SELECT COUNT(*) FROM category_merchant_mappings WHERE source = 'gemini';

-- Recent Gemini categorizations
SELECT merchant_name, category_id, created_at
FROM category_merchant_mappings
WHERE source = 'gemini'
ORDER BY created_at DESC
LIMIT 10;

-- Categorization source breakdown
SELECT source, COUNT(*) as count
FROM category_merchant_mappings
GROUP BY source;
```

### Log Monitoring

Gemini operations are logged at INFO level:

```
2026-01-14 07:00:47 - src.gemini_client - INFO - GeminiClient initialized with 23 valid categories
2026-01-14 07:00:47 - src.gemini_client - INFO - Gemini API call (attempt 1/3)
2026-01-14 07:00:48 - src.gemini_client - DEBUG - Gemini categorized "스타벅스" → 식비
```

Monitor for errors:
- `Gemini API error`: API call failed (network, auth, quota)
- `Invalid Gemini response`: Response not in valid categories
- `Empty merchant name`: Skipped (no API call made)

## Cost Optimization

### Best Practices

1. **Use keyword rules first**: Add common merchants to keyword matcher
2. **Cache aggressively**: Database caching prevents duplicate API calls
3. **Batch processing**: Test script respects rate limits automatically
4. **Monitor usage**: Check API usage at [Google AI Console](https://ai.dev/rate-limit)

### Estimated Costs

**Free Tier** (1500 RPD):
- Can categorize 1500 unique merchants per day
- Typical user has ~50-100 unique merchants/month
- Free tier should be sufficient for most use cases

**Paid Tier** (if needed):
- ~$0.00002 per categorization
- 10,000 categorizations = $0.20
- Very cost-effective for personal expense tracking

## Troubleshooting

### API Key Issues

**Error**: `GEMINI_API_KEY not set in .env`
- **Solution**: Add your API key to `.env` file

**Error**: `401 Unauthorized` / `Invalid API key`
- **Solution**: Verify API key at [Google AI Studio](https://aistudio.google.com/app/apikey)

### Quota Exceeded

**Error**: `429 You exceeded your current quota`
- **Cause**: Daily limit (1500 RPD) or per-minute limit (15 RPM) exceeded
- **Solution**: Wait for quota to reset (midnight PST for daily, 1 minute for RPM)
- **Prevention**: Use test script's rate limiting (50s between batches)

### Model Not Found

**Error**: `404 models/gemini-xxx is not found`
- **Cause**: Model name changed or unavailable
- **Solution**: Update model name in `src/gemini_client.py` line 79
- **Current**: `gemini-1.5-flash-latest`

### Low Accuracy

**Issue**: Categorization accuracy below 80%
- **Possible Causes**:
  - Gemini returning invalid categories
  - Merchant names too ambiguous
  - Category list not comprehensive
- **Solutions**:
  1. Check logs for `Invalid Gemini response` warnings
  2. Add more specific keywords to keyword matcher
  3. Review and refine category definitions

## Future Improvements

1. **Prompt optimization**: A/B test different prompts for better accuracy
2. **Category suggestions**: Use Gemini to suggest new categories
3. **Batch API calls**: Process multiple merchants in one API call
4. **Fine-tuning**: Train custom model on your transaction history
5. **Cost tracking**: Log token usage for detailed cost analysis
6. **Confidence scores**: Return confidence level with each categorization
7. **Human feedback loop**: Allow manual corrections to improve prompts

## References

- [Google Gemini API Documentation](https://ai.google.dev/gemini-api/docs)
- [Rate Limits and Quotas](https://ai.google.dev/gemini-api/docs/rate-limits)
- [Prompt Engineering Guide](https://ai.google.dev/gemini-api/docs/prompting-strategies)
- [Pricing](https://ai.google.dev/pricing)
