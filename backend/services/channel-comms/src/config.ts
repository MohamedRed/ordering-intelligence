export interface ChannelCommsConfig {
  PORT: number;
  ENVIRONMENT: string;
  TELEGRAM_BOT_TOKEN?: string;
  TELEGRAM_API_BASE_URL?: string;
  DISCORD_BOT_TOKEN?: string;
  DISCORD_API_BASE_URL?: string;
}
