//------------------------------------------------------------------------------------------------//
// This file is part of the Nebula Logger project, released under the MIT License.                //
// See LICENSE file or go to https://github.com/jongpie/NebulaLogger for full license details.    //
//------------------------------------------------------------------------------------------------//

/**
 * @group Logger Engine
 * @description Handles adding new log entries in Flow
 * @see FlowRecordLogEntry
 * @see FlowCollectionLogEntry
 * @see FlowLogger
 * @see Logger
 * @see LogEntryEventBuilder
 */
@SuppressWarnings('PMD.AvoidGlobalModifier')
global inherited sharing class FlowLogEntry {
  /**
   * @description The API name of the Flow creating the log entry.
   *   Due to Salesforce limitations, this cannot be automatically determined.
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
   * @description Optionally relate the log entry to a particular record ID
   */
  @InvocableVariable(required=false label='(Optional) Record ID' description='The ID of a record to relate to this log entry.')
  global Id recordId;

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
   * @description Current system timestamp.
   */
  public DateTime timestamp = System.now();

  /**
   * @description Invocable method, that can be called via flow.
   * @param flowLogEntries The list of FlowLogEntry instances to save
   * @return The current transaction's ID (based on `Logger.getTransactionId()`)
   */
  @InvocableMethod(category='Logging' label='Add Log Entry' description='Creates a log entry for a flow or process builder')
  global static List<String> addFlowEntries(List<FlowLogEntry> flowLogEntries) {
    List<FlowLogger.LogEntry> shadowLogEntries = new List<FlowLogger.LogEntry>();
    for (FlowLogEntry flowLogEntry : flowLogEntries) {
      FlowLogger.LogEntry shadowLogEntry = (FlowLogger.LogEntry) System.JSON.deserialize(System.JSON.serialize(flowLogEntry), FlowLogger.LogEntry.class);
      shadowLogEntry.addToLoggerBuffer()?.setRecordId(flowLogEntry.recordId);

      shadowLogEntries.add(shadowLogEntry);
    }

    return FlowLogger.addEntries(shadowLogEntries);
  }
}
