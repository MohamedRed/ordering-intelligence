import { resolveMenuObjectMimeType } from '../../src/services/menu_object_mime';

describe('resolveMenuObjectMimeType', () => {
  it.each([
    ['menu-raw/store/job/page-1.jpg', 'image/jpeg'],
    ['menu-raw/store/job/page-1.jpeg', 'image/jpeg'],
    ['menu-raw/store/job/page-1.PNG', 'image/png'],
    ['menu-raw/store/job/page-1.webp', 'image/webp'],
    ['menu-raw/store/job/menu.pdf', 'application/pdf'],
  ])('maps %s to %s', (object, expected) => {
    expect(resolveMenuObjectMimeType(object)).toBe(expected);
  });

  it('rejects unsupported extensions', () => {
    expect(() => resolveMenuObjectMimeType('menu-raw/store/job/page-1.txt')).toThrow(
      'unsupported menu upload file type',
    );
  });
});
