import React from 'react';
import { Card as AntCard } from 'antd';
import type { CardProps as AntCardProps } from 'antd';

export interface CardProps extends AntCardProps {
  children: React.ReactNode;
}

/**
 * Reusable Card component wrapper for Ant Design Card
 * Provides consistent styling across the application
 */
const Card: React.FC<CardProps> = ({ children, ...props }) => {
  return (
    <AntCard
      bordered={false}
      style={{
        borderRadius: 8,
        boxShadow: '0 2px 8px rgba(0, 0, 0, 0.06)',
        ...props.style,
      }}
      {...props}
    >
      {children}
    </AntCard>
  );
};

export default Card;
