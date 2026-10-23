//------------------------------------------------------------------------------------------------//
// This file is part of the Nebula Logger project, released under the MIT License.                //
// See LICENSE file or go to https://github.com/jongpie/NebulaLogger for full license details.    //
//------------------------------------------------------------------------------------------------//

@SuppressWarnings('PMD.MethodNamingConventions')
@IsTest(IsParallel=true)
private class LoggerMockDataCreator_Tests {
  @IsTest
  static void it_should_create_users_with_unique_example_dot_com_email_addresses() {
    Schema.User firstUser = LoggerMockDataCreator.createUser();
    Schema.User secondUser = LoggerMockDataCreator.createUser();

    System.Assert.isTrue(firstUser.Email.endsWith('@example.com'), firstUser.Email);
    System.Assert.isTrue(secondUser.Email.endsWith('@example.com'), secondUser.Email);
    System.Assert.areNotEqual(firstUser.Email, secondUser.Email);
    System.Assert.areNotEqual(firstUser.Username, secondUser.Username);
    // User.Email and User.Username are both limited to 80 characters in Salesforce
    System.Assert.isTrue(firstUser.Email.length() <= 80, firstUser.Email);
    System.Assert.isTrue(secondUser.Email.length() <= 80, secondUser.Email);
    System.Assert.isTrue(firstUser.Username.length() <= 80, firstUser.Username);
    System.Assert.isTrue(secondUser.Username.length() <= 80, secondUser.Username);
  }
}
