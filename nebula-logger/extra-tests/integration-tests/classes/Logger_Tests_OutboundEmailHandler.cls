//------------------------------------------------------------------------------------------------//
// This file is part of the Nebula Logger project, released under the MIT License.                //
// See LICENSE file or go to https://github.com/jongpie/NebulaLogger for full license details.    //
//------------------------------------------------------------------------------------------------//

@SuppressWarnings('PMD.ApexDoc, PMD.CyclomaticComplexity, PMD.ExcessiveParameterList, PMD.MethodNamingConventions, PMD.NcssMethodCount')
@IsTest(IsParallel=true)
private class Logger_Tests_OutboundEmailHandler {
  @IsTest
  private static void it_should_save_logs_when_running_within_outbound_email_handler() {
    Messaging.SingleEmailMessage email = new Messaging.SingleEmailMessage();
    email.setPlainTextBody('Example outbound email content');
    email.setSubject('My example outbound email');
    email.setToAddresses(new List<String>{ 'recipient@test.com' });

    ExampleOutboundEmailHandler emailHandler = new ExampleOutboundEmailHandler();
    System.Test.startTest();
    LoggerTestConfigurator.setupMockSObjectHandlerConfigurations();
    String transactionId = Logger.getTransactionId();
    System.Assert.areNotEqual(1, Logger.saveLogCallCount, 'No logging should have occurred yet');

    OutboundEmailResult result = emailHandler.handleOutboundEmail(email);

    System.Assert.areNotEqual(0, Logger.saveLogCallCount, 'ExampleOutboundEmailHandler class should have logged & saved some logging data');
    System.Test.stopTest();
    System.Assert.isTrue(result.success, 'OutboundEmailResult returned a failure message');
    List<Log__c> logs = [SELECT Id, TransactionId__c FROM Log__c];
    System.Assert.areEqual(1, logs.size(), 'Logs size did not match expected value of 1.');
    System.Assert.areEqual(transactionId, logs.get(0).TransactionId__c, 'Transaction Id does match expected value');
    List<LogEntry__c> logEntries = [SELECT Id, Message__c FROM LogEntry__c WHERE LoggingLevelOrdinal__c >= :System.LoggingLevel.INFO.ordinal()];
    System.Assert.areEqual(2, logEntries.size(), 'Log entries size did not match expected value of 2 ' + System.JSON.serializePretty(logEntries));
    System.Assert.areEqual(ExampleOutboundEmailHandler.logEntryMessage, logEntries.get(0).Message__c, 'Log entries message did not match expected value');
  }
}
