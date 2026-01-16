#!/usr/bin/env python3
import argparse
import datetime as dt
import json
import subprocess
import sys
import urllib.request


def _now():
    return dt.datetime.utcnow().replace(microsecond=0)


def _ts(value: dt.datetime) -> str:
    return value.isoformat() + "Z"


def _firestore_value(value):
    if value is None:
        return None
    if isinstance(value, bool):
        return {"booleanValue": value}
    if isinstance(value, int) and not isinstance(value, bool):
        return {"integerValue": str(value)}
    if isinstance(value, float):
        return {"doubleValue": value}
    if isinstance(value, dt.datetime):
        return {"timestampValue": _ts(value)}
    if isinstance(value, dict):
        fields = {}
        for key, item in value.items():
            converted = _firestore_value(item)
            if converted is not None:
                fields[key] = converted
        return {"mapValue": {"fields": fields}}
    if isinstance(value, list):
        values = []
        for item in value:
            converted = _firestore_value(item)
            if converted is not None:
                values.append(converted)
        return {"arrayValue": {"values": values}}
    return {"stringValue": str(value)}


def _doc_body(fields: dict) -> dict:
    out = {}
    for key, value in fields.items():
        converted = _firestore_value(value)
        if converted is not None:
            out[key] = converted
    return {"fields": out}


def _access_token() -> str:
    token = subprocess.check_output(["gcloud", "auth", "print-access-token"]).decode().strip()
    if not token:
        raise RuntimeError("Unable to obtain gcloud access token.")
    return token


def _patch_doc(base_url: str, token: str, collection: str, doc_id: str, fields: dict):
    url = f"{base_url}/{collection}/{doc_id}"
    body = json.dumps(_doc_body(fields)).encode("utf-8")
    req = urllib.request.Request(url, data=body, method="PATCH")
    req.add_header("Authorization", f"Bearer {token}")
    req.add_header("Content-Type", "application/json")
    with urllib.request.urlopen(req) as resp:
        resp.read()


def main():
    parser = argparse.ArgumentParser(description="Seed test Firestore data.")
    parser.add_argument("--project", default="", help="GCP project ID (defaults to FIRESTORE_PROJECT_ID or GOOGLE_CLOUD_PROJECT)")
    parser.add_argument("--suffix", default="dev", help="Suffix for test IDs (default: dev)")
    args = parser.parse_args()

    project = args.project or (
        subprocess.getoutput("printenv FIRESTORE_PROJECT_ID").strip()
        or subprocess.getoutput("printenv GOOGLE_CLOUD_PROJECT").strip()
        or "ordering-intelligence"
    )
    base_url = f"https://firestore.googleapis.com/v1/projects/{project}/databases/(default)/documents"
    token = _access_token()
    now = _now()
    suffix = args.suffix.strip() or "dev"

    test_customer_id = f"test-customer-{suffix}"
    test_tenant_id = f"test-tenant-{suffix}"
    test_store_id = f"test-store-{suffix}"

    stores = [
        {
            "id": test_store_id,
            "fields": {
                "store_id": test_store_id,
                "name": f"Test Store ({suffix})",
                "tenant_id": test_tenant_id,
                "business_type": "restaurant",
                "currency": "eur",
                "logo_url": "https://cdn.liive.app/demo/demo-pizza.png",
                "delivery_settings": {
                    "enabled": True,
                    "fleet_mode": "marketplace",
                    "store_location": {
                        "lat": 48.8566,
                        "lng": 2.3522,
                        "formatted": "Paris, FR",
                    },
                },
                "updated_at": _ts(now),
                "is_test": True,
                "test_tag": suffix,
            },
        }
    ]

    tenants = [
        {
            "id": test_tenant_id,
            "fields": {
                "id": test_tenant_id,
                "name": f"Test Tenant ({suffix})",
                "primaryUser": "test@liive.app",
                "status": "active",
                "featureFlags": {},
                "storeId": test_store_id,
                "businessType": "restaurant",
                "timezone": "Europe/Paris",
                "phone": "+33123456789",
                "createdAt": now,
                "updatedAt": now,
                "is_test": True,
                "test_tag": suffix,
            },
        }
    ]

    orders = [
        {
            "id": f"test-order-{suffix}-1",
            "fields": {
                "id": f"test-order-{suffix}-1",
                "displayNumber": f"T-{suffix}-1001",
                "storeId": test_store_id,
                "callSid": f"test-call-{suffix}-1",
                "channel": "webapp",
                "customerName": "Test Customer",
                "tenantId": test_tenant_id,
                "customerId": test_customer_id,
                "callerId": "+33123456789",
                "notes": "Test order (pickup).",
                "businessType": "restaurant",
                "paymentMethod": "cash",
                "items": [
                    {
                        "itemId": "test-pizza",
                        "name": "Test Pizza",
                        "quantity": 1,
                        "priceCents": 1200,
                        "category": "Pizza",
                        "modifiers": [],
                    }
                ],
                "status": "pending",
                "fulfillmentType": "pickup",
                "subtotalCents": 1200,
                "taxCents": 120,
                "feeCents": 0,
                "discountCents": 0,
                "totalCents": 1320,
                "createdAt": now - dt.timedelta(minutes=15),
                "updatedAt": now - dt.timedelta(minutes=10),
                "expireAt": now + dt.timedelta(days=30),
                "is_test": True,
                "test_tag": suffix,
            },
        },
        {
            "id": f"test-order-{suffix}-2",
            "fields": {
                "id": f"test-order-{suffix}-2",
                "displayNumber": f"T-{suffix}-1002",
                "storeId": test_store_id,
                "callSid": f"test-call-{suffix}-2",
                "channel": "webapp",
                "customerName": "Test Customer",
                "tenantId": test_tenant_id,
                "customerId": test_customer_id,
                "callerId": "+33123456789",
                "notes": "Test order (delivery).",
                "businessType": "restaurant",
                "paymentMethod": "card",
                "items": [
                    {
                        "itemId": "test-dessert",
                        "name": "Test Dessert",
                        "quantity": 2,
                        "priceCents": 500,
                        "category": "Dessert",
                        "modifiers": [],
                    }
                ],
                "status": "confirmed",
                "fulfillmentType": "delivery",
                "delivery": {
                    "fleetMode": "marketplace",
                    "dropoffAddress": {
                        "line1": "1 Rue de Test",
                        "city": "Paris",
                        "postalCode": "75001",
                        "country": "FR",
                        "formatted": "1 Rue de Test, 75001 Paris",
                    },
                },
                "subtotalCents": 1000,
                "taxCents": 100,
                "feeCents": 200,
                "discountCents": 0,
                "totalCents": 1300,
                "createdAt": now - dt.timedelta(hours=2),
                "updatedAt": now - dt.timedelta(hours=1, minutes=30),
                "expireAt": now + dt.timedelta(days=30),
                "is_test": True,
                "test_tag": suffix,
            },
        },
    ]

    menus = [
        {
            "id": test_store_id,
            "fields": {
                "storeId": test_store_id,
                "items": [
                    {
                        "id": "test-pizza",
                        "name": "Test Pizza",
                        "priceCents": 1200,
                        "available": True,
                        "category": "Pizza",
                        "description": "Tomato, mozzarella, basil",
                        "modifiers": [],
                    },
                    {
                        "id": "test-dessert",
                        "name": "Test Dessert",
                        "priceCents": 500,
                        "available": True,
                        "category": "Dessert",
                        "description": "Sweet test treat",
                        "modifiers": [],
                    },
                ],
                "bundleRules": [],
                "updatedAt": now,
                "is_test": True,
                "test_tag": suffix,
            },
        }
    ]

    customers = [
        {
            "id": test_customer_id,
            "fields": {
                "customerId": test_customer_id,
                "displayName": "Test Customer",
                "status": "active",
                "createdAt": now - dt.timedelta(days=5),
                "updatedAt": now,
                "lastSeenAt": now,
                "firstSeenAt": now - dt.timedelta(days=5),
                "firstSeenChannel": "webapp",
                "firstSeenStoreId": test_store_id,
                "firstSeenPlatform": "web",
                "firstSeenProvider": "test",
                "is_test": True,
                "test_tag": suffix,
            },
        }
    ]

    identities = [
        {
            "id": f"test-identity-{suffix}",
            "fields": {
                "customerId": test_customer_id,
                "channel": "webapp",
                "userId": f"test-user-{suffix}",
                "displayName": "Test Customer",
                "linkedAt": now,
                "lastSeenAt": now,
                "verifiedAt": now,
                "is_test": True,
                "test_tag": suffix,
            },
        }
    ]

    group_orders = [
        {
            "id": f"test-group-order-{suffix}-1",
            "fields": {
                "id": f"test-group-order-{suffix}-1",
                "joinCode": f"{suffix}JOIN",
                "tenantId": test_tenant_id,
                "storeId": test_store_id,
                "customerId": test_customer_id,
                "fulfillmentType": "pickup",
                "status": "open",
                "host": {
                    "channel": "webapp",
                    "userId": f"test-user-{suffix}",
                    "displayName": "Test Host",
                },
                "participants": [
                    {
                        "participantId": f"test-user-{suffix}",
                        "displayName": "Test Host",
                        "contact": {
                            "channel": "webapp",
                            "userId": f"test-user-{suffix}",
                            "displayName": "Test Host",
                        },
                    }
                ],
                "items": [],
                "pricing": {
                    "subtotalCents": 0,
                    "taxCents": 0,
                    "feeCents": 0,
                    "discountCents": 0,
                    "totalCents": 0,
                    "allocations": [],
                },
                "paymentMode": "single_payer",
                "paymentMethod": "cash",
                "expiresAt": now + dt.timedelta(hours=2),
                "createdAt": now - dt.timedelta(hours=1),
                "updatedAt": now - dt.timedelta(minutes=10),
                "is_test": True,
                "test_tag": suffix,
            },
        }
    ]

    reorders = [
        {
            "id": f"{test_customer_id}-{test_store_id}",
            "fields": {
                "customerId": test_customer_id,
                "storeId": test_store_id,
                "topReorders": [
                    {
                        "orderTemplateId": f"test-reorder-{suffix}-1",
                        "title": "Test Pizza Reorder",
                        "orderType": "single_order",
                        "items": [
                            {
                                "itemId": "test-pizza",
                                "name": "Test Pizza",
                                "quantity": 1,
                                "category": "Pizza",
                                "modifiers": [],
                            }
                        ],
                        "lastOrderedAt": now - dt.timedelta(days=1),
                    }
                ],
                "updatedAt": now,
                "is_test": True,
                "test_tag": suffix,
            },
        }
    ]

    driver_docs = [
        {
            "collection": f"stores/{test_store_id}/drivers",
            "id": f"test-driver-{suffix}",
            "fields": {
                "displayName": "Test Driver",
                "phoneE164": "+33123450000",
                "active": True,
                "maxActiveStops": 3,
                "createdAt": now - dt.timedelta(days=1),
                "updatedAt": now,
                "is_test": True,
                "test_tag": suffix,
            },
        }
    ]

    for store in stores:
        _patch_doc(base_url, token, "stores", store["id"], store["fields"])

    for tenant in tenants:
        _patch_doc(base_url, token, "tenants", tenant["id"], tenant["fields"])

    for order in orders:
        _patch_doc(base_url, token, "orders", order["id"], order["fields"])

    for menu in menus:
        _patch_doc(base_url, token, "menus", menu["id"], menu["fields"])

    for customer in customers:
        _patch_doc(base_url, token, "customers", customer["id"], customer["fields"])

    for identity in identities:
        _patch_doc(base_url, token, "customer_identities", identity["id"], identity["fields"])

    for group in group_orders:
        _patch_doc(base_url, token, "group_orders", group["id"], group["fields"])

    for doc in reorders:
        _patch_doc(base_url, token, "customer_reorders", doc["id"], doc["fields"])

    for driver in driver_docs:
        _patch_doc(base_url, token, driver["collection"], driver["id"], driver["fields"])

    print(f"Seeded test data in project {project} (suffix={suffix}).")


if __name__ == "__main__":
    try:
        main()
    except Exception as exc:
        print(f"Seeding failed: {exc}", file=sys.stderr)
        sys.exit(1)
