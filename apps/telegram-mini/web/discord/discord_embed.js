import { DiscordSDK } from '../discord-sdk/index.mjs';

const sdkCache = new Map();

function resolveParentOrigin() {
  try {
    const ancestors = window.location.ancestorOrigins;
    if (ancestors && ancestors.length) {
      return ancestors[0];
    }
  } catch (_) {}
  try {
    if (document.referrer) {
      return new URL(document.referrer).origin;
    }
  } catch (_) {}
  return '';
}

async function getSdk(clientId) {
  if (!clientId) {
    throw new Error('missing_client_id');
  }
  if (sdkCache.has(clientId)) {
    return sdkCache.get(clientId);
  }
  const sdk = new DiscordSDK(clientId);
  const parentOrigin = resolveParentOrigin();
  if (parentOrigin) {
    try {
      if (sdk.sourceOrigin !== parentOrigin) {
        sdk.sourceOrigin = parentOrigin;
        if (typeof sdk.handshake === 'function') {
          sdk.handshake();
        }
      }
    } catch (err) {
      console.warn('discord_sdk_origin_override_failed', err);
    }
  }
  try {
    await withTimeout(sdk.ready(), 15000, 'sdk_ready_timeout');
  } catch (err) {
    console.error('discord_sdk_ready_failed', err);
    throw err;
  }
  sdkCache.set(clientId, sdk);
  return sdk;
}

function resolveRedirectUri(explicitUri) {
  if (explicitUri && explicitUri.trim()) {
    return explicitUri.trim();
  }
  const url = new URL(window.location.href);
  return `${url.origin}${url.pathname}`;
}

function isDiscordContext() {
  const params = new URLSearchParams(window.location.search);
  const host = (window.location.hostname || '').toLowerCase();
  return (
    params.get('platform') === 'discord' ||
    params.has('frame_id') ||
    params.has('frameId') ||
    host.endsWith('discordsays.com')
  );
}

function withTimeout(promise, timeoutMs, label) {
  return Promise.race([
    promise,
    new Promise((_, reject) => {
      setTimeout(() => {
        reject(new Error(label || 'timeout'));
      }, timeoutMs);
    }),
  ]);
}

async function authorize(clientId, scopes, redirectUri) {
  const sdk = await getSdk(clientId);
  const finalScopes = Array.isArray(scopes) && scopes.length > 0 ? scopes : ['identify'];
  const payload = {
    client_id: clientId,
    response_type: 'code',
    scope: finalScopes,
  };
  let redirect = '';
  if (!isDiscordContext()) {
    redirect = resolveRedirectUri(redirectUri);
    payload.redirect_uri = redirect;
  }
  try {
    const auth = await withTimeout(
      sdk.commands.authenticate({}),
      8000,
      'authenticate_timeout',
    );
    if (auth && auth.access_token) {
      return {
        code: '',
        redirectUri: redirect,
        accessToken: auth.access_token,
      };
    }
  } catch (err) {
    console.warn('discord_authenticate_failed', err);
  }
  let code;
  try {
    const result = await withTimeout(
      sdk.commands.authorize(payload),
      15000,
      'authorize_timeout',
    );
    code = result.code;
  } catch (err) {
    console.error('discord_authorize_failed', err);
    throw err;
  }
  if (!code) {
    console.error('discord_authorize_missing_code');
  }
  return { code, redirectUri: redirect, accessToken: '' };
}

window.DiscordWebApp = {
  isAvailable() {
    return isDiscordContext();
  },
  authorize,
};
