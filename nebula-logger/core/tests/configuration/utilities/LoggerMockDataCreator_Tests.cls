//------------------------------------------------------------------------------------------------//
// This file is part of the Nebula Logger project, released under the MIT License.                //
// See LICENSE file or go to https://github.com/jongpie/NebulaLogger for full license details.    //
//------------------------------------------------------------------------------------------------//

@SuppressWarnings('PMD.ApexDoc, PMD.MethodNamingConventions')
@IsTest(IsParallel=true)
private class LoggerMockDataCreator_Tests {
  static {
    LoggerConfigurationSelector.useMocks();
  }

  @IsTest
  static void it_uses_an_active_target_picklist_value_for_a_mapped_text_field() {
    LoggerConfigurationSelector.mockLoggerFieldMappings.add(
      new LoggerFieldMapping__mdt(
        DeveloperName = 'MappedPicklist',
        IsEnabled__c = true,
        SourceSObjectType__c = Schema.LogEntryEvent__e.SObjectType.toString(),
        SourceField__c = Schema.LogEntryEvent__e.Message__c.toString(),
        TargetSObjectType__c = Schema.Log__c.SObjectType.toString(),
        TargetField__c = Schema.Log__c.Priority__c.toString()
      )
    );
    Schema.PicklistEntry firstActiveValue;
    for (Schema.PicklistEntry value : Schema.Log__c.Priority__c.getDescribe().getPicklistValues()) {
      if (value.isActive()) {
        firstActiveValue = value;
        break;
      }
    }
    System.Assert.isNotNull(firstActiveValue, 'The test requires an active priority');

    LogEntryEvent__e event = (LogEntryEvent__e) LoggerMockDataCreator.createDataBuilder(Schema.LogEntryEvent__e.SObjectType).populateAllFields().getRecord();

    System.Assert.areEqual(firstActiveValue.getValue(), event.Message__c);
  }

  @IsTest
  static void it_leaves_text_unset_when_mapped_picklists_have_no_common_active_value() {
    LoggerConfigurationSelector.mockLoggerFieldMappings.add(
      new LoggerFieldMapping__mdt(
        DeveloperName = 'PriorityMapping',
        IsEnabled__c = true,
        SourceSObjectType__c = Schema.LogEntryEvent__e.SObjectType.toString(),
        SourceField__c = Schema.LogEntryEvent__e.Message__c.toString(),
        TargetSObjectType__c = Schema.Log__c.SObjectType.toString(),
        TargetField__c = Schema.Log__c.Priority__c.toString()
      )
    );
    LoggerConfigurationSelector.mockLoggerFieldMappings.add(
      new LoggerFieldMapping__mdt(
        DeveloperName = 'LoggingLevelMapping',
        IsEnabled__c = true,
        SourceSObjectType__c = Schema.LogEntryEvent__e.SObjectType.toString(),
        SourceField__c = Schema.LogEntryEvent__e.Message__c.toString(),
        TargetSObjectType__c = Schema.LogEntry__c.SObjectType.toString(),
        TargetField__c = Schema.LogEntry__c.LoggingLevel__c.toString()
      )
    );

    LogEntryEvent__e event = (LogEntryEvent__e) LoggerMockDataCreator.createDataBuilder(Schema.LogEntryEvent__e.SObjectType).populateAllFields().getRecord();

    System.Assert.isNull(event.Message__c);
  }

  @IsTest
  static void it_preserves_generated_text_when_there_is_no_picklist_mapping() {
    LogEntryEvent__e event = (LogEntryEvent__e) LoggerMockDataCreator.createDataBuilder(Schema.LogEntryEvent__e.SObjectType).populateAllFields().getRecord();

    System.Assert.areEqual('Message__c Test STRING', event.Message__c);
  }
}
