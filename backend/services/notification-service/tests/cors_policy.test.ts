import {
  buildNotificationCorsOptions,
  DEFAULT_NOTIFICATION_CORS_ORIGINS,
  resolveNotificationCorsOrigins
} from "../src/cors_policy";

describe("notification CORS policy", () => {
  it("uses local origins by default outside production-like environments", () => {
    expect(resolveNotificationCorsOrigins("", "test")).toEqual(DEFAULT_NOTIFICATION_CORS_ORIGINS);
  });

  it("normalizes and deduplicates explicit origins", () => {
    expect(
      resolveNotificationCorsOrigins("https://admin.example.com/, https://admin.example.com", "dev")
    ).toEqual(["https://admin.example.com"]);
  });

  it("requires explicit origins in staging and production", () => {
    expect(() => resolveNotificationCorsOrigins("", "staging")).toThrow(/required/);
    expect(() => resolveNotificationCorsOrigins("", "production")).toThrow(/required/);
  });

  it("rejects wildcard origins in production-like environments", () => {
    expect(() => resolveNotificationCorsOrigins("*", "prod")).toThrow(/Wildcard/);
  });

  it("rejects origins with paths", () => {
    expect(() => resolveNotificationCorsOrigins("https://admin.example.com/app", "dev")).toThrow(
      /scheme, host, and optional port/
    );
  });

  it("blocks unlisted browser origins", (done) => {
    const options = buildNotificationCorsOptions(["https://admin.example.com"]);
    expect(typeof options.origin).toBe("function");
    if (typeof options.origin !== "function") {
      done.fail("origin callback missing");
      return;
    }
    options.origin("https://other.example.com", (err) => {
      expect(err).toBeInstanceOf(Error);
      done();
    });
  });
});
