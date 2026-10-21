# Billing issues reported this sprint

Collected from support and finance. Please investigate and fix what is actually
broken. Each item is as reported; reporters are not always right about the cause.

## 1. Duplicate charges (support, P1)

> Customer C-1042 was charged twice for order 7731. Our logs show the first
> gateway call timed out, the service retried and the retry succeeded - but the
> gateway settlement shows two captures. We have also seen duplicates when the
> mobile app double-submits a payment (two requests with the same
> Idempotency-Key a few milliseconds apart).

## 2. Daily totals do not reconcile (finance)

> The "daily totals" export for Sunday 2026-03-29 does not match the gateway's
> settlement report for that day. Same thing for Sunday 2025-10-26. When we run
> the multi-day export (`daily_totals_range`) for the week around those dates,
> several days are off and the week's sum does not equal the sum of all ledger
> entries in that week. Most other weeks reconcile fine. Our books are kept in
> Helsinki time.

## 3. Refund days show the wrong total (finance)

> On 2026-05-04 a customer was charged 50.00 and fully refunded the same
> afternoon. The daily total for 2026-05-04 shows 0.00, but we did take a 50.00
> payment that day. Totals on refund days look too low in general.
