/**
 * Copyright (c) 2015-present, Facebook, Inc.
 * All rights reserved.
 *
 * This source code is licensed under the BSD-style license found in the
 * LICENSE file in the root directory of this source tree. An additional grant
 * of patent rights can be found in the PATENTS file in the same directory.
 */

#import "AppDelegate.h"

#import "RCTRootView.h"
#import "CodePush.h"



@interface AppDelegate ()
@property(nonatomic, strong) void (^registrationHandler)
(NSString *registrationToken, NSError *error);
@property(nonatomic, assign) BOOL connectedToGCM;
@property(nonatomic, strong) NSString* registrationToken;
@property(nonatomic, assign) BOOL subscribedToTopic;
@end

NSString *const SubscriptionTopic = @"/topics/global";


@implementation AppDelegate

@synthesize bridge = _bridge;
/* Required to publish events */
RCTBridge * _mybridge;

//RCT_EXPORT_MODULE(GCM);


- (BOOL)application:(UIApplication *)application didFinishLaunchingWithOptions:(NSDictionary *)launchOptions
{
  NSURL *jsCodeLocation;

  /**
   * Loading JavaScript code - uncomment the one you want.
   *
   * OPTION 1
   * Load from development server. Start the server from the repository root:
   *
   * $ npm start
   *
   * To run on device, change `localhost` to the IP address of your computer
   * (you can get this by typing `ifconfig` into the terminal and selecting the
   * `inet` value under `en0:`) and make sure your computer and iOS device are
   * on the same Wi-Fi network.
   */


  //jsCodeLocation = [[NSBundle mainBundle] URLForResource:@"main" withExtension:@"jsbundle"];
#ifdef DEBUG
  jsCodeLocation = [NSURL URLWithString:@"http://localhost:8081/index.bundle?platform=ios&dev=true"];
  //jsCodeLocation = [CodePush bundleURL];
#else
  jsCodeLocation = [CodePush bundleURL];
#endif

 // RCTRootView *rootView = [[RCTRootView alloc] initWithBundleURL:jsCodeLocation
 //                                                     moduleName:@"SocialLearningApp"
 //                                              initialProperties:nil
 //                                                  launchOptions:launchOptions];

  _mybridge = [[RCTBridge alloc] initWithBundleURL:jsCodeLocation
                                    moduleProvider:nil
                                     launchOptions:launchOptions];

    RCTRootView *rootView = [[RCTRootView alloc] initWithBridge:_mybridge moduleName:@"SocialLearningApp" initialProperties:nil];


  self.window = [[UIWindow alloc] initWithFrame:[UIScreen mainScreen].bounds];
  UIViewController *rootViewController = [UIViewController new];
  rootViewController.view = rootView;
  self.window.rootViewController = rootViewController;
  [self.window makeKeyAndVisible];


  //************ GCM  ************
  _registrationKey = @"onRegistrationCompleted";
  _messageKey = @"onMessageReceived";

  // Configure the Google context: parses the GoogleService-Info.plist, and initializes
  // the services that have entries in the file
  NSError* configureError;
  [[GGLContext sharedInstance] configureWithError:&configureError];
  NSAssert(!configureError, @"Error configuring Google services: %@", configureError);
  _gcmSenderID = [[[GGLContext sharedInstance] configuration] gcmSenderID];

  // [START start_gcm_service]
  GCMConfig *gcmConfig = [GCMConfig defaultConfig];
  gcmConfig.receiverDelegate = self;
  [[GCMService sharedInstance] startWithConfig:gcmConfig];
  // [END start_gcm_service]

  __weak typeof(self) weakSelf = self;
  // Handler for registration token request
  _registrationHandler = ^(NSString *registrationToken, NSError *error){
    if (registrationToken != nil) {
      weakSelf.registrationToken = registrationToken;
      NSLog(@"Registration Token: %@", registrationToken);
      [weakSelf subscribeToTopic];
      NSDictionary *userInfo = @{@"registrationToken":registrationToken, @"type":@"Registration"};
      [[NSNotificationCenter defaultCenter] postNotificationName:weakSelf.registrationKey
                                                          object:nil
                                                        userInfo:userInfo];
      NSLog(@"Sending token");
      [_mybridge.eventDispatcher sendAppEventWithName:@"GCMEvent"
                                                   body:userInfo];

      NSLog(@"SENT token");
    } else {
      NSLog(@"Registration to GCM failed with error: %@", error.localizedDescription);
      NSDictionary *userInfo = @{@"error":error.localizedDescription};
      [[NSNotificationCenter defaultCenter] postNotificationName:weakSelf.registrationKey
                                                          object:nil
                                                        userInfo:userInfo];
    }
  };

  _myGCMScript = [[GCM alloc] init];

  //Check if we user has already registered for notification, if yes then call register (duh.. strange)
  BOOL notificationEnabled=false;
  if (floor(NSFoundationVersionNumber) <= NSFoundationVersionNumber_iOS_7_1) {

    UIRemoteNotificationType types = [[UIApplication sharedApplication] enabledRemoteNotificationTypes];
    notificationEnabled = (types != UIRemoteNotificationTypeNone);

  }
  else {

    notificationEnabled = [[UIApplication sharedApplication] isRegisteredForRemoteNotifications];

  }

  if(notificationEnabled){
    // Register for remote notifications
    if (floor(NSFoundationVersionNumber) <= NSFoundationVersionNumber_iOS_7_1) {
      // iOS 7.1 or earlier
      UIRemoteNotificationType allNotificationTypes =
      (UIRemoteNotificationTypeSound | UIRemoteNotificationTypeAlert | UIRemoteNotificationTypeBadge);
      [[UIApplication sharedApplication] registerForRemoteNotificationTypes:allNotificationTypes];
    } else {
      // iOS 8 or later
      // [END_EXCLUDE]
      UIUserNotificationType allNotificationTypes =
      (UIUserNotificationTypeSound | UIUserNotificationTypeAlert | UIUserNotificationTypeBadge);
      UIUserNotificationSettings *settings =
      [UIUserNotificationSettings settingsForTypes:allNotificationTypes categories:nil];
      [[UIApplication sharedApplication] registerUserNotificationSettings:settings];
      [[UIApplication sharedApplication] registerForRemoteNotifications];
    }
    // [END register_for_remote_notifications]
  }

  return YES;
}




//********GCM METHODS START*********//
- (void)subscribeToTopic {
  // If the app has a registration token and is connected to GCM, proceed to subscribe to the
  // topic
  if (_registrationToken && _connectedToGCM) {
    [[GCMPubSub sharedInstance] subscribeWithToken:_registrationToken
                                             topic:SubscriptionTopic
                                           options:nil
                                           handler:^(NSError *error) {
                                             if (error) {
                                               // Treat the "already subscribed" error more gently
                                               if (error.code == 3001) {
                                                 NSLog(@"Already subscribed to %@",
                                                       SubscriptionTopic);
                                               } else {
                                                 NSLog(@"Subscription failed: %@",
                                                       error.localizedDescription);
                                               }
                                             } else {
                                               self.subscribedToTopic = true;
                                               NSLog(@"Subscribed to %@", SubscriptionTopic);
                                             }
                                           }];
  }
}

// [START connect_gcm_service]
- (void)applicationDidBecomeActive:(UIApplication *)application {
  // Connect to the GCM server to receive non-APNS notifications
  [[GCMService sharedInstance] connectWithHandler:^(NSError *error) {
    if (error) {
      NSLog(@"Could not connect to GCM: %@", error.localizedDescription);
    } else {
      _connectedToGCM = true;
      NSLog(@"Connected to GCM");
      // [START_EXCLUDE]
      [self subscribeToTopic];
      // [END_EXCLUDE]
    }
  }];
}
// [END connect_gcm_service]

// [START disconnect_gcm_service]
- (void)applicationDidEnterBackground:(UIApplication *)application {
  [[GCMService sharedInstance] disconnect];
  // [START_EXCLUDE]
  _connectedToGCM = NO;
  // [END_EXCLUDE]
}
// [END disconnect_gcm_service]

// [START receive_apns_token]
- (void)application:(UIApplication *)application
didRegisterForRemoteNotificationsWithDeviceToken:(NSData *)deviceToken {
  // [END receive_apns_token]
  // [START get_gcm_reg_token]
  // Create a config and set a delegate that implements the GGLInstaceIDDelegate protocol.
  GGLInstanceIDConfig *instanceIDConfig = [GGLInstanceIDConfig defaultConfig];
  instanceIDConfig.delegate = self;
  // Start the GGLInstanceID shared instance with the that config and request a registration
  // token to enable reception of notifications
  [[GGLInstanceID sharedInstance] startWithConfig:instanceIDConfig];
  _registrationOptions = @{kGGLInstanceIDRegisterAPNSOption:deviceToken,
                           kGGLInstanceIDAPNSServerTypeSandboxOption:@YES};
  [[GGLInstanceID sharedInstance] tokenWithAuthorizedEntity:_gcmSenderID
                                                      scope:kGGLInstanceIDScopeGCM
                                                    options:_registrationOptions
                                                    handler:_registrationHandler];
  // [END get_gcm_reg_token]
}

// [START receive_apns_token_error]
- (void)application:(UIApplication *)application
didFailToRegisterForRemoteNotificationsWithError:(NSError *)error {
  NSLog(@"Registration for remote notification failed with error: %@", error.localizedDescription);
  // [END receive_apns_token_error]
  NSDictionary *userInfo = @{@"error" :error.localizedDescription};
  [[NSNotificationCenter defaultCenter] postNotificationName:_registrationKey
                                                      object:nil
                                                    userInfo:userInfo];
}

// [START ack_message_reception]
- (void)application:(UIApplication *)application
didReceiveRemoteNotification:(NSDictionary *)userInfo {
  NSDictionary *myUserInfo = @{@"body":userInfo, @"type":@"Message"};
  NSLog(@"Notification received: %@", userInfo);
  // This works only if the app started the GCM service
  [[GCMService sharedInstance] appDidReceiveMessage:userInfo];
  // Handle the received message
  // [START_EXCLUDE]
  [[NSNotificationCenter defaultCenter] postNotificationName:_messageKey
                                                      object:nil
                                                    userInfo:userInfo];


  NSLog(@"Sending message");
  [_mybridge.eventDispatcher sendAppEventWithName:@"GCMEvent"
                                             body:myUserInfo];

  NSLog(@"SENT message");

  // [END_EXCLUDE]
}

- (void)application:(UIApplication *)application
didReceiveRemoteNotification:(NSDictionary *)userInfo
fetchCompletionHandler:(void (^)(UIBackgroundFetchResult))handler {
  NSLog(@"Notification received: %@", userInfo);
  //This is actual GCM message (not registration message kind)
  NSDictionary *myUserInfo = @{@"body":userInfo, @"type":@"Message"};
  // This works only if the app started the GCM service
  [[GCMService sharedInstance] appDidReceiveMessage:userInfo];
  // Handle the received message
  // Invoke the completion handler passing the appropriate UIBackgroundFetchResult value
  // [START_EXCLUDE]
  [[NSNotificationCenter defaultCenter] postNotificationName:_messageKey
                                                      object:nil
                                                    userInfo:userInfo];

  NSLog(@"Sending message");
  [_mybridge.eventDispatcher sendAppEventWithName:@"GCMEvent"
                                             body:myUserInfo];

  NSLog(@"SENT message");

  handler(UIBackgroundFetchResultNoData);
  // [END_EXCLUDE]
}
// [END ack_message_reception]

// [START on_token_refresh]
- (void)onTokenRefresh {
  // A rotation of the registration tokens is happening, so the app needs to request a new token.
  NSLog(@"The GCM registration token needs to be changed.");
  [[GGLInstanceID sharedInstance] tokenWithAuthorizedEntity:_gcmSenderID
                                                      scope:kGGLInstanceIDScopeGCM
                                                    options:_registrationOptions
                                                    handler:_registrationHandler];
}
// [END on_token_refresh]

// [START upstream_callbacks]
- (void)willSendDataMessageWithID:(NSString *)messageID error:(NSError *)error {
  if (error) {
    // Failed to send the message.
  } else {
    // Will send message, you can save the messageID to track the message
  }
}

- (void)didSendDataMessageWithID:(NSString *)messageID {
  // Did successfully send message identified by messageID
}
// [END upstream_callbacks]

- (void)didDeleteMessagesOnServer {
  // Some messages sent to this device were deleted on the GCM server before reception, likely
  // because the TTL expired. The client should notify the app server of this, so that the app
  // server can resend those messages.
}

//********GCM METHODS END*********//


@end
