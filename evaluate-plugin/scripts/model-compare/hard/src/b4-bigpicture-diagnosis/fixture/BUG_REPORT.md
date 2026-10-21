# INC-2291: wrong prices shown in Nordic storefronts

Reported by: storefront team, Tuesday

Since the FX provider had a few short outages last week, customers in the
Nordic region occasionally see wrong prices:

- A Swedish customer saw the 24-pack of AA batteries at "SEK 14.90". The real
  price is about SEK 170; 14.90 is the EUR catalog price.
- Afterwards, for a few minutes, *Norwegian* customers were also shown the same
  wrong number, labelled NOK.
- On a normal day (no FX outage) we have also had one report of a Danish
  customer being shown a price that matched the Swedish krona amount.
- Restarting the service makes the problem go away for a while.

FX provider outages are expected to happen. Expected behaviour is documented in
README.md.
