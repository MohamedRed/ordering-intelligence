import { slugifyName, ordinal, parseGsUri } from '../src/utils';

describe('utils', () => {
  it('slugifyName lowercases and replaces non-alnum', () => {
    expect(slugifyName('Spicy Taco #1!')).toBe('spicy_taco_1');
    expect(slugifyName('___')).toBe('item'); // fallback when empty after cleanup
  });

  it('ordinal formats english ordinals', () => {
    expect(ordinal(1)).toBe('1st');
    expect(ordinal(2)).toBe('2nd');
    expect(ordinal(3)).toBe('3rd');
    expect(ordinal(4)).toBe('4th');
    expect(ordinal(11)).toBe('11th');
    expect(ordinal(22)).toBe('22nd');
  });

  it('parseGsUri splits bucket and object', () => {
    const { bucket, object } = parseGsUri('gs://my-bucket/path/to/file.png');
    expect(bucket).toBe('my-bucket');
    expect(object).toBe('path/to/file.png');
  });
});
