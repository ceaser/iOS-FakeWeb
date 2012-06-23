//
//  FakeWeb.m
//  FakeWeb
//
//  Created by Toshihiro Morimoto on 2/8/12.
//  Copyright (c) 2012 Toshihiro Morimoto (id:dealforest). All rights reserved.
//

#import "FakeWeb.h"

#define ALL_HTTP_METHOD [NSArray arrayWithObjects:@"GET", @"POST", @"PUT", @"DELETE", nil]

NSString * const FakeWebRequestKey = @"FakeWebRequestKey";
NSString * const FakeWebNotAllowedNetConnetException = @"FakeWebNotAllowedNetConnetException";

static NSMutableDictionary *uriMap;
static NSMutableDictionary *passthroughUriMap;
static BOOL allowNetConnect;
static BOOL autoCleanup;
static FakeWebResponder *mattingResponder;

@implementation FakeWeb

+ (void)initialize
{
    uriMap = [NSMutableDictionary new];
    passthroughUriMap = [NSMutableDictionary new];
    allowNetConnect = autoCleanup = TRUE;
    mattingResponder = nil;
}

//--------------------------------------------------------------//
#pragma mark -- register --
//--------------------------------------------------------------//

+(void) registerUri:(NSString *)uri method:(NSString *)method responses:(NSArray *)responses
{
    if (!method) return;
    
    NSMutableArray *responders = [NSMutableArray array];
    for (NSDictionary *response in responses) {
        NSString *body = [response objectForKey:@"body"];
        if ([body length] == 0) continue;
        
        NSInteger statusCode = 200;
        id status = [response objectForKey:@"status"];
        if ([status isKindOfClass:[NSString class]] || [status isKindOfClass:[NSNumber class]])
            statusCode = [(NSString *)status integerValue];
    
        FakeWebResponder *responder = [[FakeWebResponder alloc] initWithUri:uri 
                                                                     method:method 
                                                                       body:body
                                                                     status:statusCode
                                                              statusMessage:[response objectForKey:@"statusMessage"]];
        [responders addObject:responder];
    }
    if ([responders count] == 0) return;
    
    NSArray *methods = [self convertToMethodList:method];
    for (NSString *method_ in methods)
    {
        [uriMap setObject:responders forKey:[self keyForUri:uri method:method_]];
    }
}

+ (void)registerUri:(NSString *)uri method:(NSString *)method body:(NSString *)body staus:(NSInteger)status
{
    [self registerUri:uri method:method body:body staus:status statusMessage:nil];
}

+ (void)registerUri:(NSString*)uri method:(NSString*)method body:(NSString*)body 
{
    [self registerUri:uri method:method body:body staus:200 statusMessage:nil];
}

+ (void)registerUri:(NSString*)uri method:(NSString*)method body:(NSString*)body staus:(NSInteger)status statusMessage:(NSString*)statusMessage 
{
    if (!method) return;
    
    FakeWebResponder *responder = [[FakeWebResponder alloc] initWithUri:uri method:method body:body status:status statusMessage:statusMessage];

    NSArray *methods = [self convertToMethodList:method];
    for (NSString *method_ in methods)
    {
        NSString *key = [self keyForUri:uri method:method_];
        NSMutableArray *responders = (NSMutableArray *)[uriMap objectForKey:key];
        if (responders)
        {
            [responders removeAllObjects];
            [responders addObject:responder];
        }
        else 
            responders = [NSMutableArray arrayWithObjects:responder, nil];
        [uriMap setObject:responders forKey:key];
    }
}

+(void) registerPassthroughUri:(NSString *)uri
{
    [self registerPassthroughUri:uri method:@"ANY"];
}

+ (void)registerPassthroughUri:(NSString*)uri method:(NSString*)method 
{
    NSArray *methods = [self convertToMethodList:method];
    for (NSString *method_ in methods)
    {
        NSString *key = [self keyForUri:uri method:method_];
        [passthroughUriMap setValue:[NSString stringWithFormat:@"%d", YES] forKey:key];
    }
}

//--------------------------------------------------------------//
#pragma mark -- check --
//--------------------------------------------------------------//

+ (BOOL)registeredUri:(NSString*)uri 
{
    return [self registeredUri:uri method:@"ANY"];
}

+ (BOOL)registeredUri:(NSString*)uri method:(NSString*)method 
{
    NSArray *methods = [self convertToMethodList:method];
    for (NSString *method_ in methods)
    {
        NSString *key = [self keyForUri:uri method:method_];
        NSMutableArray *responders = (NSMutableArray *)[uriMap objectForKey:key];
        return [responders count] > 0 ? YES : NO;
    }
    return NO;
}

+ (BOOL)registeredPassthroughUri:(NSString*)uri 
{
    return [self registeredPassthroughUri:uri method:@"ANY"];
}

+ (BOOL)registeredPassthroughUri:(NSString*)uri method:(NSString*)method
{
    NSArray *methods = [self convertToMethodList:method];
    for (NSString *method_ in methods)
    {
        NSString *key = [self keyForUri:uri method:method_];
        if ([passthroughUriMap objectForKey:key])
            return TRUE;
    }
    return FALSE;
}

//--------------------------------------------------------------//
#pragma mark -- thorow exception --
//--------------------------------------------------------------//

+ (void)raiseNetConnectException:(NSString *)uri method:(NSString*)method
{
	@throw [NSException exceptionWithName:FakeWebNotAllowedNetConnetException
                                   reason:[self keyForUri:uri method:method]
                                 userInfo:nil];
}

//--------------------------------------------------------------//
#pragma mark -- settings --
//--------------------------------------------------------------//

+ (BOOL)allowNetConnet
{
    return allowNetConnect;
}

+ (BOOL)setAllowNetConnet:(BOOL)isConnect
{
    allowNetConnect = isConnect;
    return [self allowNetConnet];
}

+ (void)cleanRegistry
{
    [uriMap removeAllObjects];
    [passthroughUriMap removeAllObjects];
}

+ (FakeWebResponder *)responderFor:(NSString *)uri method:(NSString *)method
{
    mattingResponder = nil;
    if (allowNetConnect == NO && [self registeredPassthroughUri:uri method:method] == NO) {
        [self raiseNetConnectException:uri method:method];
        return nil;
    }

    FakeWebResponder *responder;
    responder = [self uriMapMatches:uriMap uri:uri method:method type:@"URI"];
    if (responder) return responder;
    
    responder = [self uriMapMatches:uriMap uri:uri method:@"ANY" type:@"URI"];
    if (responder) return  responder;
    
    responder = [self uriMapMatches:uriMap uri:uri method:method type:@"REGEX"];
    if (responder) return responder;
    
    responder = [self uriMapMatches:uriMap uri:uri method:@"ANY" type:@"REGEX"];
    return responder;
}

//--------------------------------------------------------------//
#pragma mark -- private --
//--------------------------------------------------------------//

+(FakeWebResponder *) machingResponder {
    return mattingResponder;
}

+(FakeWebResponder *) uriMapMatches:(NSMutableDictionary *)map uri:(NSString *)uri method:(NSString *)method type:(NSString *)type
{
    NSString *key = [self keyForUri:uri method:method];
    
    if ([type isEqualToString:@"URI"]) 
    {
        mattingResponder = [self matchFirstResponser:map key:key];
        return mattingResponder;
    }
    else {
        NSArray *methods = [self convertToMethodList:method];
        for (NSString *mapKey in [map allKeys]) 
        {
            NSString *uri_ = [[mapKey componentsSeparatedByString:@" "] objectAtIndex:1];
            for (NSString *method_ in methods)
            {
                NSString *key_ = [self keyForUri:uri_ method:method];
                NSError *error;
                NSRegularExpression *regex = [NSRegularExpression 
                                              regularExpressionWithPattern:key_
                                              options:NSRegularExpressionCaseInsensitive 
                                              error:&error];
                if (error) return nil;
                
                if ([regex numberOfMatchesInString:key options:0 range:NSMakeRange(0, [key length])] > 0) 
                {
                    mattingResponder = [self matchFirstResponser:map key:key_];
                    return mattingResponder;
                }
            }
        }
    }
    return nil;
}

+(FakeWebResponder *) matchFirstResponser:(NSDictionary *)map key:(NSString *)key
{
    NSMutableArray *responders = [map objectForKey:key];
    if ([responders count] == 1)
    {
        return [responders objectAtIndex:0];
    }
    else
    {
        FakeWebResponder *responder = [responders objectAtIndex:0];
        [responders removeObjectAtIndex:0];
        [responders addObject:responder];
        return responder;
    }
}

+(NSArray *) convertToMethodList:(NSString *)method 
{
    if (!method || [method isKindOfClass:[NSNull class]])
        return nil;
    
    return [method isEqualToString:@"ANY"] ? ALL_HTTP_METHOD : [NSArray arrayWithObjects:method, nil];
}

+(NSString *) keyForUri:(NSString *)uri method:(NSString *)method
{
    return [NSString stringWithFormat:@"%@ %@", method, [self sortQuery:[self normalizeUri:uri]]];
}

+(NSString*) normalizeUri:(NSString*)uri
{
    return [uri lowercaseString];
}

+(NSString*) sortQuery:(NSString *)uri
{
    NSArray *url = [uri componentsSeparatedByString:@"?"];
    if ([url count] > 1)
    {
        NSArray *params = [[url objectAtIndex:1] componentsSeparatedByString:@"&"];
        NSArray *sortParams = [params sortedArrayUsingSelector:@selector(compare:)];
        return [NSString stringWithFormat:@"%@?%@", [url objectAtIndex:0], [sortParams componentsJoinedByString:@"&"]];
    }
    return uri;
}

@end
