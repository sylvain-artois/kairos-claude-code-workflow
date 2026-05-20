# Example — LITE test plan

A filled-in `TEST_PLAN_*_LITE.md` for a generic `api` service, in the shape
[`/create-test-plan`](../../commands/create-test-plan.md) generates and
[`/qa`](../../commands/qa.md) executes. It would live at `api/qa/TEST_PLAN_HEALTHZ_LITE.md`.

Note the two gating signals `/qa` looks for: the per-phase observable `- [ ]`
checkboxes, and the closing **Critical points** table that marks which phases block.

---

```markdown
# Test plan: /healthz smoke — LITE

> Date de création : 2026-05-20
> Service : api (api/)
> Source prompt : "smoke test for the /healthz endpoint and the orders table"

## Variables

| Variable | Valeur |
|----------|--------|
| `BASE_URL` | `http://localhost:8000` |
| `DB`       | `postgresql://app:app@localhost:5432/app` |
| `ORDER_ID` | (filled in Phase 1) |

---

## Phase 0 — Setup minimal

### 0.1 Service reachable

```bash
curl -fsS "$BASE_URL/healthz"
```

- [ ] HTTP 200
- [ ] body contains `"status":"ok"`

### 0.2 Database reachable

```sql
SELECT 1;
```

- [ ] 1 row returned

---

## Phase 1 — Create an order

### 1.1 POST a new order

```bash
curl -fsS -X POST "$BASE_URL/api/v1/orders" \
  -H "Content-Type: application/json" \
  -d '{"sku":"DEMO-1","qty":2}'
```

- [ ] HTTP 201
- [ ] response includes an `id` → capture as `ORDER_ID`

### 1.2 Order persisted

```sql
SELECT status FROM orders WHERE id = '<ORDER_ID>';
```

- [ ] 1 row, `status = 'pending'`

---

## Phase 2 — No orphaned rows

### 2.1 Every order line points at a live order

```sql
SELECT COUNT(*) AS orphans
FROM order_lines ol
LEFT JOIN orders o ON o.id = ol.order_id
WHERE o.id IS NULL;
```

- [ ] `orphans = 0`

---

## Critical points

| # | Risk | Phase |
|---|------|-------|
| 1 | Service or DB down — wrong environment | 0.1, 0.2 |
| 2 | Order creation silently fails | 1.1, 1.2 |
| 3 | Referential integrity broken (orphan lines) | 2.1 |
```
