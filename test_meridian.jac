"""Deterministic unit and concurrency checks for Meridian."""

import time;

import from endpoints {
    SCHEMA_FIELDS,
    SIGNAL_WEIGHTS,
    load_demo_data,
    score_signals,
    recommendation_for,
    status_for,
    launch_research
}


test "demo fixture contains eight complete issuers" {
    data = load_demo_data();
    entities = data["entities"];
    assert len(entities) == 8, "the no-key demo must remain deterministic";
    assert len(SCHEMA_FIELDS) == 5;
    for entity in entities {
        assert len(entity["attributes"]) == 5;
        for attribute in entity["attributes"] {
            assert str(attribute["source_url"]).startswith("https://");
        }
    }
}


test "risk score is deterministic and explainable" {
    signals = [
        {"category": "rating_action", "severity": 1.0},
        {"category": "yield_deviation", "severity": 0.8},
        {"category": "litigation", "severity": 0.5},
        {"category": "unknown", "severity": 1.0}
    ];
    (score, count) = score_signals(signals);
    assert score == 55.0;
    assert count == 3;
    assert SIGNAL_WEIGHTS["rating_action"] == 25.0;
    assert status_for(score, count) == "flagged";
    assert recommendation_for(score, count) == "Request updated financials";
}


test "single high signal does not meet corroboration rule" {
    assert status_for(75.0, 1) == "done";
    assert status_for(50.0, 2) == "flagged";
    assert recommendation_for(25.0, 2) == "Proceed with standard diligence";
}


test "research flows execute concurrently" {
    started = time.perf_counter();
    futures: list = [];
    for key in ["boeing", "ford-credit", "carnival", "wbd"] {
        futures.append(launch_research(key, key, "demo"));
    }
    payloads: list = [];
    for future in futures {
        payloads.append(wait future);
    }
    elapsed = time.perf_counter() - started;
    sequential_ms = sum([
        int(payload["_elapsed_ms"]) for payload in payloads
    ]);
    wall_clock_ms = int(elapsed * 1000);
    assert len(payloads) == 4;
    assert elapsed < 1.5, "flows should fan out instead of sleeping serially";
    assert sequential_ms > wall_clock_ms * 2, (
        "the sum of worker times should visibly exceed parallel wall time"
    );
}
