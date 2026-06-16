type FirebaseAuth = {
  verifyIdToken(token: string): Promise<Record<string, unknown>>;
};

let authPromise: Promise<FirebaseAuth> | undefined;

export async function verifyFirebaseIdToken(
  token: string,
  projectId: string,
): Promise<Record<string, unknown>> {
  const auth = await loadFirebaseAuth(projectId);
  return auth.verifyIdToken(token);
}

async function loadFirebaseAuth(projectId: string): Promise<FirebaseAuth> {
  if (!authPromise) {
    authPromise = initializeFirebaseAuth(projectId);
  }
  return authPromise;
}

async function initializeFirebaseAuth(projectId: string): Promise<FirebaseAuth> {
  const appModule = 'firebase-admin/app';
  const authModule = 'firebase-admin/auth';
  const app = await import(appModule);
  const auth = await import(authModule);
  if (!app.getApps().length) {
    app.initializeApp({
      credential: app.applicationDefault(),
      projectId: projectId || undefined,
    });
  }
  return auth.getAuth() as FirebaseAuth;
}
