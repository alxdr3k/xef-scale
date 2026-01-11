// Antd v6 compatible types
type MessageInstance = any;
type NotificationInstance = any;
type ModalStaticFunctions = any;

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
