"""SafeWire full-stack entry point."""

import from endpoints {
    Customer,
    Account,
    Transfer,
    Payee,
    Device,
    IPAddress,
    AuthorizedUser,
    Merchant,
    ScamSignal,
    InvestigationCase,
    EvidenceSpan,
    InvestigatorResult,
    GraphNodeView,
    GraphEdgeView,
    InvestigationEvent,
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
    ResetWorkspace,
    investigate_transfer_stream
}

cl {
    import from .frontend { app as ClientApp }

    def:pub app -> JsxElement {
        return <ClientApp/>;
    }
}
