#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@interface NodeJSManager : NSObject

@property (nonatomic, assign, readonly) BOOL isRunning;
@property (nonatomic, assign, readonly) BOOL isNodeReady;
@property (nonatomic, assign, readonly) int nativeServerPort;
@property (nonatomic, assign, readonly) int managementPort;
@property (nonatomic, assign, readonly) int spiderPort;

+ (instancetype)shared;

- (void)startNodeJS:(void (^)(BOOL success))completion;
- (void)stopNodeJS;
- (void)waitForNodeReady:(void (^)(BOOL ready))completion NS_SWIFT_NAME(waitForNodeReady(_:));
- (void)waitForSpiderPort:(void (^)(BOOL ready))completion NS_SWIFT_NAME(waitForSpiderPort(_:));

- (void)loadSourceFromURL:(NSString *)urlString
               completion:(void (^)(BOOL success, NSString * _Nullable message))completion;
- (void)deleteSourceWithCompletion:(void (^)(BOOL success))completion;

- (int)getNativeServerPort;
- (int)getManagementPort;
- (int)getSpiderPort;
- (NSString *)getDocumentsSourcePath;

@end

NS_ASSUME_NONNULL_END
