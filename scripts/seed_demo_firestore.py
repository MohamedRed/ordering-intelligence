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
    parser = argparse.ArgumentParser(description="Seed demo Firestore data.")
    parser.add_argument("--project", default="", help="GCP project ID (defaults to FIRESTORE_PROJECT_ID or GOOGLE_CLOUD_PROJECT)")
    args = parser.parse_args()

    project = args.project or (
        subprocess.getoutput("printenv FIRESTORE_PROJECT_ID").strip()
        or subprocess.getoutput("printenv GOOGLE_CLOUD_PROJECT").strip()
        or "liive-dev"
    )
    base_url = f"https://firestore.googleapis.com/v1/projects/{project}/databases/(default)/documents"
    token = _access_token()
    now = _now()

    demo_customer_id = "demo-customer-1"
    demo_tenant_id = "demo-tenant"

    stores = [
        {
            "id": "demo-store",
            "fields": {
                "store_id": "demo-store",
                "name": "Demo Pizzeria",
                "tenant_id": demo_tenant_id,
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
            },
        },
        {
            "id": "demo-gas",
            "fields": {
                "store_id": "demo-gas",
                "name": "Demo Fuel Station",
                "tenant_id": demo_tenant_id,
                "business_type": "gas_station",
                "currency": "eur",
                "fuel_default_prepay_cents": 5000,
                "logo_url": "https://cdn.liive.app/demo/demo-fuel.png",
                "delivery_settings": {
                    "enabled": False,
                    "fleet_mode": "marketplace",
                    "store_location": {
                        "lat": 48.8580,
                        "lng": 2.2945,
                        "formatted": "Paris, FR",
                    },
                },
                "updated_at": _ts(now),
            },
        },
        {
            "id": "demo-bakery",
            "fields": {
                "store_id": "demo-bakery",
                "name": "Demo Bakery",
                "tenant_id": demo_tenant_id,
                "business_type": "restaurant",
                "currency": "eur",
                "logo_url": "https://cdn.liive.app/demo/demo-bakery.png",
                "delivery_settings": {
                    "enabled": True,
                    "fleet_mode": "marketplace",
                    "store_location": {
                        "lat": 48.8606,
                        "lng": 2.3376,
                        "formatted": "Paris, FR",
                    },
                },
                "updated_at": _ts(now),
            },
        },
    ]

    orders = [
        {
            "id": "demo-order-1",
            "fields": {
                "id": "demo-order-1",
                "displayNumber": "A-1001",
                "storeId": "demo-store",
                "callSid": "demo-call-1",
                "channel": "telegram",
                "customerName": "Alex Demo",
                "tenantId": demo_tenant_id,
                "customerId": demo_customer_id,
                "callerId": "+33123456789",
                "notes": "No olives.",
                "businessType": "restaurant",
                "paymentMethod": "card",
                "items": [
                    {
                        "itemId": "pizza-margherita",
                        "name": "Margherita",
                        "quantity": 1,
                        "priceCents": 1200,
                        "category": "Pizza",
                        "modifiers": [],
                    },
                    {
                        "itemId": "tiramisu",
                        "name": "Tiramisu",
                        "quantity": 1,
                        "priceCents": 600,
                        "category": "Dessert",
                        "modifiers": [],
                    },
                ],
                "status": "completed",
                "fulfillmentType": "pickup",
                "subtotalCents": 1800,
                "taxCents": 180,
                "feeCents": 0,
                "discountCents": 0,
                "totalCents": 1980,
                "createdAt": now,
                "updatedAt": now,
                "expireAt": now + dt.timedelta(days=30),
            },
        },
        {
            "id": "demo-order-2",
            "fields": {
                "id": "demo-order-2",
                "displayNumber": "G-2001",
                "storeId": "demo-gas",
                "callSid": "demo-call-2",
                "channel": "telegram",
                "customerName": "Alex Demo",
                "tenantId": demo_tenant_id,
                "customerId": demo_customer_id,
                "callerId": "+33123456789",
                "notes": "",
                "businessType": "gas_station",
                "paymentMethod": "card",
                "items": [],
                "fuel": {
                    "fuelGradeId": "diesel",
                    "fuelGradeName": "Diesel",
                    "unit": "liter",
                    "unitPriceCents": 190,
                    "requestedLiters": 30.0,
                    "requestedAmountCents": 5700,
                    "preauthAmountCents": 8000,
                    "paymentFlow": "preauth",
                    "pumpNumber": "3",
                },
                "status": "completed",
                "fulfillmentType": "pickup",
                "subtotalCents": 5700,
                "taxCents": 0,
                "feeCents": 0,
                "discountCents": 0,
                "totalCents": 5700,
                "createdAt": now,
                "updatedAt": now,
                "expireAt": now + dt.timedelta(days=30),
            },
        },
    ]

    group_orders = [
        {
            "id": "demo-group-order-1",
            "fields": {
                "id": "demo-group-order-1",
                "joinCode": "DEMO123",
                "storeId": "demo-store",
                "tenantId": demo_tenant_id,
                "customerId": demo_customer_id,
                "status": "submitted",
                "fulfillmentType": "pickup",
                "host": {
                    "channel": "telegram",
                    "userId": "demo-user-1",
                    "displayName": "Alex Demo",
                },
                "participants": [
                    {
                        "participantId": "p1",
                        "displayName": "Alex Demo",
                        "channelContact": {"channel": "telegram", "userId": "demo-user-1"},
                    },
                    {
                        "participantId": "p2",
                        "displayName": "Jamie",
                        "channelContact": {"channel": "telegram", "userId": "demo-user-2"},
                    },
                    {
                        "participantId": "p3",
                        "displayName": "Chris",
                        "channelContact": {"channel": "telegram", "userId": "demo-user-3"},
                    },
                ],
                "items": [
                    {
                        "itemId": "pizza-pepperoni",
                        "name": "Pepperoni",
                        "quantity": 2,
                        "priceCents": 1400,
                        "participantId": "p2",
                        "participantLabel": "Jamie",
                        "category": "Pizza",
                        "modifiers": [],
                    },
                    {
                        "itemId": "salad",
                        "name": "Mixed Salad",
                        "quantity": 1,
                        "priceCents": 500,
                        "participantId": "p3",
                        "participantLabel": "Chris",
                        "category": "Salads",
                        "modifiers": [],
                    },
                ],
                "pricing": {
                    "subtotalCents": 3300,
                    "taxCents": 330,
                    "feeCents": 0,
                    "discountCents": 0,
                    "totalCents": 3630,
                    "allocations": [
                        {
                            "participantId": "p2",
                            "subtotalCents": 2800,
                            "taxCents": 280,
                            "feeCents": 0,
                            "discountCents": 0,
                            "totalCents": 3080,
                        },
                        {
                            "participantId": "p3",
                            "subtotalCents": 500,
                            "taxCents": 50,
                            "feeCents": 0,
                            "discountCents": 0,
                            "totalCents": 550,
                        },
                    ],
                },
                "paymentMode": "single_payer",
                "paymentMethod": "card",
                "expiresAt": now + dt.timedelta(days=1),
                "createdAt": now,
                "updatedAt": now,
            },
        },
    ]

    reorders = [
        {
            "id": f"{demo_customer_id}_demo-store",
            "fields": {
                "storeId": "demo-store",
                "customerId": demo_customer_id,
                "topReorders": [
                    {
                        "orderTemplateId": "demo-reorder-1",
                        "title": "Margherita + 1 item",
                        "items": [
                            {
                                "itemId": "pizza-margherita",
                                "name": "Margherita",
                                "quantity": 1,
                                "category": "Pizza",
                                "modifiers": [],
                            },
                            {
                                "itemId": "tiramisu",
                                "name": "Tiramisu",
                                "quantity": 1,
                                "category": "Dessert",
                                "modifiers": [],
                            },
                        ],
                        "lastOrderedAt": now - dt.timedelta(days=2),
                    },
                    {
                        "orderTemplateId": "demo-reorder-group-1",
                        "title": "Group lunch",
                        "orderType": "group_order",
                        "participantCount": 3,
                        "items": [
                            {
                                "itemId": "pizza-pepperoni",
                                "name": "Pepperoni",
                                "quantity": 2,
                                "category": "Pizza",
                                "modifiers": [],
                            }
                        ],
                        "lastOrderedAt": now - dt.timedelta(days=5),
                    },
                ],
                "updatedAt": now,
            },
        }
    ]

    for store in stores:
        _patch_doc(base_url, token, "stores", store["id"], store["fields"])

    for order in orders:
        _patch_doc(base_url, token, "orders", order["id"], order["fields"])

    for group in group_orders:
        _patch_doc(base_url, token, "group_orders", group["id"], group["fields"])

    for doc in reorders:
        _patch_doc(base_url, token, "customer_reorders", doc["id"], doc["fields"])

    print(f"Seeded demo data in project {project}.")


if __name__ == "__main__":
    try:
        main()
    except Exception as exc:
        print(f"Seeding failed: {exc}", file=sys.stderr)
        sys.exit(1)
