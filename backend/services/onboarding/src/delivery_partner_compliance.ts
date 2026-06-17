import express from 'express';
import { FieldValue, Firestore, Timestamp } from '@google-cloud/firestore';
import type { Bucket } from '@google-cloud/storage';
import multer from 'multer';
import { v4 as uuidv4 } from 'uuid';
import {
  appendAudit,
  buildPublicUrl,
  buildRequirements,
  computeStatus,
  DELIVERY_PARTNER_COMPLIANCE,
  type DeliveryPartnerComplianceDoc,
  type DeliveryPartnerComplianceDocument,
  DOC_LABELS,
  ensureDelivererExists,
  normalizeDelivererId,
  normalizeVehicleType,
  VEHICLE_TYPES,
} from './delivery_partner_compliance_helpers.js';

const upload = multer({ storage: multer.memoryStorage() });

type DeliveryPartnerComplianceDeps = {
  app: express.Express;
  firestore: Firestore;
  bucket: Bucket;
  publicBaseUrl?: string;
  makePublic: boolean;
};

export const registerDeliveryPartnerComplianceRoutes = ({
  app,
  firestore,
  bucket,
  publicBaseUrl,
  makePublic,
}: DeliveryPartnerComplianceDeps) => {
  app.post('/delivery-partners/compliance/start', express.json(), async (req, res) => {
    try {
      const delivererId = normalizeDelivererId(req.body?.deliverer_id ?? req.body?.delivererId);
      if (!delivererId) return res.status(400).json({ error: 'deliverer_id_required' });

      const vehicleType = normalizeVehicleType(req.body?.vehicle_type ?? req.body?.vehicleType);
      if (!VEHICLE_TYPES.has(vehicleType)) {
        return res.status(400).json({ error: 'vehicle_type_invalid' });
      }
      const countryRaw = String(req.body?.country || '').trim();
      if (!countryRaw) {
        return res.status(400).json({ error: 'country_required' });
      }
      const country = countryRaw.toUpperCase();

      const exists = await ensureDelivererExists(firestore, delivererId);
      if (!exists) return res.status(404).json({ error: 'deliverer_not_found' });

      const docRef = firestore.collection(DELIVERY_PARTNER_COMPLIANCE).doc(delivererId);
      const snap = await docRef.get();
      const existing = snap.exists ? (snap.data() as DeliveryPartnerComplianceDoc) : undefined;
      const documents = existing?.documents ?? undefined;
      const { requiredDocs, optionalDocs } = buildRequirements(vehicleType);
      const { status, missingDocs } = computeStatus(requiredDocs, documents);
      const ts = Timestamp.now();

      const payload: Partial<DeliveryPartnerComplianceDoc> = {
        deliverer_id: delivererId,
        country,
        vehicle_type: vehicleType,
        required_docs: requiredDocs,
        optional_docs: optionalDocs,
        status,
        updated_at: ts,
        ...(snap.exists ? {} : { created_at: ts }),
      };
      if (status === 'approved') {
        payload.approved_at = ts;
        payload.approval_source = 'auto';
      } else {
        payload.approved_at = FieldValue.delete() as any;
        payload.approval_source = FieldValue.delete() as any;
      }

      await docRef.set(payload, { merge: true });
      await appendAudit(docRef, 'compliance_start', { vehicle_type: vehicleType, country });

      res.status(snap.exists ? 200 : 201).json({
        ...(payload as DeliveryPartnerComplianceDoc),
        documents,
        missing_docs: missingDocs,
        doc_labels: DOC_LABELS,
      });
    } catch (err: any) {
      console.error('delivery partner compliance start error', err);
      res.status(500).json({ error: 'delivery_partner_compliance_start_failed', message: err.message });
    }
  });

  app.get('/delivery-partners/compliance/:delivererId', async (req, res) => {
    try {
      const delivererId = normalizeDelivererId(req.params.delivererId);
      if (!delivererId) return res.status(400).json({ error: 'deliverer_id_required' });
      const snap = await firestore.collection(DELIVERY_PARTNER_COMPLIANCE).doc(delivererId).get();
      if (!snap.exists) return res.status(404).json({ error: 'compliance_not_started' });
      const data = snap.data() as DeliveryPartnerComplianceDoc;
      const { status, missingDocs } = computeStatus(data.required_docs ?? [], data.documents);
      res.status(200).json({
        ...data,
        status,
        missing_docs: missingDocs,
        doc_labels: DOC_LABELS,
      });
    } catch (err: any) {
      console.error('delivery partner compliance status error', err);
      res.status(500).json({ error: 'delivery_partner_compliance_status_failed', message: err.message });
    }
  });

  app.post(
    '/delivery-partners/compliance/:delivererId/documents',
    upload.single('file'),
    async (req, res) => {
      try {
        const delivererId = normalizeDelivererId(req.params.delivererId);
        if (!delivererId) return res.status(400).json({ error: 'deliverer_id_required' });
        if (!req.file) return res.status(400).json({ error: 'file_required' });

        const docType = String(req.body?.docType || req.body?.doc_type || '').trim();
        if (!docType || !DOC_LABELS[docType]) {
          return res.status(400).json({ error: 'doc_type_invalid' });
        }

        const docRef = firestore.collection(DELIVERY_PARTNER_COMPLIANCE).doc(delivererId);
        const snap = await docRef.get();
        if (!snap.exists) return res.status(404).json({ error: 'compliance_not_started' });
        const data = snap.data() as DeliveryPartnerComplianceDoc;
        const allowedDocs = new Set([...(data.required_docs || []), ...(data.optional_docs || [])]);
        if (!allowedDocs.has(docType)) {
          return res.status(400).json({ error: 'doc_type_not_allowed' });
        }

        const { originalname, buffer, mimetype } = req.file;
        const ext = originalname.split('.').pop() || 'bin';
        const safeName = originalname.replace(/[^a-zA-Z0-9._-]+/g, '_');
        const key = `delivery-partners/${delivererId}/${docType}/${uuidv4()}-${safeName}`;

        await bucket.file(key).save(buffer, {
          resumable: false,
          contentType: mimetype || 'application/octet-stream',
          metadata: { cacheControl: 'private, max-age=0' },
        });

        const url = await buildPublicUrl({
          bucket,
          key,
          makePublic,
          publicBaseUrl,
        });

        const ts = Timestamp.now();
        const docEntry: DeliveryPartnerComplianceDocument = {
          status: 'uploaded',
          url,
          key,
          bucket: bucket.name,
          content_type: mimetype || undefined,
          file_name: originalname || undefined,
          uploaded_at: ts,
        };

        const nextDocuments = { ...(data.documents || {}), [docType]: docEntry };
        const { status, missingDocs } = computeStatus(data.required_docs || [], nextDocuments);
        const update: Partial<DeliveryPartnerComplianceDoc> = {
          documents: { [docType]: docEntry } as any,
          status,
          updated_at: ts,
        };
        if (status === 'approved') {
          update.approved_at = ts;
          update.approval_source = 'auto';
        } else {
          update.approved_at = FieldValue.delete() as any;
          update.approval_source = FieldValue.delete() as any;
        }

        await docRef.set(update, { merge: true });
        await appendAudit(docRef, 'compliance_doc_uploaded', { doc_type: docType, key });

        res.status(201).json({
          ...data,
          documents: nextDocuments,
          status,
          missing_docs: missingDocs,
          updated_at: ts,
          doc_labels: DOC_LABELS,
        });
      } catch (err: any) {
        console.error('delivery partner compliance upload error', err);
        res.status(500).json({ error: 'delivery_partner_compliance_upload_failed', message: err.message });
      }
    },
  );
};
