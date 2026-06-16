export async function withTimeout<T>(
  promise: Promise<T>,
  ms: number,
  label: string,
): Promise<T> {
  let timeout: NodeJS.Timeout;
  const wrapped = new Promise<never>((_, reject) => {
    timeout = setTimeout(() => reject(new Error(`${label} timed out after ${ms}ms`)), ms);
  });
  try {
    return await Promise.race([promise, wrapped]);
  } finally {
    clearTimeout(timeout!);
  }
}
