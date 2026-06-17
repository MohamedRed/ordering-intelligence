import fs from "fs";
import os from "os";
import path from "path";
import { parseServiceAccount } from "../src/firebase_init";

describe("firebase initialization helpers", () => {
  it("parses service account JSON provided inline", () => {
    expect(parseServiceAccount('{"project_id":"demo","client_email":"demo@example.com"}')).toEqual({
      project_id: "demo",
      client_email: "demo@example.com"
    });
  });

  it("parses service account JSON from a file path", () => {
    const dir = fs.mkdtempSync(path.join(os.tmpdir(), "notification-service-account-"));
    const file = path.join(dir, "service-account.json");
    fs.writeFileSync(file, '{"project_id":"demo-file"}', "utf-8");

    expect(parseServiceAccount(file)).toEqual({ project_id: "demo-file" });
  });
});
