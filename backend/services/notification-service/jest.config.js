const { createDefaultPreset } = require("ts-jest");

const tsJestTransformCfg = createDefaultPreset().transform;

/** @type {import("jest").Config} **/
module.exports = {
  testEnvironment: "node",
  transform: {
    ...tsJestTransformCfg,
  },
  collectCoverage: true,
  coverageThreshold: {
    global: {
      branches: 25,
      functions: 38,
      lines: 42,
      statements: 42,
    },
  },
};
