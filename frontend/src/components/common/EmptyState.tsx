import React from 'react';
import { Empty, Button } from 'antd';
import type { EmptyProps } from 'antd';

interface EmptyStateProps extends EmptyProps {
  message?: string;
  actionText?: string;
  onAction?: () => void;
}

/**
 * Empty state component for displaying when no data is available
 * Supports custom message and optional action button
 */
const EmptyState: React.FC<EmptyStateProps> = ({
  message = '데이터가 없습니다',
  actionText,
  onAction,
  ...props
}) => {
  return (
    <Empty
      description={message}
      {...props}
    >
      {actionText && onAction && (
        <Button type="primary" onClick={onAction}>
          {actionText}
        </Button>
      )}
    </Empty>
  );
};

export default EmptyState;
