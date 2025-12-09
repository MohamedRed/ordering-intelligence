# GCS Bucket TTL (to implement)

## Goal
- Retain transcripts/audio and exports for 13 months (per spec).

## Steps
1. Identify buckets (e.g., `oi-transcripts`, `oi-audio`, Firestore export bucket).
2. Set lifecycle rule:
```
gsutil lifecycle set lifecycle.json gs://oi-transcripts
```
Example `lifecycle.json`:
```
{
  "rule": [
    {
      "action": { "type": "Delete" },
      "condition": { "age": 395 }
    }
  ]
}
```
3. Enable uniform bucket-level access; remove object ACLs.
4. Optionally enable CMEK.

## Next
- Automate via Terraform and runbook entry.*** End Patch​```림
