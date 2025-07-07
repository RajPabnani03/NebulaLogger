# NebulaLogger Architecture Flow

This document provides a high-level architectural overview of the NebulaLogger application using a Mermaid flow diagram. The diagram illustrates the main components, their relationships, and the data flow from logging requests to persistent storage.

## Architecture Overview

NebulaLogger is built as an event-driven, multi-technology logging framework for Salesforce. It supports logging from various Salesforce technologies through dedicated entry points, processes log data through platform events, and provides flexible storage and configuration options.

## Component Architecture & Data Flow

```mermaid
flowchart TD
    %% Entry Points
    subgraph "Entry Points"
        A1[Apex Code<br/>Logger.cls]
        A2[Lightning Components<br/>ComponentLogger.cls]
        A3[Salesforce Flows<br/>FlowLogger.cls]
        A4[OmniStudio<br/>CallableLogger.cls]
    end

    %% Core Engine
    subgraph "Core Logger Engine"
        B1[Logger.cls<br/>Main Entry Point]
        B2[LogEntryEventBuilder.cls<br/>Event Builder]
        B3[LogEntryEvent__e<br/>Platform Event]
    end

    %% Configuration
    subgraph "Configuration Layer"
        C1[LoggerSettings__c<br/>User/Profile/Org Settings]
        C2[LoggerParameter__mdt<br/>System Parameters]
        C3[LogEntryDataMaskRule__mdt<br/>Data Masking Rules]
    end

    %% Save Methods Decision
    D1{Save Method<br/>Selection}
    D2[EVENT_BUS<br/>Default]
    D3[QUEUEABLE<br/>Async Processing]
    D4[REST<br/>API Callout]
    D5[SYNCHRONOUS_DML<br/>Direct Insert]

    %% Event Processing
    subgraph "Event Processing"
        E1[LogEntryEventHandler.cls<br/>Platform Event Handler]
        E2[Data Validation &<br/>Filtering]
        E3[Scenario Processing]
        E4[Tag Assignment Rules]
    end

    %% Storage Layer
    subgraph "Storage Layer"
        F1[Log__c<br/>Transaction Records]
        F2[LogEntry__c<br/>Individual Log Entries]
        F3[LoggerScenario__c<br/>Scenario Categorization]
        F4[LoggerTag__c<br/>Tag Management]
        F5[LogEntryTag__c<br/>Entry-Tag Relationships]
    end

    %% Plugin Framework
    subgraph "Plugin Framework"
        G1[LoggerPlugin__mdt<br/>Plugin Configuration]
        G2[Plugin Handlers<br/>Custom Processing]
        G3[External Integrations<br/>Slack, Email, etc.]
    end

    %% Data Flow Connections
    A1 --> B1
    A2 --> B1
    A3 --> B1
    A4 --> B1

    B1 --> B2
    B2 --> B3
    B3 --> D1

    C1 --> B1
    C2 --> B1
    C3 --> B2

    D1 --> D2
    D1 --> D3
    D1 --> D4
    D1 --> D5

    D2 --> E1
    D3 --> E1
    D4 --> E1
    D5 --> F1

    E1 --> E2
    E2 --> E3
    E3 --> E4
    E4 --> F1

    F1 --> F2
    E4 --> F3
    E4 --> F4
    F2 --> F5
    F4 --> F5

    E1 --> G1
    G1 --> G2
    G2 --> G3

    %% Styling
    classDef entryPoint fill:#e1f5fe
    classDef coreEngine fill:#f3e5f5
    classDef config fill:#fff3e0
    classDef storage fill:#e8f5e8
    classDef plugin fill:#fce4ec

    class A1,A2,A3,A4 entryPoint
    class B1,B2,B3 coreEngine
    class C1,C2,C3 config
    class F1,F2,F3,F4,F5 storage
    class G1,G2,G3 plugin
```

## Component Descriptions

### Entry Points
- **Logger.cls**: Primary Apex interface providing methods like `debug()`, `info()`, `warn()`, `error()`
- **ComponentLogger.cls**: Handles logging from Lightning Web Components and Aura components
- **FlowLogger.cls**: Provides Flow actions for logging within Salesforce Flows
- **CallableLogger.cls**: Implements `System.Callable` for OmniStudio and external system integration

### Core Logger Engine
- **Logger.cls**: Central orchestrator managing log entries, scenarios, and save operations
- **LogEntryEventBuilder.cls**: Builder pattern class that constructs `LogEntryEvent__e` records with all necessary metadata
- **LogEntryEvent__e**: Platform event that carries log data through the system before persistence

### Configuration Layer
- **LoggerSettings__c**: Hierarchical custom settings controlling logging behavior per user, profile, or organization
- **LoggerParameter__mdt**: Custom metadata for system-wide feature flags and parameters
- **LogEntryDataMaskRule__mdt**: Rules for automatically masking sensitive data in logs

### Save Methods
The system supports multiple persistence strategies:
- **EVENT_BUS**: Default method using platform events for asynchronous processing
- **QUEUEABLE**: Defers processing using queueable jobs to manage limits
- **REST**: Uses REST API callouts to avoid mixed DML operations
- **SYNCHRONOUS_DML**: Direct database operations bypassing platform events

### Event Processing
- **LogEntryEventHandler.cls**: Processes `LogEntryEvent__e` platform events and creates persistent records
- **Data Validation & Filtering**: Applies user settings and logging level filters
- **Scenario Processing**: Handles scenario-based logging and categorization
- **Tag Assignment Rules**: Automatically assigns tags based on configurable rules

### Storage Layer
- **Log__c**: Represents a logging session/transaction with metadata about the execution context
- **LogEntry__c**: Individual log messages with details like level, message, stack trace, and related records
- **LoggerScenario__c**: Categorizes related logs for better organization and analysis
- **LoggerTag__c**: Manages available tags for labeling log entries
- **LogEntryTag__c**: Junction object linking log entries to their assigned tags

### Plugin Framework
- **LoggerPlugin__mdt**: Configuration for extending the system with custom functionality
- **Plugin Handlers**: Custom Apex classes that process logs for specific integrations
- **External Integrations**: Built-in plugins for Slack notifications, email alerts, and other systems

## Data Flow Process

1. **Log Request**: A logging request is initiated from any entry point (Apex, LWC, Flow, OmniStudio)
2. **Event Building**: The core engine uses `LogEntryEventBuilder` to construct a `LogEntryEvent__e` with all necessary metadata
3. **Configuration Application**: User settings and system parameters are applied to determine logging behavior
4. **Save Method Selection**: Based on configuration and context, an appropriate save method is chosen
5. **Event Processing**: `LogEntryEventHandler` processes the platform event, applying filters and rules
6. **Data Persistence**: Log data is stored in the appropriate custom objects with proper relationships
7. **Plugin Execution**: Any configured plugins process the log data for additional functionality

This architecture provides a robust, scalable, and extensible logging solution that can handle complex Salesforce environments while maintaining performance and flexibility.
