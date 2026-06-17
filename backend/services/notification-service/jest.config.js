const { createDefaultPreset } = require("ts-jest");

const tsJestTransformCfg = createDefaultPreset().transform;

/** @type {import("jest").Config} **/
module.exports = {
  testEnvironment: "node",
  transform: {
    ...tsJestTransformCfg,
  },
  coveragePathIgnorePatterns: ["/node_modules/", "/tests/support/"],
  collectCoverage: true,
  coverageThreshold: {
    global: {
      branches: 26,
      functions: 40,
      lines: 34,
      statements: 32,
    },
  },
};
