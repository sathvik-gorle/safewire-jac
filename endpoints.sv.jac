"""Meridian backend: a Jac-native parallel diligence mesh."""

import csv;
import io;
import json;
import os;
import time;
import httpx;

enum EntityStatus {
    PENDING,
    RESEARCHING,
    SCORING,
    DONE,
    FLAGGED,
    PARTIAL,
    FAILED
}


obj LiveFact {
    has key: str,
        label: str,
        value: str,
        evidence_index: int,
        confidence: float;
}

obj LiveSignal {
    has category: str,
        severity: float,
        rationale: str,
        evidence_key: str;
}

sem LiveFact = "A structured diligence fact grounded in exactly one supplied search result.";
sem LiveFact.evidence_index = "Zero-based index into the supplied search results. Never invent an index.";
sem LiveSignal = "An explainable risk signal classified from supplied diligence facts.";

def extract_live_facts(
    entity_name: str,
    search_results: list[dict]
) -> list[LiveFact] by llm();

sem extract_live_facts = """Extract the five diligence fields use_of_proceeds,
stated_covenant_terms, recent_credit_rating_action, comparable_bond_yield, and
disclosed_litigation. Use only supplied evidence. Return no fact whose evidence
index is not present.""";

def classify_live_signals(facts: list[LiveFact]) -> list[LiveSignal] by llm();

sem classify_live_signals = """Classify only independently supported risk
signals. Allowed categories are rating_action, yield_deviation, litigation,
covenant_strength, and disclosure_gap. Severity is from 0.0 to 1.0.""";


node EntityBatch {
    has title: str,
        mode: str = "demo",
        status: str = "pending",
        snapshot_date: str = "",
        schema_fields: list[str] = [],
        total_entities: int = 0,
        completed_entities: int = 0,
        started_at: str = "",
        finished_at: str = "",
        wall_clock_ms: int = 0,
        sequential_ms: int = 0;
}

node Entity {
    has key: str,
        name: str,
        identifier: str,
        sector: str = "Custom",
        status: str = "pending",
        risk_score: float = 0.0,
        recommendation: str = "Pending research",
        coverage: float = 0.0,
        signal_count: int = 0,
        elapsed_ms: int = 0,
        error: str = "";
}

node Attribute {
    has key: str,
        label: str,
        value: str,
        source_url: str,
        source_title: str,
        excerpt: str,
        confidence: float,
        captured_at: str;
}

node SubEntity {
    has name: str,
        relationship: str = "Comparable bond",
        status: str = "researched";
}

node RiskSignal {
    has category: str,
        severity: float,
        weight: float,
        contribution: float,
        rationale: str,
        evidence_key: str;
}

node Report {
    has summary_md: str,
        generated_at: str,
        entity_count: int,
        flagged_count: int;
}

edge OwnsBatch {}
edge ContainsEntity {}
edge HasAttribute {}
edge HasSubEntity {}
edge HasSignal {}
edge HasReport {}
edge IncludedIn {}


obj BatchBundle {
    has batch: EntityBatch,
        entities: list[Entity],
        report: Report | None = None,
        live_available: bool = False,
        message: str = "";
}

obj EntityDetail {
    has entity: Entity,
        attributes: list[Attribute],
        signals: list[RiskSignal],
        comparables: list[SubEntity];
}

obj CapabilityView {
    has live_available: bool,
        openai_configured: bool,
        tavily_configured: bool,
        mode: str,
        extract_model: str,
        report_model: str;
}


glob FIXTURE_PATH = os.path.join(
    os.path.dirname(__file__), "fixtures", "demo_evidence.json"
);

glob SCHEMA_FIELDS: list[str] = [
    "use_of_proceeds",
    "stated_covenant_terms",
    "recent_credit_rating_action",
    "comparable_bond_yield",
    "disclosed_litigation"
];

glob SIGNAL_WEIGHTS: dict[str, float] = {
    "rating_action": 25.0,
    "yield_deviation": 25.0,
    "litigation": 20.0,
    "covenant_strength": 15.0,
    "disclosure_gap": 15.0
};


def now_iso -> str {
    import datetime;
    return datetime.datetime.now(datetime.timezone.utc).isoformat();
}

def live_available -> bool {
    return bool(os.environ.get("OPENAI_API_KEY")) and bool(
        os.environ.get("TAVILY_API_KEY")
    );
}

def load_demo_data -> dict {
    with open(FIXTURE_PATH, "r", encoding="utf-8") as fixture_file {
        return json.load(fixture_file);
    }
}

def find_fixture(entity_key: str) -> dict {
    for item in load_demo_data()["entities"] {
        if item["key"] == entity_key {
            return item;
        }
    }
    return {};
}

def tavily_search(entity_name: str) -> list[dict] {
    api_key = os.environ.get("TAVILY_API_KEY", "");
    if not api_key {
        return [];
    }
    query = (
        f"{entity_name} bond use of proceeds covenant terms credit rating "
        "action comparable yield litigation SEC filing"
    );
    last_error: Exception | None = None;
    for attempt in range(3) {
        try {
            response = httpx.post(
                "https://api.tavily.com/search",
                json={
                    "api_key": api_key,
                    "query": query,
                    "search_depth": "advanced",
                    "max_results": 10,
                    "include_answer": False
                },
                timeout=25.0
            );
            response.raise_for_status();
            return response.json().get("results", []);
        } except Exception as error {
            last_error = error;
            if attempt < 2 {
                time.sleep(0.25 * (attempt + 1));
            }
        }
    }
    raise last_error if last_error else RuntimeError("Tavily search failed");
}

def live_payload(entity_key: str, entity_name: str) -> dict {
    seeded = find_fixture(entity_key);
    results = tavily_search(entity_name);
    if not results {
        return seeded;
    }
    facts = extract_live_facts(entity_name, results);
    signals = classify_live_signals(facts);
    attributes: list[dict] = [];
    for fact in facts {
        if fact.evidence_index < 0 or fact.evidence_index >= len(results) {
            continue;
        }
        evidence = results[fact.evidence_index];
        source_url = str(evidence.get("url", ""));
        if not source_url.startswith("http") {
            continue;
        }
        attributes.append({
            "key": fact.key,
            "label": fact.label,
            "value": fact.value,
            "source_url": source_url,
            "source_title": str(evidence.get("title", "Live web source")),
            "excerpt": str(evidence.get("content", ""))[:400],
            "confidence": max(0.0, min(1.0, fact.confidence))
        });
    }
    if len(attributes) < 3 {
        return seeded;
    }
    normalized_signals: list[dict] = [];
    for signal in signals {
        if signal.category in SIGNAL_WEIGHTS {
            normalized_signals.append({
                "category": signal.category,
                "severity": max(0.0, min(1.0, signal.severity)),
                "rationale": signal.rationale,
                "evidence_key": signal.evidence_key
            });
        }
    }
    return {
        "key": entity_key,
        "name": entity_name,
        "identifier": seeded.get("identifier", entity_key),
        "sector": seeded.get("sector", "Custom"),
        "attributes": attributes,
        "signals": normalized_signals,
        "comparables": seeded.get("comparables", [])
    };
}

def research_payload(entity_key: str, entity_name: str, mode: str) -> dict {
    start = time.perf_counter();
    if mode == "live" and live_available() {
        payload = live_payload(entity_key, entity_name);
    } else {
        # Deliberate blocking I/O stand-in makes concurrency observable in demo
        # mode while all graph writes remain serialized in the orchestrator.
        delay = 0.38 + (len(entity_key) % 4) * 0.16;
        time.sleep(delay);
        payload = find_fixture(entity_key);
    }
    payload["_elapsed_ms"] = int((time.perf_counter() - start) * 1000);
    return payload;
}

def launch_research(entity_key: str, entity_name: str, mode: str) -> any {
    # Parameters are captured by value here before flow defers the call.
    return flow research_payload(entity_key, entity_name, mode);
}

def score_signals(signal_rows: list[dict]) -> tuple[float, int] {
    score: float = 0.0;
    categories: set[str] = set();
    for row in signal_rows {
        category = str(row.get("category", ""));
        if category not in SIGNAL_WEIGHTS {
            continue;
        }
        severity = max(0.0, min(1.0, float(row.get("severity", 0.0))));
        score += SIGNAL_WEIGHTS[category] * severity;
        if severity > 0.0 {
            categories.add(category);
        }
    }
    return (round(score, 1), len(categories));
}

def recommendation_for(score: float, signal_count: int) -> str {
    if score >= 70.0 and signal_count >= 2 {
        return "Escalate for manual credit review";
    }
    if score >= 50.0 and signal_count >= 2 {
        return "Request updated financials";
    }
    if score >= 50.0 {
        return "Seek independent corroboration";
    }
    if score >= 30.0 {
        return "Monitor and refresh evidence";
    }
    return "Proceed with standard diligence";
}

def status_for(score: float, signal_count: int) -> str {
    return "flagged" if score >= 50.0 and signal_count >= 2 else "done";
}

def build_report_markdown(
    batch: EntityBatch,
    entities: list[Entity]
) -> tuple[str, int] {
    ranked = sorted(
        entities,
        key=lambda (item: Entity) { return -item.risk_score; }
    );
    flagged = len([item for item in ranked if item.status == "flagged"]);
    lines: list[str] = [
        "# Meridian Diligence Report",
        "",
        f"**Snapshot:** {batch.snapshot_date}  ",
        f"**Entities:** {len(ranked)} · **Flagged:** {flagged}",
        "",
        "> Illustrative research prototype — not investment advice.",
        "",
        "## Ranked review"
    ];
    rank = 1;
    for entity in ranked {
        attributes = [entity->:HasAttribute:->];
        source = attributes[0] if attributes else None;
        lines.append(
            f"### {rank}. {entity.name} — {entity.risk_score:.1f}/100"
        );
        lines.append(
            f"**Action:** {entity.recommendation}  "
        );
        lines.append(
            f"**Coverage:** {entity.coverage:.0f}% · "
            f"**Independent signals:** {entity.signal_count}"
        );
        if source {
            lines.append(
                f"- Evidence: [{source.source_title}]({source.source_url}) — "
                f"{source.value}"
            );
        } else {
            lines.append("- Evidence incomplete; manual follow-up required.");
        }
        lines.append("");
        rank += 1;
    }
    lines.extend([
        "## Method",
        "",
        "The score is deterministic: credit rating changes 25%, borrowing "
        "cost versus peers 25%, legal exposure 20%, lender protections 15%, "
        "and missing disclosures 15%. "
        "Flagging requires a score of at least 50 and two independent signals."
    ]);
    return ("\n".join(lines), flagged);
}


walker:pub GetCapabilities {
    has reports: list[CapabilityView] = [];

    can inspect with Root entry {
        has_openai = bool(os.environ.get("OPENAI_API_KEY"));
        has_tavily = bool(os.environ.get("TAVILY_API_KEY"));
        report CapabilityView(
            live_available=has_openai and has_tavily,
            openai_configured=has_openai,
            tavily_configured=has_tavily,
            mode="live" if has_openai and has_tavily else "demo",
            extract_model=os.environ.get(
                "MERIDIAN_EXTRACT_MODEL", "gpt-5.6-luna"
            ),
            report_model=os.environ.get(
                "MERIDIAN_REPORT_MODEL", "gpt-5.6-terra"
            )
        );
    }
}


walker:pub CreateDemoBatch {
    has force: bool = False,
        request_id: str = "",
        reports: list[BatchBundle] = [];

    can create with Root entry {
        existing = [-->][?:EntityBatch];
        if existing and not self.force {
            batch = existing[0];
            entities = [batch->:ContainsEntity:->];
            reports = [batch->:HasReport:->];
            report BatchBundle(
                batch=batch,
                entities=entities,
                report=reports[0] if reports else None,
                live_available=live_available(),
                message="Loaded persistent Meridian workspace"
            );
            disengage;
        }
        data = load_demo_data();
        batch = (
            here +>:OwnsBatch:+> EntityBatch(
                title="Corporate Credit Watchlist",
                mode="demo",
                status="pending",
                snapshot_date=data["snapshot_date"],
                schema_fields=SCHEMA_FIELDS,
                total_entities=len(data["entities"])
            )
        )[0];
        for item in data["entities"] {
            batch +>:ContainsEntity:+> Entity(
                key=item["key"],
                name=item["name"],
                identifier=item["identifier"],
                sector=item["sector"]
            );
        }
        report BatchBundle(
            batch=batch,
            entities=[batch->:ContainsEntity:->],
            live_available=live_available(),
            message="Seeded eight-issuer diligence batch"
        );
    }
}


walker:pub CreateCsvBatch {
    has csv_text: str,
        title: str = "Custom diligence batch",
        request_id: str = "",
        reports: list[BatchBundle] = [];

    can create with Root entry {
        if len(self.csv_text.encode("utf-8")) > 1_000_000 {
            raise ValueError("CSV exceeds the 1 MB demo limit");
        }
        reader = csv.DictReader(io.StringIO(self.csv_text));
        if not reader.fieldnames or "name" not in [
            str(field).strip().lower() for field in reader.fieldnames
        ] {
            raise ValueError("CSV must include a name column");
        }
        rows = list(reader);
        if len(rows) == 0 or len(rows) > 50 {
            raise ValueError("CSV must contain between 1 and 50 entities");
        }
        seen: set[str] = set();
        normalized: list[dict] = [];
        for (index, row) in enumerate(rows) {
            name = str(row.get("name", "")).strip();
            identifier = str(row.get("identifier", "")).strip();
            identity = (identifier if identifier else name).lower();
            if not name {
                raise ValueError(f"Row {index + 2} is missing a name");
            }
            if identity in seen {
                raise ValueError(f"Duplicate entity on row {index + 2}");
            }
            seen.add(identity);
            normalized.append({
                "key": identity.replace(" ", "-"),
                "name": name,
                "identifier": identifier if identifier else name,
                "sector": str(row.get("sector", "Custom")).strip() or "Custom"
            });
        }
        batch = (
            here +>:OwnsBatch:+> EntityBatch(
                title=self.title,
                mode="demo",
                status="pending",
                snapshot_date=now_iso()[:10],
                schema_fields=SCHEMA_FIELDS,
                total_entities=len(normalized)
            )
        )[0];
        for item in normalized {
            batch +>:ContainsEntity:+> Entity(
                key=item["key"],
                name=item["name"],
                identifier=item["identifier"],
                sector=item["sector"]
            );
        }
        report BatchBundle(
            batch=batch,
            entities=[batch->:ContainsEntity:->],
            live_available=live_available(),
            message="Created custom CSV batch"
        );
    }
}


walker EntityResearcher {
    has payload: dict;

    can apply with Entity entry {
        for old_node in [-->] {
            del old_node;
        }
        here.status = "scoring";
        attributes = list(self.payload.get("attributes", []));
        for row in attributes {
            here +>:HasAttribute:+> Attribute(
                key=str(row.get("key", "")),
                label=str(row.get("label", "")),
                value=str(row.get("value", "")),
                source_url=str(row.get("source_url", "")),
                source_title=str(row.get("source_title", "Public source")),
                excerpt=str(row.get("excerpt", "")),
                confidence=float(row.get("confidence", 0.0)),
                captured_at=now_iso()
            );
        }
        signal_rows = list(self.payload.get("signals", []));
        for row in signal_rows {
            category = str(row.get("category", ""));
            severity = max(0.0, min(1.0, float(row.get("severity", 0.0))));
            weight = SIGNAL_WEIGHTS.get(category, 0.0);
            here +>:HasSignal:+> RiskSignal(
                category=category,
                severity=severity,
                weight=weight,
                contribution=round(weight * severity, 1),
                rationale=str(row.get("rationale", "")),
                evidence_key=str(row.get("evidence_key", ""))
            );
        }
        for comparable in self.payload.get("comparables", [])[:3] {
            here +>:HasSubEntity:+> SubEntity(name=str(comparable));
        }
        (score, count) = score_signals(signal_rows);
        here.risk_score = score;
        here.signal_count = count;
        here.coverage = round(
            min(100.0, (len(attributes) / max(1, len(SCHEMA_FIELDS))) * 100.0),
            0
        );
        here.recommendation = (
            recommendation_for(score, count)
            if attributes
            else "Enable live mode or provide seeded evidence"
        );
        here.status = status_for(score, count) if attributes else "partial";
        here.error = (
            ""
            if attributes
            else "No seeded evidence matched this custom entity"
        );
        here.elapsed_ms = int(self.payload.get("_elapsed_ms", 0));
    }
}


walker:pub Orchestrator {
    has mode: str = "demo",
        request_id: str = "",
        reports: list[BatchBundle] = [];

    can start with Root entry {
        visit [-->][?:EntityBatch];
    }

    can run with EntityBatch entry {
        run_started = time.perf_counter();
        requested_mode = (
            "live" if self.mode == "live" and live_available() else "demo"
        );
        here.mode = requested_mode;
        here.status = "researching";
        here.started_at = now_iso();
        here.completed_entities = 0;
        entities = [->:ContainsEntity:->];
        futures: list = [];
        for entity in entities {
            entity.status = "researching";
            entity.error = "";
            futures.append(
                launch_research(entity.key, entity.name, requested_mode)
            );
        }
        for index in range(len(entities)) {
            try {
                payload = wait futures[index];
                entities[index] spawn EntityResearcher(payload=payload);
            } except Exception as error {
                fallback = find_fixture(entities[index].key);
                if fallback {
                    fallback["_elapsed_ms"] = 0;
                    entities[index] spawn EntityResearcher(payload=fallback);
                } else {
                    entities[index].status = "partial";
                    entities[index].error = str(error);
                }
            }
            here.completed_entities += 1;
        }
        here.status = "reporting";
        report_result = here spawn Reporter();
        here.status = "done";
        here.finished_at = now_iso();
        here.sequential_ms = sum([
            entity.elapsed_ms for entity in entities
        ]);
        here.wall_clock_ms = max(
            1,
            int((time.perf_counter() - run_started) * 1000)
        );
        reports = [->:HasReport:->];
        report BatchBundle(
            batch=here,
            entities=entities,
            report=reports[0] if reports else None,
            live_available=live_available(),
            message=(
                "Live research complete"
                if requested_mode == "live"
                else "Concurrent seeded research complete"
            )
        );
    }
}


walker Reporter {
    can build with EntityBatch entry {
        for old_report in [->:HasReport:->] {
            del old_report;
        }
        entities = [->:ContainsEntity:->];
        (markdown, flagged) = build_report_markdown(here, entities);
        report_node = (
            here +>:HasReport:+> Report(
                summary_md=markdown,
                generated_at=now_iso(),
                entity_count=len(entities),
                flagged_count=flagged
            )
        )[0];
        for entity in entities {
            entity +>:IncludedIn:+> report_node;
        }
    }
}


walker:pub GetBatch {
    has request_id: str = "",
        reports: list[BatchBundle] = [];

    can start with Root entry {
        visit [-->][?:EntityBatch];
    }

    can collect with EntityBatch entry {
        entities = [->:ContainsEntity:->];
        report_nodes = [->:HasReport:->];
        report BatchBundle(
            batch=here,
            entities=entities,
            report=report_nodes[0] if report_nodes else None,
            live_available=live_available(),
            message="Current persistent batch"
        );
        disengage;
    }
}


walker:pub GetEntityDetail {
    has entity_id: str,
        request_id: str = "",
        reports: list[EntityDetail] = [];

    can start with Root entry {
        visit [-->][?:EntityBatch];
    }

    can enter_batch with EntityBatch entry {
        visit [->:ContainsEntity:->];
    }

    can collect with Entity entry {
        if here.key == self.entity_id {
            report EntityDetail(
                entity=here,
                attributes=[->:HasAttribute:->],
                signals=[->:HasSignal:->],
                comparables=[->:HasSubEntity:->]
            );
            disengage;
        }
    }
}


walker:pub ResetWorkspace {
    has request_id: str = "";

    can start with Root entry {
        visit [-->];
    }

    can descend with EntityBatch | Entity entry {
        visit [-->];
    }

    can remove with EntityBatch | Entity | Attribute | SubEntity | RiskSignal | Report exit {
        del here;
    }
}
