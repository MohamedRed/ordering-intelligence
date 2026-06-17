import {
  isAllowedMenuFlyerContentType,
  resolveMenuFlyerMediaFromFilename,
  resolveMenuFlyerMediaFromUrl,
} from './menu_flyer_media';

describe('menu flyer media helpers', () => {
  it.each([
    ['menu.jpg', { extension: 'jpg', contentType: 'image/jpeg' }],
    ['menu.jpeg', { extension: 'jpeg', contentType: 'image/jpeg' }],
    ['menu.PNG', { extension: 'png', contentType: 'image/png' }],
    ['menu.webp', { extension: 'webp', contentType: 'image/webp' }],
  ])('resolves %s', (filename, expected) => {
    expect(resolveMenuFlyerMediaFromFilename(filename)).toEqual(expected);
  });

  it('resolves signed or public GCS URLs from their path extension', () => {
    expect(resolveMenuFlyerMediaFromUrl('https://storage.googleapis.com/b/menu-flyers/a.png?x=1')).toEqual({
      extension: 'png',
      contentType: 'image/png',
    });
  });

  it('rejects content type and extension mismatches', () => {
    expect(isAllowedMenuFlyerContentType('image/png', 'jpg')).toBe(false);
    expect(resolveMenuFlyerMediaFromFilename('menu.pdf')).toBeUndefined();
  });
});
