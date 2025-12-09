# Google Cloud Vendor Package

- **Services used:** Cloud Run, Firestore, Pub/Sub, Secret Manager, Cloud Monitoring, BigQuery.
- **Data processed:** Full application stack (PII, transcripts, orders). Covered under shared responsibility model.
- **Security artefacts:**
  - CAIQ + Shared Responsibility Matrix (2025 update) – `vault://compliance/gcp/caiq-2025.xlsx`.
  - FedRAMP Moderate ATO letter for reference customers.
- **Controls:**
  - Projects segmented per environment (dev/staging/prod) with dedicated service accounts.
  - Cloud Audit Logs enabled for Admin Read + Data Write (see `ops/security/README.md`).
  - IAM analyzer lint prevents broad role regressions.
- **Open items:** finalize committed-use discount & document cost anomaly alerts (provider selection doc).
