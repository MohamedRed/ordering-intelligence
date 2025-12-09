import crypto from 'node:crypto';

export interface OrderItem {
  orderId: string;
  name: string;
  price?: number;
  details?: Record<string, unknown>;
}

export class OrderState {
  private items: Map<string, OrderItem> = new Map();

  add(name: string, price?: number, details?: Record<string, unknown>): OrderItem {
    const orderId = this.generateId();
    const item: OrderItem = { orderId, name, price, details };
    this.items.set(orderId, item);
    return item;
  }

  remove(orderId: string): OrderItem | undefined {
    const item = this.items.get(orderId);
    if (item) {
      this.items.delete(orderId);
    }
    return item;
  }

  list(): OrderItem[] {
    return Array.from(this.items.values());
  }

  total(): number {
    return this.list()
      .map((item) => item.price ?? 0)
      .reduce((sum, price) => sum + price, 0);
  }

  clear(): void {
    this.items.clear();
  }

  private generateId(): string {
    return `oi_${crypto.randomBytes(3).toString('hex')}`;
  }
}

export interface CheckoutSummary {
  items: OrderItem[];
  totalPrice: number;
}

export function formatOrderSummary(state: OrderState): CheckoutSummary {
  const items = state.list();
  const totalPrice = state.total();
  return { items, totalPrice };
}
