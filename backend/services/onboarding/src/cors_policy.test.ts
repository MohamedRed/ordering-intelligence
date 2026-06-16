import { buildCorsOptions, resolveCorsOrigins } from './cors_policy';

describe('onboarding CORS policy', () => {
  it('requires explicit origins', () => {
    expect(() => resolveCorsOrigins('', 'development')).toThrow(/CORS_ORIGINS is required/);
  });

  it('rejects wildcard origins in staging and production', () => {
    expect(() => resolveCorsOrigins('*', 'staging')).toThrow(/Wildcard CORS origins are not allowed/);
    expect(() => resolveCorsOrigins('https://admin.example.com,*', 'prod')).toThrow(
      /Wildcard CORS origins are not allowed/,
    );
  });

  it('normalizes and de-duplicates origin URLs', () => {
    expect(
      resolveCorsOrigins(
        'https://admin.example.com/,https://admin.example.com,http://localhost:4000',
        'development',
      ),
    ).toEqual(['https://admin.example.com', 'http://localhost:4000']);
  });

  it('rejects paths and unsupported schemes', () => {
    expect(() => resolveCorsOrigins('https://admin.example.com/onboarding', 'development')).toThrow(
      /Include only scheme, host, and optional port/,
    );
    expect(() => resolveCorsOrigins('file://admin.example.com', 'development')).toThrow(
      /Only http and https origins are supported/,
    );
  });

  it('allows configured origins and rejects unknown browser origins', async () => {
    const originHandler = buildCorsOptions(['https://admin.example.com']).origin;
    expect(typeof originHandler).toBe('function');
    if (typeof originHandler !== 'function') throw new Error('origin handler is not callable');

    await expect(
      new Promise((resolve, reject) => {
        originHandler('https://admin.example.com', (error, allowed) => {
          if (error) reject(error);
          else resolve(allowed);
        });
      }),
    ).resolves.toBe(true);

    await expect(
      new Promise((resolve, reject) => {
        originHandler(undefined, (error, allowed) => {
          if (error) reject(error);
          else resolve(allowed);
        });
      }),
    ).resolves.toBe(true);

    await expect(
      new Promise((resolve, reject) => {
        originHandler('https://unknown.example.com', (error) => {
          if (error) reject(error);
          else resolve(true);
        });
      }),
    ).rejects.toThrow(/CORS blocked/);
  });
});
