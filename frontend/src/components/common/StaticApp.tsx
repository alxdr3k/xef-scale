import { App } from 'antd';
import { useEffect } from 'react';
import { setGlobalInstances } from '../../lib/antd-static';

const StaticApp = () => {
  const { message, notification, modal } = App.useApp();
  useEffect(() => {
    setGlobalInstances(message, notification, modal);
  }, [message, notification, modal]);
  return null;
};
export default StaticApp;
