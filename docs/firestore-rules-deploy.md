# Deploy Firestore Rules

```
# Order service rules
firebase firestore:rules:set backend/services/order-service/firestore.rules --project $PROJECT_ID

# Notification service rules
firebase firestore:rules:set backend/services/notification-service/firestore.rules --project $PROJECT_ID
```

If using gcloud:
```
gcloud alpha firestore security-rules update backend/services/order-service/firestore.rules --project=$PROJECT_ID
gcloud alpha firestore security-rules update backend/services/notification-service/firestore.rules --project=$PROJECT_ID
```
