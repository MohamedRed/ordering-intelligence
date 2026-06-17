import { resolveOnboardingStripeConfig } from './stripe_config';

describe('onboarding stripe config', () => {
  it('requires all Stripe keys in staging and production', () => {
    expect(() =>
      resolveOnboardingStripeConfig({
        ENVIRONMENT: 'staging',
      } as NodeJS.ProcessEnv),
    ).toThrow(/STRIPE_SECRET_KEY, STRIPE_WEBHOOK_SECRET, STRIPE_PUBLISHABLE_KEY/);

    expect(() =>
      resolveOnboardingStripeConfig({
        ENVIRONMENT: 'prod',
        STRIPE_SECRET_KEY: 'sk_live_test',
        STRIPE_PUBLISHABLE_KEY: 'pk_live_test',
      } as NodeJS.ProcessEnv),
    ).toThrow(/STRIPE_WEBHOOK_SECRET is required/);
  });

  it('trims configured values and accepts complete strict config', () => {
    expect(
      resolveOnboardingStripeConfig({
        ENVIRONMENT: 'production',
        STRIPE_SECRET_KEY: ' sk_live_test ',
        STRIPE_WEBHOOK_SECRET: ' whsec_test ',
        STRIPE_PUBLISHABLE_KEY: ' pk_live_test ',
      } as NodeJS.ProcessEnv),
    ).toEqual({
      strictEnvironment: true,
      secretKey: 'sk_live_test',
      webhookSecret: 'whsec_test',
      publishableKey: 'pk_live_test',
    });
  });

  it('allows partial local config for developer workflows', () => {
    expect(
      resolveOnboardingStripeConfig({
        ENVIRONMENT: 'development',
        STRIPE_SECRET_KEY: 'sk_test_local',
      } as NodeJS.ProcessEnv),
    ).toMatchObject({
      strictEnvironment: false,
      secretKey: 'sk_test_local',
      webhookSecret: '',
      publishableKey: '',
    });
  });
});
