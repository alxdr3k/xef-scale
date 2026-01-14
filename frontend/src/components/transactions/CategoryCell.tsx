import React, { useState } from 'react';
import { Select, Space } from 'antd';
import type { TransactionAPIResponse, CategoryAPIResponse } from '../../api/services';
import { categoryColors } from '../../theme.config';

interface CategoryCellProps {
  transaction: TransactionAPIResponse;
  categories: CategoryAPIResponse[];
  onUpdate: (transactionId: number, category: string) => Promise<void>;
}

/**
 * CategoryCell component for inline editing of transaction categories
 * Displays category with colored dot indicator
 * Switches to Select dropdown on click for editing
 */
const CategoryCell: React.FC<CategoryCellProps> = ({ transaction, categories, onUpdate }) => {
  const [isEditing, setIsEditing] = useState(false);
  const [selectedCategory, setSelectedCategory] = useState<string>(transaction.category);

  /**
   * Get category color from theme configuration
   */
  const getCategoryColor = (categoryName: string): string => {
    return categoryColors[categoryName] || categoryColors['기타'];
  };

  /**
   * Handle category change from Select dropdown
   */
  const handleCategoryChange = async (newCategory: string) => {
    try {
      setSelectedCategory(newCategory);
      setIsEditing(false);
      await onUpdate(transaction.id, newCategory);
    } catch (error) {
      // Error handled by parent component
      // Revert to original category on failure
      setSelectedCategory(transaction.category);
    }
  };

  /**
   * Handle dropdown close without selection
   */
  const handleBlur = () => {
    setIsEditing(false);
    setSelectedCategory(transaction.category);
  };

  // Editing mode - Show Select dropdown
  if (isEditing) {
    return (
      <Select
        value={selectedCategory}
        onChange={handleCategoryChange}
        onBlur={handleBlur}
        showSearch
        filterOption={(input, option) =>
          (option?.label ?? '').toLowerCase().includes(input.toLowerCase())
        }
        options={categories.map((cat) => ({
          value: cat.name,
          label: cat.name,
        }))}
        style={{ width: '100%' }}
        autoFocus
        open={isEditing}
      />
    );
  }

  // Display mode - Show category with colored dot
  return (
    <Space
      style={{
        cursor: 'pointer',
        userSelect: 'none',
      }}
      onClick={() => setIsEditing(true)}
    >
      <span
        style={{
          display: 'inline-block',
          width: 8,
          height: 8,
          borderRadius: '50%',
          backgroundColor: getCategoryColor(selectedCategory),
        }}
      />
      <span>{selectedCategory}</span>
    </Space>
  );
};

export default CategoryCell;
