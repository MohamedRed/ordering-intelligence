export type StripeEmbedPageOptions = {
  publishableKey: string;
  fetchClientSecretUrl: string;
  title: string;
  subtitle: string;
};

const jsEscape = (value: string): string =>
  value.replace(/\\/g, '\\\\').replace(/'/g, "\\'");

export const buildStripeEmbedHtml = (opts: StripeEmbedPageOptions) => {
  const publishableKey = jsEscape(opts.publishableKey);
  const fetchUrl = jsEscape(opts.fetchClientSecretUrl);
  const title = jsEscape(opts.title);
  const subtitle = jsEscape(opts.subtitle);
  return `<!doctype html>
<html lang="en">
<head>
  <meta charset="utf-8" />
  <meta name="viewport" content="width=device-width, initial-scale=1" />
  <title>${title}</title>
  <style>
    body { font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", sans-serif; margin: 0; background: #f6f7fb; }
    .container { max-width: 920px; margin: 0 auto; padding: 24px; }
    #connect-root { background: #fff; border-radius: 16px; padding: 16px; box-shadow: 0 12px 30px rgba(0,0,0,0.08); }
    .header { padding: 24px 24px 0; }
    .header h1 { margin: 0 0 8px; font-size: 22px; }
    .header p { margin: 0 0 16px; color: #5a5a5a; }
    .error { color: #b42318; padding: 16px; }
  </style>
  <script src="https://connect-js.stripe.com/v1.0/connect.js" async></script>
</head>
<body>
  <div class="header">
    <h1>${title}</h1>
    <p>${subtitle}</p>
  </div>
  <div class="container">
    <div id="connect-root"></div>
  </div>
  <script>
    const publishableKey = '${publishableKey}';
    const fetchUrl = '${fetchUrl}';

    const fetchClientSecret = async () => {
      const response = await fetch(fetchUrl, {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
      });
      const payload = await response.json().catch(() => ({}));
      if (!response.ok || !payload.client_secret) {
        throw new Error(payload.error || 'session_failed');
      }
      return payload.client_secret;
    };

    window.StripeConnect = window.StripeConnect || {};
    window.StripeConnect.onLoad = () => {
      try {
        if (!publishableKey) {
          document.getElementById('connect-root').innerHTML = '<div class="error">Stripe publishable key not configured.</div>';
          return;
        }
        const stripeConnectInstance = window.StripeConnect.init({
          publishableKey: publishableKey,
          fetchClientSecret: fetchClientSecret,
        });
        const onboarding = stripeConnectInstance.create('account-onboarding');
        onboarding.mount('#connect-root');
      } catch (err) {
        document.getElementById('connect-root').innerHTML = '<div class="error">Unable to load Stripe onboarding.</div>';
      }
    };
  </script>
</body>
</html>`;
};
