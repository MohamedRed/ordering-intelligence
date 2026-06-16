"use strict";
Object.defineProperty(exports, "__esModule", { value: true });
const config_1 = require("../src/config");
describe("config", () => {
    const OLD_ENV = process.env;
    beforeEach(() => {
        process.env = { ...OLD_ENV };
    });
    afterEach(() => {
        process.env = OLD_ENV;
    });
    it("throws when required values are missing", () => {
        delete process.env.ORDER_SERVICE_URL;
        expect(() => (0, config_1.loadConfig)()).toThrow(/ORDER_SERVICE_URL/);
    });
    it("falls back to defaults", () => {
        process.env.ORDER_SERVICE_URL = "https://orders.example.com";
        const cfg = (0, config_1.loadConfig)();
        expect(cfg.environment).toBe("dev");
        expect(cfg.port).toBe(8080);
    });
    it("honours overrides", () => {
        process.env.ORDER_SERVICE_URL = "https://orders.example.com";
        process.env.ENVIRONMENT = "test";
        process.env.PORT = "9000";
        const cfg = (0, config_1.loadConfig)();
        expect(cfg.environment).toBe("test");
        expect(cfg.port).toBe(9000);
    });
});
