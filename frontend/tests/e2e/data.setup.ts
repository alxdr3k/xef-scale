import { test as setup, expect } from '@playwright/test';

/**
 * Data setup for E2E tests
 *
 * This setup file runs after authentication and creates seed data for testing:
 * - Categories (created automatically when transactions are created)
 * - Institutions (created automatically when transactions are created)
 * - Sample transactions (both manual and parsed)
 *
 * Categories and institutions are created implicitly through transaction creation,
 * as the backend uses get_or_create patterns for these entities.
 */

setup('seed test data', async ({ request }) => {
  const baseUrl = 'http://localhost:8000';

  // First, authenticate to get access token
  const authResponse = await request.post(`${baseUrl}/api/test/login`);
  expect(authResponse.ok()).toBeTruthy();
  const authData = await authResponse.json();
  const accessToken = authData.access_token;

  console.log('⚠️  Note: Using existing database - data will accumulate across test runs');
  console.log('   Consider clearing ./data/expense_tracker.db manually for a fresh start');

  // Common headers with authentication
  const headers = {
    'Content-Type': 'application/json',
    'Authorization': `Bearer ${accessToken}`
  };

  // Define test categories and institutions that will be created via transactions
  const categories = ['식비', '교통', '쇼핑', '생활', '기타'];
  const institutions = [
    { name: '신한카드', type: 'CARD' },
    { name: '하나카드', type: 'CARD' },
    { name: '토스뱅크', type: 'BANK' },
    { name: '카카오뱅크', type: 'BANK' }
  ];

  // Create manual transactions (file_id = NULL)
  // These transactions will automatically create categories and institutions
  const manualTransactions = [
    {
      date: '2025.01.15',
      category: '식비',
      merchant_name: '스타벅스 강남점',
      amount: 5500,
      institution: '신한카드',
      notes: '회의 중 커피'
    },
    {
      date: '2025.01.16',
      category: '교통',
      merchant_name: '카카오T 택시',
      amount: 12000,
      institution: '하나카드'
    },
    {
      date: '2025.01.17',
      category: '쇼핑',
      merchant_name: '쿠팡',
      amount: 45000,
      institution: '토스뱅크',
      notes: '생필품 구매'
    },
    {
      date: '2025.01.18',
      category: '식비',
      merchant_name: '맥도날드',
      amount: 8500,
      institution: '카카오뱅크'
    },
    {
      date: '2025.01.19',
      category: '생활',
      merchant_name: 'GS25 편의점',
      amount: 3200,
      institution: '신한카드'
    },
    {
      date: '2025.01.20',
      category: '기타',
      merchant_name: '다이소',
      amount: 15000,
      institution: '하나카드'
    },
    {
      date: '2025.01.21',
      category: '식비',
      merchant_name: '이디야커피',
      amount: 4000,
      institution: '토스뱅크'
    },
    {
      date: '2025.01.22',
      category: '교통',
      merchant_name: '지하철',
      amount: 1350,
      institution: '카카오뱅크'
    },
    {
      date: '2025.01.23',
      category: '쇼핑',
      merchant_name: '무신사',
      amount: 89000,
      institution: '신한카드',
      notes: '겨울 재킷'
    },
    {
      date: '2025.01.24',
      category: '식비',
      merchant_name: '김밥천국',
      amount: 6000,
      institution: '하나카드'
    }
  ];

  console.log('Creating manual transactions...');
  for (const transaction of manualTransactions) {
    const response = await request.post(`${baseUrl}/api/transactions`, {
      headers,
      data: transaction
    });

    if (!response.ok()) {
      const error = await response.text();
      console.error(`Failed to create transaction: ${transaction.merchant_name}`, error);
    } else {
      const created = await response.json();
      console.log(`✓ Created manual transaction: ${created.merchant_name} (ID: ${created.id})`);
    }
  }

  // Now create a processed file entry for parsed transactions
  // Since there's no API endpoint for this, we'll need to directly insert into the database
  // For now, we'll create transactions with different patterns that simulate parsed data

  // Create parsed-style transactions (these will still have file_id = NULL since we can't create files via API)
  // In a real scenario, these would be created by the file parser
  const parsedStyleTransactions = [
    {
      date: '2025.01.10',
      category: '식비',
      merchant_name: '올리브영',
      amount: 25000,
      institution: '신한카드'
    },
    {
      date: '2025.01.11',
      category: '교통',
      merchant_name: 'SK주유소',
      amount: 60000,
      institution: '하나카드'
    },
    {
      date: '2025.01.12',
      category: '쇼핑',
      merchant_name: '애플스토어',
      amount: 1290000,
      institution: '토스뱅크',
      installment_months: 12,
      installment_current: 1,
      original_amount: 1290000
    },
    {
      date: '2025.01.13',
      category: '식비',
      merchant_name: '도미노피자',
      amount: 32000,
      institution: '카카오뱅크'
    },
    {
      date: '2025.01.14',
      category: '생활',
      merchant_name: '홈플러스',
      amount: 125000,
      institution: '신한카드'
    }
  ];

  console.log('\nCreating parsed-style transactions...');
  for (const transaction of parsedStyleTransactions) {
    const response = await request.post(`${baseUrl}/api/transactions`, {
      headers,
      data: transaction
    });

    if (!response.ok()) {
      const error = await response.text();
      console.error(`Failed to create parsed-style transaction: ${transaction.merchant_name}`, error);
    } else {
      const created = await response.json();
      console.log(`✓ Created parsed-style transaction: ${created.merchant_name} (ID: ${created.id})`);
    }
  }

  // Verify that categories were created
  console.log('\nVerifying categories...');
  const categoriesResponse = await request.get(`${baseUrl}/api/categories`, { headers });
  expect(categoriesResponse.ok()).toBeTruthy();
  const categoriesData = await categoriesResponse.json();
  console.log(`✓ Found ${categoriesData.length} categories:`, categoriesData.map((c: any) => c.name).join(', '));

  // Verify that institutions were created
  console.log('\nVerifying institutions...');
  const institutionsResponse = await request.get(`${baseUrl}/api/institutions`, { headers });
  expect(institutionsResponse.ok()).toBeTruthy();
  const institutionsData = await institutionsResponse.json();
  console.log(`✓ Found ${institutionsData.length} institutions:`, institutionsData.map((i: any) => i.name).join(', '));

  // Verify that transactions were created
  console.log('\nVerifying transactions...');
  const transactionsResponse = await request.get(`${baseUrl}/api/transactions?limit=100`, { headers });
  expect(transactionsResponse.ok()).toBeTruthy();
  const transactionsData = await transactionsResponse.json();
  console.log(`✓ Found ${transactionsData.total} total transactions`);
  console.log(`  - Expected: ${manualTransactions.length + parsedStyleTransactions.length}`);

  // Verify we have the minimum required data
  expect(categoriesData.length).toBeGreaterThanOrEqual(5);
  expect(institutionsData.length).toBeGreaterThanOrEqual(4);
  expect(transactionsData.total).toBeGreaterThanOrEqual(10);

  console.log('\n✅ Data setup complete!');
});
