import type { Timestamp } from '@google-cloud/firestore';

export type SessionStatus = 'collecting' | 'prefill_ready' | 'awaiting_kyc' | 'ingesting' | 'ready' | 'failed';

export interface OnboardingSession {
  status: SessionStatus;
  business?: {
    name?: string;
    address?: string;
    phone?: string;
    timezone?: string;
    type?: string;
    primaryContact?: string;
    currency?: string;
    fuel_default_prepay_cents?: number;
    fuelDefaultPrepayCents?: number;
  };
  flyers?: string[];
  prefill?: Record<string, any>;
  stripe?: {
    account_id?: string;
    status?: string;
    capabilities?: Record<string, any>;
  };
  twilio?: {
    number?: string;
    sid?: string;
    status?: string;
    elevenlabs_phone_number_id?: string;
  };
  ingestion?: {
    job_ids?: string[];
    status?: string;
    fast_ready?: boolean;
  };
  agent?: {
    template_agent_id?: string;
    business_type?: string;
    mode?: 'shared_template' | 'per_tenant';
    agent_id?: string;
    voice_id?: string;
    branch_id?: string;
    status?: string;
  };
  notifications?: {
    device_tokens?: string[];
    webhook_url?: string;
  };
  audit?: { ts: Timestamp; actor: string; event: string; data?: any }[];
  tenant?: {
    tenant_id?: string;
    store_id?: string;
  };
  created_at: Timestamp;
  updated_at: Timestamp;
}
