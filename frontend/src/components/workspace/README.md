# Workspace Components

## WorkspaceSelector

A dropdown component for switching between workspaces. Designed for placement in the application's TopBar/Navbar.

### Features

- **Workspace Switching**: Select dropdown that allows users to switch between available workspaces
- **Role Badges**: Visual indicators for user's role in each workspace
- **Member Count**: Shows the number of members in each workspace
- **Loading State**: Displays spinner during workspace data fetch
- **Empty State**: Handles case when user has no workspaces
- **Responsive**: Compact design suitable for navbar placement

### Usage

```tsx
import { WorkspaceSelector } from '../components/workspace';

// In your TopBar or Navbar component
<WorkspaceSelector />
```

### Integration

The component uses `useWorkspace()` hook from `WorkspaceContext` and requires:
- `WorkspaceProvider` wrapping the application
- Valid workspace data from backend API

### Visual Design

**Role Badge Colors:**
- OWNER: Gold (#faad14) - "소유자"
- CO_OWNER: Blue (#1890ff) - "공동소유자"
- MEMBER_WRITE: Green (#52c41a) - "편집 가능"
- MEMBER_READ: Gray (#8c8c8c) - "읽기 전용"

**Layout:**
```
[Workspace Name] · [Role Badge] · [Member Count Icon]
```

**Dimensions:**
- Select width: 200px (minimum)
- Dropdown width: 280px (minimum)

### States

1. **Loading**: Shows spinner with "워크스페이스 로딩 중..."
2. **Empty**: Shows "사용 가능한 워크스페이스가 없습니다"
3. **Normal**: Shows workspace dropdown with all available workspaces

### Example Integration in TopBar

```tsx
import { WorkspaceSelector } from '../components/workspace';

const TopBar: React.FC = () => {
  return (
    <div style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'center' }}>
      <div style={{ display: 'flex', alignItems: 'center', gap: 16 }}>
        <div>지출 추적기</div>
        <WorkspaceSelector />
      </div>
      {/* User menu, etc. */}
    </div>
  );
};
```

### Dependencies

- `antd`: Select, Badge, Spin, Space, Tag components
- `@ant-design/icons`: UserOutlined icon
- `../../contexts/WorkspaceContext`: useWorkspace hook
- `../../types`: Workspace, WorkspaceRole types

### Accessibility

- Semantic HTML with proper ARIA attributes (provided by Ant Design Select)
- Keyboard navigation support
- Clear visual feedback for selected workspace

### Future Enhancements

- Add workspace search/filter for users with many workspaces
- Add workspace creation shortcut button
- Add workspace settings quick access
- Add recent workspaces section
