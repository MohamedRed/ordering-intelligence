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
      branches: 14,
      functions: 26,
      lines: 32,
      statements: 32,
    },
  },
};

module.exports = config;
