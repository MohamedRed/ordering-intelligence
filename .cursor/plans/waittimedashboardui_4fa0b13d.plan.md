---
name: WaitTimeDashboardUI
overview: "Show wait-time/ETA analytics in the business app: a top card on Orders and a detailed 7-day insights route powered by daily aggregates from wait-time-service."
todos:
  - id: wait-time-daily-aggregates
    content: Extend wait-time-service to maintain 7-day daily aggregates per store (median/p90/count), in addition to current daypart stats.
    status: pending
  - id: order-service-wait-time-read-endpoints
    content: "Add read-only endpoints in order-service: /wait-time/summary and /wait-time/daily?days=7 (reads Firestore aggregates)."
    status: pending
    dependencies:
      - wait-time-daily-aggregates
  - id: business-orders-top-card
    content: "Business app: add a top dashboard card on /orders showing current ETA + source + samples + link to details."
    status: pending
    dependencies:
      - order-service-wait-time-read-endpoints
  - id: business-wait-time-route
    content: "Business app: add new /wait-time route with 7-day chart + numeric table."
    status: pending
    dependencies:
      - business-orders-top-card
  - id: charts-dependency
    content: "Business app: add charting dependency (fl_chart) and implement median/p90 + count visualization."
    status: pending
    dependencies:
      - business-wait-time-route
---

# Business dashboard: show wait-time/ETA analytics

## Goal

Expose the same prep-time intelligence we compute for the voice agent to the restaurant staff:

- **Orders list** (`/orders`): a compact top dashboard card showing “what the agent will say right now” + a couple of supporting metrics.
- **New route** (e.g. `/wait-time`): a 7‑day analytics view with trends and distributions so the business can understand performance and variability.

This plan assumes the ETA pipeline plan is in progress (lifecycle timestamps + wait-time aggregation). It adds the **read models + UI**.

## Data we should store (to make the UI fast)

Extend `wait-time-service` to maintain *two* read-optimized aggregates per store:

1) **Current bucket stats** (already planned)

- `stores/{storeId}/wait_time_stats/{daypartKey}`
- `samples[]` (bounded)
- `count`
- `medianMinutes`
- `p90Minutes` (compute from samples)
- `lastDurationMinutes`
- `updatedAt`

2) **Daily aggregates for 7 days** (new)

- `stores/{storeId}/wait_time_daily/{yyyy-mm-dd}`
- `dayparts.weekday_lunch|weekday_dinner|weekend_lunch|weekend_dinner` each with:
- `count`, `medianMinutes`, `p90Minutes`, `lastDurationMinutes`
- `overall.count`, `overall.medianMinutes`, `overall.p90Minutes`
- `updatedAt`

This avoids expensive “scan last 7 days of orders” queries from the mobile client.

## API surface (business app reads)

Because the business app already calls `order-service`, we’ll add **read-only endpoints** there that simply read the aggregate docs from Firestore:

- `GET /stores/{storeId}/wait-time/summary`
- Returns:
- `etaMinutes` (the number the agent would say **right now** using the selection logic)
- `daypartKeyUsed`
- `source` (`historical_median` | `historical_last` | `store_default`)
- `medianMinutes`, `p90Minutes`, `lastDurationMinutes`, `count`
- `defaultWaitMinutes`

- `GET /stores/{storeId}/wait-time/daily?days=7`
- Returns an array of 7 daily points with per-daypart stats + overall.

This keeps the Flutter app simple and avoids Firestore client-side querying/permissions complexity.

## UI design

### A) Orders list: top dashboard card

Add a card above the list in [apps/business/lib/features/orders/order_list_screen.dart](apps/business/lib/features/orders/order_list_screen.dart):

- **Primary**: “Current quoted wait: about **N minutes**”
- **Secondary**:
- “Based on: median / last order / store default”
- “Last order: X min” (when available)
- “Samples: K (this daypart)”
- **CTA**: “View details” → navigates to the new route.

Data source: `OrderServiceURL + /stores/{storeId}/wait-time/summary`.

### B) New route: 7‑day details (more data)

Add a new route, e.g. `/wait-time`, wired from [apps/business/lib/main.dart](apps/business/lib/main.dart).

Screen contents:

1) **Top summary (same as Orders card)**

- Agent ETA now + bucket + source.

2) **Trend chart (7 days)**

Because the app currently has no charting dependency, we’ll add one (recommended): **`fl_chart`**.

Chart proposal (high-signal, not a heatmap):

- **Line chart**: daily **median minutes** (overall)
- **Second line (dashed)**: daily **p90 minutes** (overall) to communicate “concentration/variability”
- **Bar chart below** (or a small sub-chart): daily **order count**

Add a toggle:

- Overall (default)
- Lunch vs Dinner (switch lines to show median/p90 for the relevant daypart)

This representation makes it obvious:

- whether wait times are trending up/down,
- how spiky the kitchen is (p90 gap),
- and how much data backs each day (count bars).

3) **Table (optional, high-clarity)**

Below the chart, show a compact table for the last 7 days:

- Date
- Median
- p90
- Count

This gives the “numbers” view you asked for.

## Files expected to change

Backend:

- [backend/services/order-service/cmd/order-service/main.go](backend/services/order-service/cmd/order-service/main.go) (new read-only endpoints)
- `backend/services/wait-time-service/...` (update to write daily aggregates)

Business app:

- [apps/business/lib/features/orders/order_list_screen.dart](apps/business/lib/features/orders/order_list_screen.dart) (top card)
- [apps/business/lib/main.dart](apps/business/lib/main.dart) (new route)
- `apps/business/lib/features/wait_time/wait_time_screen.dart` (new)
- `apps/business/pubspec.yaml` (add `fl_chart`)

## Acceptance criteria

- Orders list shows a dashboard card with:
- ETA now (“about N minutes”)
- Source (median/last/default)
- A link to details
- New route shows 7-day trend with median + p90 + counts and a numeric table.
- All data loads fast (no scanning raw orders on the client).