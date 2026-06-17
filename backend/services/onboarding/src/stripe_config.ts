export type OnboardingStripeConfig = {
  strictEnvironment: boolean;
  secretKey: string;
  webhookSecret: string;
  publishableKey: string;
};

function isStrictEnvironment(environment: string): boolean {
  return ['prod', 'production', 'staging'].includes(environment.trim().toLowerCase());
}

function readEnv(env: NodeJS.ProcessEnv, name: string): string {
  return (env[name] || '').trim();
}

export function resolveOnboardingStripeConfig(
  env: NodeJS.ProcessEnv = process.env,
): OnboardingStripeConfig {
  const environment = env.ENVIRONMENT || env.NODE_ENV || 'development';
  const strictEnvironment = isStrictEnvironment(environment);
  const config = {
    strictEnvironment,
    secretKey: readEnv(env, 'STRIPE_SECRET_KEY'),
    webhookSecret: readEnv(env, 'STRIPE_WEBHOOK_SECRET'),
    publishableKey: readEnv(env, 'STRIPE_PUBLISHABLE_KEY'),
  };

  if (strictEnvironment) {
    const missing = [
      ['STRIPE_SECRET_KEY', config.secretKey],
      ['STRIPE_WEBHOOK_SECRET', config.webhookSecret],
      ['STRIPE_PUBLISHABLE_KEY', config.publishableKey],
    ]
      .filter(([, value]) => !value)
      .map(([name]) => name);

    if (missing.length) {
      throw new Error(
        `${missing.join(', ')} ${missing.length === 1 ? 'is' : 'are'} required for onboarding-service in staging/production`,
      );
    }
  }

  return config;
}
