export type ChannelContact = {
  channel?: string;
  accountId?: string;
  userId?: string;
  displayName?: string;
  metadata?: Record<string, unknown>;
};

export type GroupOrderParticipant = {
  participantId: string;
  channelContact?: ChannelContact;
  displayName?: string;
};

export type GroupOrderAllocation = {
  participantId: string;
  subtotalCents: number;
  feeCents: number;
  taxCents: number;
  discountCents: number;
  totalCents: number;
};

export type GroupOrderPricing = {
  subtotalCents: number;
  taxCents: number;
  feeCents: number;
  discountCents: number;
  totalCents: number;
  allocations?: GroupOrderAllocation[];
};

export type GroupOrderSession = {
  id: string;
  tenantId: string;
  storeId: string;
  status: string;
  paymentMode?: string;
  host?: ChannelContact;
  participants?: GroupOrderParticipant[];
  pricing?: GroupOrderPricing;
  orderId?: string;
};

export type GroupOrderPayment = {
  paymentId: string;
  groupOrderId: string;
  participantId: string;
  amountCents: number;
  currency: string;
  status: "requires_payment" | "succeeded" | "failed" | "refunded" | "expired";
  stripeCheckoutSessionId?: string;
  stripePaymentIntentId?: string;
  refundedAmountCents?: number;
  refundReason?: string;
  refundNote?: string;
  refundRequestedBy?: string;
  refundType?: "refund" | "void";
  stripeRefundId?: string;
  refundedAt?: string;
  createdAt: string;
};

export type OrderRecord = {
  id: string;
  tenantId: string;
  storeId?: string;
  customerId?: string;
  customerName?: string;
  paymentMethod?: string;
  totalCents: number;
  fuelPaymentFlow?: string;
};

export type OrderPayment = {
  paymentId: string;
  orderId: string;
  amountCents: number;
  currency: string;
  status:
    | "requires_payment"
    | "requires_capture"
    | "succeeded"
    | "failed"
    | "refunded"
    | "expired";
  stripeCheckoutSessionId?: string;
  stripePaymentIntentId?: string;
  capturedAmountCents?: number;
  refundedAmountCents?: number;
  refundReason?: string;
  refundNote?: string;
  refundRequestedBy?: string;
  refundType?: "refund" | "void";
  stripeRefundId?: string;
  refundedAt?: string;
  createdAt: string;
};
