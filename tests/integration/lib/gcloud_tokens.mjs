import { execFileSync } from 'node:child_process';

const getImpersonateServiceAccount = () => {
  const account =
    process.env.GCLOUD_IMPERSONATE_SERVICE_ACCOUNT ||
    process.env.GOOGLE_IMPERSONATE_SERVICE_ACCOUNT ||
    process.env.GCP_SERVICE_ACCOUNT_EMAIL ||
    process.env.GOOGLE_SERVICE_ACCOUNT_EMAIL ||
    '';
  return account.trim();
};

export const getIdentityToken = (audience) => {
  if (!audience) {
    throw new Error('Missing audience for identity token');
  }
  const envToken =
    process.env.INTERNAL_AUTH_ID_TOKEN ||
    process.env.INTERNAL_IDENTITY_TOKEN ||
    process.env.IDENTITY_TOKEN ||
    '';
  if (envToken.trim()) {
    return envToken.trim();
  }
  try {
    const impersonate = getImpersonateServiceAccount();
    const args = ['auth', 'print-identity-token', `--audiences=${audience}`];
    if (impersonate) {
      args.push(`--impersonate-service-account=${impersonate}`);
    }
    const out = execFileSync(
      'gcloud',
      args,
      { encoding: 'utf8' },
    );
    return out.trim();
  } catch (err) {
    const stderr = err?.stderr?.toString?.() || '';
    const message = err?.message?.toString?.() || '';
    const combined = `${stderr}\n${message}`;
    if (
      combined.includes('Invalid account type for `--audiences`') ||
      combined.includes('Requires valid service account')
    ) {
      throw new Error(
        `Identity token unavailable for ${audience}. Ensure CI uses a service account or sets INTERNAL_AUTH_ID_TOKEN.`,
      );
    }
    throw err;
  }
};

export const getAccessToken = () => {
  const out = execFileSync(
    'gcloud',
    ['auth', 'print-access-token'],
    { encoding: 'utf8' },
  );
  return out.trim();
};
