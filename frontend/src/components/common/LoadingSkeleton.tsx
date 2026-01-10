import React from 'react';
import { Skeleton, Card } from 'antd';

export type SkeletonType = 'table' | 'card' | 'list' | 'page';

interface LoadingSkeletonProps {
  type?: SkeletonType;
  rows?: number;
  active?: boolean;
}

/**
 * Loading skeleton component for different content types
 * Provides visual feedback during data loading
 */
const LoadingSkeleton: React.FC<LoadingSkeletonProps> = ({
  type = 'card',
  rows = 3,
  active = true,
}) => {
  switch (type) {
    case 'table':
      return (
        <div>
          {Array.from({ length: rows }).map((_, index) => (
            <Skeleton
              key={index}
              active={active}
              paragraph={{ rows: 1 }}
              style={{ marginBottom: 16 }}
            />
          ))}
        </div>
      );

    case 'list':
      return (
        <div>
          {Array.from({ length: rows }).map((_, index) => (
            <Skeleton
              key={index}
              active={active}
              avatar
              paragraph={{ rows: 2 }}
              style={{ marginBottom: 24 }}
            />
          ))}
        </div>
      );

    case 'page':
      return (
        <div>
          <Skeleton active={active} title paragraph={{ rows: 1 }} style={{ marginBottom: 24 }} />
          <Card>
            <Skeleton active={active} paragraph={{ rows: rows || 4 }} />
          </Card>
        </div>
      );

    case 'card':
    default:
      return (
        <Card>
          <Skeleton active={active} paragraph={{ rows }} />
        </Card>
      );
  }
};

export default LoadingSkeleton;
