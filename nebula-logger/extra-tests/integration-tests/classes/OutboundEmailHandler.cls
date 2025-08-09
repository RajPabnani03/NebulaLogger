global interface OutboundEmailHandler {
  OutboundEmailResult handleOutboundEmail(Messaging.SingleEmailMessage email);
}
