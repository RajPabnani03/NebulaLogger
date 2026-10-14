//------------------------------------------------------------------------------------------------//
// This file is part of the Nebula Logger project, released under the MIT License.                //
// See LICENSE file or go to https://github.com/jongpie/NebulaLogger for full license details.    //
//------------------------------------------------------------------------------------------------//

@SuppressWarnings('PMD.ApexDoc, PMD.MethodNamingConventions')
@IsTest(IsParallel=false)
private class LoggerMockDataCreator_Tests {
  @IsTest
  static void it_uses_the_running_user_email_domain_for_mock_users() {
    String expectedDomain = System.UserInfo.getUserEmail().substringAfter('@');
    System.Assert.isFalse(String.isBlank(expectedDomain), 'The running user should have an email domain');

    Schema.User firstUser = LoggerMockDataCreator.createUser();
    Schema.User secondUser = LoggerMockDataCreator.createUser();

    System.Assert.isTrue(firstUser.Email.endsWith('@' + expectedDomain), firstUser.Email);
    System.Assert.isTrue(secondUser.Email.endsWith('@' + expectedDomain), secondUser.Email);
    System.Assert.areNotEqual(firstUser.Email, secondUser.Email, 'Each mock user should get a unique email');
    System.Assert.areNotEqual('user_xyz@test.com.net.org', firstUser.Email);
    System.Assert.isTrue(firstUser.Username.endsWith('@test.com'), firstUser.Username);
    System.Assert.areNotEqual(firstUser.Username, secondUser.Username);

    insert new List<Schema.User>{ firstUser, secondUser };

    System.Assert.isNotNull(firstUser.Id);
    System.Assert.isNotNull(secondUser.Id);
  }
}
