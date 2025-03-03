//------------------------------------------------------------------------------------------------//
// This file is part of the Nebula Logger project, released under the MIT License.                //
// See LICENSE file or go to https://github.com/jongpie/NebulaLogger for full license details.    //
//------------------------------------------------------------------------------------------------//

/**
 * @group Log Management
 * @description Processes `LogEntryEvent__e` platform events and normalizes the data into `Log__c` and `LogEntry__c` records
 */
@SuppressWarnings(
    'PMD.ApexCrudViolation, PMD.CognitiveComplexity, PMD.CyclomaticComplexity, PMD.FieldDeclarationsShouldBeAtStart, PMD.PropertyNamingConventions'
)
public without sharing class LogEntryEventHandler extends LoggerSObjectHandler {
    @TestVisible
    private static final String DEFAULT_STORAGE_LOCATION_NAME = 'CUSTOM_OBJECTS';
    private static final Database.DmlOptions DML_OPTIONS = createDmlOptions();
    private static final String GUEST_USER_TYPE = 'Guest';
    private static final String NEW_LINE_DELIMITER = '\n';
    private static final Map<String, LoggerScenario__c> SCENARIO_UNIQUE_ID_TO_SCENARIO = new Map<String, LoggerScenario__c>();
    private static final Map<String, Log__c> TRANSACTION_ID_TO_LOG = new Map<String, Log__c>();

    @TestVisible
    private static List<LogEntryTagRule__mdt> TAG_ASSIGNMENT_RULES {
        get {
            if (TAG_ASSIGNMENT_RULES == null) {
                TAG_ASSIGNMENT_RULES = getTagAssignmentRules();
            }
            return TAG_ASSIGNMENT_RULES;
        }
        set;
    }

    @TestVisible
    private List<LogEntryEvent__e> logEntryEvents;
    private List<LogEntry__c> logEntries = new List<LogEntry__c>();
    private Map<String, List<String>> logEntryEventUuidToTagNames = new Map<String, List<String>>();
    private Set<String> tagNames = new Set<String>();

    /**
     * @description Default constructor, used by the trigger `LogEntryEvent.trigger`
     */
    public LogEntryEventHandler() {
        super();
    }

    /**
     * @description Returns SObject Type that the handler is responsible for processing
     * @return      The instance of `SObjectType`
     */
    public override Schema.SObjectType getSObjectType() {
        return Schema.LogEntryEvent__e.SObjectType;
    }

    protected override void executeAfterInsert(List<SObject> triggerNew) {
        this.logEntryEvents = this.filterLogEntryEventsToSave((List<LogEntryEvent__e>) triggerNew);

        if (this.logEntryEvents.isEmpty() == false) {
            this.upsertLoggerScenarios();
            this.upsertLogs();
            this.upsertLogEntries();
            this.appendRuleBasedTags();
            this.upsertLogEntryTags();
        }
    }

    private List<LogEntryEvent__e> filterLogEntryEventsToSave(List<LogEntryEvent__e> newLogEntryEvents) {
        final String trueString = String.valueOf(true);
        List<LogEntryEvent__e> logEntryEventsToSave = new List<LogEntryEvent__e>();
        for (LogEntryEvent__e logEntryEvent : newLogEntryEvents) {
            User loggingUser = new User(Id = logEntryEvent.LoggedById__c, ProfileId = logEntryEvent.ProfileId__c);
            String platformEventStorageLocation = Logger.getUserSettings(loggingUser).DefaultPlatformEventStorageLocation__c;
            if (logEntryEvent.TransactionScenario__c != null && LoggerScenarioRule.getAll().containsKey(logEntryEvent.TransactionScenario__c) == true) {
                LoggerScenarioRule__mdt scenarioRule = LoggerScenarioRule.getInstance(logEntryEvent.TransactionScenario__c);
                if (scenarioRule.IsPlatformEventStorageLocationEnabled__c == trueString) {
                    platformEventStorageLocation = scenarioRule.PlatformEventStorageLocation__c;
                }
            }
            if (platformEventStorageLocation == DEFAULT_STORAGE_LOCATION_NAME) {
                logEntryEventsToSave.add(logEntryEvent);
            }
        }
        return logEntryEventsToSave;
    }

    private void upsertLoggerScenarios() {
        List<Schema.SObjectField> scenarioFields = new List<Schema.SObjectField>{
            Schema.LogEntryEvent__e.EntryScenario__c,
            Schema.LogEntryEvent__e.TransactionScenario__c
        };
        for (LogEntryEvent__e logEntryEvent : this.logEntryEvents) {
            for (Schema.SObjectField scenarioField : scenarioFields) {
                String scenario = (String) logEntryEvent.get(scenarioField);

                if (String.isBlank(scenario) == true || SCENARIO_UNIQUE_ID_TO_SCENARIO.containsKey(scenario)) {
                    continue;
                } else if (LoggerParameter.NORMALIZE_SCENARIO_DATA == true) {
                    LoggerScenario__c loggerScenario = new LoggerScenario__c(Name = scenario, UniqueId__c = scenario);
                    loggerScenario.setOptions(DML_OPTIONS);
                    SCENARIO_UNIQUE_ID_TO_SCENARIO.put(loggerScenario.UniqueId__c, loggerScenario);
                }
            }
        }

        List<Database.UpsertResult> upsertResults = LoggerDataStore.getDatabase()
            .upsertRecords(SCENARIO_UNIQUE_ID_TO_SCENARIO.values(), Schema.LoggerScenario__c.UniqueId__c, System.Test.isRunningTest());
        LoggerEmailSender.sendErrorEmail(Schema.LoggerScenario__c.SObjectType, upsertResults);

        // Requery to get the OwnerId field as well
        for (LoggerScenario__c loggerScenario : [
            SELECT Id, Name, OwnerId, UniqueId__c
            FROM LoggerScenario__c
            WHERE Id IN :SCENARIO_UNIQUE_ID_TO_SCENARIO.values()
        ]) {
            SCENARIO_UNIQUE_ID_TO_SCENARIO.put(loggerScenario.UniqueId__c, loggerScenario);
        }
    }

    private void upsertLogs() {
        // To avoid making a callout for every log for details retrieved from api.status.salesforce.com,
        // try to query recent logs first to see if there is a recent log with the details already populated
        Log__c recentLogWithApiReleaseDetails = LogManagementDataSelector.getInstance().getCachedRecentLogWithApiReleaseDetails();

        for (LogEntryEvent__e logEntryEvent : this.logEntryEvents) {
            // The LogEntryEvent__e object stores a denormalized version of Log__c & LogEntry__c data
            // In case the list contains entries tied to multiple transactions, use the TRANSACTION_ID_TO_LOG map to create 1 Log__c per transaction ID
            if (TRANSACTION_ID_TO_LOG.containsKey(logEntryEvent.TransactionId__c) == true) {
                continue;
            }

            Log__c log = new Log__c(
                ApiReleaseNumber__c = recentLogWithApiReleaseDetails?.ApiReleaseNumber__c,
                ApiReleaseVersion__c = recentLogWithApiReleaseDetails?.ApiReleaseVersion__c,
                ApiVersion__c = logEntryEvent.ApiVersion__c,
                ImpersonatedBy__c = logEntryEvent.ImpersonatedById__c,
                Locale__c = logEntryEvent.Locale__c,
                LoggedBy__c = logEntryEvent.LoggedById__c,
                LoggedByUsername__c = logEntryEvent.LoggedByUsername__c,
                LoggerVersionNumber__c = logEntryEvent.LoggerVersionNumber__c,
                LoginApplication__c = logEntryEvent.LoginApplication__c,
                LoginBrowser__c = logEntryEvent.LoginBrowser__c,
                LoginDomain__c = logEntryEvent.LoginDomain__c,
                LoginHistoryId__c = logEntryEvent.LoginHistoryId__c,
                LoginPlatform__c = logEntryEvent.LoginPlatform__c,
                LoginType__c = logEntryEvent.LoginType__c,
                LogoutUrl__c = logEntryEvent.LogoutUrl__c,
                NetworkId__c = logEntryEvent.NetworkId__c,
                NetworkLoginUrl__c = logEntryEvent.NetworkLoginUrl__c,
                NetworkLogoutUrl__c = logEntryEvent.NetworkLogoutUrl__c,
                NetworkName__c = logEntryEvent.NetworkName__c,
                NetworkSelfRegistrationUrl__c = logEntryEvent.NetworkSelfRegistrationUrl__c,
                NetworkUrlPathPrefix__c = logEntryEvent.NetworkUrlPathPrefix__c,
                OrganizationDomainUrl__c = logEntryEvent.OrganizationDomainUrl__c,
                OrganizationEnvironmentType__c = logEntryEvent.OrganizationEnvironmentType__c,
                OrganizationId__c = logEntryEvent.OrganizationId__c,
                OrganizationInstanceName__c = logEntryEvent.OrganizationInstanceName__c,
                OrganizationName__c = logEntryEvent.OrganizationName__c,
                OrganizationNamespacePrefix__c = logEntryEvent.OrganizationNamespacePrefix__c,
                OrganizationType__c = logEntryEvent.OrganizationType__c,
                OwnerId = this.determineLogOwnerId(logEntryEvent),
                ParentLogTransactionId__c = logEntryEvent.ParentLogTransactionId__c,
                ProfileId__c = logEntryEvent.ProfileId__c,
                ProfileName__c = logEntryEvent.ProfileName__c,
                RequestId__c = logEntryEvent.RequestId__c,
                Scenario__c = logEntryEvent.TransactionScenario__c,
                SessionId__c = logEntryEvent.SessionId__c,
                SessionSecurityLevel__c = logEntryEvent.SessionSecurityLevel__c,
                SessionType__c = logEntryEvent.SessionType__c,
                SourceIp__c = logEntryEvent.SourceIp__c,
                SystemMode__c = logEntryEvent.SystemMode__c,
                ThemeDisplayed__c = logEntryEvent.ThemeDisplayed__c,
                TimeZoneId__c = logEntryEvent.TimeZoneId__c,
                TimeZoneName__c = logEntryEvent.TimeZoneName__c,
                TransactionId__c = logEntryEvent.TransactionId__c,
                UserLicenseDefinitionKey__c = logEntryEvent.UserLicenseDefinitionKey__c,
                UserLicenseId__c = logEntryEvent.UserLicenseId__c,
                UserLicenseName__c = logEntryEvent.UserLicenseName__c,
                UserLoggingLevel__c = logEntryEvent.UserLoggingLevel__c,
                UserLoggingLevelOrdinal__c = logEntryEvent.UserLoggingLevelOrdinal__c,
                UserRoleId__c = logEntryEvent.UserRoleId__c,
                UserRoleName__c = logEntryEvent.UserRoleName__c,
                UserType__c = logEntryEvent.UserType__c
            );

            if (LoggerParameter.NORMALIZE_SCENARIO_DATA == false) {
                log.TransactionScenarioName__c = logEntryEvent.TransactionScenario__c;
            }

            if (
                String.isNotBlank(logEntryEvent.TransactionScenario__c) == true &&
                SCENARIO_UNIQUE_ID_TO_SCENARIO.containsKey(logEntryEvent.TransactionScenario__c) == true
            ) {
                log.TransactionScenario__c = SCENARIO_UNIQUE_ID_TO_SCENARIO.get(logEntryEvent.TransactionScenario__c).Id;
            }

            log.setOptions(DML_OPTIONS);
            TRANSACTION_ID_TO_LOG.put(log.TransactionId__c, log);
        }

        setQueriedAuthSessionDetails(TRANSACTION_ID_TO_LOG.values());
        setQueriedNetworkDetails(TRANSACTION_ID_TO_LOG.values());
        setQueriedOrganizationDetails(TRANSACTION_ID_TO_LOG.values());
        setQueriedUserDetails(TRANSACTION_ID_TO_LOG.values());

        List<Database.UpsertResult> upsertResults = LoggerDataStore.getDatabase()
            .upsertRecords(TRANSACTION_ID_TO_LOG.values(), Schema.Log__c.TransactionId__c, System.Test.isRunningTest());
        LoggerEmailSender.sendErrorEmail(Schema.Log__c.SObjectType, upsertResults);

        // If no recent logs have the details, and there is not another instance of the job in progress, then start a new one
        // TODO this probably should be moved to LogHandler instead of here
        String apexClassName = LogEntryEventHandler.class.getName();
        // I really dislike hardcoding this method name, but haven't found a better approach yet
        // FIXME by possibly converting the future method to a private queueable class (which would be better than future method anyway)
        String apexMethodName = 'setStatusApiDetails';
        List<String> jobStatuses = new List<String>{ 'Holding', 'Queued', 'Preparing', 'Processing' };
        if (
            LoggerParameter.CALL_STATUS_API == true &&
            recentLogWithApiReleaseDetails == null &&
            LogManagementDataSelector.getInstance().getCountOfAsyncApexJobs(apexClassName, apexMethodName, jobStatuses) == 0
        ) {
            setStatusApiDetails();
        }
    }

    private void upsertLogEntries() {
        List<LogEntry__c> logEntriesWithUuid = new List<LogEntry__c>();
        List<LogEntry__c> logEntriesWithoutUuid = new List<LogEntry__c>();
        for (LogEntryEvent__e logEntryEvent : this.logEntryEvents) {
            // Salesforce does not provide precise datetimes in Apex triggers for platform events
            // Use the string value of timestamp to set the actual datetime field as a workaround
            // See https://developer.salesforce.com/docs/atlas.en-us.platform_events.meta/platform_events/platform_events_api_considerations.htm
            Datetime timestamp = logEntryEvent.Timestamp__c;
            if (String.isNotBlank(logEntryEvent.TimestampString__c) == true) {
                timestamp = Datetime.valueOf(Long.valueOf(logEntryEvent.TimestampString__c));
            }

            LogEntry__c logEntry = new LogEntry__c(
                ComponentType__c = logEntryEvent.ComponentType__c,
                DatabaseResultCollectionSize__c = logEntryEvent.DatabaseResultCollectionSize__c,
                DatabaseResultCollectionType__c = logEntryEvent.DatabaseResultCollectionType__c,
                DatabaseResultJson__c = logEntryEvent.DatabaseResultJson__c,
                DatabaseResultType__c = logEntryEvent.DatabaseResultType__c,
                EpochTimestamp__c = logEntryEvent.EpochTimestamp__c,
                EventUuid__c = logEntryEvent.EventUuid,
                ExceptionMessage__c = logEntryEvent.ExceptionMessage__c,
                ExceptionStackTrace__c = logEntryEvent.ExceptionStackTrace__c,
                ExceptionType__c = logEntryEvent.ExceptionType__c,
                HttpRequestBody__c = logEntryEvent.HttpRequestBody__c,
                HttpRequestBodyMasked__c = logEntryEvent.HttpRequestBodyMasked__c,
                HttpRequestCompressed__c = logEntryEvent.HttpRequestCompressed__c,
                HttpRequestEndpoint__c = logEntryEvent.HttpRequestEndpoint__c,
                HttpRequestMethod__c = logEntryEvent.HttpRequestMethod__c,
                HttpResponseBody__c = logEntryEvent.HttpResponseBody__c,
                HttpResponseBodyMasked__c = logEntryEvent.HttpResponseBodyMasked__c,
                HttpResponseHeaderKeys__c = logEntryEvent.HttpResponseHeaderKeys__c,
                HttpResponseStatus__c = logEntryEvent.HttpResponseStatus__c,
                HttpResponseStatusCode__c = logEntryEvent.HttpResponseStatusCode__c,
                LimitsAggregateQueriesMax__c = logEntryEvent.LimitsAggregateQueriesMax__c,
                LimitsAggregateQueriesUsed__c = logEntryEvent.LimitsAggregateQueriesUsed__c,
                LimitsAsyncCallsMax__c = logEntryEvent.LimitsAsyncCallsMax__c,
                LimitsAsyncCallsUsed__c = logEntryEvent.LimitsAsyncCallsUsed__c,
                LimitsCalloutsMax__c = logEntryEvent.LimitsCalloutsMax__c,
                LimitsCalloutsUsed__c = logEntryEvent.LimitsCalloutsUsed__c,
                LimitsCpuTimeMax__c = logEntryEvent.LimitsCpuTimeMax__c,
                LimitsCpuTimeUsed__c = logEntryEvent.LimitsCpuTimeUsed__c,
                LimitsDmlRowsMax__c = logEntryEvent.LimitsDmlRowsMax__c,
                LimitsDmlRowsUsed__c = logEntryEvent.LimitsDmlRowsUsed__c,
                LimitsDmlStatementsMax__c = logEntryEvent.LimitsDmlStatementsMax__c,
                LimitsDmlStatementsUsed__c = logEntryEvent.LimitsDmlStatementsUsed__c,
                LimitsEmailInvocationsMax__c = logEntryEvent.LimitsEmailInvocationsMax__c,
                LimitsEmailInvocationsUsed__c = logEntryEvent.LimitsEmailInvocationsUsed__c,
                LimitsFutureCallsMax__c = logEntryEvent.LimitsFutureCallsMax__c,
                LimitsFutureCallsUsed__c = logEntryEvent.LimitsFutureCallsUsed__c,
                LimitsHeapSizeMax__c = logEntryEvent.LimitsHeapSizeMax__c,
                LimitsHeapSizeUsed__c = logEntryEvent.LimitsHeapSizeUsed__c,
                LimitsMobilePushApexCallsMax__c = logEntryEvent.LimitsMobilePushApexCallsMax__c,
                LimitsMobilePushApexCallsUsed__c = logEntryEvent.LimitsMobilePushApexCallsUsed__c,
                LimitsPublishImmediateDmlStatementsMax__c = logEntryEvent.LimitsPublishImmediateDmlStatementsMax__c,
                LimitsPublishImmediateDmlStatementsUsed__c = logEntryEvent.LimitsPublishImmediateDmlStatementsUsed__c,
                LimitsQueueableJobsMax__c = logEntryEvent.LimitsQueueableJobsMax__c,
                LimitsQueueableJobsUsed__c = logEntryEvent.LimitsQueueableJobsUsed__c,
                LimitsSoqlQueriesMax__c = logEntryEvent.LimitsSoqlQueriesMax__c,
                LimitsSoqlQueriesUsed__c = logEntryEvent.LimitsSoqlQueriesUsed__c,
                LimitsSoqlQueryLocatorRowsMax__c = logEntryEvent.LimitsSoqlQueryLocatorRowsMax__c,
                LimitsSoqlQueryLocatorRowsUsed__c = logEntryEvent.LimitsSoqlQueryLocatorRowsUsed__c,
                LimitsSoqlQueryRowsMax__c = logEntryEvent.LimitsSoqlQueryRowsMax__c,
                LimitsSoqlQueryRowsUsed__c = logEntryEvent.LimitsSoqlQueryRowsUsed__c,
                LimitsSoslSearchesMax__c = logEntryEvent.LimitsSoslSearchesMax__c,
                LimitsSoslSearchesUsed__c = logEntryEvent.LimitsSoslSearchesUsed__c,
                Log__c = TRANSACTION_ID_TO_LOG.get(logEntryEvent.TransactionId__c).Id,
                LoggingLevel__c = logEntryEvent.LoggingLevel__c,
                LoggingLevelOrdinal__c = logEntryEvent.LoggingLevelOrdinal__c,
                Message__c = logEntryEvent.Message__c,
                MessageMasked__c = logEntryEvent.MessageMasked__c,
                MessageTruncated__c = logEntryEvent.MessageTruncated__c,
                Name = null, // Salesforce will auto-set the record ID as the name when null
                OriginLocation__c = logEntryEvent.OriginLocation__c,
                OriginType__c = logEntryEvent.OriginType__c,
                RecordCollectionSize__c = logEntryEvent.RecordCollectionSize__c,
                RecordCollectionType__c = logEntryEvent.RecordCollectionType__c,
                RecordId__c = logEntryEvent.RecordId__c,
                RecordJson__c = logEntryEvent.RecordJson__c,
                RecordJsonMasked__c = logEntryEvent.RecordJsonMasked__c,
                RecordSObjectClassification__c = logEntryEvent.RecordSObjectClassification__c,
                RecordSObjectType__c = logEntryEvent.RecordSObjectType__c,
                RecordSObjectTypeNamespace__c = logEntryEvent.RecordSObjectTypeNamespace__c,
                StackTrace__c = logEntryEvent.StackTrace__c,
                Timestamp__c = timestamp,
                TransactionEntryNumber__c = logEntryEvent.TransactionEntryNumber__c,
                TriggerIsExecuting__c = logEntryEvent.TriggerIsExecuting__c,
                TriggerOperationType__c = logEntryEvent.TriggerOperationType__c,
                TriggerSObjectType__c = logEntryEvent.TriggerSObjectType__c
            );

            if (String.isNotBlank(logEntryEvent.EntryScenario__c) == true) {
                if (LoggerParameter.NORMALIZE_SCENARIO_DATA == true && SCENARIO_UNIQUE_ID_TO_SCENARIO.containsKey(logEntryEvent.EntryScenario__c) == true) {
                    logEntry.EntryScenario__c = SCENARIO_UNIQUE_ID_TO_SCENARIO.get(logEntryEvent.EntryScenario__c).Id;
                } else {
                    logEntry.EntryScenarioName__c = logEntryEvent.EntryScenario__c;
                }
            }

            if (String.isNotBlank(logEntryEvent.Tags__c) == true && LoggerParameter.NORMALIZE_TAG_DATA == false) {
                logEntry.Tags__c = logEntryEvent.Tags__c;
            }

            logEntry.setOptions(DML_OPTIONS);
            this.logEntries.add(logEntry);
            if (logEntry.EventUuid__c == null) {
                logEntriesWithoutUuid.add(logEntry);
            } else {
                logEntriesWithUuid.add(logEntry);
                if (logEntryEvent.Tags__c != null) {
                    List<String> logEntryTagNames = getTagNames(logEntryEvent.Tags__c);

                    this.tagNames.addAll(logEntryTagNames);
                    this.logEntryEventUuidToTagNames.put(logEntry.EventUuid__c, logEntryTagNames);
                }
            }
        }
        List<Database.SaveResult> saveResults = LoggerDataStore.getDatabase().insertRecords(logEntriesWithoutUuid);
        LoggerEmailSender.sendErrorEmail(Schema.LogEntry__c.SObjectType, saveResults);
        List<Database.UpsertResult> upsertResults = LoggerDataStore.getDatabase().upsertRecords(logEntriesWithUuid, Schema.LogEntry__c.EventUuid__c);
        LoggerEmailSender.sendErrorEmail(Schema.LogEntry__c.SObjectType, upsertResults);
    }

    private void appendRuleBasedTags() {
        if (LoggerParameter.ENABLE_TAGGING == false || TAG_ASSIGNMENT_RULES.isEmpty() == true) {
            return;
        }

        for (LogEntry__c logEntry : this.logEntries) {
            for (LogEntryTagRule__mdt rule : TAG_ASSIGNMENT_RULES) {
                if (isRuleCriteriaMet(logEntry, rule) == true) {
                    List<String> configuredTagNames = getTagNames(rule.Tags__c);
                    this.tagNames.addAll(configuredTagNames);
                    List<String> logEntryTags = logEntryEventUuidToTagNames.get(logEntry.EventUuid__c);
                    if (logEntryTags == null) {
                        logEntryTags = new List<String>();
                    }
                    logEntryTags.addAll(configuredTagNames);

                    this.logEntryEventUuidToTagNames.put(logEntry.EventUuid__c, logEntryTags);
                    this.tagNames.addAll(logEntryTags);
                }
            }
        }
    }

    private void upsertLogEntryTags() {
        if (LoggerParameter.ENABLE_TAGGING == false || LoggerParameter.NORMALIZE_TAG_DATA == false || this.tagNames.isEmpty() == true) {
            return;
        }

        // Orgs can be configured to either use LoggerTag__c & LogEntryTag__c (default), or use Topic & TopicAssignment
        Schema.SObjectType tagSObjectType = LoggerParameter.USE_TOPICS_FOR_TAGS == true ? Topic.SObjectType : LoggerTag__c.SObjectType;
        Map<String, Id> tagNameToId = getTagNameToId(tagSObjectType);
        this.tagNames.addAll(tagNameToId.keySet());

        // Assign the tags to the records
        Schema.SObjectType tagAssignmentSObjectType;
        Set<SObject> tagAssignments = new Set<SObject>();
        for (LogEntry__c logEntry : this.logEntries) {
            if (logEntry.EventUuid__c == null) {
                continue;
            }

            List<String> logEntryTagNames = this.logEntryEventUuidToTagNames.get(logEntry.EventUuid__c);
            if (logEntryTagNames == null || logEntryEventUuidToTagNames.isEmpty() == true) {
                continue;
            }

            for (String tagName : logEntryTagNames) {
                if (LoggerParameter.USE_TOPICS_FOR_TAGS == true) {
                    // Add TopicAssignment records for both the LogEntry__c & the parent Log__c
                    tagAssignmentSObjectType = Schema.TopicAssignment.SObjectType;
                    tagAssignments.add(new TopicAssignment(EntityId = logEntry.Id, TopicId = tagNameToId.get(tagName)));
                    tagAssignments.add(new TopicAssignment(EntityId = logEntry.Log__c, TopicId = tagNameToId.get(tagName)));
                } else {
                    // Add a LogEntryTag__c record for only the LogEntry__c - this approach does not directly link to the Log__c record
                    tagAssignmentSObjectType = Schema.LogEntryTag__c.SObjectType;
                    LogEntryTag__c logEntryTag = new LogEntryTag__c(LogEntry__c = logEntry.Id, Tag__c = tagNameToId.get(tagName));
                    logEntryTag.UniqueId__c = LogEntryTagHandler.generateUniqueId(logEntryTag);
                    logEntryTag.setOptions(DML_OPTIONS);
                    tagAssignments.add(logEntryTag);
                }
            }
        }

        switch on tagAssignmentSObjectType.newSObject() {
            when LogEntryTag__c logEntryTag {
                List<Database.UpsertResult> upsertResults = LoggerDataStore.getDatabase()
                    .upsertRecords(new List<SObject>(tagAssignments), Schema.LogEntryTag__c.UniqueId__c);
                LoggerEmailSender.sendErrorEmail(tagAssignmentSObjectType, upsertResults);
            }
            when TopicAssignment topicAssignment {
                Database.DmlOptions topicAssignmentDmlOptions = createDmlOptions();
                topicAssignmentDmlOptions.OptAllOrNone = false;
                List<Database.SaveResult> saveResults = LoggerDataStore.getDatabase()
                    .insertRecords(new List<SObject>(tagAssignments), topicAssignmentDmlOptions);
                LoggerEmailSender.sendErrorEmail(tagAssignmentSObjectType, saveResults);
            }
        }
    }

    private Id determineLogOwnerId(LogEntryEvent__e logEntryEvent) {
        Id logOwnerId = logEntryEvent.LoggedById__c;

        LoggerSettings__c loggingUserSettings = Logger.getUserSettings(new User(Id = logEntryEvent.LoggedById__c, ProfileId = logEntryEvent.ProfileId__c));
        if (logEntryEvent.UserType__c == GUEST_USER_TYPE || String.isBlank(logOwnerId) == true || loggingUserSettings.IsAnonymousModeEnabled__c == true) {
            logOwnerId = System.UserInfo.getUserId();
        }

        if (logEntryEvent.TransactionScenario__c != null && LoggerScenarioRule.getAll().containsKey(logEntryEvent.TransactionScenario__c) == true) {
            LoggerScenarioRule__mdt scenarioRule = LoggerScenarioRule.getInstance(logEntryEvent.TransactionScenario__c);
            if (
                scenarioRule.IsLogAssignmentEnabled__c == String.valueOf(true) &&
                SCENARIO_UNIQUE_ID_TO_SCENARIO.containsKey(logEntryEvent.TransactionScenario__c) == true
            ) {
                logOwnerId = SCENARIO_UNIQUE_ID_TO_SCENARIO.get(logEntryEvent.TransactionScenario__c).OwnerId;
            }
        }

        return logOwnerId;
    }

    private Map<String, Id> getTagNameToId(Schema.SObjectType tagSObjectType) {
        Map<String, Id> tagNameToId = new Map<String, Id>();

        List<SObject> tagRecords;
        switch on tagSObjectType.newSObject() {
            when LoggerTag__c loggerTag {
                tagRecords = LogManagementDataSelector.getInstance().getTagsByName(this.tagNames);
            }
            when Topic topic {
                tagRecords = LogManagementDataSelector.getInstance().getTopicsByName(this.tagNames);
            }
        }

        for (SObject tag : tagRecords) {
            tagNameToId.put((String) tag.get('Name'), (Id) tag.get('Id'));
        }
        tagNameToId.putAll(this.insertMissingTags(tagSObjectType, tagNameToId));

        return tagNameToId;
    }

    private Map<String, Id> insertMissingTags(Schema.SObjectType tagSObjectType, Map<String, Id> existingTagNameToId) {
        Map<String, Id> missingTagNameToId = new Map<String, Id>();

        List<SObject> missingTagsToCreate = new List<SObject>();
        for (String tagName : this.tagNames) {
            if (existingTagNameToId.containsKey(tagName) == false) {
                SObject tag = tagSObjectType.newSObject();
                tag.put('Name', tagName);
                tag.setOptions(DML_OPTIONS);
                missingTagsToCreate.add(tag);
            }
        }

        if (missingTagsToCreate.isEmpty() == false) {
            List<Database.SaveResult> saveResults = LoggerDataStore.getDatabase().insertRecords(missingTagsToCreate);
            LoggerEmailSender.sendErrorEmail(tagSObjectType, saveResults);
            for (SObject tag : missingTagsToCreate) {
                missingTagNameToId.put((String) tag.get('Name'), (Id) tag.get('Id'));
            }
        }

        return missingTagNameToId;
    }

    // Private static methods
    private static Database.DmlOptions createDmlOptions() {
        Database.DmlOptions dmlOptions = new Database.DmlOptions();
        dmlOptions.AllowFieldTruncation = true;
        dmlOptions.OptAllOrNone = System.Test.isRunningTest();
        return dmlOptions;
    }

    private static Boolean isRuleCriteriaMet(LogEntry__c logEntry, LogEntryTagRule__mdt rule) {
        Boolean ruleCriteriaMet = false;
        String ruleComparisonValue = rule.ComparisonValue__c;
        String logEntryFieldValue = rule.SObjectField__c == null ||
            logEntry.get(rule.SObjectField__c) == null
            ? ''
            : String.valueOf(logEntry.get(rule.SObjectField__c));

        switch on rule?.ComparisonType__c.toUpperCase() {
            when 'CONTAINS' {
                ruleCriteriaMet = logEntryFieldValue.containsIgnoreCase(ruleComparisonValue);
            }
            when 'EQUALS' {
                ruleCriteriaMet = logEntryFieldValue == ruleComparisonValue;
            }
            when 'MATCHES_REGEX' {
                ruleCriteriaMet = Pattern.compile(ruleComparisonValue).matcher(logEntryFieldValue).matches();
            }
            when 'STARTS_WITH' {
                ruleCriteriaMet = logEntryFieldValue.startsWith(ruleComparisonValue);
            }
        }

        return ruleCriteriaMet;
    }

    private static List<String> getTagNames(String tagsString) {
        List<String> cleanedTagNames = new List<String>();

        for (String tagName : tagsString.split(NEW_LINE_DELIMITER)) {
            if (String.isNotBlank(tagName) == true) {
                cleanedTagNames.add(tagName.trim());
            }
        }

        return cleanedTagNames;
    }

    private static List<LogEntryTagRule__mdt> getTagAssignmentRules() {
        List<LogEntryTagRule__mdt> tagAssignmentRules = LoggerEngineDataSelector.getInstance().getCachedTagAssignmentRules();
        if (System.Test.isRunningTest() == true) {
            // During tests, only use mock records - tests can add mock records using LogEntryEventHandler.TAG_ASSIGNMENT_RULES.add()
            tagAssignmentRules.clear();
        }
        return tagAssignmentRules;
    }

    private static void setQueriedAuthSessionDetails(List<Log__c> logs) {
        if (LoggerParameter.QUERY_AUTH_SESSION_DATA_SYNCHRONOUSLY == true) {
            return;
        }

        List<Id> userIds = new List<Id>();
        for (Log__c log : logs) {
            if (log.LoggedBy__c != null) {
                userIds.add(log.LoggedBy__c);
            }
        }
        Map<Id, LoggerSObjectProxy.AuthSession> userIdToAuthSessionProxy = LoggerEngineDataSelector.getInstance().getAuthSessionProxies(userIds);
        for (Log__c log : logs) {
            if (log.LoggedBy__c == null) {
                continue;
            }

            LoggerSObjectProxy.AuthSession matchingAuthSessionProxy = userIdToAuthSessionProxy.get(log.LoggedBy__c);
            if (matchingAuthSessionProxy == null) {
                continue;
            }

            log.LoginApplication__c = matchingAuthSessionProxy.LoginHistory.Application;
            log.LoginBrowser__c = matchingAuthSessionProxy.LoginHistory.Browser;
            log.LoginHistoryId__c = matchingAuthSessionProxy.LoginHistoryId;
            log.LoginPlatform__c = matchingAuthSessionProxy.LoginHistory.Platform;
            log.LoginType__c = matchingAuthSessionProxy.LoginType;
            log.LogoutUrl__c = matchingAuthSessionProxy.LogoutUrl;
            log.SessionId__c = matchingAuthSessionProxy.Id;
            log.SessionSecurityLevel__c = matchingAuthSessionProxy.SessionSecurityLevel;
            log.SessionType__c = matchingAuthSessionProxy.SessionType;
            log.SourceIp__c = matchingAuthSessionProxy.SourceIp;
        }
    }

    private static void setQueriedNetworkDetails(List<Log__c> logs) {
        if (LoggerParameter.QUERY_NETWORK_DATA_SYNCHRONOUSLY == true) {
            return;
        }

        List<Id> networkIds = new List<Id>();
        for (Log__c log : logs) {
            if (log.NetworkId__c != null && log.NetworkId__c instanceof Id) {
                networkIds.add(log.NetworkId__c);
            }
        }

        if (networkIds.isEmpty() == true) {
            return;
        }

        Map<Id, LoggerSObjectProxy.Network> networkIdToNetworkProxy = LoggerEngineDataSelector.getInstance().getNetworkProxies(networkIds);
        for (Log__c log : logs) {
            if (log.NetworkId__c == null) {
                continue;
            }

            LoggerSObjectProxy.Network matchingNetworkProxy = networkIdToNetworkProxy.get(log.NetworkId__c);
            if (matchingNetworkProxy == null) {
                continue;
            }

            log.NetworkLoginUrl__c = System.Network.getLoginUrl(matchingNetworkProxy.Id);
            log.NetworkLogoutUrl__c = System.Network.getLogoutUrl(matchingNetworkProxy.Id);
            log.NetworkName__c = matchingNetworkProxy.Name;
            log.NetworkSelfRegistrationUrl__c = System.Network.getSelfRegUrl(matchingNetworkProxy.Id);
            log.NetworkUrlPathPrefix__c = matchingNetworkProxy.UrlPathPrefix;
        }
    }

    private static void setQueriedOrganizationDetails(List<Log__c> logs) {
        if (LoggerParameter.QUERY_ORGANIZATION_DATA_SYNCHRONOUSLY == true) {
            return;
        }

        Organization cachedOrganization = LoggerEngineDataSelector.getInstance().getCachedOrganization();
        if (cachedOrganization == null) {
            return;
        }

        for (Log__c log : logs) {
            log.OrganizationId__c = cachedOrganization.Id;
            log.OrganizationInstanceName__c = cachedOrganization.InstanceName;
            log.OrganizationName__c = cachedOrganization.Name;
            log.OrganizationNamespacePrefix__c = cachedOrganization.NamespacePrefix;
            log.OrganizationType__c = cachedOrganization.OrganizationType;
        }
    }

    private static void setQueriedUserDetails(List<Log__c> logs) {
        if (LoggerParameter.QUERY_USER_DATA_SYNCHRONOUSLY == true) {
            return;
        }

        List<Id> userIds = new List<Id>();
        for (Log__c log : logs) {
            if (log.LoggedBy__c != null) {
                userIds.add(log.LoggedBy__c);
            }
        }

        Map<Id, User> userIdToUser = LoggerEngineDataSelector.getInstance().getUsers(userIds);
        for (Log__c log : logs) {
            if (log.LoggedBy__c == null) {
                continue;
            }

            User matchingUser = userIdToUser.get(log.LoggedBy__c);
            log.LoggedByUsername__c = matchingUser.Username;
            log.ProfileName__c = matchingUser.Profile.Name;
            log.UserLicenseDefinitionKey__c = matchingUser.Profile.UserLicense.LicenseDefinitionKey;
            log.UserLicenseId__c = matchingUser.Profile.UserLicenseId;
            log.UserLicenseName__c = matchingUser.Profile.UserLicense.Name;
            log.UserRoleName__c = matchingUser.UserRole?.Name;
        }
    }

    @future(callout=true)
    private static void setStatusApiDetails() {
        Organization organization = LoggerEngineDataSelector.getInstance().getCachedOrganization();
        String statusApiEndpoint = 'https://api.status.salesforce.com/v1/instances/' + organization.InstanceName + '/status';

        System.HttpRequest request = new System.HttpRequest();
        request.setEndpoint(statusApiEndpoint);
        request.setMethod('GET');

        System.HttpResponse response = new System.Http().send(request);
        if (response.getStatusCode() >= 400) {
            String errorMessage =
                'Callout failed for ' +
                statusApiEndpoint +
                '\nReceived request status code ' +
                response.getStatusCode() +
                ', status message: ' +
                response.getStatus();
            throw new System.CalloutException(errorMessage);
        }

        StatusApiResponse statusApiResponse = (StatusApiResponse) JSON.deserialize(response.getBody(), StatusApiResponse.class);
        List<Log__c> logsToUpdate = new List<Log__c>();
        for (Log__c log : [
            SELECT Id
            FROM Log__c
            WHERE CreatedDate = TODAY AND ApiReleaseNumber__c = NULL
            ORDER BY CreatedDate
            LIMIT :System.Limits.getLimitDmlRows()
        ]) {
            log.ApiReleaseNumber__c = statusApiResponse.releaseNumber;
            log.ApiReleaseVersion__c = statusApiResponse.releaseVersion;

            logsToUpdate.add(log);
        }
        LoggerDataStore.getDatabase().updateRecords(logsToUpdate);
    }

    // Private class for handling the response from api.status.salesforce.com
    @TestVisible
    private class StatusApiResponse {
        /**
         * @description String containing the release number.
         */
        public String releaseNumber { get; set; }

        /**
         * @description String containing the release version.
         */
        public String releaseVersion { get; set; }
    }
}
