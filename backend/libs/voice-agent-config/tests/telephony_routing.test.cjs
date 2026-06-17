const assert = require("node:assert/strict");
const { test } = require("node:test");

const { loadTelephonyRouting } = require("../dist");

test("loadTelephonyRouting defaults to SIP trunk routing", () => {
  assert.deepEqual(
    loadTelephonyRouting({
      TELEPHONY_NUMBER: "+15551234567",
      TELEPHONY_DISPATCH_RULE_ID: "dispatch-rule-1",
    }),
    {
      provider: "sip-trunk",
      number: "+15551234567",
      dispatchRuleId: "dispatch-rule-1",
    }
  );
});

test("loadTelephonyRouting supports LiveKit PSTN routing", () => {
  assert.deepEqual(
    loadTelephonyRouting({
      TELEPHONY_PROVIDER: "us-livekit-pstn",
      TELEPHONY_NUMBER: "+15557654321",
      TELEPHONY_DISPATCH_RULE_ID: "dispatch-rule-2",
    }),
    {
      provider: "us-livekit-pstn",
      number: "+15557654321",
      dispatchRuleId: "dispatch-rule-2",
    }
  );
});

test("loadTelephonyRouting fails fast for unsupported providers", () => {
  assert.throws(
    () =>
      loadTelephonyRouting({
        TELEPHONY_PROVIDER: "unknown",
        TELEPHONY_NUMBER: "+15551234567",
        TELEPHONY_DISPATCH_RULE_ID: "dispatch-rule-1",
      }),
    /Unsupported TELEPHONY_PROVIDER/
  );
});

test("loadTelephonyRouting fails fast when required routing env is missing", () => {
  assert.throws(
    () =>
      loadTelephonyRouting({
        TELEPHONY_NUMBER: "+15551234567",
      }),
    /Missing required telephony routing env vars: TELEPHONY_DISPATCH_RULE_ID/
  );
});
