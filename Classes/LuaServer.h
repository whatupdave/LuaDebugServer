//
//  LuaServer.h
//  LuaDebugServer
//
//  Created by Miguel Angel Friginal on 7/4/10.
//  Copyright 2010 Mystery Coconut Games. All rights reserved.
//

#import <Foundation/Foundation.h>
#import "LuaObjCBridge.h"

@class AsyncSocket;

@interface LuaServer : NSObject {
    AsyncSocket *debugServer;
    NSMutableArray *connectedClients;
    lua_State* luaState;
    bool running;
}

@property (readonly,getter=isRunning) bool running;

- (void) start; // Starts in default port: 9990 
- (void) startOnPort:(int)port;
- (void) stop;
- (void) registerObject:(id)obj withKey:(NSString*)key;

@end
