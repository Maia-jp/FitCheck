# RFC-000: FitCheck — RFC Index & Dependency Map

| Field       | Value                                       |
|-------------|---------------------------------------------|
| Status      | Living Document                             |
| Created     | 2026-03-31                                  |
| Depends on  | —                                           |
| Phase       | —                                           |

---

## 1. Purpose

FitCheck is a Swift package for macOS (Apple Silicon only) that lets developers discover which open-weight AI models can run on their machine, inspect model metadata, and obtain download instructions for Ollama and LM Studio. The model catalog is GitHub-hosted and auto-updated, so even old installations always see the latest models.

This document serves as the master index for all FitCheck RFCs. It tracks status, dependencies, and the implementation phase of each RFC.

## 2. RFC Index

| RFC   | Title                                  | Phase | Status | Depends on          |
|-------|----------------------------------------|-------|--------|---------------------|
| 001   | Project Foundation & Package Architecture | 1     | Draft  | —                   |
| 002   | Hardware Profiling                     | 1     | Draft  | RFC-001             |
| 003   | Model Catalog & Data Model             | 1     | Draft  | RFC-001             |
| 004   | Compatibility Engine                   | 2     | Draft  | RFC-002, RFC-003    |
| 005   | Download Provider Integration          | 2     | Draft  | RFC-001, RFC-003    |
| 006   | Public API Surface & Developer Experience | 3  | Draft  | RFC-004, RFC-005    |
| 007   | Catalog Generation Pipeline              | 1     | Draft  | RFC-003             |

## 3. Dependency Graph

```
                    ┌─────────────────────┐
                    │     RFC-001         │
                    │  Foundation &       │
                    │  Package Arch       │
                    └────┬───┬───┬───────┘
                         │   │   │
              ┌──────────┘   │   └──────────┐
              ▼              ▼              ▼
   ┌──────────────┐  ┌──────────────┐  ┌──────────────┐
   │   RFC-002    │  │   RFC-003    │  │  (RFC-005    │
   │  Hardware    │  │  Model       │  │   also uses  │
   │  Profiling   │  │  Catalog     │  │   RFC-001)   │
   └──────┬───────┘  └──┬──────┬───┘  └──────────────┘
          │              │      │
          │   ┌──────────┤      │
          │   │          ▼      │
          │   │   ┌──────────────┐
          │   │   │   RFC-007    │
          │   │   │  Catalog     │
          │   │   │  Generation  │
          │   │   └──────────────┘
          │   │                 │
          ▼   ▼                 ▼
   ┌──────────────┐      ┌──────────────┐
   │   RFC-004    │      │   RFC-005    │
   │ Compatibility│      │  Download    │
   │   Engine     │      │  Providers   │
   └──────┬───────┘      └──────┬──────┘
          │                      │
          └──────────┬───────────┘
                     ▼
              ┌──────────────┐
              │   RFC-006    │
              │  Public API  │
              │  Surface     │
              └──────────────┘
```

## 4. Phases

| Phase | Scope                          | RFCs               |
|-------|--------------------------------|---------------------|
| 1     | Core types, hardware, catalog  | 001, 002, 003, 007  |
| 2     | Matching engine, providers     | 004, 005            |
| 3     | Public-facing API              | 006                 |

Phase 1 RFCs have no inter-dependencies (except on RFC-001) and can be implemented in parallel. RFC-007 (catalog generation) depends on RFC-003's schema and can be built alongside it. Phase 2 depends on Phase 1. Phase 3 integrates everything.

## 5. Shared Type Registry

Types defined in one RFC and consumed by others:

| Type                    | Defined In   | Used By                  |
|-------------------------|-------------|--------------------------|
| `FitCheckError`         | RFC-001 §4  | All RFCs                 |
| `HardwareProfile`       | RFC-002 §3  | RFC-004, RFC-006         |
| `HardwareProfiler`      | RFC-002 §4  | RFC-006                  |
| `ModelCard`             | RFC-003 §3  | RFC-004, RFC-005, RFC-006|
| `ModelVariant`          | RFC-003 §3  | RFC-004, RFC-005, RFC-006|
| `ModelFamily`           | RFC-003 §3  | RFC-006                  |
| `QuantizationFormat`    | RFC-003 §3  | RFC-004, RFC-005         |
| `CatalogProvider`       | RFC-003 §4  | RFC-006                  |
| `CompatibilityVerdict`  | RFC-004 §3  | RFC-006                  |
| `CompatibilityReport`   | RFC-004 §3  | RFC-006                  |
| `CompatibilityChecker`  | RFC-004 §4  | RFC-006                  |
| `ModelMatch`            | RFC-004 §3  | RFC-006                  |
| `DownloadProvider`      | RFC-005 §3  | RFC-006                  |
| `DownloadAction`        | RFC-005 §3  | RFC-006                  |
| `ShellExecutor`         | RFC-005 §4  | RFC-005 (internal)       |

## 6. File Structure

```
data/
├── catalog.json                           RFC-007 (generated — DO NOT EDIT)
├── model-map.json                         RFC-007 (models.dev → Ollama/HF mapping)
└── overrides.json                         RFC-007 (manual corrections)

Sources/CatalogGenerator/
├── CatalogGenerator.swift                 RFC-007 (@main entry point)
├── Pipeline/                              RFC-007 (data fetching & computation)
├── Validation/                            RFC-007 (schema validation)
└── Types/                                 RFC-007 (output & API types)

Sources/FitCheck/
├── FitCheck.swift                         RFC-006
├── Logging.swift                          RFC-001
├── Errors/
│   └── FitCheckError.swift                RFC-001
├── Hardware/
│   ├── HardwareProfile.swift              RFC-002
│   ├── Chip.swift                         RFC-002
│   ├── MetalSupport.swift                 RFC-002
│   ├── HardwareProfiler.swift             RFC-002
│   └── SystemHardwareProfiler.swift       RFC-002
├── Catalog/
│   ├── ModelCard.swift                    RFC-003
│   ├── ModelFamily.swift                  RFC-003
│   ├── ModelVariant.swift                 RFC-003
│   ├── QuantizationFormat.swift           RFC-003
│   ├── ModelLicense.swift                 RFC-003
│   ├── CatalogProvider.swift              RFC-003
│   ├── BundledCatalogProvider.swift        RFC-003
│   └── RemoteCatalogProvider.swift         RFC-003
├── Compatibility/
│   ├── CompatibilityVerdict.swift         RFC-004
│   ├── CompatibilityReport.swift          RFC-004
│   ├── CompatibilityChecker.swift         RFC-004
│   ├── DefaultCompatibilityChecker.swift  RFC-004
│   └── ModelMatch.swift                   RFC-004
├── Providers/
│   ├── DownloadProvider.swift             RFC-005
│   ├── DownloadAction.swift               RFC-005
│   ├── OllamaProvider.swift               RFC-005
│   ├── LMStudioProvider.swift             RFC-005
│   └── ShellExecutor.swift                RFC-005
└── Resources/
    └── bundled-catalog.json               RFC-003

Tests/FitCheckTests/
├── Hardware/
│   └── SystemHardwareProfilerTests.swift  RFC-002
├── Catalog/
│   ├── ModelCardTests.swift               RFC-003
│   └── BundledCatalogProviderTests.swift  RFC-003
├── Compatibility/
│   └── DefaultCompatibilityCheckerTests.swift  RFC-004
├── Providers/
│   ├── OllamaProviderTests.swift          RFC-005
│   └── LMStudioProviderTests.swift        RFC-005
└── FitCheckTests.swift                    RFC-006
```
