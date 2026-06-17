import { Timestamp } from '@google-cloud/firestore';
import {
  buildPublicUrl,
  buildRequirements,
  computeStatus,
  DOC_DRIVER_LICENSE,
  DOC_TRANSPORT_CAPACITY,
  DOC_VEHICLE_INSURANCE,
  DOC_VEHICLE_PHOTO,
  DOC_VEHICLE_REGISTRATION,
  normalizeDelivererId,
  normalizeVehicleType,
} from './delivery_partner_compliance_helpers';

describe('delivery partner compliance helpers', () => {
  it('normalizes deliverer and vehicle identifiers', () => {
    expect(normalizeDelivererId(' deliverer-1 ')).toBe('deliverer-1');
    expect(normalizeDelivererId(null)).toBe('');
    expect(normalizeVehicleType(' Scooter ')).toBe('scooter');
    expect(normalizeVehicleType(123)).toBe('');
  });

  it('requires vehicle compliance documents only for motorized delivery vehicles', () => {
    expect(buildRequirements('bike')).toEqual({
      requiredDocs: [],
      optionalDocs: [DOC_VEHICLE_PHOTO],
    });
    expect(buildRequirements('car')).toEqual({
      requiredDocs: [
        DOC_TRANSPORT_CAPACITY,
        DOC_DRIVER_LICENSE,
        DOC_VEHICLE_REGISTRATION,
        DOC_VEHICLE_INSURANCE,
      ],
      optionalDocs: [DOC_VEHICLE_PHOTO],
    });
  });

  it('computes missing documents from absent and rejected required uploads', () => {
    const requiredDocs = [DOC_DRIVER_LICENSE, DOC_VEHICLE_INSURANCE];
    const uploadedAt = Timestamp.now();

    expect(
      computeStatus(requiredDocs, {
        [DOC_DRIVER_LICENSE]: {
          status: 'uploaded',
          url: 'https://example.test/license.jpg',
          key: 'license.jpg',
          bucket: 'bucket',
          uploaded_at: uploadedAt,
        },
        [DOC_VEHICLE_INSURANCE]: {
          status: 'rejected',
          url: 'https://example.test/insurance.jpg',
          key: 'insurance.jpg',
          bucket: 'bucket',
          uploaded_at: uploadedAt,
        },
      }),
    ).toEqual({ status: 'needs_documents', missingDocs: [DOC_VEHICLE_INSURANCE] });

    expect(
      computeStatus(requiredDocs, {
        [DOC_DRIVER_LICENSE]: {
          status: 'uploaded',
          url: 'https://example.test/license.jpg',
          key: 'license.jpg',
          bucket: 'bucket',
          uploaded_at: uploadedAt,
        },
        [DOC_VEHICLE_INSURANCE]: {
          status: 'uploaded',
          url: 'https://example.test/insurance.jpg',
          key: 'insurance.jpg',
          bucket: 'bucket',
          uploaded_at: uploadedAt,
        },
      }),
    ).toEqual({ status: 'approved', missingDocs: [] });
  });

  it('builds signed or public compliance document URLs from storage settings', async () => {
    const bucket = {
      name: 'compliance-bucket',
      file: jest.fn(() => ({
        getSignedUrl: async () => ['https://signed.example.test/doc.jpg'],
      })),
    };

    await expect(
      buildPublicUrl({ bucket: bucket as any, key: 'docs/doc.jpg', makePublic: true }),
    ).resolves.toBe('https://signed.example.test/doc.jpg');
    expect(bucket.file).toHaveBeenCalledWith('docs/doc.jpg');

    await expect(
      buildPublicUrl({
        bucket: bucket as any,
        key: 'docs/doc.jpg',
        makePublic: false,
        publicBaseUrl: 'https://cdn.example.test/',
      }),
    ).resolves.toBe('https://cdn.example.test/docs/doc.jpg');
  });
});
