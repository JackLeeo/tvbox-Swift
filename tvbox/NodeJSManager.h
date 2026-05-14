#import <Foundation/Foundation.h>

@interface NodeJSManager : NSObject

+ (instancetype)shared;

- (void)startNodeJS:(void (^)(BOOL success))completion;
- (void)stopNodeJS;
- (void)waitForNodeReady:(void (^)(BOOL ready))completion;

- (void)loadSourceFromURL:(NSString *)urlString
               completion:(void (^)(BOOL success, NSString * _Nullable message))completion;
- (void)deleteSourceWithCompletion:(void (^)(BOOL success))completion;

- (int)getSpiderPort;
- (int)getManagementPort;
- (BOOL)isNodeReady;

@property (nonatomic, readonly) BOOL isRunning;

@end
