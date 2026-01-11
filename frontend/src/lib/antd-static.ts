import { MessageInstance } from 'antd/es/message/interface';
import { ModalStaticFunctions } from 'antd/es/modal/confirm';
import { NotificationInstance } from 'antd/es/notification/interface';

let message: MessageInstance;
let notification: NotificationInstance;
let modal: ModalStaticFunctions;

export const setGlobalInstances = (
  msg: MessageInstance,
  not: NotificationInstance,
  mod: ModalStaticFunctions
) => {
  message = msg;
  notification = not;
  modal = mod;
};

export { message, notification, modal };
