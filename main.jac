"""Meridian full-stack entry point."""

import from endpoints {
    EntityBatch,
    Entity,
    Attribute,
    SubEntity,
    RiskSignal,
    Report,
    BatchBundle,
    EntityDetail,
    CapabilityView,
    GetCapabilities,
    CreateDemoBatch,
    CreateCsvBatch,
    Orchestrator,
    GetBatch,
    GetEntityDetail,
    ResetWorkspace
}

cl {
    import from .frontend { app as ClientApp }

    def:pub app -> JsxElement {
        return <ClientApp/>;
    }
}
