import { mapDraftItemsToOrderServiceMenu } from '../../src/services/order-service-sync';

describe('order-service sync mapper', () => {
  it('maps basic fields and sizes to modifiers', () => {
    const draft = {
      jobId: 'j1',
      restaurantId: 'store-1',
      items: [
        {
          id: 'burger',
          name: 'Burger',
          price: 9.5,
          category: 'mains',
          available: true,
          sizes: ['Small', 'Large'],
          allergens: ['gluten'],
        },
      ],
      ocrLines: [],
      createdAt: 0,
      updatedAt: 0,
    };

    const res = mapDraftItemsToOrderServiceMenu(draft as any);
    expect(res.storeId).toBe('store-1');
    expect(res.items[0]).toMatchObject({
      id: 'burger',
      name: 'Burger',
      priceCents: 950,
      category: 'mains',
      modifiers: [
        { name: 'Small', priceCents: 0 },
        { name: 'Large', priceCents: 0 },
      ],
      description: 'Allergens: gluten',
    });
  });

  it('fills defaults when optional fields missing', () => {
    const draft = {
      jobId: 'j2',
      restaurantId: 'store-2',
      items: [
        {
          id: '',
          name: 'Nameless',
        },
      ],
      ocrLines: [],
      createdAt: 0,
      updatedAt: 0,
    };
    const res = mapDraftItemsToOrderServiceMenu(draft as any);
    expect(res.items[0].id).toBe('nameless');
    expect(res.items[0].category).toBe('uncategorized');
    expect(res.updatedAt instanceof Date).toBeTruthy();
  });
});
