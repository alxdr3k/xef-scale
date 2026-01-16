import React, { createContext, useContext, useState, useEffect } from 'react';
import type { ReactNode } from 'react';
import { getWorkspaces } from '../api/workspaces';
import type { Workspace } from '../types';
import { useAuth } from './AuthContext';

interface WorkspaceContextType {
  currentWorkspace: Workspace | null;
  workspaces: Workspace[];
  loading: boolean;
  switchWorkspace: (workspaceId: number) => void;
  refreshWorkspaces: () => Promise<void>;
}

const WorkspaceContext = createContext<WorkspaceContextType | undefined>(undefined);

export const useWorkspace = () => {
  const context = useContext(WorkspaceContext);
  if (!context) {
    throw new Error('useWorkspace must be used within WorkspaceProvider');
  }
  return context;
};

interface WorkspaceProviderProps {
  children: ReactNode;
}

const STORAGE_KEY = 'selectedWorkspaceId';

export const WorkspaceProvider: React.FC<WorkspaceProviderProps> = ({ children }) => {
  const { isAuthenticated } = useAuth();
  const [workspaces, setWorkspaces] = useState<Workspace[]>([]);
  const [currentWorkspace, setCurrentWorkspace] = useState<Workspace | null>(null);
  const [loading, setLoading] = useState(true);

  // Fetch workspaces and restore selected workspace from localStorage
  useEffect(() => {
    // Only fetch workspaces if user is authenticated
    if (!isAuthenticated) {
      // Clear workspace data when user logs out
      setWorkspaces([]);
      setCurrentWorkspace(null);
      setLoading(false);
      return;
    }

    const initWorkspaces = async () => {
      try {
        const fetchedWorkspaces = await getWorkspaces();
        setWorkspaces(fetchedWorkspaces);

        // Try to restore selected workspace from localStorage
        const savedWorkspaceId = localStorage.getItem(STORAGE_KEY);

        if (savedWorkspaceId) {
          const savedWorkspace = fetchedWorkspaces.find(
            (ws) => ws.id === parseInt(savedWorkspaceId, 10)
          );

          if (savedWorkspace) {
            setCurrentWorkspace(savedWorkspace);
          } else {
            // Saved workspace not found, auto-select first workspace
            selectFirstWorkspace(fetchedWorkspaces);
          }
        } else {
          // No saved workspace, auto-select first workspace
          selectFirstWorkspace(fetchedWorkspaces);
        }
      } catch (error) {
        console.error('Failed to fetch workspaces:', error);
        // Don't crash the app, just log the error
        // The loading state will be set to false below
      } finally {
        setLoading(false);
      }
    };

    initWorkspaces();
  }, [isAuthenticated]);

  // Helper function to select the first workspace
  const selectFirstWorkspace = (workspaceList: Workspace[]) => {
    if (workspaceList.length > 0) {
      const firstWorkspace = workspaceList[0];
      setCurrentWorkspace(firstWorkspace);
      localStorage.setItem(STORAGE_KEY, firstWorkspace.id.toString());
    }
  };

  // Switch to a different workspace
  const switchWorkspace = (workspaceId: number) => {
    const workspace = workspaces.find((ws) => ws.id === workspaceId);

    if (workspace) {
      setCurrentWorkspace(workspace);
      localStorage.setItem(STORAGE_KEY, workspaceId.toString());
    } else {
      console.error(`Workspace with id ${workspaceId} not found`);
    }
  };

  // Refresh workspaces from API
  const refreshWorkspaces = async () => {
    // Only refresh if user is authenticated
    if (!isAuthenticated) {
      return;
    }

    try {
      setLoading(true);
      const fetchedWorkspaces = await getWorkspaces();
      setWorkspaces(fetchedWorkspaces);

      // Update current workspace if it still exists
      if (currentWorkspace) {
        const updatedCurrent = fetchedWorkspaces.find(
          (ws) => ws.id === currentWorkspace.id
        );

        if (updatedCurrent) {
          setCurrentWorkspace(updatedCurrent);
        } else {
          // Current workspace no longer exists, select first available
          selectFirstWorkspace(fetchedWorkspaces);
        }
      } else {
        // No current workspace, auto-select first
        selectFirstWorkspace(fetchedWorkspaces);
      }
    } catch (error) {
      console.error('Failed to refresh workspaces:', error);
      throw error; // Re-throw so caller can handle if needed
    } finally {
      setLoading(false);
    }
  };

  const value: WorkspaceContextType = {
    currentWorkspace,
    workspaces,
    loading,
    switchWorkspace,
    refreshWorkspaces,
  };

  return <WorkspaceContext.Provider value={value}>{children}</WorkspaceContext.Provider>;
};
