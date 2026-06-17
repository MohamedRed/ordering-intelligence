import { FieldValue, Firestore, Timestamp } from '@google-cloud/firestore';
import type { Bucket } from '@google-cloud/storage';

export const DELIVERY_PARTNER_COMPLIANCE = 'delivery_partner_compliance';
export const MARKETPLACE_DELIVERERS = 'marketplace_deliverers';

export const VEHICLE_TYPES = new Set(['bike', 'ebike', 'scooter', 'car', 'van']);
const MOTOR_VEHICLES = new Set(['scooter', 'car', 'van', 'motorbike']);

export const DOC_TRANSPORT_CAPACITY = 'transport_capacity';
export const DOC_DRIVER_LICENSE = 'driver_license';
export const DOC_VEHICLE_REGISTRATION = 'vehicle_registration';
export const DOC_VEHICLE_INSURANCE = 'vehicle_insurance';
export const DOC_VEHICLE_PHOTO = 'vehicle_photo';

export const DOC_LABELS: Record<string, string> = {
  [DOC_TRANSPORT_CAPACITY]: 'Transport capacity certificate',
  [DOC_DRIVER_LICENSE]: 'Driver license',
  [DOC_VEHICLE_REGISTRATION]: 'Vehicle registration (carte grise)',
  [DOC_VEHICLE_INSURANCE]: 'Vehicle insurance',
  [DOC_VEHICLE_PHOTO]: 'Vehicle photo',
};

export type DeliveryPartnerComplianceDocument = {
  status: string;
  url: string;
  key: string;
  bucket: string;
  content_type?: string;
  file_name?: string;
  uploaded_at: FirebaseFirestore.Timestamp;
};

export type DeliveryPartnerComplianceDoc = {
  deliverer_id: string;
  country: string;
  vehicle_type: string;
  required_docs: string[];
  optional_docs: string[];
  documents?: Record<string, DeliveryPartnerComplianceDocument>;
  status: string;
  created_at?: FirebaseFirestore.Timestamp;
  updated_at: FirebaseFirestore.Timestamp;
  approved_at?: FirebaseFirestore.Timestamp;
  approval_source?: string;
};

export const normalizeDelivererId = (value: unknown): string => {
  if (typeof value !== 'string') return '';
  return value.trim();
};

export const normalizeVehicleType = (value: unknown): string => {
  if (typeof value !== 'string') return '';
  return value.trim().toLowerCase();
};

export const isMotorizedVehicle = (vehicleType: string): boolean => MOTOR_VEHICLES.has(vehicleType);

export const buildRequirements = (vehicleType: string): { requiredDocs: string[]; optionalDocs: string[] } => {
  if (isMotorizedVehicle(vehicleType)) {
    return {
      requiredDocs: [
        DOC_TRANSPORT_CAPACITY,
        DOC_DRIVER_LICENSE,
        DOC_VEHICLE_REGISTRATION,
        DOC_VEHICLE_INSURANCE,
      ],
      optionalDocs: [DOC_VEHICLE_PHOTO],
    };
  }
  return {
    requiredDocs: [],
    optionalDocs: [DOC_VEHICLE_PHOTO],
  };
};

export const computeMissingDocs = (
  requiredDocs: string[],
  documents?: Record<string, DeliveryPartnerComplianceDocument>,
): string[] =>
  requiredDocs.filter((doc) => {
    const entry = documents?.[doc];
    if (!entry) return true;
    return entry.status === 'rejected';
  });

export const computeStatus = (
  requiredDocs: string[],
  documents?: Record<string, DeliveryPartnerComplianceDocument>,
): { status: string; missingDocs: string[] } => {
  const missingDocs = computeMissingDocs(requiredDocs, documents);
  if (missingDocs.length === 0) return { status: 'approved', missingDocs };
  return { status: 'needs_documents', missingDocs };
};

export const ensureDelivererExists = async (firestore: Firestore, delivererId: string): Promise<boolean> => {
  const snap = await firestore.collection(MARKETPLACE_DELIVERERS).doc(delivererId).get();
  return snap.exists;
};

export const buildPublicUrl = async (params: {
  bucket: Bucket;
  key: string;
  makePublic: boolean;
  publicBaseUrl?: string;
}): Promise<string> => {
  if (params.makePublic) {
    const [signed] = await params.bucket.file(params.key).getSignedUrl({
      action: 'read',
      expires: Date.now() + 7 * 24 * 60 * 60 * 1000,
    });
    return signed;
  }
  const baseUrl = params.publicBaseUrl?.replace(/\/$/, '') || `https://storage.googleapis.com/${params.bucket.name}`;
  return `${baseUrl}/${params.key}`;
};

export const appendAudit = async (
  docRef: FirebaseFirestore.DocumentReference,
  event: string,
  data?: any,
) => {
  const ts = Timestamp.now();
  const entry: any = { ts, actor: 'system', event };
  if (data !== undefined) entry.data = data;
  await docRef.set({ audit: FieldValue.arrayUnion(entry), updated_at: ts }, { merge: true });
};
