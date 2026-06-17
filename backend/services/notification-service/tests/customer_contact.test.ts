import { resolveCustomerContact } from "../src/customer_contact";

const config = {
  CUSTOMER_PROFILE_SERVICE_URL: "https://customer-profile.example.com/"
};

describe("customer contact lookup", () => {
  it("uses customer-profile service when tenant context is available", async () => {
    const request = jest.fn(async () => ({
      data: { phoneE164: " +15551234567 ", customerName: " Test Customer " }
    }));
    const auth = {
      getIdTokenClient: jest.fn(async () => ({ request }))
    };

    await expect(
      resolveCustomerContact(auth, config, {
        tenantId: "tenant 1",
        callerId: "+15550000000"
      })
    ).resolves.toEqual({
      phoneE164: "+15551234567",
      customerName: "Test Customer"
    });

    expect(auth.getIdTokenClient).toHaveBeenCalledWith("https://customer-profile.example.com");
    expect(request).toHaveBeenCalledWith({
      method: "GET",
      url: "https://customer-profile.example.com/v1/customers/contact?tenantId=tenant%201&callerId=%2B15550000000"
    });
  });

  it("uses direct caller contact when profile lookup context is unavailable", async () => {
    const auth = {
      getIdTokenClient: jest.fn()
    };

    await expect(
      resolveCustomerContact(auth as any, { CUSTOMER_PROFILE_SERVICE_URL: "" }, {
        tenantId: "tenant-1",
        callerId: "+15550000000"
      })
    ).resolves.toEqual({ phoneE164: "+15550000000", customerName: "" });

    await expect(
      resolveCustomerContact(auth as any, config, {
        tenantId: "",
        callerId: "+15550000001"
      })
    ).resolves.toEqual({ phoneE164: "+15550000001", customerName: "" });
    expect(auth.getIdTokenClient).not.toHaveBeenCalled();
  });

  it("does not mask customer-profile lookup failures", async () => {
    const auth = {
      getIdTokenClient: jest.fn(async () => ({
        request: jest.fn(async () => {
          throw new Error("profile unavailable");
        })
      }))
    };

    await expect(
      resolveCustomerContact(auth, config, {
        tenantId: "tenant-1",
        callerId: "+15550000000"
      })
    ).rejects.toThrow("profile unavailable");
  });

  it("returns null when no caller id is available", async () => {
    const auth = {
      getIdTokenClient: jest.fn()
    };

    await expect(
      resolveCustomerContact(auth as any, config, {
        tenantId: "tenant-1",
        callerId: " "
      })
    ).resolves.toBeNull();
  });
});
