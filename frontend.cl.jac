"""Meridian client: institutional diligence workspace."""

sv import from endpoints {
    Entity,
    Attribute,
    RiskSignal,
    SubEntity,
    Report,
    BatchBundle,
    EntityDetail,
    CapabilityView,
    CreateDemoBatch,
    CreateCsvBatch,
    Orchestrator,
    GetBatch,
    GetEntityDetail,
    GetCapabilities,
    ResetWorkspace
}

import from "lucide-react" {
    Activity,
    ArrowUpRight,
    Check,
    ChevronRight,
    CircleAlert,
    Database,
    Download,
    ExternalLink,
    FileSearch,
    FileText,
    GitBranch,
    Play,
    RefreshCw,
    Search,
    ShieldCheck,
    Sparkles,
    Upload,
    X
}

cl import ".styles.css";


def risk_class(score: float) -> str {
    if score >= 70.0 {
        return "risk-critical";
    }
    if score >= 50.0 {
        return "risk-high";
    }
    if score >= 30.0 {
        return "risk-medium";
    }
    return "risk-low";
}

def status_label(status: str) -> str {
    labels = {
        "pending": "Queued",
        "researching": "Researching",
        "scoring": "Scoring",
        "done": "Reviewed",
        "flagged": "Flagged",
        "partial": "Partial",
        "failed": "Failed"
    };
    return labels.get(status, status);
}

def signal_label(category: str) -> str {
    labels = {
        "rating_action": "Credit rating changes",
        "yield_deviation": "Borrowing cost vs peers",
        "litigation": "Legal exposure",
        "covenant_strength": "Lender protections",
        "disclosure_gap": "Missing disclosures"
    };
    return labels.get(category, category.replace("_", " "));
}

def csv_escape(value: str) -> str {
    return '"' + value.replace('"', '""') + '"';
}


def:pub app -> JsxElement {
    has bundle: BatchBundle | None = None,
        capabilities: CapabilityView | None = None,
        selected: EntityDetail | None = None,
        activeView: str = "workspace",
        runMode: str = "demo",
        isRunning: bool = False,
        isLoading: bool = True,
        elapsedSeconds: int = 0,
        runMessage: str = "",
        uploadError: str = "",
        searchQuery: str = "";

    async can with entry {
        try {
            capResult = root spawn GetCapabilities();
            capabilities = capResult.reports[0] if capResult.reports else None;
            setupResult = root spawn CreateDemoBatch(
                request_id=str(Date.now())
            );
            initialBundle = (
                setupResult.reports[0] if setupResult.reports else None
            );
            bundle = initialBundle;
            if initialBundle and initialBundle.entities {
                await selectEntity(initialBundle.entities[0].key);
            }
        } except Exception as error {
            runMessage = f"Could not initialize Meridian: {error}";
        }
        isLoading = False;
    }

    async def runResearch {
        if isRunning {
            return;
        }
        isRunning = True;
        elapsedSeconds = 0;
        runMessage = (
            "Launching live Tavily + byLLM research"
            if runMode == "live"
            else "Launching eight concurrent Jac research workers"
        );
        if bundle {
            for entity in bundle.entities {
                entity.status = "researching";
            }
        }
        intervalHandle = setInterval(lambda {
            elapsedSeconds = elapsedSeconds + 1;
        }, 1000);
        try {
            # Re-establish the persistent demo batch after a backend restart while
            # preserving an existing demo or CSV batch when one is available.
            root spawn CreateDemoBatch(request_id=str(Date.now()));
            response = root spawn Orchestrator(
                mode=runMode,
                request_id=str(Date.now())
            );
            completedBundle = (
                response.reports[0] if response.reports else None
            );
            if not completedBundle {
                currentResponse = root spawn GetBatch(
                    request_id=str(Date.now())
                );
                completedBundle = (
                    currentResponse.reports[0]
                    if currentResponse.reports
                    else None
                );
            }
            if not completedBundle {
                # A long-lived browser tab can outlast its development backend.
                # Rebuild the demo graph once so Run remains a one-click action.
                root spawn ResetWorkspace(request_id=str(Date.now()));
                root spawn CreateDemoBatch(
                    force=True,
                    request_id=str(Date.now())
                );
                recoveryResponse = root spawn Orchestrator(
                    mode=runMode,
                    request_id=str(Date.now())
                );
                completedBundle = (
                    recoveryResponse.reports[0]
                    if recoveryResponse.reports
                    else None
                );
            }
            if completedBundle {
                bundle = completedBundle;
                runMessage = completedBundle.message;
                if completedBundle.entities {
                    await selectEntity(completedBundle.entities[0].key);
                }
            } else {
                runMessage = "No active diligence batch was returned";
            }
        } except Exception as error {
            runMessage = f"Research interrupted: {error}";
        }
        clearInterval(intervalHandle);
        isRunning = False;
    }

    async def selectEntity(entityId: str) {
        try {
            response = root spawn GetEntityDetail(
                entity_id=entityId,
                request_id=str(Date.now())
            );
            selected = response.reports[0] if response.reports else None;
        } except Exception as error {
            runMessage = f"Could not load evidence: {error}";
        }
    }

    async def resetDemo {
        isLoading = True;
        selected = None;
        root spawn ResetWorkspace(request_id=str(Date.now()));
        response = root spawn CreateDemoBatch(
            force=True,
            request_id=str(Date.now())
        );
        resetBundle = response.reports[0] if response.reports else None;
        bundle = resetBundle;
        runMode = "demo";
        runMessage = "Demo workspace reset";
        if resetBundle and resetBundle.entities {
            await selectEntity(resetBundle.entities[0].key);
        }
        isLoading = False;
    }

    async def uploadCsv(event: ChangeEvent) {
        uploadError = "";
        file = event.target.files[0] if event.target.files else None;
        if not file {
            return;
        }
        try {
            csvText = await file.text();
            root spawn ResetWorkspace(request_id=str(Date.now()));
            response = root spawn CreateCsvBatch(
                csv_text=csvText,
                title=file.name.replace(".csv", ""),
                request_id=str(Date.now())
            );
            csvBundle = response.reports[0] if response.reports else None;
            bundle = csvBundle;
            runMessage = f"Loaded {file.name}";
            if csvBundle and csvBundle.entities {
                await selectEntity(csvBundle.entities[0].key);
            }
        } except Exception as error {
            uploadError = str(error);
        }
        event.target.value = "";
    }

    def downloadText(filename: str, content: str, contentType: str) {
        anchor = document.createElement("a");
        anchor.href = (
            "data:" + contentType + ";charset=utf-8," + encodeURIComponent(content)
        );
        anchor.download = filename;
        document.body.appendChild(anchor);
        anchor.click();
        document.body.removeChild(anchor);
    }

    def exportMarkdown {
        if bundle and bundle.report {
            downloadText(
                "meridian-diligence-report.md",
                bundle.report.summary_md,
                "text/markdown"
            );
        }
    }

    def exportCsv {
        if not bundle {
            return;
        }
        csvText = (
            "rank,name,identifier,sector,risk_score,status,recommendation,coverage"
        );
        ranked = sorted(
            bundle.entities,
            key=lambda (entity: Entity) { return -entity.risk_score; }
        );
        rank = 1;
        for entity in ranked {
            csvText += (
                "\n" + str(rank)
                + "," + csv_escape(entity.name)
                + "," + csv_escape(entity.identifier)
                + "," + csv_escape(entity.sector)
                + "," + str(entity.risk_score)
                + "," + csv_escape(entity.status)
                + "," + csv_escape(entity.recommendation)
                + "," + str(entity.coverage)
            );
            rank += 1;
        }
        downloadText(
            "meridian-ranked-entities.csv",
            csvText,
            "text/csv"
        );
    }

    if isLoading {
        return
            <div className="loading-shell">
                <div className="loading-mark"><Sparkles size={24}/></div>
                <div>
                    <strong>Opening Meridian</strong>
                    <span>Loading the persistent diligence graph…</span>
                </div>
            </div>;
    }

    entities = bundle.entities if bundle else [];
    filteredEntities = [
        entity
        for entity in entities
        if not searchQuery
        or searchQuery.lower() in entity.name.lower()
        or searchQuery.lower() in entity.identifier.lower()
    ];
    rankedEntities = sorted(
        filteredEntities,
        key=lambda (entity: Entity) { return -entity.risk_score; }
    );
    completed = len([
        entity
        for entity in entities
        if entity.status in ["done", "flagged", "partial"]
    ]);
    flagged = len([
        entity
        for entity in entities
        if entity.status == "flagged"
    ]);
    averageScore = (
        sum([entity.risk_score for entity in entities]) / len(entities)
        if entities
        else 0.0
    );
    hasReport = bool(bundle and bundle.report);
    liveEnabled = bool(capabilities and capabilities.live_available);
    hasParallelProof = bool(
        bundle
        and bundle.batch.wall_clock_ms > 0
        and bundle.batch.sequential_ms > 0
    );
    wallClockSeconds = (
        round(bundle.batch.wall_clock_ms / 1000.0, 1)
        if hasParallelProof
        else 0.0
    );
    sequentialSeconds = (
        round(bundle.batch.sequential_ms / 1000.0, 1)
        if hasParallelProof
        else 0.0
    );
    speedup = (
        round(
            bundle.batch.sequential_ms / bundle.batch.wall_clock_ms,
            1
        )
        if hasParallelProof
        else 0.0
    );

    return
        <div className="app-shell">
            <header className="topbar">
                <div className="brand-lockup">
                    <div className="brand-symbol">
                        <span></span><span></span><span></span>
                    </div>
                    <div>
                        <div className="brand-name">MERIDIAN</div>
                        <div className="brand-subtitle">Parallel diligence mesh</div>
                    </div>
                </div>
                <nav className="view-switcher" aria-label="Primary views">
                    <button
                        className={"view-tab active" if activeView == "workspace" else "view-tab"}
                        onClick={lambda { activeView = "workspace"; }}
                    >
                        Workspace
                    </button>
                    <button
                        className={"view-tab active" if activeView == "report" else "view-tab"}
                        onClick={lambda { activeView = "report"; }}
                    >
                        Report
                        {if hasReport {
                            <span key="report-ready" className="tab-dot"></span>
                        }}
                    </button>
                </nav>
                <div className="topbar-actions">
                    <div className={"mode-trust-badge " + runMode}>
                        <span className="mode-trust-dot"></span>
                        <div>
                            <strong>
                                {("LIVE APIs" if runMode == "live" else "SEEDED DEMO")}
                            </strong>
                            <small>
                                {(
                                    "OpenAI + Tavily"
                                    if runMode == "live"
                                    else "Frozen evidence · real Jac execution"
                                )}
                            </small>
                        </div>
                    </div>
                    <div className="snapshot-chip">
                        <Database size={14}/>
                        Snapshot {bundle.batch.snapshot_date if bundle else "—"}
                    </div>
                    <button className="icon-button" title="Reset demo" onClick={resetDemo}>
                        <RefreshCw size={17}/>
                    </button>
                    <div className="run-action-cluster">
                        <button
                            className="primary-button compact"
                            onClick={runResearch}
                            disabled={isRunning}
                        >
                            {if isRunning {
                                <RefreshCw key="running-icon" className="spin" size={16}/>
                                <span key="running-label">Running · {elapsedSeconds}s</span>
                            } else {
                                <Play key="run-icon" size={16}/>
                                <span key="run-label">Run diligence</span>
                            }}
                        </button>
                        {if hasParallelProof {
                            <div
                                key="parallel-proof"
                                className="parallel-proof"
                                title="Measured wall-clock run time compared with the sum of all issuer worker times"
                            >
                                <strong>{wallClockSeconds}s parallel</strong>
                                <span>vs {sequentialSeconds}s one-by-one</span>
                                <b>{speedup}× faster</b>
                            </div>
                        } else {
                            <div key="parallel-pending" className="parallel-proof pending">
                                8 Jac workers launch together
                            </div>
                        }}
                    </div>
                </div>
            </header>

            {if activeView == "workspace" {
                <div key="workspace" className="workspace-layout">
                    <aside className="left-rail">
                        <section className="rail-section">
                            <div className="section-eyebrow">Dataset</div>
                            <div className="dataset-card">
                                <div className="dataset-icon"><Database size={18}/></div>
                                <div className="dataset-copy">
                                    <strong>{bundle.batch.title if bundle else "No batch"}</strong>
                                    <span>{len(entities)} issuers · 5 diligence fields</span>
                                </div>
                                <Check size={16} className="success-icon"/>
                            </div>
                            <label className="upload-button">
                                <Upload size={15}/>
                                Upload entity CSV
                                <input
                                    type="file"
                                    accept=".csv,text/csv"
                                    onChange={uploadCsv}
                                />
                            </label>
                            {if uploadError {
                                <div key="upload-error" className="inline-error">
                                    <CircleAlert size={14}/>{uploadError}
                                </div>
                            }}
                        </section>

                        <section className="rail-section">
                            <div className="section-eyebrow">Execution mode</div>
                            <button
                                className={"mode-card selected" if runMode == "demo" else "mode-card"}
                                onClick={lambda { runMode = "demo"; }}
                            >
                                <div className="mode-radio"></div>
                                <div>
                                    <strong>Seeded evidence</strong>
                                    <span>No keys required · deterministic</span>
                                </div>
                            </button>
                            <button
                                className={"mode-card selected" if runMode == "live" else "mode-card"}
                                onClick={lambda { if liveEnabled { runMode = "live"; }}}
                                disabled={not liveEnabled}
                            >
                                <div className="mode-radio"></div>
                                <div>
                                    <strong>Live research</strong>
                                    <span>
                                        {(
                                            "OpenAI + Tavily ready"
                                            if liveEnabled
                                            else "Add API keys to enable"
                                        )}
                                    </span>
                                </div>
                            </button>
                        </section>

                        <section className="rail-section schema-section">
                            <div className="section-eyebrow">Research schema</div>
                            {for (field, weight) in [
                                ("Use of proceeds", "Context"),
                                ("Lender protections", "15%"),
                                ("Credit rating changes", "25%"),
                                ("Borrowing cost vs peers", "25%"),
                                ("Legal exposure", "20%"),
                                ("Missing disclosures", "15%")
                            ] {
                                <div className="schema-row" key={field}>
                                    <span>{field}</span>
                                    <small>{weight}</small>
                                </div>
                            }}
                        </section>

                        <div className="rail-footnote">
                            <ShieldCheck size={15}/>
                            Claims are bound to stored source URLs. Unknown citations are rejected.
                        </div>
                    </aside>

                    <main className="main-canvas">
                        <section className="hero-strip">
                            <div>
                                <div className="section-eyebrow">Credit risk screening · before market open</div>
                                <h1>Find hidden credit risk across a bond watchlist</h1>
                                <p>
                                    Eight Jac researchers work in parallel, anchor every
                                    finding to a source, and turn five credit checks into
                                    one explainable ranking.
                                </p>
                            </div>
                            <div className="hero-meta">
                                <div className="live-indicator">
                                    <span className={("pulse-dot active" if isRunning else "pulse-dot")}></span>
                                    {("Workers active" if isRunning else "Workspace ready")}
                                </div>
                                <div className="run-message">{runMessage or "Select Run diligence to execute the mesh"}</div>
                            </div>
                        </section>

                        <section className="metrics-grid">
                            <div className="metric-card">
                                <span>Entities</span>
                                <strong>{len(entities)}</strong>
                                <small>{completed} completed</small>
                            </div>
                            <div className="metric-card">
                                <span>Flagged</span>
                                <strong className="metric-risk">{flagged}</strong>
                                <small>Two-signal minimum</small>
                            </div>
                            <div className="metric-card">
                                <span>Average risk</span>
                                <strong>{round(averageScore, 1)}</strong>
                                <small>Deterministic / 100</small>
                            </div>
                            <div className="metric-card">
                                <span>Evidence fields</span>
                                <strong>{completed * 5}</strong>
                                <small>URL-anchored claims</small>
                            </div>
                        </section>

                        <section className="mesh-panel">
                            <div className="panel-heading">
                                <div>
                                    <div className="section-eyebrow">Concurrent execution proof</div>
                                    <h2>Parallel issuer research</h2>
                                </div>
                                <div className="mesh-heading-meta">
                                    {if hasParallelProof {
                                        <div key="mesh-proof-line" className="mesh-proof-line">
                                            <Activity size={14}/>
                                            <strong>{wallClockSeconds}s parallel</strong>
                                            <span>vs {sequentialSeconds}s one-by-one</span>
                                            <b>{speedup}× faster</b>
                                        </div>
                                    }}
                                    <div className="pipeline-legend">
                                        <span><i className="legend-dot queued"></i>Queued</span>
                                        <span><i className="legend-dot running"></i>Active</span>
                                        <span><i className="legend-dot complete"></i>Complete</span>
                                    </div>
                                </div>
                            </div>
                            <div className="pipeline">
                                {for step in [
                                    "Batch",
                                    "Research",
                                    "Extract",
                                    "Score",
                                    "Report"
                                ] {
                                    <div
                                        key={step}
                                        className={"pipeline-step active" if (isRunning or completed > 0) else "pipeline-step"}
                                    >
                                        <div className="pipeline-icon">
                                            {if step == "Batch" { <Database key="batch-icon" size={15}/> }}
                                            {if step == "Research" { <Search key="research-icon" size={15}/> }}
                                            {if step == "Extract" { <FileSearch key="extract-icon" size={15}/> }}
                                            {if step == "Score" { <Activity key="score-icon" size={15}/> }}
                                            {if step == "Report" { <FileText key="report-icon" size={15}/> }}
                                        </div>
                                        <span>{step}</span>
                                    </div>
                                    if step != "Report" {
                                        <ChevronRight key={step + "-arrow"} className="pipeline-arrow" size={15}/>
                                    }
                                }}
                            </div>
                            <div className="worker-grid">
                                {for entity in entities {
                                    <button
                                        key={entity.key}
                                        className={
                                            "worker-card selected"
                                            if selected and selected.entity.key == entity.key
                                            else "worker-card"
                                        }
                                        onClick={lambda { selectEntity(entity.key); }}
                                    >
                                        <div className="worker-topline">
                                            <span className={"worker-status " + entity.status}></span>
                                            <small>{status_label(entity.status)}</small>
                                            {if entity.elapsed_ms > 0 {
                                                <small key="elapsed" className="worker-time">{entity.elapsed_ms}ms</small>
                                            }}
                                        </div>
                                        <strong>{entity.name}</strong>
                                        <span>{entity.identifier}</span>
                                        <div className="worker-progress">
                                            <i style={{"width": (
                                                "100%"
                                                if entity.status in ["done", "flagged"]
                                                else ("62%" if entity.status == "researching" else "12%")
                                            )}}></i>
                                        </div>
                                    </button>
                                }}
                            </div>
                        </section>

                        <section className="ranking-panel">
                            <div className="panel-heading ranking-heading">
                                <div>
                                    <div className="section-eyebrow">Decision queue</div>
                                    <h2>Ranked entities</h2>
                                    <p className="ranking-explainer">
                                        Five weighted risk checks—ratings, market pricing,
                                        legal exposure, lender protections, and disclosure
                                        quality—must be independently corroborated.
                                    </p>
                                </div>
                                <div className="table-tools">
                                    <label className="search-box">
                                        <Search size={15}/>
                                        <input
                                            value={searchQuery}
                                            onChange={lambda (event: ChangeEvent) {
                                                searchQuery = event.target.value;
                                            }}
                                            placeholder="Filter issuers"
                                        />
                                        {if searchQuery {
                                            <button key="clear-search" onClick={lambda { searchQuery = ""; }}><X size={14}/></button>
                                        }}
                                    </label>
                                    <button className="secondary-button" onClick={exportCsv}>
                                        <Download size={15}/> CSV
                                    </button>
                                </div>
                            </div>
                            <div className="entity-table">
                                <div className="table-row table-header">
                                    <span>Rank / entity</span>
                                    <span>Sector</span>
                                    <span>Coverage</span>
                                    <span>Risk score</span>
                                    <span>Recommended action</span>
                                    <span></span>
                                </div>
                                {for (index, entity) in enumerate(rankedEntities) {
                                    <button
                                        key={entity.key}
                                        className="table-row"
                                        onClick={lambda { selectEntity(entity.key); }}
                                    >
                                        <span className="entity-cell">
                                            <i>{index + 1}</i>
                                            <span>
                                                <strong>{entity.name}</strong>
                                                <small>{entity.identifier}</small>
                                            </span>
                                        </span>
                                        <span>{entity.sector}</span>
                                        <span>
                                            <div className="coverage-cell">
                                                <i><b style={{"width": f"{entity.coverage}%"}}></b></i>
                                                {int(round(entity.coverage))}%
                                            </div>
                                        </span>
                                        <span>
                                            <div className={"risk-pill " + risk_class(entity.risk_score)}>
                                                {round(entity.risk_score, 1)}
                                            </div>
                                        </span>
                                        <span className="action-cell">{entity.recommendation}</span>
                                        <span><ChevronRight size={16}/></span>
                                    </button>
                                }}
                            </div>
                        </section>
                    </main>

                    <aside className="evidence-drawer">
                        {if selected {
                            <div key="drawer-header" className="drawer-header">
                                <div>
                                    <div className="section-eyebrow">Evidence record</div>
                                    <h2>{selected.entity.name}</h2>
                                    <span>{selected.entity.identifier} · {selected.entity.sector}</span>
                                </div>
                                <div className={"score-orb " + risk_class(selected.entity.risk_score)}>
                                    <strong>{round(selected.entity.risk_score, 1)}</strong>
                                    <span>risk</span>
                                </div>
                            </div>
                            <div key="recommendation" className="recommendation-box">
                                <ShieldCheck size={18}/>
                                <div>
                                    <small>Recommended next action</small>
                                    <strong>{selected.entity.recommendation}</strong>
                                </div>
                            </div>
                            <div key="drawer-tabs" className="drawer-tabs">
                                <button className="active">Evidence</button>
                                <button>Signals <span>{len(selected.signals)}</span></button>
                                <button>Comparables <span>{len(selected.comparables)}</span></button>
                            </div>
                            <div key="evidence-list" className="evidence-list">
                                {if not selected.attributes {
                                    <div key="no-evidence" className="drawer-empty">
                                        <FileSearch size={24}/>
                                        <strong>No evidence collected yet</strong>
                                        <span>Run the diligence mesh to populate this graph.</span>
                                    </div>
                                }}
                                {for attribute in selected.attributes {
                                    <article className="evidence-card" key={attribute.key}>
                                        <div className="evidence-card-top">
                                            <span>{attribute.label}</span>
                                            <small>{int(round(attribute.confidence * 100))}% confidence</small>
                                        </div>
                                        <p>{attribute.value}</p>
                                        <blockquote>{attribute.excerpt}</blockquote>
                                        <a
                                            href={attribute.source_url}
                                            target="_blank"
                                            rel="noreferrer"
                                        >
                                            <ExternalLink size={13}/>
                                            {attribute.source_title}
                                        </a>
                                    </article>
                                }}
                            </div>
                            if selected.signals {
                                <div key="signals" className="signal-section">
                                    <div className="section-eyebrow">Corroboration trail</div>
                                    {for signal in selected.signals {
                                        <div className="signal-row" key={signal.category}>
                                            <div>
                                                <strong>{signal_label(signal.category)}</strong>
                                                <span>{signal.rationale}</span>
                                            </div>
                                            <b>+{round(signal.contribution, 1)}</b>
                                        </div>
                                    }}
                                </div>
                            }
                            if selected.comparables {
                                <div key="comparables" className="signal-section">
                                    <div className="section-eyebrow">Comparable instruments</div>
                                    {for comparable in selected.comparables {
                                        <div className="comparable-row" key={comparable.name}>
                                            <GitBranch size={14}/>
                                            <span>{comparable.name}</span>
                                        </div>
                                    }}
                                </div>
                            }
                        } else {
                            <div key="no-selection" className="drawer-empty standalone">
                                <FileSearch size={30}/>
                                <strong>Select an issuer</strong>
                                <span>Its sourced evidence and score calculation will appear here.</span>
                            </div>
                        }}
                    </aside>
                </div>
            } else {
                <main key="report-view" className="report-view">
                    <div className="report-toolbar">
                        <div>
                            <div className="section-eyebrow">Reporter walker output</div>
                            <h1>Ranked diligence report</h1>
                            <p>Every linked claim resolves to evidence stored in the Jac graph.</p>
                        </div>
                        <div>
                            <button className="secondary-button" onClick={exportCsv}>
                                <Download size={15}/> Export CSV
                            </button>
                            <button
                                className="primary-button"
                                onClick={exportMarkdown}
                                disabled={not hasReport}
                            >
                                <FileText size={15}/> Download Markdown
                            </button>
                        </div>
                    </div>
                    {if bundle and bundle.report {
                        <div key="report-paper" className="report-paper">
                            <div className="report-cover">
                                <div className="brand-symbol large">
                                    <span></span><span></span><span></span>
                                </div>
                                <span>MERIDIAN / DILIGENCE MEMORANDUM</span>
                                <h2>{bundle.batch.title}</h2>
                                <p>
                                    Generated {bundle.report.generated_at[:10]} ·
                                    {bundle.report.entity_count} entities ·
                                    {bundle.report.flagged_count} flagged
                                </p>
                            </div>
                            <pre className="report-markdown">{bundle.report.summary_md}</pre>
                        </div>
                    } else {
                        <div key="report-empty" className="report-empty">
                            <FileText size={32}/>
                            <h2>No report yet</h2>
                            <p>Run the diligence mesh to research, score, and rank the active batch.</p>
                            <button className="primary-button" onClick={lambda {
                                activeView = "workspace";
                                runResearch();
                            }}>
                                <Play size={16}/> Run diligence
                            </button>
                        </div>
                    }}
                </main>
            }}

            <footer className="app-footer">
                <span>Meridian is an explainable research prototype, not investment advice.</span>
                <span>Built with Jac OSP · byLLM-ready · Tavily-ready</span>
            </footer>
        </div>;
}
