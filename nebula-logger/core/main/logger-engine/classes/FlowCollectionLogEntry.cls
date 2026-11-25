//------------------------------------------------------------------------------------------------//
// This file is part of the Nebula Logger project, released under the MIT License.                //
// See LICENSE file or go to https://github.com/jongpie/NebulaLogger for full license details.    //
//------------------------------------------------------------------------------------------------//

/**
 * @group Logger Engine
 * @description Handles adding new log entries in Flow for a particular `SObject` record collection
 * @see FlowLogEntry
 * @see FlowRecordLogEntry
 * @see FlowLogger
 * @see Logger
 * @see LogEntryEventBuilder
 */
@SuppressWarnings('PMD.AvoidGlobalModifier')
global inherited sharing class FlowCollectionLogEntry {
  /**
   * @description The API name of the Flow creating the log entry.
   *   Due to Salesforce limitations, this cannot be automatically determined
   */
  @InvocableVariable(
    required=true
    label='Flow API Name'
    description='The API name of the Flow creating this log entry. Salesforce cannot determine this automatically, so it must be provided.'
  )
  global String flowName;

  /**
   * @description The message to log
   */
  @InvocableVariable(required=true label='Log Entry Message' description='The message text to include in the log entry.')
  global String message;

  /**
   * @description The records to relate to this log entry - the records' JSON is automatically added to the log entry
   */
  @InvocableVariable(
    required=false
    label='Records'
    description='A collection of records to relate to this log entry. The records\' JSON is automatically stored on the log entry.'
  )
  global List<SObject> records;

  /**
   * @description Optionally specify a logging level - the default is 'DEBUG'
   */
  @InvocableVariable(
    required=false
    label='(Optional) Logging Level'
    description='The logging level for this entry: ERROR, WARN, INFO, DEBUG, FINE, FINER or FINEST. Defaults to ERROR when a Flow Fault Error Message is provided, otherwise DEBUG.'
  )
  global String loggingLevelName;

  /**
   * @description Optionally log a Flow fault error message
   */
  @InvocableVariable(
    required=false
    label='(Optional) Flow Fault Error Message'
    description='A Flow fault error message (such as {!$Flow.FaultMessage}) to store as the log entry\'s exception message.'
  )
  global String faultMessage;

  /**
   * @description Optionally rollback Database operations executed until Apex action was called and save the log entry.
   */
  @InvocableVariable(
    required=false
    label='(Optional) Throw FlowException for Fault Error Message'
    description='When true, saves the log and then throws a FlowException, rolling back the Flow\'s pending database changes. Uses the Flow Fault Error Message, if provided. Defaults to false.'
  )
  global Boolean shouldThrowFaultMessageException;

  /**
   * @description Optionally choose to save any pending log entries
   */
  @InvocableVariable(
    required=false
    label='(Optional) Save Log'
    description='When true, saves all pending log entries in the current transaction. Defaults to false.'
  )
  global Boolean saveLog;

  /**
   * @description Optionally choose the save method to use when 'Save Log' is true
   */
  @InvocableVariable(
    required=false
    label='(Optional) Save Method'
    description='The save method to use when Save Log is true: EVENT_BUS, QUEUEABLE, REST or SYNCHRONOUS_DML. Defaults to the save method configured in Logger Settings.'
  )
  global String saveMethodName;

  /**
   * @description Optionally specify the name to use for the current transaction's scenario
   */
  @InvocableVariable(
    required=false
    label='(Optional) Scenario'
    description='The name of the scenario to use for the current transaction, useful for filtering and grouping logs.'
  )
  global String scenario;

  /**
   * @description Optionally provide a comma-separated String of tags to dynamically assign to the log entry
   */
  @InvocableVariable(
    required=false
    label='(Optional) Tags (comma-separated)'
    description='A comma-separated list of tags to add to the log entry, such as: Authentication, Login'
  )
  global String tagsString;

  /**
   * @description Optionally provide a comma-separated String of tags to dynamically assign to the log entry
   */
  @InvocableVariable(required=false label='DEPRECATED: Use \'Tags\' Instead')
  public List<String> topics;

  /**
   * @description Represents the current system time
   */
  public DateTime timestamp = System.now();

  /**
   * @description Invocable method for adding LogEntry records via flow or process builder
   * @param  flowCollectionLogEntries The list of FlowRecordLogEntry instances to save
   * @return The current transaction's ID (based on `Logger.getTransactionId()`)
   */
  @InvocableMethod(
    category='Logging'
    label='Add Log Entry for an SObject Record Collection'
    description='Creates a log entry for a flow or process builder and stores the record list as JSON'
  )
  global static List<String> addFlowCollectionEntries(List<FlowCollectionLogEntry> flowCollectionLogEntries) {
    List<FlowLogger.LogEntry> shadowLogEntries = new List<FlowLogger.LogEntry>();
    for (FlowCollectionLogEntry flowCollectionLogEntry : flowCollectionLogEntries) {
      FlowLogger.LogEntry shadowLogEntry = (FlowLogger.LogEntry) System.JSON.deserialize(
        System.JSON.serialize(flowCollectionLogEntry),
        FlowLogger.LogEntry.class
      );
      LogEntryEventBuilder builder = shadowLogEntry.addToLoggerBuffer()?.setRecord(flowCollectionLogEntry.records);
      if (builder.shouldSave() && flowCollectionLogEntry.records?.size() > 0) {
        builder.getLogEntryEvent().RecordSObjectType__c = flowCollectionLogEntry.records.get(0).getSObjectType().toString();
      }

      shadowLogEntries.add(shadowLogEntry);
    }

    return FlowLogger.addEntries(shadowLogEntries);
  }
}
