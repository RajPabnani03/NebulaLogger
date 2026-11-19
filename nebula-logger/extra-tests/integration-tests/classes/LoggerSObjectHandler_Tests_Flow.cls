//------------------------------------------------------------------------------------------------//
// This file is part of the Nebula Logger project, released under the MIT License.                //
// See LICENSE file or go to https://github.com/jongpie/NebulaLogger for full license details.    //
//------------------------------------------------------------------------------------------------//

@SuppressWarnings('PMD.ApexDoc, PMD.CyclomaticComplexity, PMD.ExcessiveParameterList, PMD.MethodNamingConventions, PMD.NcssMethodCount')
@IsTest(IsParallel=true)
private class LoggerSObjectHandler_Tests_Flow {
  // This Flow simply returns a string variable called 'someExampleVariable'
  // that's used in tests below to verify if the Flow was dynamically executed
  private static final String MOCK_FLOW_NAME = 'MockLoggerSObjectHandlerPlugin';
  private static final String MOCK_FLOW_OUTPUT_VARIABLE_VALUE = 'Hello, world';
  private static final String RECORD_FLOW_NAME = 'MockLoggerTriggerRecordPlugin';

  @IsTest
  static void it_should_execute_flow_plugin() {
    LoggerPlugin__mdt mockPluginConfiguration = new LoggerPlugin__mdt(
      DeveloperName = 'ExampleFlowPlugin',
      IsEnabled__c = true,
      SObjectHandlerFlowName__c = MOCK_FLOW_NAME
    );
    LoggerTestConfigurator.setMock(mockPluginConfiguration);
    MockLogHandler mockHandler = new MockLogHandler();
    mockHandler.triggerOperationType = System.TriggerOperation.BEFORE_INSERT;
    mockHandler.triggerNew = new List<Log__c>{ new Log__c(TransactionId__c = '1234') };
    mockHandler.triggerNewMap = null;
    mockHandler.triggerOldMap = null;

    mockHandler.execute();

    System.Assert.areEqual(1, mockHandler.getPluginConfigurations().size(), mockHandler.getPluginConfigurations().toString());
    System.Assert.areEqual(1, mockHandler.getExecutedFlowPlugins().size(), mockHandler.getExecutedFlowPlugins().toString());
    Flow.Interview executedFlowPlugin = mockHandler.getExecutedFlowPlugins().get(0);
    System.Assert.areEqual(mockPluginConfiguration, executedFlowPlugin.getVariableValue('pluginConfiguration'));
    System.Assert.areEqual(mockHandler.input, executedFlowPlugin.getVariableValue('pluginInput'));
    System.Assert.areEqual(MOCK_FLOW_OUTPUT_VARIABLE_VALUE, executedFlowPlugin.getVariableValue('someExampleVariable'));
  }

  @IsTest
  static void it_should_pass_new_records_to_a_scoped_flow_after_insert() {
    configureRecordFlow();
    Id logId = LoggerMockDataCreator.createId(Schema.Log__c.SObjectType);
    List<SObject> records = new List<SObject>{ new Log__c(Id = logId, TransactionId__c = 'new') };
    MockLogHandler handler = new MockLogHandler();
    handler.triggerOperationType = System.TriggerOperation.AFTER_INSERT;
    handler.triggerNew = records;
    handler.triggerNewMap = new Map<Id, SObject>(records);

    handler.execute();

    System.Assert.areEqual(1, handler.getExecutedFlowPlugins().size());
    Flow.Interview interview = handler.getExecutedFlowPlugins().get(0);
    System.Assert.areEqual('AFTER_INSERT', interview.getVariableValue('receivedOperation'));
    List<Log__c> triggerNew = (List<Log__c>) interview.getVariableValue('triggerNew');
    System.Assert.areEqual(1, triggerNew.size());
    System.Assert.areEqual(logId, triggerNew.get(0).Id);
    System.Assert.areEqual('new', triggerNew.get(0).TransactionId__c);
  }

  @IsTest
  static void it_should_pass_both_record_versions_to_a_scoped_flow_after_update() {
    configureRecordFlow();
    Id logId = LoggerMockDataCreator.createId(Schema.Log__c.SObjectType);
    List<SObject> records = new List<SObject>{ new Log__c(Id = logId, TransactionId__c = 'new') };
    MockLogHandler handler = new MockLogHandler();
    handler.triggerOperationType = System.TriggerOperation.AFTER_UPDATE;
    handler.triggerNew = records;
    handler.triggerNewMap = new Map<Id, SObject>(records);
    handler.triggerOldMap = new Map<Id, SObject>{ logId => new Log__c(Id = logId, TransactionId__c = 'old') };

    handler.execute();

    System.Assert.areEqual(1, handler.getExecutedFlowPlugins().size());
    Flow.Interview interview = handler.getExecutedFlowPlugins().get(0);
    System.Assert.areEqual('AFTER_UPDATE', interview.getVariableValue('receivedOperation'));
    List<Log__c> triggerNew = (List<Log__c>) interview.getVariableValue('triggerNew');
    List<Log__c> triggerOld = (List<Log__c>) interview.getVariableValue('triggerOld');
    System.Assert.areEqual(1, triggerNew.size());
    System.Assert.areEqual('new', triggerNew.get(0).TransactionId__c);
    System.Assert.areEqual(1, triggerOld.size());
    System.Assert.areEqual(logId, triggerOld.get(0).Id);
    System.Assert.areEqual('old', triggerOld.get(0).TransactionId__c);
  }

  @IsTest
  static void it_should_skip_a_flow_scoped_to_a_different_object() {
    configureRecordFlow();
    MockLogEntryHandler handler = new MockLogEntryHandler();
    handler.triggerOperationType = System.TriggerOperation.BEFORE_DELETE;

    handler.execute();

    System.Assert.areEqual(1, handler.getPluginConfigurations().size());
    System.Assert.areEqual(0, handler.getExecutedFlowPlugins().size());
  }

  private static void configureRecordFlow() {
    LoggerTestConfigurator.setMock(
      new LoggerPlugin__mdt(
        DeveloperName = 'ExampleRecordFlowPlugin',
        IsEnabled__c = true,
        SObjectHandlerFlowName__c = RECORD_FLOW_NAME,
        SObjectHandlerFlowObjectApiName__c = 'Log__c'
      )
    );
  }

  private class MockLogHandler extends LoggerSObjectHandler {
    public override Schema.SObjectType getSObjectType() {
      return Schema.Log__c.SObjectType;
    }
  }

  private class MockLogEntryHandler extends LoggerSObjectHandler {
    public override Schema.SObjectType getSObjectType() {
      return Schema.LogEntry__c.SObjectType;
    }
  }
}
