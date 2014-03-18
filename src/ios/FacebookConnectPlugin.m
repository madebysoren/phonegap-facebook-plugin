//
//  FacebookConnectPlugin.m
//  GapFacebookConnect
//
//  Created by Jesse MacFadyen on 11-04-22.
//  Updated by Mathijs de Bruin on 11-08-25.
//  Updated by Christine Abernathy on 13-01-22
//  Copyright 2011 Nitobi, Mathijs de Bruin. All rights reserved.
//

#import "FacebookConnectPlugin.h"

@interface FacebookConnectPlugin ()

@property (strong, nonatomic) NSString *userid;
@property (strong, nonatomic) NSString* loginCallbackId;
@property (strong, nonatomic) NSString* dialogCallbackId;

@end

@implementation FacebookConnectPlugin

/* This overrides CDVPlugin's method, which receives a notification when handleOpenURL is called on the main app delegate */
- (void) handleOpenURL:(NSNotification*)notification
{
        NSURL* url = [notification object];

        if (![url isKindOfClass:[NSURL class]]) {
        return;
        }

        [FBSession.activeSession handleOpenURL:url];
}

- (void)pluginInitialize
{
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(onAppDidBecomeActive:)
                                                 name:UIApplicationDidBecomeActiveNotification object:nil];
}

/*
 * This method is called to let your application know that it moved from the inactive to active state.
 */
- (void)onAppDidBecomeActive:(NSNotification*)notification
{
    [FBSettings setDefaultAppID:[[NSBundle mainBundle] objectForInfoDictionaryKey:@"FacebookAppID"]];
    [FBAppEvents activateApp];
    // We need to properly handle activation of the application with regards to Facebook Login
    // (e.g., returning from iOS 6.0 Login Dialog or from fast app switching).
    // See https://developers.facebook.com/docs/tutorials/ios-sdk-tutorial/authenticate/
    [FBSession.activeSession handleDidBecomeActive];
}

/*
 * Callback for session changes.
 */
- (void)sessionStateChanged:(FBSession *)session
                      state:(FBSessionState) state
                      error:(NSError *)error
{
    switch (state) {
        case FBSessionStateOpen:
        case FBSessionStateOpenTokenExtended:
            if (!error) {
                // We have a valid session

                if (state == FBSessionStateOpen) {
                    // Get the user's info
                    [FBRequestConnection startForMeWithCompletionHandler:
                     ^(FBRequestConnection *connection, id <FBGraphUser>user, NSError *error) {
                         if (!error) {
                             self.userid = user[@"id"];
                             // Send the plugin result. Wait for a successful fetch of user info.
                             CDVPluginResult* pluginResult = [CDVPluginResult resultWithStatus:CDVCommandStatus_OK
                                                                           messageAsDictionary:[self responseObject]];
                             [self.commandDelegate sendPluginResult:pluginResult callbackId:self.loginCallbackId];
                         } else {
                             self.userid = @"";

                         }
                     }];
                }else {
                    // Don't get user's info but trigger success callback
                    // Send the plugin result. Wait for a successful fetch of user info.
                    CDVPluginResult* pluginResult = [CDVPluginResult resultWithStatus:CDVCommandStatus_OK
                                                                messageAsDictionary:[self responseObject]];
                    [self.commandDelegate sendPluginResult:pluginResult callbackId:self.loginCallbackId];
                }
            }
            break;
        case FBSessionStateClosed:
        case FBSessionStateClosedLoginFailed:
            [FBSession.activeSession closeAndClearTokenInformation];
            self.userid = @"";
            break;
        default:
            break;
    }

    if (error) {
        NSString *alertMessage = nil;

        if (error.fberrorShouldNotifyUser) {
            // If the SDK has a message for the user, surface it.
            alertMessage = error.fberrorUserMessage;
        } else if (error.fberrorCategory == FBErrorCategoryAuthenticationReopenSession) {
            // Handles session closures that can happen outside of the app.
            // Here, the error is inspected to see if it is due to the app
            // being uninstalled. If so, this is surfaced. Otherwise, a
            // generic session error message is displayed.
            NSInteger underlyingSubCode = [[error userInfo]
                                           [@"com.facebook.sdk:ParsedJSONResponseKey"]
                                           [@"body"]
                                           [@"error"]
                                           [@"error_subcode"] integerValue];
            if (underlyingSubCode == 458) {
                alertMessage = @"The app was removed. Please log in again.";
            } else {
                alertMessage = @"Your current session is no longer valid. Please log in again.";
            }
        } else if (error.fberrorCategory == FBErrorCategoryUserCancelled) {
            // The user has cancelled a login. You can inspect the error
            // for more context.  Per the Facebook JS SDK, treat cancels as
            // a success and let the caller distinguish them by checking
            // response.authResponse.
            //
            // See comment for FB.login (facebook-js-sdk.js ln 6087):
            //
            //     FB.login(function(response) {
            //       if (response.authResponse) {
            //         // user successfully logged in
            //       } else {
            //         // user cancelled login
            //       }
            //     });
            //
            CDVPluginResult* pluginResult = [CDVPluginResult resultWithStatus:CDVCommandStatus_OK
                                                          messageAsDictionary:[self responseObject]];
            [self.commandDelegate sendPluginResult:pluginResult callbackId:self.loginCallbackId];
        } else {
            // For simplicity, this sample treats other errors blindly.
            alertMessage = @"Error. Please try again later.";
        }

        if (alertMessage) {
            CDVPluginResult* pluginResult = [CDVPluginResult resultWithStatus:CDVCommandStatus_ERROR
                                                              messageAsString:alertMessage];
            [self.commandDelegate sendPluginResult:pluginResult callbackId:self.loginCallbackId];
        }
    }
}

/*
 * Check if a permision is a read permission.
 */
- (BOOL)isPublishPermission:(NSString*)permission {
    return [permission hasPrefix:@"publish"] ||
    [permission hasPrefix:@"manage"] ||
    [permission isEqualToString:@"ads_management"] ||
    [permission isEqualToString:@"create_event"] ||
    [permission isEqualToString:@"rsvp_event"];
}

/*
 * Check if all permissions are read permissions.
 */
- (BOOL)areAllPermissionsReadPermissions:(NSArray*)permissions {
    for (NSString *permission in permissions) {
        if ([self isPublishPermission:permission]) {
            return NO;
        }
    }
    return YES;
}

- (void) init:(CDVInvokedUrlCommand*)command
{
    self.userid = @"";

    [FBSession openActiveSessionWithReadPermissions:nil
                                   allowLoginUI:NO
                              completionHandler:^(FBSession *session,
                                                  FBSessionState state,
                                                  NSError *error) {
                                  [self sessionStateChanged:session
                                                      state:state
                                                      error:error];
                              }];

    CDVPluginResult *pluginResult = [CDVPluginResult resultWithStatus:CDVCommandStatus_OK];
    [self.commandDelegate sendPluginResult:pluginResult callbackId:command.callbackId];
}

- (void) getLoginStatus:(CDVInvokedUrlCommand*)command
{
    CDVPluginResult* pluginResult = [CDVPluginResult resultWithStatus:CDVCommandStatus_OK
                                                  messageAsDictionary:[self responseObject]];
    [self.commandDelegate sendPluginResult:pluginResult callbackId:command.callbackId];
}

- (void) login:(CDVInvokedUrlCommand*)command
{
    NSArray *permissions = nil;
    if ([command.arguments count] > 0) {
        // sanitize permissions array
        // remove empty strings
        permissions = [command.arguments filteredArrayUsingPredicate:[NSPredicate predicateWithBlock:^BOOL(id evaluatedObject, NSDictionary *bindings) {
            return ![evaluatedObject isEqual:@""];
        }]];
    }

    // save the callbackId for the login callback
    self.loginCallbackId = command.callbackId;

    // Check if the session is open or not
    if (FBSession.activeSession.isOpen) {
        // Reauthorize if the session is already open.
        // In this instance we can ask for publish type
        // or read type only if taking advantage of iOS6.
        // To mix both, we'll use deprecated methods
        BOOL publishPermissionFound = NO;
        BOOL readPermissionFound = NO;
        for (NSString *p in permissions) {
            if ([self isPublishPermission:p]) {
                publishPermissionFound = YES;
            } else {
                readPermissionFound = YES;
            }

            // If we've found one of each we can stop looking.
            if (publishPermissionFound && readPermissionFound) {
                break;
            }
        }
        if (publishPermissionFound && readPermissionFound) {
            // Mix of permissions, use deprecated method
            [FBSession.activeSession
             reauthorizeWithPermissions:permissions
             behavior:FBSessionLoginBehaviorWithFallbackToWebView
             completionHandler:^(FBSession *session, NSError *error) {
                 [self sessionStateChanged:session
                                     state:session.state
                                     error:error];
             }];
        } else if (publishPermissionFound) {
            // Only publish permissions
            [FBSession.activeSession
             requestNewPublishPermissions:permissions
             defaultAudience:FBSessionDefaultAudienceFriends
             completionHandler:^(FBSession *session, NSError *error) {
                [self sessionStateChanged:session
                                    state:session.state
                                    error:error];
             }];
        } else {
            // Only read permissions
            [FBSession.activeSession
             requestNewReadPermissions:permissions
             completionHandler:^(FBSession *session, NSError *error) {
                 [self sessionStateChanged:session
                                     state:session.state
                                     error:error];
             }];
        }
    } else {
        // Initial log in, can only ask to read
        // type permissions if one wants to use the
        // non-deprecated open session methods and
        // take advantage of iOS6 integration
        if ([self areAllPermissionsReadPermissions:permissions]) {
            [FBSession
             openActiveSessionWithReadPermissions:permissions
             allowLoginUI:YES
             completionHandler:^(FBSession *session,
                                 FBSessionState state,
                                 NSError *error) {
                 [self sessionStateChanged:session
                                     state:state
                                     error:error];
             }];
        } else {
            // Use deprecated methods for backward compatibility
            [FBSession
             openActiveSessionWithPermissions:permissions
             allowLoginUI:YES completionHandler:^(FBSession *session,
                                                  FBSessionState state,
                                                  NSError *error) {
                 [self sessionStateChanged:session
                                     state:state
                                     error:error];
             }];
        }



    }

    [super writeJavascript:nil];
}

- (void) logout:(CDVInvokedUrlCommand*)command
{
    if (!FBSession.activeSession.isOpen) {
        return;
    }

    // Close the session and clear the cache
    [FBSession.activeSession closeAndClearTokenInformation];

    CDVPluginResult* pluginResult = [CDVPluginResult resultWithStatus:CDVCommandStatus_OK];
    [self.commandDelegate sendPluginResult:pluginResult callbackId:command.callbackId];
}

- (void) showDialog:(CDVInvokedUrlCommand*)command
{
    // Save the callback ID
    self.dialogCallbackId = command.callbackId;

    NSMutableDictionary *options = [[command.arguments lastObject] mutableCopy];
    NSString* method = [[NSString alloc] initWithString:[options objectForKey:@"method"]];
    if ([options objectForKey:@"method"]) {
        [options removeObjectForKey:@"method"];
    }
    NSMutableDictionary *params = [[NSMutableDictionary alloc] init];
    [options enumerateKeysAndObjectsUsingBlock:^(id key, id obj, BOOL *stop) {
        if ([obj isKindOfClass:[NSString class]]) {
            params[key] = obj;
        } else {
            NSError *error;
            NSData *jsonData = [NSJSONSerialization dataWithJSONObject:obj
                                                               options:0
                                                                 error:&error];
            if (jsonData) {
                NSString *jsonDataString = [[NSString alloc] initWithData:jsonData
                                                                 encoding:NSUTF8StringEncoding];
                params[key] = jsonDataString;
#if __has_feature(objc_arc)
#else
                [jsonDataString release];
#endif
            }
//            // For optional ARC support
//#if __has_feature(objc_arc)
//            FBSBJSON *jsonWriter = [FBSBJSON new];
//#else
//            FBSBJSON *jsonWriter = [[FBSBJSON new] autorelease];
//#endif
//            params[key] = [jsonWriter stringWithObject:obj];
        }
    }];

    // Show the web dialog
    [FBWebDialogs
     presentDialogModallyWithSession:FBSession.activeSession
     dialog:method parameters:params
     handler:^(FBWebDialogResult result, NSURL *resultURL, NSError *error) {
         CDVPluginResult* pluginResult = nil;
         if (error) {
             // Dialog failed with error
             pluginResult = [CDVPluginResult resultWithStatus:CDVCommandStatus_ERROR
                                              messageAsString:@"Error completing dialog."];
         } else {
             if (result == FBWebDialogResultDialogNotCompleted) {
                 // User clicked the "x" icon to Cancel
                 pluginResult = [CDVPluginResult resultWithStatus:CDVCommandStatus_NO_RESULT];
             } else {
                 // Send the URL parameters back, for a requests dialog, the "request" parameter
                 // will include the resutling request id. For a feed dialog, the "post_id"
                 // parameter will include the resulting post id.
                 NSDictionary *params = [self parseURLParams:[resultURL query]];
                 pluginResult = [CDVPluginResult resultWithStatus:CDVCommandStatus_OK messageAsDictionary:params];
             }
         }
         [self.commandDelegate sendPluginResult:pluginResult callbackId:self.dialogCallbackId];
    }];

    // For optional ARC support
    #if __has_feature(objc_arc)
    #else
        [method release];
        [params release];
        [options release];
    #endif

    [super writeJavascript:nil];
}

- (NSDictionary*) responseObject
{
    NSString* status = @"unknown";
    NSDictionary* sessionDict = nil;

    NSTimeInterval expiresTimeInterval = [FBSession.activeSession.accessTokenData.expirationDate timeIntervalSinceNow];
    NSString* expiresIn = @"0";
    if (expiresTimeInterval > 0) {
        expiresIn = [NSString stringWithFormat:@"%0.0f", expiresTimeInterval];
    }

    if (FBSession.activeSession.isOpen) {

        status = @"connected";
        sessionDict = @{
                        @"accessToken" : FBSession.activeSession.accessTokenData.accessToken,
                        @"expiresIn" : expiresIn,
                        @"secret" : @"...",
                        @"session_key" : [NSNumber numberWithBool:YES],
                        @"sig" : @"...",
                        @"userID" : self.userid,
                        };
    }

    NSMutableDictionary *statusDict = [NSMutableDictionary dictionaryWithObject:status forKey:@"status"];
    if (nil != sessionDict) {
        [statusDict setObject:sessionDict forKey:@"authResponse"];
    }

    return statusDict;
}

/**
 * A method for parsing URL parameters.
 */
- (NSDictionary*)parseURLParams:(NSString *)query {
    NSString *regexStr = @"^(.+)\\[(.*)\\]$";
    NSRegularExpression *regex = [NSRegularExpression regularExpressionWithPattern:regexStr options:0 error:nil];

    NSArray *pairs = [query componentsSeparatedByString:@"&"];
    NSMutableDictionary *params = [[NSMutableDictionary alloc] init];
    [pairs enumerateObjectsUsingBlock:
     ^(NSString *pair, NSUInteger idx, BOOL *stop) {
         NSArray *kv = [pair componentsSeparatedByString:@"="];
         NSString *key = [kv[0] stringByReplacingPercentEscapesUsingEncoding:NSUTF8StringEncoding];
         NSString *val = [kv[1] stringByReplacingPercentEscapesUsingEncoding:NSUTF8StringEncoding];

         NSArray *matches = [regex matchesInString:key options:0 range:NSMakeRange(0, [key length])];
         if ([matches count] > 0) {
             for (NSTextCheckingResult *match in matches) {

                 NSString *newKey = [key substringWithRange:[match rangeAtIndex:1]];

                 if ([[params allKeys] containsObject:newKey]) {
                     NSMutableArray *obj = [params objectForKey:newKey];
                     [obj addObject: val];
                     [params setObject: obj forKey: newKey];
                 } else {
                     NSMutableArray *obj = [NSMutableArray arrayWithObject:val];
                     [params setObject: obj forKey: newKey];
                 }
             }
         } else {
             params[key] = val;
         }
    }];
    return params;
}

@end
