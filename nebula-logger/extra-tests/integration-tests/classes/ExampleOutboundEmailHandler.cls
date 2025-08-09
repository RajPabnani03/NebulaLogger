//------------------------------------------------------------------------------------------------//
// This file is part of the Nebula Logger project, released under the MIT License.                //
// See LICENSE file or go to https://github.com/jongpie/NebulaLogger for full license details.    //
//------------------------------------------------------------------------------------------------//

/**
 * @description Example outbound email handler class
 */
@SuppressWarnings('PMD.AvoidGlobalModifier')
global with sharing class ExampleOutboundEmailHandler implements OutboundEmailHandler {
  @TestVisible
  private static String logEntryMessage = 'Testing logging from OutboundEmailHandler';

  global OutboundEmailResult handleOutboundEmail(Messaging.SingleEmailMessage email) {
    OutboundEmailResult result = new OutboundEmailResult();
    try {
      String nullString = null;
      nullString.length();
    } catch (System.Exception apexException) {
      Logger.error(logEntryMessage, apexException);
    } finally {
      result.success = true;
      Logger.info('Logger buffer size before save: ' + Logger.getBufferSize());
      Logger.saveLog();
      Logger.info('Logger buffer size after save: ' + Logger.getBufferSize());
    }

    return result;
  }
}
