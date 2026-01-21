import { execFileSync } from 'node:child_process';

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
    const out = execFileSync(
      'gcloud',
      ['auth', 'print-identity-token', `--audiences=${audience}`],
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
      console.warn(
        `Skipping identity-token protected test: no service account available for ${audience}.`,
      );
      process.exit(0);
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
