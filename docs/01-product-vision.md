# 1. Product Vision

## 1.1 What SignalFlow is

SignalFlow is an **iOS-native operations console for distributed physical assets**. It connects to
a fleet of remote IoT devices, streams their telemetry in near-real-time, persists a complete local
history, and helps an operator answer three questions fast:

1. **Is anything wrong right now?** (live status, alerting)
2. **What happened while I wasn't looking?** (history, trends, audit)
3. **What does it mean and what should I do?** (on-device AI insight)

It is intentionally a **read/observe-and-act-light** platform rather than a device-control system.
The center of gravity is *situational awareness*, because that is where the interesting iOS
engineering lives (streaming, persistence, concurrency, visualization, AI) and where a single
well-built app delivers disproportionate value.

> **One-sentence pitch:** SignalFlow turns a noisy firehose of sensor data from trucks, greenhouses
> and warehouses into a calm, trustworthy, offline-capable picture of "what's happening to my
> stuff" — with an AI co-pilot that explains the *why*.

## 1.2 Business value

The value proposition is **loss prevention and operational confidence**, framed per buyer:

| Stakeholder | Pain today | Value SignalFlow delivers |
| --- | --- | --- |
| Cold-chain logistics manager | A temperature excursion ruins a shipment; they find out at delivery | Real-time excursion alerts + a defensible audit trail for insurance/compliance |
| Greenhouse operator | Crop stress from humidity/CO₂ drift discovered too late | Early trend detection and AI-explained anomalies before damage |
| Warehouse / facilities lead | Manual spot-checks, no continuous record | Continuous monitoring with a searchable history, fewer truck-rolls |
| Field technician | No connectivity at the asset site | Offline-first app that works in a basement, dead zone, or moving vehicle |
| Compliance / QA | Reconstructing "what the conditions were" for audits | Immutable local log + exportable reports |

The recurring economic argument is simple: a **single prevented excursion** (a spoiled
refrigerated truckload, a ruined crop cycle, a failed compliance audit) dwarfs the cost of the
software. SignalFlow's job is to shorten *time-to-awareness* and *time-to-explanation*.

### Why "on-device AI" is a business feature, not a gimmick

Running insight generation through Apple's **on-device Foundation Models** means:

- **No backend inference cost** and no per-token API bill.
- **No data egress** — sensor data and location never leave the device for AI processing, which is
  a genuine selling point for regulated logistics and industrial customers.
- **Works offline**, which is exactly when field operators need help most.

## 1.3 User personas

**Persona A — "Marta", Cold-Chain Operations Manager (primary)**
- Manages 40 refrigerated trucks. Lives in a dashboard. Phone is her primary device on the move.
- Needs: at-a-glance fleet health, instant excursion alerts, proof for clients.
- Success = she hears about a problem from the app, not from an angry customer.

**Persona B — "Kenji", Greenhouse Grower (primary)**
- Runs several climate-controlled zones. Cares about slow drifts, not just hard limits.
- Needs: trends over days/weeks, "is this normal for this time of year?", plain-language summaries.
- Success = he catches a failing humidifier from a trend before the crop notices.

**Persona C — "Sam", Field Technician (secondary)**
- Drives to remote sites with poor or no signal. Needs the app to be useful in a dead zone.
- Needs: last-known state, local history, ability to acknowledge alerts offline and sync later.
- Success = the app never shows a spinner of death when there's no network.

**Persona D — "Dana", Compliance / QA Analyst (secondary)**
- Doesn't watch live; pulls records after the fact.
- Needs: accurate, time-stamped history; export; an explanation of any flagged event.
- Success = she can reconstruct and defend any incident in minutes.

**Persona E — "The Hiring Manager / Tech Lead" (meta-persona)**
- Reads the repo to evaluate the *author*. This persona is a first-class design constraint:
  every architectural decision is documented and justified for them (see
  [Portfolio Value](11-portfolio-value.md)).

## 1.4 Real-world use cases

1. **Cold-chain excursion (the headline scenario).** A truck's reefer unit drifts above 4 °C for
   10 minutes. SignalFlow raises a critical alert, the on-device model summarizes *"Unit 12 has
   been above the 4 °C threshold for 11 minutes while stationary — likely a door left open or a
   compressor fault,"* and the event is permanently recorded for the audit trail.

2. **Greenhouse slow drift.** Overnight humidity creeps up 1 %/hour. No single reading breaches a
   limit, but the trend does. SignalFlow's anomaly detection flags the *slope*, and the AI
   summary explains the multi-hour pattern a single threshold check would miss.

3. **The dead-zone visit.** Sam opens the app at a rural pump station with no signal. He sees the
   full last-synced state and history, acknowledges two stale alerts, and adjusts a threshold —
   all offline. On the drive back, connectivity returns and his changes sync automatically via the
   outbox.

4. **Morning fleet triage.** Marta opens the app at 7 a.m. Instead of scanning 40 trucks, she
   reads a one-paragraph AI digest: *"38 of 40 nominal. Truck 7 battery at 11 % and dropping;
   Truck 22 lost connectivity 40 min ago near the depot."* She acts on two, ignores 38.

5. **Compliance export.** Dana exports a truck's 72-hour record with the AI-generated incident
   narrative attached, satisfying a client audit without engineering involvement.

## 1.5 Explicit non-goals (scope discipline)

A senior project is defined as much by what it *refuses* to do. SignalFlow deliberately excludes:

- **Device firmware / hardware** — we consume telemetry; we don't build sensors.
- **Heavy device control / actuation** — limited acknowledgements and threshold settings only,
  not "turn the compressor on" safety-critical control.
- **A custom cloud backend** — the app is the product. A gateway abstraction lets it talk to a real
  broker *or* a built-in deterministic simulator, so the portfolio runs with zero infrastructure.
- **Android / web** — single platform, done excellently.

These boundaries keep the project shippable, reviewable, and focused on iOS craft. See
[Functional Requirements](02-functional-requirements.md) for how this scope maps to an MVP.
