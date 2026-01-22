export const getServerTimestamp = async (url, timeoutMs = 20000) => {
  const controller = new AbortController();
  const timeout = setTimeout(() => controller.abort(), timeoutMs);
  try {
    const res = await fetch(url, { signal: controller.signal });
    if (!res.ok) {
      throw new Error(`server time check failed: ${res.status}`);
    }
    const dateHeader = res.headers.get('date');
    if (!dateHeader) {
      throw new Error('server time check missing Date header.');
    }
    const date = new Date(dateHeader);
    if (Number.isNaN(date.getTime())) {
      throw new Error(`invalid Date header from server time check: ${dateHeader}`);
    }
    return Math.floor(date.getTime() / 1000);
  } finally {
    clearTimeout(timeout);
  }
};
