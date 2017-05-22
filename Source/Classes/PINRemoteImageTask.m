//
//  PINRemoteImageTask.m
//  Pods
//
//  Created by Garrett Moon on 3/9/15.
//
//

#import "PINRemoteImageTask.h"

#import "PINRemoteImageCallbacks.h"
#import "PINRemoteImageManager+Private.h"

@interface PINRemoteImageTask ()
{
    NSMutableDictionary<NSUUID *, PINRemoteImageCallbacks *> *_callbackBlocks;
}

@end

@implementation PINRemoteImageTask

@synthesize lock = _lock;

- (instancetype)initWithManager:(PINRemoteImageManager *)manager
{
    if (self = [super init]) {
        _lock = [[PINRemoteLock alloc] initWithName:@"Task Lock"];
        _manager = manager;
        _callbackBlocks = [[NSMutableDictionary alloc] init];
    }
    return self;
}

- (NSString *)description
{
    return [NSString stringWithFormat:@"<%@: %p> completionBlocks: %lu", NSStringFromClass([self class]), self, (unsigned long)self.callbackBlocks.count];
}

- (void)addCallbacksWithCompletionBlock:(PINRemoteImageManagerImageCompletion)completionBlock
                     progressImageBlock:(PINRemoteImageManagerImageCompletion)progressImageBlock
                  progressDownloadBlock:(PINRemoteImageManagerProgressDownload)progressDownloadBlock
                               withUUID:(NSUUID *)UUID
{
    PINRemoteImageCallbacks *completion = [[PINRemoteImageCallbacks alloc] init];
    completion.completionBlock = completionBlock;
    completion.progressImageBlock = progressImageBlock;
    completion.progressDownloadBlock = progressDownloadBlock;
    
    [self.lock lockWithBlock:^{
        [_callbackBlocks setObject:completion forKey:UUID];
    }];
}

- (void)removeCallbackWithUUID:(NSUUID *)UUID
{
    [self.lock lockWithBlock:^{
        [self __locked_removeCallbackWithUUID:UUID];
    }];
}

- (void)__locked_removeCallbackWithUUID:(NSUUID *)UUID
{
    [_callbackBlocks removeObjectForKey:UUID];
}

- (NSDictionary<NSUUID *, PINRemoteImageCallbacks *> *)callbackBlocks
{
    __block NSDictionary *callbackBlocks;
    [self.lock lockWithBlock:^{
        callbackBlocks = [_callbackBlocks copy];
    }];
    return callbackBlocks;
}

- (void)callCompletionsWithImage:(PINImage *)image
       alternativeRepresentation:(id)alternativeRepresentation
                          cached:(BOOL)cached
                           error:(NSError *)error
                          remove:(BOOL)remove;
{
    __weak typeof(self) weakSelf = self;
    [self.callbackBlocks enumerateKeysAndObjectsUsingBlock:^(NSUUID *UUID, PINRemoteImageCallbacks *callback, BOOL *stop) {
        typeof(self) strongSelf = weakSelf;
        if (callback.completionBlock != nil) {
            PINLog(@"calling completion for UUID: %@ key: %@", UUID, strongSelf.key);
            PINRemoteImageManagerImageCompletion completionBlock = callback.completionBlock;
            CFTimeInterval requestTime = callback.requestTime;
            
            //The code run asynchronously below is *not* guaranteed to be run in the manager's lock!
            //All access to the callbacks and self should be done outside the block below!
            dispatch_async(self.manager.callbackQueue, ^
            {
                PINRemoteImageResultType result;
                if (image || alternativeRepresentation) {
                    result = cached ? PINRemoteImageResultTypeCache : PINRemoteImageResultTypeDownload;
                } else {
                    result = PINRemoteImageResultTypeNone;
                }
                completionBlock([self imageResultWithImage:image
                                 alternativeRepresentation:alternativeRepresentation
                                             requestLength:CACurrentMediaTime() - requestTime
                                                     error:error
                                                resultType:result
                                                      UUID:UUID]);
            });
        }
        if (remove) {
            [strongSelf removeCallbackWithUUID:UUID];
        }
    }];
}

- (BOOL)cancelWithUUID:(NSUUID *)UUID resume:(PINResume **)resume
{
    BOOL noMoreCompletions = NO;
    [self removeCallbackWithUUID:UUID];
    if ([self.callbackBlocks count] == 0) {
        noMoreCompletions = YES;
    }
    return noMoreCompletions;
}

- (BOOL)__locked_cancelWithUUID:(NSUUID *)UUID resume:(PINResume **)resume
{
    BOOL noMoreCompletions = NO;
    [self __locked_removeCallbackWithUUID:UUID];
    if ([_callbackBlocks count] == 0) {
        noMoreCompletions = YES;
    }
    return noMoreCompletions;
}

- (void)setPriority:(PINRemoteImageManagerPriority)priority
{
    
}

- (nonnull PINRemoteImageManagerResult *)imageResultWithImage:(nullable PINImage *)image
                                    alternativeRepresentation:(nullable id)alternativeRepresentation
                                                requestLength:(NSTimeInterval)requestLength
                                                        error:(nullable NSError *)error
                                                   resultType:(PINRemoteImageResultType)resultType
                                                         UUID:(nullable NSUUID *)UUID
{
    return [PINRemoteImageManagerResult imageResultWithImage:image
                                   alternativeRepresentation:alternativeRepresentation
                                               requestLength:requestLength
                                                       error:error
                                                  resultType:resultType
                                                        UUID:UUID];
}

- (NSMutableDictionary *)__locked_callbackBlocks
{
    return _callbackBlocks;
}

@end
