//
//  LuaServer.m
//  LuaDebugServer
//
//  Created by Miguel Angel Friginal on 7/4/10.
//  Copyright 2010 Mystery Coconut Games. All rights reserved.
//

#import "LuaServer.h"
#import "AsyncSocket.h"
#import "NetworkInfo.h"

#include <stdio.h>
#include <stdlib.h>
#include <unistd.h>
#include <fcntl.h>
#include <ifaddrs.h>
#include <arpa/inet.h>

enum MessageTags
{
    WelcomeMsg = 0,
    GenericMsg,
    WarningMsg,
};

@implementation LuaServer

@synthesize running;

- (id) init;
{
    self = [super init];
    if (self != nil)
    {
        debugServer = [[AsyncSocket alloc] initWithDelegate:self];
        connectedClients = [[NSMutableArray alloc] initWithCapacity:1];
        running = false;
        
        // Prepare Lua interpreter
        luaState = lua_objc_init();
    }
    return self;
}


- (void) dealloc;
{
    [self stop];
    
    lua_close(luaState);
    [connectedClients release];
    [debugServer release];
    [super dealloc];
}


#pragma mark Start/Stop server

- (void) start;
{
    [self startOnPort:9990];
}

- (void) startOnPort:(int)port;
{
    if (running)
        return;
    
    if (port < 0 || port > 65535)
        port = 0;
    
    NSError *error = nil;
    if (![debugServer acceptOnPort:port error:&error])
    {
        NSLog(@"Error starting Debug Server: %@", error);
        return;
    }
    
    NSString *bundleName = [[NSBundle mainBundle] objectForInfoDictionaryKey:@"CFBundleDisplayName"];
    NSLog(@"%@ Debug Server started at %@:%hu", bundleName, [NetworkInfo localIpAddress], [debugServer localPort]);
    NSLog(@"telnet %@ %hu", [NetworkInfo localIpAddress], [debugServer localPort]);
    
    running = true;
}


- (void) stop;
{
    if (!running)
        return;
    
    [debugServer disconnect];
    
    // Stop any client connections
    for (AsyncSocket* socket in connectedClients)
        [socket disconnect]; // Will call onSocketDidDisconnect: and remove it from connectedClients
    
    NSLog(@"Debug Server stopped");
    
    running = false;
}


- (void) registerObject:(id)obj withKey:(NSString*)key;
{
    lua_pushstring(luaState, [key UTF8String]);
    lua_objc_pushid(luaState, obj);
    lua_settable(luaState, LUA_GLOBALSINDEX);
}

#pragma mark Delegate methods


- (void)onSocket:(AsyncSocket *)socket didAcceptNewSocket:(AsyncSocket *)newSocket;
{
    NSLog(@"Connected");
	[connectedClients addObject:newSocket];
}


- (void)onSocketDidDisconnect:(AsyncSocket *)socket;
{
    NSLog(@"Disconnected");
	[connectedClients removeObject:socket];
}


- (void)onSocket:(AsyncSocket *)socket didConnectToHost:(NSString *)host port:(UInt16)port;
{
	NSLog(@"Accepted client %@:%hu", host, port);

    const NSString *bundleName = [[NSBundle mainBundle] objectForInfoDictionaryKey:@"CFBundleDisplayName"];
	const NSString *welcomeMsg = [NSString stringWithFormat:@"Welcome to the %@ Debug Server\r\n", bundleName];
	NSData *welcomeData = [welcomeMsg dataUsingEncoding:NSUTF8StringEncoding];
	
	[socket writeData:welcomeData withTimeout:-1 tag:WelcomeMsg];
    
    // Start reading from client
    [socket readDataWithTimeout:-1 tag:GenericMsg];
}


- (void)onSocket:(AsyncSocket *)socket didReadData:(NSData *)data withTag:(long)tag;
{
    NSString *input = [[NSString stringWithUTF8String:[data bytes]] stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    
    if ([input isEqualToString:@"exit"])
    {
        [socket writeData:[@"Bye!\r\n" dataUsingEncoding:NSUTF8StringEncoding] withTimeout:-1 tag:GenericMsg];
        [socket disconnectAfterWriting];
        return;
    }
    
    // Open pipe
    char buffer[256] = {0};
    int out_pipe[2];
    int saved_stdout;
    
    saved_stdout = dup(STDOUT_FILENO);
    pipe(out_pipe);
    fcntl(out_pipe[0], F_SETFL, O_NONBLOCK);
    dup2(out_pipe[1], STDOUT_FILENO);
    close(out_pipe[1]);
    
    // Run Lua
    luaL_loadbuffer(luaState, [input UTF8String], [input length], nil);
    lua_pcall(luaState, 0, 0, 0);
    
    // Read pipe into buffer and reconnect stdout
    read(out_pipe[0], buffer, 255);
    dup2(saved_stdout, STDOUT_FILENO);
    
    // Any output? Send it down the socket
    NSString *output = [NSString stringWithFormat:@"%@\r\n", [NSString stringWithCString:buffer encoding:NSUTF8StringEncoding]];
    NSData *outputData = [output dataUsingEncoding:NSUTF8StringEncoding];
    [socket writeData:outputData withTimeout:-1 tag:GenericMsg];

    // Start reading again
    [socket readDataWithTimeout:-1 tag:GenericMsg];
}

@end
