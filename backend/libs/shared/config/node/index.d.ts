export type ConfigValue = string | number | boolean | undefined;

export interface ConfigDefinition {
  readonly type: "string" | "number" | "boolean";
  readonly required?: boolean;
  readonly enum?: readonly string[];
  readonly default?: ConfigValue;
  readonly description?: string;
  readonly sensitive?: boolean;
  readonly env?: string;
}

export type ServiceSchema = Record<string, ConfigDefinition>;

export interface ConfigSchema {
  readonly [serviceName: string]: ServiceSchema;
}

export interface LoadOptions {
  env?: Record<string, string | undefined>;
}

export function loadConfig<T extends Record<string, ConfigValue>>(
  serviceName: string,
  options?: LoadOptions
): T;

export function getSchema(): ConfigSchema;
