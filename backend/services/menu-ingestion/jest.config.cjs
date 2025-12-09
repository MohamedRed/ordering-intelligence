const config = {
  preset: 'ts-jest/presets/default-esm',
  testEnvironment: 'node',
  extensionsToTreatAsEsm: ['.ts'],
  moduleNameMapper: {
    '^(\\.{1,2}/.*)\\.js$': '$1',
  },
  transform: {
    '^.+\\.ts$': ['ts-jest', { useESM: true }],
  },
  collectCoverage: true,
  coverageThreshold: {
    global: {
      branches: 12,
      functions: 20,
      lines: 26,
      statements: 26,
    },
  },
};

module.exports = config;
