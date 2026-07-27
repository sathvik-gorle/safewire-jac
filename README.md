# SafeWire

**Legacy systems score one transfer. SafeWire investigates the network behind
it.**

SafeWire helps community-bank fraud analysts stop suspicious transfers before
an elder scammer moves the money, while preserving human review and the
customer relationship.

The demonstration is fully synthetic and works without API keys. Five
specialized Jac investigators traverse separate paths through a persistent
fraud graph in parallel. A skeptic then looks for legitimate explanations
before an intervention policy produces an analyst-facing recommendation.

## The two-minute demo

1. Run SafeWire and open [http://localhost:8000](http://localhost:8000).
2. Select **Ruth Bennett** and click **Investigate transfer**.
3. Watch the exact evidence path assemble as real investigators finish:
   Ruth's transfer → recipient account → shared device → linked recipient →
   prior scam case, plus the downstream transfer → crypto off-ramp path.
4. Inspect every signal's **Accepted** or **Suppressed** skeptic disposition and
   the legitimate explanation that was tested.
5. Compare measured parallel wall time with the sum of the five worker times,
   then inspect the score and recommendation.
6. Select **Harold Kim** and run the same investigation to see the skeptic clear
   a documented roofing payment.

Expected outcomes:

| Case | Legacy result | SafeWire result | Why |
| --- | --- | --- | --- |
| Ruth Bennett, $4,800 | 24 · Allow | **96 · Hold for analyst review** | Five independently sourced signals; call using the verified number on file |
| Harold Kim, $5,200 | 18 · Allow | **20 · Allow** | Matching invoice, established merchant, and no linked recipient network |

No account is frozen, no payment is moved, and no customer or relative is
contacted. Analyst actions are persisted simulations only.

## Start locally

Python 3.12 is recommended.

```bash
python3 -m venv .venv
source .venv/bin/activate
pip install -r requirements.txt
jac install
jac start -d -p 8000 main.jac
```

The client and its relative Jac API routes are served from
`http://localhost:8000`.

Generated graph data lives under `.jac/` and is ignored by Git. Use the reset
button in the header to recreate the synthetic workspace.

## Why Jac

The data model is a persistent graph of customers, accounts, transfers, payees,
devices, IP addresses, authorized users, merchants, signals, and investigation
cases. Typed edges describe ownership, payment movement, shared identity
infrastructure, downstream forwarding, and case evidence.

The orchestrator launches these five read-only traversals before awaiting any
result:

- `BehaviorBaselineWalker`
- `RecipientNetworkWalker`
- `MoneyFlowWalker`
- `IdentityLinkWalker`
- `ScamContextWalker`

Each returns a typed `InvestigatorResult`. Results are applied to the graph
serially, avoiding shared-write races. `SkepticWalker` then suppresses
correlated evidence and searches for invoices, established relationships, and
merchant identity. `InterventionWalker` applies the constrained decision policy
and generates the case file.

The UI consumes buffered server-sent events from
`investigate_transfer_stream`, merging graph deltas only when real walkers
finish. The timing card reports both measured wall time and summed worker time,
making the concurrency directly inspectable.

## Decision policy

Risk contributions are capped by category:

- Behavior anomaly: 20
- Recipient network: 25
- Rapid money flow: 25
- Shared identity infrastructure: 15
- Scam context: 15

A hold requires a score of at least 50, two accepted signal categories, and two
distinct evidence families. Scores from 30–49 or cases without sufficient
corroboration require step-up verification. Lower scores and positively
verified decoys are allowed.

## Optional AI-assisted note review

SafeWire never needs a model for the complete demo. Deterministic exact-span
matching handles the supplied call note by default.

To enable optional note-only classification:

```bash
cp .env.example .env
# Add a newly issued OPENAI_API_KEY to .env locally.
```

Only the supplied call note may be classified. Accepted spans must be exact
substrings of that note. Invalid output, unavailable credentials, rate limits,
or API errors fall back to deterministic classification.

Never paste credentials into chat or commit `.env`.

## CSV import

Use `fixtures/safewire/incoming_transfers.csv` as the example format. Uploads
are limited to 200 rows and 1 MB. Stable identifiers merge existing entities;
duplicates are rejected; missing relationships remain visibly partial instead
of being invented.

## Public interfaces

- `CreateDemoWorkspace`
- `ImportTransferCsv`
- `GetCommandCenter`
- `GetCaseDetail`
- `GetCapabilities`
- `RecordAnalystDecision`
- `ResetWorkspace`
- `investigate_transfer_stream`

Mutation and run interfaces require request IDs to prevent duplicate execution.
The main typed views are `CommandCenterBundle`, `CaseDetail`,
`InvestigatorResult`, `GraphNodeView`, `GraphEdgeView`,
`InvestigationEvent`, and `CapabilityView`.

## Verify

```bash
jac check -p -n main.jac endpoints.sv.jac frontend.cl.jac
jac test test_safewire.jac
bash scripts/check_jac_share.sh
```

CI runs the same checks. The source-share guard fails unless Jac remains more
than 50% of implementation source bytes.

## Synthetic-data and safety notice

All names, accounts, addresses, devices, infrastructure, case identifiers, call
notes, transactions, and evidence in this repository are fictional
demonstration fixtures. SafeWire is analyst decision support, not an autonomous
banking-control system.

See [UPSTREAM.md](UPSTREAM.md) for snapshot provenance.
