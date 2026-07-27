"""SafeWire Elder Scam Command Center client."""

sv import from endpoints {
    Customer,
    Account,
    Transfer,
    ScamSignal,
    InvestigationCase,
    EvidenceSpan,
    GraphNodeView,
    GraphEdgeView,
    CapabilityView,
    CaseSummary,
    CommandCenterBundle,
    CaseDetail,
    ImportResult,
    AnalystDecisionView,
    CreateDemoWorkspace,
    ImportTransferCsv,
    GetCommandCenter,
    GetCaseDetail,
    GetCapabilities,
    RecordAnalystDecision,
    ResetWorkspace
}

import from "lucide-react" {
    Activity,
    AlertTriangle,
    ArrowRight,
    BadgeCheck,
    Check,
    CheckCircle2,
    ChevronRight,
    CircleDot,
    Clock3,
    Database,
    Download,
    FileCheck2,
    FileText,
    GitBranch,
    Info,
    Network,
    PhoneCall,
    Play,
    RefreshCw,
    Search,
    Shield,
    ShieldAlert,
    Sparkles,
    Upload,
    UserCheck,
    XCircle,
    Zap
}

cl import ".styles.css";


def money(value: float) -> str {
    return "$" + value.toLocaleString(
        "en-US",
        {"minimumFractionDigits": 0, "maximumFractionDigits": 0}
    );
}

def score_tone(score: int) -> str {
    if score >= 70 {
        return "critical";
    }
    if score >= 50 {
        return "high";
    }
    if score >= 30 {
        return "medium";
    }
    return "low";
}

def short_worker(name: str) -> str {
    labels = {
        "BehaviorBaselineWalker": "Behavior baseline",
        "RecipientNetworkWalker": "Recipient network",
        "MoneyFlowWalker": "Money flow",
        "IdentityLinkWalker": "Identity links",
        "ScamContextWalker": "Scam context",
        "SkepticWalker": "Skeptic review",
        "InterventionWalker": "Intervention"
    };
    return labels.get(name, name.replace("Walker", ""));
}

def worker_path(name: str) -> str {
    labels = {
        "BehaviorBaselineWalker": "Customer → Account → Transfer history",
        "RecipientNetworkWalker": "Transfer → Recipient → Peer senders",
        "MoneyFlowWalker": "Transfer → Downstream → Merchant",
        "IdentityLinkWalker": "Account → Device → IP",
        "ScamContextWalker": "Transfer → supplied call note",
        "SkepticWalker": "Invoice → relationship → merchant",
        "InterventionWalker": "Signals → policy → case"
    };
    return labels.get(name, "Graph traversal");
}

def signal_plain_language(category: str) -> str {
    labels = {
        "behavior_anomaly": "Is this unlike the customer's normal behavior?",
        "recipient_network": "Are other older customers paying the same network?",
        "rapid_money_flow": "Does the money move out too quickly to recover?",
        "shared_identity": "Do supposedly separate accounts share devices or IPs?",
        "scam_context": "Does the customer's own note show coercion?"
    };
    return labels.get(category, "Independent fraud-risk category");
}

def is_discovery_node(transfer_id: str, node_id: str) -> bool {
    paths = {
        "TX-RUTH-4800": {
            "TX-RUTH-4800", "ACC-RAVEN-001", "DEV-RAVEN-7",
            "ACC-RAVEN-002", "CASE-2026-041",
            "TX-RUTH-FORWARD-1", "MERCHANT-ARCLIGHT"
        },
        "TX-HAROLD-5200": {
            "TX-HAROLD-5200", "ACC-BAYVIEW-001",
            "DEV-BAYVIEW-2", "MERCHANT-BAYVIEW"
        }
    };
    return node_id in paths.get(transfer_id, set());
}

def is_discovery_edge(transfer_id: str, edge_id: str) -> bool {
    paths = {
        "TX-RUTH-4800": {
            "TX-RUTH-4800|RECEIVED|ACC-RAVEN-001",
            "ACC-RAVEN-001|USES_DEVICE|DEV-RAVEN-7",
            "ACC-RAVEN-002|USES_DEVICE|DEV-RAVEN-7",
            "ACC-RAVEN-002|INCLUDED_IN_CASE|CASE-2026-041",
            "TX-RUTH-4800|FORWARDED_TO|TX-RUTH-FORWARD-1",
            "TX-RUTH-FORWARD-1|RECEIVED|MERCHANT-ARCLIGHT"
        },
        "TX-HAROLD-5200": {
            "TX-HAROLD-5200|RECEIVED|ACC-BAYVIEW-001",
            "ACC-BAYVIEW-001|USES_DEVICE|DEV-BAYVIEW-2",
            "TX-HAROLD-5200|RECEIVED|MERCHANT-BAYVIEW"
        }
    };
    return edge_id in paths.get(transfer_id, set());
}

def discovery_lanes(transfer_id: str) -> list[dict] {
    if transfer_id == "TX-HAROLD-5200" {
        return [
            {
                "label": "Identity verification path",
                "steps": [
                    {"id": "TX-HAROLD-5200", "relation": "START", "label": "$5,200 transfer"},
                    {"id": "ACC-BAYVIEW-001", "relation": "RECEIVED", "label": "Established account"},
                    {"id": "DEV-BAYVIEW-2", "relation": "USES DEVICE", "label": "Known workstation"}
                ]
            },
            {
                "label": "Legitimate-purpose path",
                "steps": [
                    {"id": "TX-HAROLD-5200", "relation": "START", "label": "Invoice INV-8842"},
                    {"id": "MERCHANT-BAYVIEW", "relation": "RECEIVED", "label": "Verified merchant since 2012"}
                ]
            }
        ];
    }
    return [
        {
            "label": "Identity-to-prior-case path",
            "steps": [
                {"id": "TX-RUTH-4800", "relation": "START", "label": "$4,800 transfer"},
                {"id": "ACC-RAVEN-001", "relation": "RECEIVED", "label": "Mule account · 4419"},
                {"id": "DEV-RAVEN-7", "relation": "USES DEVICE", "label": "Shared device 7D91"},
                {"id": "ACC-RAVEN-002", "relation": "SHARED BY", "label": "Second mule · 8302"},
                {"id": "CASE-2026-041", "relation": "IN PRIOR CASE", "label": "Confirmed scam case"}
            ]
        },
        {
            "label": "Money-movement path",
            "steps": [
                {"id": "TX-RUTH-4800", "relation": "START", "label": "$4,800 transfer"},
                {"id": "TX-RUTH-FORWARD-1", "relation": "FORWARDED_TO", "label": "$3,936 · 11 minutes"},
                {"id": "MERCHANT-ARCLIGHT", "relation": "RECEIVED", "label": "Crypto off-ramp"}
            ]
        }
    ];
}

def find_view_node(
    views: list[GraphNodeView],
    node_id: str
) -> GraphNodeView | None {
    for view_node in views {
        if view_node.id == node_id {
            return view_node;
        }
    }
    return None;
}

def csv_escape(value: str) -> str {
    return '"' + value.replace('"', '""') + '"';
}


def:pub app -> JsxElement {
    has bundle: CommandCenterBundle | None = None,
        detail: CaseDetail | None = None,
        selectedCaseKey: str = "CASE-RUTH-4800",
        selectedNodeId: str = "",
        graphNodes: list[GraphNodeView] = [],
        graphEdges: list[GraphEdgeView] = [],
        workerStates: dict[str, str] = {},
        workerMessages: dict[str, str] = {},
        isLoading: bool = True,
        isRunning: bool = False,
        runMode: str = "synthetic",
        runMessage: str = "Ready to trace the transfer graph",
        activeTab: str = "signals",
        activeView: str = "investigation",
        searchQuery: str = "",
        uploadMessage: str = "",
        analystNote: str = "",
        actionMessage: str = "";

    async can with entry {
        try {
            setup = root spawn CreateDemoWorkspace(
                request_id=str(Date.now())
            );
            bundle = setup.reports[0] if setup.reports else None;
            await selectCase("CASE-RUTH-4800");
        } except Exception as error {
            runMessage = f"Could not open SafeWire: {error}";
        }
        isLoading = False;
    }

    def initialWorkerStates(caseDetail: CaseDetail) -> dict[str, str] {
        states: dict[str, str] = {};
        for name in caseDetail.worker_names {
            states[name] = (
                "completed"
                if caseDetail.case_node.status == "completed"
                else "pending"
            );
        }
        return states;
    }

    async def refreshBundle {
        response = root spawn GetCommandCenter(
            request_id=str(Date.now())
        );
        bundle = response.reports[0] if response.reports else bundle;
    }

    async def selectCase(caseKey: str) {
        selectedCaseKey = caseKey;
        selectedNodeId = "";
        activeTab = "signals";
        response = root spawn GetCaseDetail(
            case_key=caseKey,
            request_id=str(Date.now())
        );
        nextDetail = response.reports[0] if response.reports else None;
        detail = nextDetail;
        if nextDetail {
            if nextDetail.case_node.status == "completed" {
                graphNodes = nextDetail.graph_nodes;
                graphEdges = nextDetail.graph_edges;
            } else {
                graphNodes = nextDetail.graph_nodes[:3];
                graphEdges = nextDetail.graph_edges[:2];
            }
            workerStates = initialWorkerStates(nextDetail);
            workerMessages = {};
            runMessage = (
                "Persisted investigation restored"
                if nextDetail.case_node.status == "completed"
                else "Ready to trace the transfer graph"
            );
        }
    }

    def mergeNodes(incoming: list[GraphNodeView]) {
        merged = list(graphNodes);
        known = set([view_node.id for view_node in merged]);
        for view_node in incoming {
            if view_node.id not in known {
                merged.append(view_node);
                known.add(view_node.id);
            }
        }
        graphNodes = merged;
    }

    def mergeEdges(incoming: list[GraphEdgeView]) {
        merged = list(graphEdges);
        known = set([view_edge.id for view_edge in merged]);
        for view_edge in incoming {
            if view_edge.id not in known {
                merged.append(view_edge);
                known.add(view_edge.id);
            }
        }
        graphEdges = merged;
    }

    def hydrateNodes(rows: list) -> list {
        # SSE data is already a serialized GraphNodeView. Keeping the browser's
        # plain objects avoids treating a typed server view constructor as an
        # authenticated remote function.
        return rows;
    }

    def hydrateEdges(rows: list) -> list {
        # See hydrateNodes: graph deltas arrive in the exact public-view shape.
        return rows;
    }

    def updateWorker(name: str, state: str, message: str = "") {
        states = {**workerStates};
        states[name] = state;
        workerStates = states;
        if message {
            messages = {**workerMessages};
            messages[name] = message;
            workerMessages = messages;
        }
    }

    async def runInvestigation {
        if isRunning or not detail {
            return;
        }
        isRunning = True;
        actionMessage = "";
        runMessage = "Launching five read-only Jac graph traversals…";
        states: dict[str, str] = {};
        for name in detail.worker_names {
            states[name] = "pending";
        }
        workerStates = states;
        workerMessages = {};
        graphNodes = detail.graph_nodes[:3];
        graphEdges = detail.graph_edges[:2];
        requestId = (
            "run-" + detail.transfer.key + "-" + str(Date.now())
        );
        try {
            response = await fetch("/function/investigate_transfer_stream", {
                "method": "POST",
                "headers": {"Content-Type": "application/json"},
                "body": JSON.stringify({
                    "transfer_id": detail.transfer.key,
                    "mode": runMode,
                    "request_id": requestId
                })
            });
            if not response.ok {
                raise Error("Streaming endpoint returned " + str(response.status));
            }
            reader = response.body.getReader();
            decoder = new(TextDecoder);
            nl = chr(10);
            buffer = "";
            reading = True;
            while reading {
                part = await reader.read();
                if part.done {
                    reading = False;
                    continue;
                }
                buffer = buffer + decoder.decode(
                    part.value,
                    {"stream": True}
                );
                frames = buffer.split(nl + nl);
                buffer = frames.pop();
                for frame in frames {
                    if frame.startswith("event: end") {
                        reading = False;
                        await reader.cancel();
                        continue;
                    }
                    for line in frame.split(nl) {
                        if (
                            line.startswith("data: ")
                            and not frame.startswith("event:")
                        ) {
                            encoded = JSON.parse(line[6:]);
                            payload = JSON.parse(encoded);
                            eventName = str(payload.event);
                            investigator = str(payload.investigator or "");
                            if eventName == "run_started" {
                                runMessage = str(payload.message);
                            } elif eventName == "worker_started" {
                                updateWorker(
                                    investigator,
                                    "running",
                                    str(payload.message)
                                );
                            } elif eventName == "worker_completed" {
                                updateWorker(
                                    investigator,
                                    "completed",
                                    str(payload.message)
                                );
                            } elif eventName == "graph_delta" {
                                mergeNodes(hydrateNodes(payload.nodes or []));
                                mergeEdges(hydrateEdges(payload.edges or []));
                            } elif eventName == "skeptic_completed" {
                                updateWorker(
                                    "SkepticWalker",
                                    "completed",
                                    str(payload.message)
                                );
                                mergeNodes(hydrateNodes(payload.nodes or []));
                                mergeEdges(hydrateEdges(payload.edges or []));
                            } elif eventName == "decision_completed" {
                                updateWorker(
                                    "InterventionWalker",
                                    "completed",
                                    str(payload.message)
                                );
                                runMessage = (
                                    str(payload.score) + "/100 · "
                                    + str(payload.decision)
                                );
                            } elif eventName == "worker_failed" {
                                updateWorker(
                                    investigator,
                                    "failed",
                                    str(payload.message)
                                );
                                runMessage = (
                                    "One investigator failed; the run continued"
                                );
                            } elif eventName == "run_completed" {
                                runMessage = (
                                    "Completed in "
                                    + str(round(float(payload.wall_clock_ms) / 1000.0, 2))
                                    + "s wall time vs "
                                    + str(round(float(payload.summed_worker_ms) / 1000.0, 2))
                                    + "s summed worker time"
                                );
                            }
                        }
                    }
                }
            }
            await refreshBundle();
            await selectCase(selectedCaseKey);
        } except Exception as error {
            runMessage = f"Stream interrupted: {error}. Run again to reconnect.";
        }
        isRunning = False;
    }

    async def resetDemo {
        isLoading = True;
        root spawn ResetWorkspace(request_id=str(Date.now()));
        response = root spawn CreateDemoWorkspace(
            force=True,
            request_id=str(Date.now())
        );
        bundle = response.reports[0] if response.reports else None;
        runMode = "synthetic";
        await selectCase("CASE-RUTH-4800");
        runMessage = "Synthetic workspace reset";
        isLoading = False;
    }

    async def uploadCsv(event: ChangeEvent) {
        file = event.target.files[0] if event.target.files else None;
        if not file {
            return;
        }
        uploadMessage = "";
        try {
            csvText = await file.text();
            result = root spawn ImportTransferCsv(
                csv_text=csvText,
                request_id="upload-" + str(Date.now())
            );
            imported = result.reports[0] if result.reports else None;
            uploadMessage = (
                imported.message
                if imported
                else "Upload completed"
            );
            await refreshBundle();
        } except Exception as error {
            uploadMessage = f"Upload rejected: {error}";
        }
        event.target.value = "";
    }

    async def recordDecision(decision: str) {
        if not detail {
            return;
        }
        try {
            response = root spawn RecordAnalystDecision(
                case_key=detail.case_node.key,
                decision=decision,
                note=analystNote,
                request_id="decision-" + str(Date.now())
            );
            saved = response.reports[0] if response.reports else None;
            actionMessage = (
                "Simulated analyst decision recorded: " + saved.decision
                if saved
                else "Decision recorded"
            );
            await selectCase(selectedCaseKey);
        } except Exception as error {
            actionMessage = f"Could not record decision: {error}";
        }
    }

    def downloadText(filename: str, content: str, mime: str) {
        anchor = document.createElement("a");
        anchor.href = (
            "data:" + mime + ";charset=utf-8,"
            + encodeURIComponent(content)
        );
        anchor.download = filename;
        document.body.appendChild(anchor);
        anchor.click();
        document.body.removeChild(anchor);
    }

    def exportCaseFile {
        if detail and detail.case_node.generated_case_file {
            downloadText(
                "safewire-" + detail.case_node.key.lower() + ".md",
                detail.case_node.generated_case_file,
                "text/markdown"
            );
        }
    }

    def exportQueue {
        if not bundle {
            return;
        }
        csvText = (
            "rank,case,customer,amount,legacy_score,safewire_score,"
            "decision,status,callback"
        );
        rank = 1;
        for item in bundle.cases {
            csvText += (
                chr(10) + str(rank)
                + "," + csv_escape(item.key)
                + "," + csv_escape(item.subject)
                + "," + str(item.amount)
                + "," + str(item.legacy_score)
                + "," + str(item.safewire_score)
                + "," + csv_escape(item.decision)
                + "," + csv_escape(item.status)
                + "," + str(item.callback_recommended)
            );
            rank += 1;
        }
        downloadText(
            "safewire-intervention-queue.csv",
            csvText,
            "text/csv"
        );
    }

    if isLoading {
        return
            <div className="loading-screen">
                <div className="loading-logo"><Shield size={28}/></div>
                <div>
                    <strong>Opening SafeWire</strong>
                    <span>Restoring the synthetic fraud graph…</span>
                </div>
            </div>;
    }

    cases = bundle.cases if bundle else [];
    filteredCases = [
        item for item in cases
        if not searchQuery
        or searchQuery.lower() in item.subject.lower()
        or searchQuery.lower() in item.key.lower()
    ];
    completedWorkers = len([
        name for name in (detail.worker_names if detail else [])
        if workerStates.get(name, "pending") == "completed"
    ]);
    activeCase = detail.case_node if detail else None;
    activeTransfer = detail.transfer if detail else None;
    activeCustomer = detail.customer if detail else None;
    signals = sorted(
        detail.signals if detail else [],
        key=lambda (signal: ScamSignal) { return -signal.contribution; }
    );
    acceptedSignals = [
        signal for signal in signals
        if signal.skeptic_disposition == "accepted"
    ];
    suppressedSignals = [
        signal for signal in signals
        if signal.skeptic_disposition == "suppressed"
    ];
    activeTransferId = activeTransfer.key if activeTransfer else "";
    activeDiscoveryLanes = discovery_lanes(activeTransferId);
    selectedGraphNode = find_view_node(graphNodes, selectedNodeId);
    hasTiming = bool(
        activeCase
        and activeCase.wall_clock_ms > 0
        and activeCase.summed_worker_ms > 0
    );
    speedup = (
        round(
            activeCase.summed_worker_ms / activeCase.wall_clock_ms,
            1
        )
        if hasTiming
        else 0.0
    );
    aiReady = bool(
        bundle and bundle.capabilities.openai_configured
    );

    return
        <div className="app-shell">
            <header className="topbar">
                <button
                    className="brand"
                    onClick={lambda { activeView = "investigation"; }}
                >
                    <span className="brand-mark"><Shield size={19}/></span>
                    <span>
                        <strong>SAFEWIRE</strong>
                        <small>Elder Scam Command Center</small>
                    </span>
                </button>
                <nav className="topnav" aria-label="Primary">
                    <button
                        className={"active" if activeView == "investigation" else ""}
                        onClick={lambda { activeView = "investigation"; }}
                    >
                        Investigation
                    </button>
                    <button
                        className={"active" if activeView == "casefile" else ""}
                        onClick={lambda { activeView = "casefile"; }}
                    >
                        Case File
                    </button>
                </nav>
                <div className="top-actions">
                    <div className={"trust-badge " + ("ai" if runMode == "ai" else "synthetic")}>
                        <span></span>
                        <div>
                            <strong>
                                {(
                                    "AI-ASSISTED NOTE REVIEW"
                                    if runMode == "ai"
                                    else "SYNTHETIC DEMO"
                                )}
                            </strong>
                            <small>
                                {(
                                    "Only supplied note is sent"
                                    if runMode == "ai"
                                    else "Offline fixtures · no real customer data"
                                )}
                            </small>
                        </div>
                    </div>
                    <button
                        className="icon-button"
                        title="Reset synthetic workspace"
                        onClick={resetDemo}
                    >
                        <RefreshCw size={17}/>
                    </button>
                </div>
            </header>

            {if activeView == "casefile" {
                <main key="casefile" className="casefile-view">
                    <div className="casefile-head">
                        <div>
                            <div className="eyebrow">Analyst-ready artifact</div>
                            <h1>Case File</h1>
                            <p>
                                Evidence, skeptic findings, recommendation, and
                                human-control safeguards in one export.
                            </p>
                        </div>
                        <button
                            className="primary-button"
                            onClick={exportCaseFile}
                            disabled={not activeCase or not activeCase.generated_case_file}
                        >
                            <Download size={16}/> Download Markdown
                        </button>
                    </div>
                    <article className="markdown-preview">
                        <pre>
                            {(
                                activeCase.generated_case_file
                                if activeCase and activeCase.generated_case_file
                                else "Run an investigation to generate the case file."
                            )}
                        </pre>
                    </article>
                </main>
            } else {
                <div key="investigation" className="command-layout">
                    <aside className="queue-rail">
                        <div className="queue-head">
                            <div>
                                <div className="eyebrow">Intervention queue</div>
                                <h2>{len(cases)} transfers</h2>
                            </div>
                            <button
                                className="small-icon"
                                title="Export intervention queue"
                                onClick={exportQueue}
                            >
                                <Download size={15}/>
                            </button>
                        </div>
                        <div className="search-box">
                            <Search size={15}/>
                            <input
                                value={searchQuery}
                                onChange={lambda event { searchQuery = event.target.value; }}
                                placeholder="Search customer or case"
                                aria-label="Search intervention queue"
                            />
                        </div>
                        <div className="queue-list">
                            {for (index, item) in enumerate(filteredCases) {
                                <button
                                    key={item.key}
                                    className={
                                        "queue-item "
                                        + ("selected " if selectedCaseKey == item.key else "")
                                        + ("cleared" if item.cleared_by_skeptic else "")
                                    }
                                    onClick={lambda { selectCase(item.key); }}
                                >
                                    <span className="queue-rank">{index + 1}</span>
                                    <span className="queue-copy">
                                        <strong>{item.subject}</strong>
                                        <small>{money(item.amount)} · {item.key}</small>
                                        <span className={"queue-decision " + score_tone(item.safewire_score)}>
                                            {(
                                                "Cleared by Skeptic"
                                                if item.cleared_by_skeptic
                                                else item.decision
                                            )}
                                        </span>
                                    </span>
                                    <span className="queue-score">
                                        <b>{item.safewire_score if item.safewire_score > 0 else item.legacy_score}</b>
                                        <small>/100</small>
                                    </span>
                                </button>
                            }}
                        </div>
                        <label className="upload-control">
                            <Upload size={15}/>
                            Import transfer CSV
                            <input
                                type="file"
                                accept=".csv,text/csv"
                                onChange={uploadCsv}
                            />
                        </label>
                        <p className="upload-note">
                            Up to 200 rows / 1 MB. Missing graph links stay partial.
                        </p>
                        {if uploadMessage {
                            <div key="upload-message" className="rail-message">
                                {uploadMessage}
                            </div>
                        }}
                    </aside>

                    <main className="investigation-main">
                        <section className="hero-panel">
                            <div className="hero-copy">
                                <div className="eyebrow">Graph-native elder scam intervention</div>
                                <h1>
                                    Legacy systems score one transfer. SafeWire
                                    investigates the network behind it.
                                </h1>
                                <p>
                                    Watch exact accounts, transfers, devices, merchants,
                                    and prior cases appear only when a specialized Jac
                                    walker discovers them—then see the skeptic challenge
                                    every signal before intervention.
                                </p>
                            </div>
                            <div className="hero-controls">
                                <div className="mode-toggle">
                                    <button
                                        className={"active" if runMode == "synthetic" else ""}
                                        onClick={lambda { runMode = "synthetic"; }}
                                    >
                                        Deterministic
                                    </button>
                                    <button
                                        className={"active" if runMode == "ai" else ""}
                                        onClick={lambda { if aiReady { runMode = "ai"; }}}
                                        disabled={not aiReady}
                                        title={"" if aiReady else "Add a new OPENAI_API_KEY locally to enable"}
                                    >
                                        AI note review
                                    </button>
                                </div>
                                <button
                                    className="primary-button run-button"
                                    onClick={runInvestigation}
                                    disabled={isRunning or not detail}
                                >
                                    {if isRunning {
                                        <RefreshCw key="spin" className="spin" size={17}/>
                                        <span key="running">Investigating…</span>
                                    } else {
                                        <Play key="play" size={17}/>
                                        <span key="run">
                                            {(
                                                "Re-run investigation"
                                                if activeCase and activeCase.status == "completed"
                                                else "Investigate transfer"
                                            )}
                                        </span>
                                    }}
                                </button>
                                <div className={"timing-proof " + ("verified" if hasTiming else "")}>
                                    <Clock3 size={15}/>
                                    {if hasTiming {
                                        <span key="timing-ready">
                                            <strong>
                                                {round(activeCase.wall_clock_ms / 1000.0, 2)}s parallel
                                            </strong>
                                            {" "}vs {round(activeCase.summed_worker_ms / 1000.0, 2)}s one-by-one
                                            <b>{speedup}× overlap</b>
                                        </span>
                                    } else {
                                        <span key="timing-pending">
                                            Five investigators launch before any result is awaited
                                        </span>
                                    }}
                                </div>
                            </div>
                        </section>

                        {if detail {
                            <section key="case-content" className="case-strip">
                                <div className="case-identity">
                                    <div className="avatar">
                                        {activeCustomer.name[0] if activeCustomer else "?"}
                                    </div>
                                    <div>
                                        <div className="case-kicker">
                                            {activeCase.key} · {activeTransfer.created_at}
                                        </div>
                                        <h2>
                                            {activeCustomer.name if activeCustomer else activeCase.subject}
                                            <span>Age {activeCustomer.age if activeCustomer else "—"}</span>
                                        </h2>
                                        <p>
                                            {money(activeTransfer.amount)} to {
                                                detail.recipient_account.label
                                                if detail.recipient_account
                                                else "recipient pending graph attachment"
                                            }
                                        </p>
                                    </div>
                                </div>
                                <div className={"recommendation-card " + ("clear" if activeCase.cleared_by_skeptic else "")}>
                                    {if activeCase.cleared_by_skeptic {
                                        <CheckCircle2 key="clear-icon" size={20}/>
                                    } else {
                                        <PhoneCall key="phone-icon" size={20}/>
                                    }}
                                    <div>
                                        <span>
                                            {(
                                                "Cleared by Skeptic"
                                                if activeCase.cleared_by_skeptic
                                                else "Recommended next step"
                                            )}
                                        </span>
                                        <strong>{activeCase.recommendation}</strong>
                                    </div>
                                </div>
                            </section>
                        }}

                        <section className="discovery-panel">
                            <div className="section-heading discovery-heading">
                                <div>
                                    <div className="eyebrow">Undeniable multi-hop discovery</div>
                                    <h2>The investigation is the graph</h2>
                                    <p>
                                        Unrevealed nodes remain locked. Each exact node
                                        appears only after its walker returns.
                                    </p>
                                </div>
                                <span className="path-proof">
                                    <Network size={14}/>
                                    {len([
                                        node for node in graphNodes
                                        if is_discovery_node(activeTransferId, node.id)
                                    ])} path nodes revealed
                                </span>
                            </div>
                            <div className="discovery-lanes">
                                {for lane in activeDiscoveryLanes {
                                    <div key={str(lane["label"])} className="discovery-lane">
                                        <strong className="lane-label">{lane["label"]}</strong>
                                        <div className="lane-steps">
                                            {for (index, step) in enumerate(lane["steps"]) {
                                                revealed = bool(
                                                    find_view_node(
                                                        graphNodes,
                                                        str(step["id"])
                                                    )
                                                );
                                                if index > 0 {
                                                    <div key={str(step["id"]) + "-relation"} className={"path-relation " + ("revealed" if revealed else "")}>
                                                        <ArrowRight size={13}/>
                                                        <span>{step["relation"]}</span>
                                                    </div>
                                                }
                                                <button
                                                    key={str(step["id"])}
                                                    className={"path-step " + ("revealed" if revealed else "locked")}
                                                    disabled={not revealed}
                                                    onClick={lambda {
                                                        selectedNodeId = str(step["id"]);
                                                        activeTab = "connections";
                                                    }}
                                                >
                                                    <span>
                                                        {if revealed {
                                                            <Check key="revealed" size={12}/>
                                                        } else {
                                                            <CircleDot key="locked" size={12}/>
                                                        }}
                                                        {step["label"]}
                                                    </span>
                                                    <code>{step["id"]}</code>
                                                </button>
                                            }}
                                        </div>
                                    </div>
                                }}
                            </div>
                        </section>

                        <section className="workers-panel">
                            <div className="section-heading">
                                <div>
                                    <div className="eyebrow">Measured Jac execution</div>
                                    <h2>Seven specialized investigators</h2>
                                </div>
                                <span className="worker-count">
                                    {completedWorkers}/7 complete
                                </span>
                            </div>
                            <div className="worker-grid">
                                {for name in (detail.worker_names if detail else []) {
                                    state = workerStates.get(name, "pending");
                                    <div key={name} className={"worker-card " + state}>
                                        <div className="worker-icon">
                                            {if state == "completed" {
                                                <Check key="done" size={15}/>
                                            } elif state == "running" {
                                                <Activity key="active" className="pulse" size={15}/>
                                            } elif state == "failed" {
                                                <XCircle key="failed" size={15}/>
                                            } else {
                                                <CircleDot key="pending" size={15}/>
                                            }}
                                        </div>
                                        <div>
                                            <strong>{short_worker(name)}</strong>
                                            <span>{worker_path(name)}</span>
                                            <small>
                                                {workerMessages.get(
                                                    name,
                                                    (
                                                        "Completed from persisted graph"
                                                        if state == "completed"
                                                        else "Waiting for launch"
                                                    )
                                                )}
                                            </small>
                                        </div>
                                    </div>
                                }}
                            </div>
                            <div className="run-status">
                                <Zap size={15}/>
                                <span>{runMessage}</span>
                            </div>
                        </section>

                        <section className="graph-panel">
                            <div className="section-heading graph-heading">
                                <div>
                                    <div className="eyebrow">Live investigation · not a static diagram</div>
                                    <h2>Watch the evidence path assemble</h2>
                                    <p>
                                        Nodes and labeled edges stream from completed
                                        walkers. Click any exact node to inspect its links.
                                    </p>
                                </div>
                                <div className="graph-stats">
                                    <span><Network size={14}/>{len(graphNodes)} nodes</span>
                                    <span><GitBranch size={14}/>{len(graphEdges)} edges</span>
                                </div>
                            </div>
                            <div className="graph-canvas">
                                <svg
                                    viewBox="0 0 960 540"
                                    role="img"
                                    aria-label="Live transfer investigation graph"
                                >
                                    {for view_edge in graphEdges {
                                        source = find_view_node(graphNodes, view_edge.from_id);
                                        target = find_view_node(graphNodes, view_edge.to_id);
                                        if source and target {
                                            midX = (source.x + target.x) / 2.0;
                                            midY = (source.y + target.y) / 2.0;
                                            <g
                                                key={view_edge.id}
                                                className={
                                                    "graph-edge " + view_edge.tone
                                                    + (
                                                        " discovery-edge"
                                                        if is_discovery_edge(
                                                            activeTransferId,
                                                            view_edge.id
                                                        )
                                                        else ""
                                                    )
                                                }
                                            >
                                                <line
                                                    x1={source.x}
                                                    y1={source.y}
                                                    x2={target.x}
                                                    y2={target.y}
                                                />
                                                <text x={midX} y={midY - 7} textAnchor="middle">
                                                    {view_edge.label}
                                                </text>
                                            </g>
                                        }
                                    }}
                                    {for view_node in graphNodes {
                                        <g
                                            key={view_node.id}
                                            className={
                                                "graph-node " + view_node.tone
                                                + (
                                                    " discovery-node"
                                                    if is_discovery_node(
                                                        activeTransferId,
                                                        view_node.id
                                                    )
                                                    else ""
                                                )
                                                + (" selected" if selectedNodeId == view_node.id else "")
                                            }
                                            transform={"translate(" + str(view_node.x) + " " + str(view_node.y) + ")"}
                                            onClick={lambda {
                                                selectedNodeId = view_node.id;
                                                activeTab = "connections";
                                            }}
                                            role="button"
                                            tabIndex="0"
                                        >
                                            <circle
                                                r={31 if view_node.kind == "InvestigationCase" else 25}
                                            />
                                            <text className="node-kind" y="-38" textAnchor="middle">
                                                {view_node.kind}
                                            </text>
                                            <text className="node-label" y="45" textAnchor="middle">
                                                {view_node.label}
                                            </text>
                                        </g>
                                    }}
                                </svg>
                                <div className="graph-legend">
                                    <span><i className="source"></i>Customer</span>
                                    <span><i className="risk"></i>Risk network</span>
                                    <span><i className="identity"></i>Identity</span>
                                    <span><i className="flow"></i>Money flow</span>
                                    <span><i className="cleared"></i>Verified</span>
                                </div>
                            </div>
                        </section>

                        {if detail {
                            <section key="score-outcome" className="score-panel">
                                <div>
                                    <div className="eyebrow">Score comes after investigation</div>
                                    <h2>Decision after the network and skeptic review</h2>
                                    <p>
                                        {len(acceptedSignals)} accepted categories · {
                                            len(suppressedSignals)
                                        } correlated clues suppressed
                                    </p>
                                </div>
                                <div className="score-comparison">
                                    <div className="legacy-score">
                                        <span>Legacy · one transfer</span>
                                        <strong>{activeCase.legacy_score}</strong>
                                        <small>{activeCase.legacy_decision}</small>
                                    </div>
                                    <ArrowRight size={20}/>
                                    <div className={"safewire-score " + score_tone(activeCase.safewire_score)}>
                                        <span>SafeWire · network</span>
                                        <strong>{activeCase.safewire_score}</strong>
                                        <small>{activeCase.decision}</small>
                                    </div>
                                </div>
                            </section>
                        }}
                    </main>

                    <aside className="evidence-drawer">
                        <div className="drawer-head">
                            <div>
                                <div className="eyebrow">Analyst evidence</div>
                                <h2>
                                    {(
                                        selectedGraphNode.label
                                        if selectedGraphNode
                                        else "Case intelligence"
                                    )}
                                </h2>
                            </div>
                            {if activeCase and activeCase.status == "completed" {
                                <span key="drawer-verdict" className="drawer-verdict">
                                    <b>{len(acceptedSignals)} accepted</b>
                                    <small>{len(suppressedSignals)} suppressed</small>
                                </span>
                            }}
                        </div>
                        {if selectedGraphNode {
                            <div key="selected-node" className="selected-node-card">
                                <span>{selectedGraphNode.kind} · {selectedGraphNode.id}</span>
                                <strong>{selectedGraphNode.detail}</strong>
                            </div>
                        }}
                        <div className="drawer-tabs">
                            {for (key, label) in [
                                ("signals", "Signals"),
                                ("evidence", "Evidence"),
                                ("skeptic", "Skeptic"),
                                ("connections", "Links"),
                                ("actions", "Actions")
                            ] {
                                <button
                                    key={key}
                                    className={"active" if activeTab == key else ""}
                                    onClick={lambda { activeTab = key; }}
                                >
                                    {label}
                                </button>
                            }}
                        </div>
                        <div className="drawer-body">
                            {if activeTab == "signals" {
                                <div key="signals" className="signal-list">
                                    <div className="plain-language-note">
                                        <Info size={15}/>
                                        Every candidate signal shows the explanation
                                        SkepticWalker tested and whether it survived.
                                    </div>
                                    {for signal in signals {
                                            <article
                                                key={signal.key}
                                                className={
                                                    "signal-card "
                                                    + signal.skeptic_disposition
                                                }
                                            >
                                                <div className="signal-top">
                                                    <span>
                                                        {(
                                                            "+" + str(signal.contribution)
                                                            if signal.contribution > 0
                                                            else "NO SCORE"
                                                        )}
                                                    </span>
                                                    <b className={"disposition-badge " + signal.skeptic_disposition}>
                                                        {signal.skeptic_disposition}
                                                    </b>
                                                    <small>{signal.investigator}</small>
                                                </div>
                                                <h3>{signal.label}</h3>
                                                <p>{signal.rationale}</p>
                                                <div className="explain-chip">
                                                    {signal_plain_language(signal.category)}
                                                </div>
                                                <div className="skeptic-test">
                                                    <span>Skeptic tested</span>
                                                    <p>
                                                        {(
                                                            signal.skeptic_explanation
                                                            if signal.skeptic_explanation
                                                            else "Pending skeptic review."
                                                        )}
                                                    </p>
                                                </div>
                                                <footer>
                                                    {len(signal.evidence_families)} source families
                                                    <code>
                                                        {len(signal.supporting_graph_node_ids)} exact nodes
                                                    </code>
                                                </footer>
                                            </article>
                                    }}
                                    {if not signals {
                                        <div key="no-signals" className="empty-state">
                                            <ShieldAlert size={28}/>
                                            <strong>No applied signals yet</strong>
                                            <span>Run the investigation to populate evidence.</span>
                                        </div>
                                    }}
                                </div>
                            } elif activeTab == "evidence" {
                                <div key="evidence" className="evidence-list">
                                    {for (index, item) in enumerate(detail.evidence if detail else []) {
                                        <article key={str(index) + item.label}>
                                            <div>
                                                <FileCheck2 size={16}/>
                                                <span>{item.label}</span>
                                            </div>
                                            <blockquote>“{item.quote}”</blockquote>
                                            <footer>
                                                {item.source_family.replace("_", " ")}
                                                {if item.verified_exact {
                                                    <b key="exact"><BadgeCheck size={13}/> exact</b>
                                                }}
                                            </footer>
                                        </article>
                                    }}
                                </div>
                            } elif activeTab == "skeptic" {
                                <div key="skeptic" className="skeptic-panel">
                                    <div className={"skeptic-verdict " + ("cleared" if activeCase and activeCase.cleared_by_skeptic else "survived")}>
                                        {if activeCase and activeCase.cleared_by_skeptic {
                                            <CheckCircle2 key="skeptic-clear" size={24}/>
                                        } else {
                                            <ShieldAlert key="skeptic-risk" size={24}/>
                                        }}
                                        <div>
                                            <strong>
                                                {(
                                                    "Cleared by Skeptic"
                                                    if activeCase and activeCase.cleared_by_skeptic
                                                    else "Signals survived challenge"
                                                )}
                                            </strong>
                                            <span>
                                                Invoice, prior relationship, merchant identity,
                                                and correlated evidence were checked.
                                            </span>
                                        </div>
                                    </div>
                                    {for finding in (activeCase.skeptic_findings if activeCase else []) {
                                        <div key={finding} className="finding">
                                            <Check size={15}/>{finding}
                                        </div>
                                    }}
                                    <div className="skeptic-ledger">
                                        <div className="eyebrow">Signal-by-signal disposition</div>
                                        {for signal in signals {
                                            <article key={signal.key}>
                                                <b className={"disposition-badge " + signal.skeptic_disposition}>
                                                    {signal.skeptic_disposition}
                                                </b>
                                                <strong>{signal.label}</strong>
                                                <p>
                                                    {(
                                                        signal.skeptic_explanation
                                                        if signal.skeptic_explanation
                                                        else "Pending skeptic review."
                                                    )}
                                                </p>
                                            </article>
                                        }}
                                    </div>
                                </div>
                            } elif activeTab == "connections" {
                                <div key="connections" className="connections-panel">
                                    <h3>
                                        {(
                                            selectedGraphNode.label
                                            if selectedGraphNode
                                            else "Select a graph node"
                                        )}
                                    </h3>
                                    {for view_edge in graphEdges {
                                        if (
                                            not selectedNodeId
                                            or view_edge.from_id == selectedNodeId
                                            or view_edge.to_id == selectedNodeId
                                        ) {
                                            <button
                                                key={view_edge.id}
                                                onClick={lambda {
                                                    selectedNodeId = (
                                                        view_edge.to_id
                                                        if view_edge.from_id == selectedNodeId
                                                        else view_edge.from_id
                                                    );
                                                }}
                                            >
                                                <GitBranch size={15}/>
                                                <span>
                                                    <b>{view_edge.label}</b>
                                                    {view_edge.from_id} → {view_edge.to_id}
                                                </span>
                                                <ChevronRight size={14}/>
                                            </button>
                                        }
                                    }}
                                </div>
                            } else {
                                <div key="actions" className="actions-panel">
                                    <div className="human-control">
                                        <UserCheck size={19}/>
                                        <div>
                                            <strong>Human decision required</strong>
                                            <span>
                                                Controls record a simulation only. No account,
                                                payment, message, or person is affected.
                                            </span>
                                        </div>
                                    </div>
                                    <label>
                                        Analyst note
                                        <textarea
                                            value={analystNote}
                                            onChange={lambda event { analystNote = event.target.value; }}
                                            placeholder="Record confirmation or request specific evidence…"
                                        ></textarea>
                                    </label>
                                    <div className="action-buttons">
                                        <button
                                            className="approve"
                                            onClick={lambda { recordDecision("approve"); }}
                                        >
                                            <CheckCircle2 size={15}/> Approve hold
                                        </button>
                                        <button
                                            onClick={lambda { recordDecision("request_more_information"); }}
                                        >
                                            <Info size={15}/> Request more info
                                        </button>
                                        <button
                                            className="reject"
                                            onClick={lambda { recordDecision("reject"); }}
                                        >
                                            <XCircle size={15}/> Reject
                                        </button>
                                    </div>
                                    {if activeCase and activeCase.analyst_decision {
                                        <div key="saved-action" className="saved-action">
                                            <BadgeCheck size={16}/>
                                            Persisted: {activeCase.analyst_decision.replace("_", " ")}
                                        </div>
                                    }}
                                    {if actionMessage {
                                        <div key="action-message" className="action-message">
                                            {actionMessage}
                                        </div>
                                    }}
                                </div>
                            }}
                        </div>
                    </aside>
                </div>
            }}
        </div>;
}
