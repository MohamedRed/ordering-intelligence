export type ChannelContact = {
  channel?: string;
  accountId?: string;
  userId?: string;
  threadId?: string;
  displayName?: string;
  locale?: string;
  metadata?: Record<string, unknown>;
};
