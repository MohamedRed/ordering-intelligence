import express from 'express';
import request from 'supertest';
import {
  assertMenuFlyerKey,
  registerMenuFlyerUploadRoutes,
  resolveMenuFlyerMaxUploadBytes,
  validateMenuFlyerUploadFile,
} from './menu_flyer_upload';

function makeBucket() {
  const saves: Array<{ key: string; buffer: Buffer; options: Record<string, unknown> }> = [];
  const deletes: string[] = [];
  const bucket = {
    name: 'test-bucket',
    file: (key: string) => ({
      save: async (buffer: Buffer, options: Record<string, unknown>) => {
        saves.push({ key, buffer, options });
      },
      delete: async () => {
        deletes.push(key);
      },
      getSignedUrl: async () => [`https://signed.example/${encodeURIComponent(key)}`] as [string],
    }),
  };
  return { bucket, saves, deletes };
}

describe('menu flyer upload routes', () => {
  it('validates allowed image types by MIME and extension', () => {
    expect(validateMenuFlyerUploadFile({ originalname: 'menu.jpg', mimetype: 'image/jpeg' })).toMatchObject({
      extension: 'jpg',
      contentType: 'image/jpeg',
    });
    expect(() =>
      validateMenuFlyerUploadFile({ originalname: 'menu.pdf', mimetype: 'application/pdf' }),
    ).toThrow(/JPEG, PNG, or WebP/);
    expect(() =>
      validateMenuFlyerUploadFile({ originalname: 'menu.jpg', mimetype: 'application/pdf' }),
    ).toThrow(/JPEG, PNG, or WebP/);
  });

  it('resolves upload size limits', () => {
    expect(resolveMenuFlyerMaxUploadBytes({ MENU_FLYER_MAX_UPLOAD_BYTES: '1234' } as NodeJS.ProcessEnv)).toBe(1234);
    expect(() =>
      resolveMenuFlyerMaxUploadBytes({ MENU_FLYER_MAX_UPLOAD_BYTES: '0' } as NodeJS.ProcessEnv),
    ).toThrow(/positive integer/);
  });

  it('accepts image uploads and saves sanitized menu-flyer keys', async () => {
    const { bucket, saves } = makeBucket();
    const app = express();
    registerMenuFlyerUploadRoutes({ app, bucket, makePublic: true, maxUploadBytes: 1024 });

    const res = await request(app)
      .post('/uploads/menu-flyer')
      .attach('file', Buffer.from('image-bytes'), {
        filename: '../menu photo.jpg',
        contentType: 'image/jpeg',
      })
      .expect(201);

    expect(res.body.key).toMatch(/^menu-flyers\/[a-f0-9-]+-menu-photo\.jpg$/);
    expect(res.body.contentType).toBe('image/jpeg');
    expect(saves).toHaveLength(1);
    expect(saves[0].options.contentType).toBe('image/jpeg');
  });

  it('rejects PDFs before saving', async () => {
    const { bucket, saves } = makeBucket();
    const app = express();
    registerMenuFlyerUploadRoutes({ app, bucket, makePublic: true, maxUploadBytes: 1024 });

    await request(app)
      .post('/uploads/menu-flyer')
      .attach('file', Buffer.from('%PDF'), {
        filename: 'menu.pdf',
        contentType: 'application/pdf',
      })
      .expect(415);

    expect(saves).toHaveLength(0);
  });

  it('rejects files over the configured size', async () => {
    const { bucket } = makeBucket();
    const app = express();
    registerMenuFlyerUploadRoutes({ app, bucket, makePublic: true, maxUploadBytes: 4 });

    const res = await request(app)
      .post('/uploads/menu-flyer')
      .attach('file', Buffer.from('too-large'), {
        filename: 'menu.jpg',
        contentType: 'image/jpeg',
      })
      .expect(413);

    expect(res.body.error).toBe('menu_flyer_too_large');
  });

  it('restricts delete keys to the menu-flyers prefix', async () => {
    expect(() => assertMenuFlyerKey('menu-flyers/a.jpg')).not.toThrow();
    expect(() => assertMenuFlyerKey('other/a.jpg')).toThrow(/menu-flyers/);

    const { bucket, deletes } = makeBucket();
    const app = express();
    registerMenuFlyerUploadRoutes({ app, bucket, makePublic: true, maxUploadBytes: 1024 });

    await request(app).delete('/uploads/menu-flyer').send({ key: 'other/a.jpg' }).expect(400);
    await request(app).delete('/uploads/menu-flyer').send({ key: 'menu-flyers/a.jpg' }).expect(204);
    expect(deletes).toEqual(['menu-flyers/a.jpg']);
  });
});
