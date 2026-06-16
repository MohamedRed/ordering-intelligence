import sharp from 'sharp';
import {
  assessMenuImageBuffer,
  ImageQualityError,
  loadImageQualityLimits,
} from '../../src/services/image_quality';

async function menuLikeImage(width = 900, height = 1200): Promise<Buffer> {
  const svg = `
    <svg width="${width}" height="${height}">
      <rect x="40" y="40" width="${width - 80}" height="140" fill="#222"/>
      <text x="70" y="120" font-size="42" fill="#fff">Menu</text>
      <text x="80" y="280" font-size="32" fill="#111">Cheeseburger</text>
      <text x="${width - 220}" y="280" font-size="32" fill="#111">$9.99</text>
      <text x="80" y="380" font-size="32" fill="#111">Fries</text>
      <text x="${width - 220}" y="380" font-size="32" fill="#111">$3.49</text>
    </svg>
  `;
  return sharp({
    create: {
      width,
      height,
      channels: 3,
      background: { r: 248, g: 246, b: 240 },
    },
  })
    .composite([{ input: Buffer.from(svg) }])
    .jpeg({ quality: 90 })
    .toBuffer();
}

describe('image quality validation', () => {
  it('loads default limits and rejects invalid overrides', () => {
    expect(loadImageQualityLimits({} as NodeJS.ProcessEnv)).toMatchObject({
      minShortEdge: 600,
      minLongEdge: 800,
      maxPixels: 25_000_000,
      minLaplacianVariance: 25,
    });
    expect(() =>
      loadImageQualityLimits({ MENU_MIN_IMAGE_SHORT_EDGE: '0' } as NodeJS.ProcessEnv),
    ).toThrow(/MENU_MIN_IMAGE_SHORT_EDGE must be a positive number/);
  });

  it('accepts a readable menu-like image', async () => {
    const report = await assessMenuImageBuffer(await menuLikeImage(), 'menu.jpg');
    expect(report.width).toBe(900);
    expect(report.height).toBe(1200);
    expect(report.laplacianVariance).toBeGreaterThan(25);
  });

  it('rejects low-resolution images', async () => {
    await expect(assessMenuImageBuffer(await menuLikeImage(300, 300), 'small.jpg')).rejects.toMatchObject({
      code: 'low_resolution_image',
    } satisfies Partial<ImageQualityError>);
  });

  it('rejects blurry images', async () => {
    const blurred = await sharp(await menuLikeImage()).blur(12).jpeg().toBuffer();
    await expect(assessMenuImageBuffer(blurred, 'blurred.jpg')).rejects.toMatchObject({
      code: 'blurry_image',
    } satisfies Partial<ImageQualityError>);
  });

  it('rejects unreadable images', async () => {
    await expect(assessMenuImageBuffer(Buffer.from('not an image'), 'bad.txt')).rejects.toMatchObject({
      code: 'invalid_image',
    } satisfies Partial<ImageQualityError>);
  });
});
