import { execFileSync } from 'node:child_process';

export const getIdentityToken = (audience) => {
  if (!audience) {
    throw new Error('Missing audience for identity token');
  }
  const out = execFileSync(
    'gcloud',
    ['auth', 'print-identity-token', `--audiences=${audience}`],
    { encoding: 'utf8' },
  );
  return out.trim();
};

export const getAccessToken = () => {
  const out = execFileSync(
    'gcloud',
    ['auth', 'print-access-token'],
    { encoding: 'utf8' },
  );
  return out.trim();
};
