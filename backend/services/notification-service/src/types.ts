export interface NotificationConfig {
  PORT: number;
  ENVIRONMENT: string;
  CORS_ORIGINS?: string;
  FIREBASE_PROJECT_ID: string;
  FIREBASE_SERVICE_ACCOUNT: string;
  TWILIO_ACCOUNT_SID?: string;
  TWILIO_AUTH_TOKEN?: string;
  TWILIO_MESSAGING_NUMBER?: string;
  SENDGRID_API_KEY?: string;
  SENDGRID_FROM_EMAIL?: string;
  ALERT_TOPIC?: string;
  OPS_PHONE?: string;
  OPS_EMAIL?: string;
  CUSTOMER_PROFILE_SERVICE_URL?: string;
  ORDERS_EVENTS_OIDC_AUDIENCE?: string;
  DISPATCH_EVENTS_OIDC_AUDIENCE?: string;
  DELIVERIES_EVENTS_OIDC_AUDIENCE?: string;
  EVENTS_OIDC_ALLOWED_EMAILS?: string;
  INTERNAL_AUTH_AUDIENCE?: string;
  INTERNAL_ALLOWED_EMAILS?: string;
  ELEVENLABS_API_KEY?: string;
  ELEVENLABS_API_BASE_URL?: string;
  NOTIFICATIONS_DRY_RUN?: string;
  NOTIFICATION_SERVICE_URL?: string;
  CLOUD_TASKS_PROJECT_ID?: string;
  CLOUD_TASKS_LOCATION?: string;
  CLOUD_TASKS_READY_ESCALATION_QUEUE?: string;
  CLOUD_TASKS_OIDC_SERVICE_ACCOUNT_EMAIL?: string;
  CLOUD_TASKS_OIDC_AUDIENCE?: string;
  CLOUD_TASKS_OIDC_ALLOWED_EMAILS?: string;
}

export interface NotificationPayload {
  title: string;
  body: string;
  data?: Record<string, string>;
}

export interface NotifyRequest {
  channel: Array<"push" | "sms" | "email">;
  target: {
    deviceTokens?: string[];
    topic?: string;
    phoneNumber?: string;
    email?: string;
  };
  payload: NotificationPayload;
}

export type NotifyMode = "auto" | "sms" | "call" | "none";

export type PubSubPushEnvelope = {
  message?: { data?: string; messageId?: string };
  subscription?: string;
};

export type OrderStatusChange = {
  previousStatus?: string;
  newStatus?: string;
  changedAt?: string;
  changedBy?: string;
  notifyMode?: NotifyMode;
  note?: string;
  templateId?: string;
};

export type OrderEvent = {
  id: string;
  storeId: string;
  status: string;
  tenantId?: string;
  customerId?: string;
  callerId?: string;
  customerName?: string;
  totalCents?: number;
  createdAt?: string;
  statusChange?: OrderStatusChange;
};

export type OrderCustomerComms = {
  kind: "delay";
  notifyMode?: NotifyMode;
  note?: string;
  templateId?: string;
};

export type OrdersEventEnvelope =
  | { kind: "order_customer_comms"; order: OrderEvent; comms: OrderCustomerComms; createdAt?: string }
  | { kind: string; order: OrderEvent; [k: string]: unknown };

export type DispatchEvent = {
  kind: string;
  storeId: string;
  orderId?: string;
  assignmentId?: string;
  offerId?: string;
  driverId?: string;
  routeId?: string;
  createdAt?: string;
  payload?: Record<string, unknown>;
};

export type DeliveryEvent = {
  kind: string;
  storeId: string;
  orderId?: string;
  deliveryId?: string;
  provider?: string;
  status?: string;
  createdAt?: string;
  payload?: Record<string, unknown>;
};

export type StoreOrderCommsTemplate = { id: string; label?: string; body?: string };

export type StoreOrderCommsStatus = {
  default_channel?: "sms" | "call" | "none";
  default_template_id?: string;
  templates?: StoreOrderCommsTemplate[];
};

export type StoreOrderComms = {
  statuses?: Record<string, StoreOrderCommsStatus>;
  ready_escalation_enabled?: boolean;
  ready_escalation_minutes?: number;
  ready_escalation_channel?: "call" | "sms" | "none";
  rate_limit_per_hour?: number;
  arriving_soon_enabled?: boolean;
  arriving_soon_eta_threshold_minutes?: number;
};

export type StoreDeliveryComms = StoreOrderComms;

export type StoreDoc = {
  name?: string;
  twilio_number?: string;
  tenant_id?: string;
  store_id?: string;
  order_comms?: StoreOrderComms;
  delivery_comms?: StoreDeliveryComms;
  elevenlabs_agent_id?: string;
  elevenlabs_agent_template_id?: string;
  elevenlabs_phone_number_id?: string;
  elevenlabs_variables?: Record<string, unknown>;
};
