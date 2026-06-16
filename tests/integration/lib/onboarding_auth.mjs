import { getIdentityToken } from './gcloud_tokens.mjs';

export const getOnboardingAuthHeaders = (baseUrl) => ({
  Authorization: `Bearer ${getIdentityToken(baseUrl.replace(/\/$/, ''))}`,
});
