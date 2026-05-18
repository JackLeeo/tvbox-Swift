#import "NodeJSManager.h"
#import <NodeMobile/NodeMobile.h>
#import <GCDWebServer/GCDWebServer.h>
#import <GCDWebServer/GCDWebServerDataRequest.h>
#import <GCDWebServer/GCDWebServerDataResponse.h>
#import <CommonCrypto/CommonDigest.h>

static const int kMaxStartupWaitSeconds = 30;

@interface NodeJSManager ()

@property (nonatomic, assign) BOOL isRunning;
@property (nonatomic, assign) BOOL nodeReady;
@property (nonatomic, strong) GCDWebServer *webServer;
@property (nonatomic, assign) int nativeServerPort;
@property (nonatomic, assign) int spiderPort;
@property (nonatomic, assign) int managementPort;

@end

@implementation NodeJSManager

+ (instancetype)shared {
    static NodeJSManager *instance = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        instance = [[NodeJSManager alloc] init];
    });
    return instance;
}

- (instancetype)init {
    self = [super init];
    if (self) {
        _isRunning = NO;
        _nodeReady = NO;
        _nativeServerPort = 0;
        _spiderPort = 0;
        _managementPort = 0;
    }
    return self;
}

#pragma mark - Path Helpers

- (NSString *)documentsSourcePath {
    NSArray *paths = NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES);
    NSString *documentsDir = paths.firstObject;
    NSString *sourcePath = [documentsDir stringByAppendingPathComponent:@"nodejs-project/src/source"];
    NSFileManager *fm = [NSFileManager defaultManager];
    if (![fm fileExistsAtPath:sourcePath]) {
        [fm createDirectoryAtPath:sourcePath withIntermediateDirectories:YES attributes:nil error:nil];
    }
    return sourcePath;
}

#pragma mark - MD5 Helper

- (NSString *)md5HexOfData:(NSData *)data {
    unsigned char digest[CC_MD5_DIGEST_LENGTH];
    CC_MD5(data.bytes, (CC_LONG)data.length, digest);
    NSMutableString *output = [NSMutableString stringWithCapacity:CC_MD5_DIGEST_LENGTH * 2];
    for (int i = 0; i < CC_MD5_DIGEST_LENGTH; i++) {
        [output appendFormat:@"%02x", digest[i]];
    }
    return output;
}

#pragma mark - Local Web Server

- (BOOL)startLocalWebServer {
    self.webServer = [[GCDWebServer alloc] init];

    __weak typeof(self) weakSelf = self;

    [self.webServer addHandlerForMethod:@"GET"
                                    path:@"/onCatPawOpenPort"
                            requestClass:[GCDWebServerDataRequest class]
                            processBlock:^GCDWebServerResponse * _Nullable(GCDWebServerDataRequest * _Nonnull request) {
        NSString *portStr = request.query[@"port"];
        NSString *typeStr = request.query[@"type"] ?: @"spider";
        if (portStr) {
            int port = [portStr intValue];
            NSLog(@"[NodeJSManager] Port received: %d, type: %@", port, typeStr);

            dispatch_async(dispatch_get_main_queue(), ^{
                __strong typeof(weakSelf) strongSelf = weakSelf;
                if (!strongSelf) return;
                if ([typeStr isEqualToString:@"management"]) {
                    strongSelf.managementPort = port;
                } else {
                    strongSelf.spiderPort = port;
                }

                [[NSNotificationCenter defaultCenter] postNotificationName:@"NodeServerPortReceived"
                                                                    object:nil
                                                                  userInfo:@{@"port": @(port), @"type": typeStr}];
            });
        }
        return [GCDWebServerDataResponse responseWithText:@"OK"];
    }];

    [self.webServer addHandlerForMethod:@"POST"
                                    path:@"/onMessage"
                            requestClass:[GCDWebServerDataRequest class]
                            processBlock:^GCDWebServerResponse * _Nullable(GCDWebServerDataRequest * _Nonnull request) {
        NSData *bodyData = request.data;
        if (bodyData) {
            NSError *error;
            NSDictionary *body = [NSJSONSerialization JSONObjectWithData:bodyData options:0 error:&error];
            if (!error && body) {
                NSString *message = body[@"message"];
                if (message) {
                    NSLog(@"[NodeJSManager] Message from Node.js: %@", message);
                    dispatch_async(dispatch_get_main_queue(), ^{
                        __strong typeof(weakSelf) strongSelf = weakSelf;
                        if (!strongSelf) return;
                        if ([message isEqualToString:@"ready"]) {
                            strongSelf.nodeReady = YES;
                            [[NSNotificationCenter defaultCenter] postNotificationName:@"NodeReady"
                                                                                object:nil
                                                                              userInfo:nil];
                        } else {
                            [[NSNotificationCenter defaultCenter] postNotificationName:@"NodeMessageReceived"
                                                                                object:nil
                                                                              userInfo:@{@"message": message}];
                        }
                    });
                }
            }
        }
        return [GCDWebServerDataResponse responseWithText:@"OK"];
    }];

    NSError *error;
    [self.webServer startWithOptions:@{
        GCDWebServerOption_Port: @0,
        GCDWebServerOption_BindToLocalhost: @YES
    } error:&error];

    if (error) {
        NSLog(@"[NodeJSManager] Local web server error: %@", error);
        return NO;
    }

    self.nativeServerPort = (int)self.webServer.port;
    NSLog(@"[NodeJSManager] Local notification server started on port: %d", self.nativeServerPort);
    return YES;
}

#pragma mark - Start / Stop

- (void)startNodeJS:(void (^)(BOOL success))completion {
    if (self.isRunning) {
        if (completion) completion(YES);
        return;
    }

    self.nodeReady = NO;
    self.spiderPort = 0;
    self.managementPort = 0;

    NSString *scriptPath = [[NSBundle mainBundle] pathForResource:@"main" ofType:@"js" inDirectory:@"nodejs-project/dist"];
    if (!scriptPath) {
        scriptPath = [[NSBundle mainBundle] pathForResource:@"main" ofType:@"js" inDirectory:@"dist"];
    }
    if (!scriptPath) {
        scriptPath = [[NSBundle mainBundle] pathForResource:@"index" ofType:@"js" inDirectory:@"nodejs-project/dist"];
    }
    if (!scriptPath) {
        scriptPath = [[NSBundle mainBundle] pathForResource:@"index" ofType:@"js" inDirectory:@"dist"];
    }
    if (!scriptPath) {
        scriptPath = [[NSBundle mainBundle] pathForResource:@"main" ofType:@"js"];
    }
    if (!scriptPath) {
        scriptPath = [[NSBundle mainBundle] pathForResource:@"index" ofType:@"js"];
    }

    if (!scriptPath) {
        NSLog(@"[NodeJSManager] Node.js script NOT FOUND in bundle!");
        if (completion) completion(NO);
        return;
    }

    if (![self startLocalWebServer]) {
        if (completion) completion(NO);
        return;
    }

    NSLog(@"[NodeJSManager] Starting Node.js with script: %@, nativeServerPort: %d", scriptPath, self.nativeServerPort);

    NSString *sourcePath = [self documentsSourcePath];
    const char *nodePathC = [sourcePath UTF8String];
    setenv("NODE_PATH", nodePathC, 1);

    NSMutableArray *args = [NSMutableArray arrayWithObjects:@"node", @"--security-revert=CVE-2023-46809", scriptPath, nil];
    if (self.nativeServerPort > 0) {
        [args addObject:@"--native-port"];
        [args addObject:[NSString stringWithFormat:@"%d", self.nativeServerPort]];
    }

    int argc = (int)args.count;
    char **argv = (char **)malloc((argc + 1) * sizeof(char *));
    for (int i = 0; i < argc; i++) {
        argv[i] = strdup([args[i] UTF8String]);
    }
    argv[argc] = NULL;

    self.isRunning = YES;

    __weak typeof(self) weakSelf = self;

    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
        node_start(argc, argv);

        for (int i = 0; i < argc; i++) {
            free(argv[i]);
        }
        free(argv);

        __strong typeof(weakSelf) strongSelf = weakSelf;
        if (strongSelf) {
            dispatch_async(dispatch_get_main_queue(), ^{
                strongSelf.isRunning = NO;
                strongSelf.nodeReady = NO;
                [strongSelf.webServer stop];
            });
        }
    });

    if (completion) {
        [self waitForNodeReadyInternalWithCompletion:completion];
    }
}

- (void)waitForNodeReadyInternalWithCompletion:(void (^)(BOOL ready))completion {
    __block id observer = nil;
    __block BOOL completed = NO;

    void (^finish)(BOOL) = ^(BOOL ready) {
        @synchronized (self) {
            if (completed) return;
            completed = YES;
        }
        if (observer) {
            [[NSNotificationCenter defaultCenter] removeObserver:observer];
            observer = nil;
        }
        if (completion) completion(ready);
    };

    observer = [[NSNotificationCenter defaultCenter] addObserverForName:@"NodeReady"
                                                                object:nil
                                                                 queue:[NSOperationQueue mainQueue]
                                                            usingBlock:^(NSNotification * _Nonnull note) {
        finish(YES);
    }];

    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(kMaxStartupWaitSeconds * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        finish(NO);
    });
}

- (void)waitForSpiderPort:(void (^)(BOOL ready))completion {
    if (self.spiderPort > 0) {
        if (completion) completion(YES);
        return;
    }

    __block id observer = nil;
    __block BOOL completed = NO;

    void (^finish)(BOOL) = ^(BOOL ready) {
        @synchronized (self) {
            if (completed) return;
            completed = YES;
        }
        if (observer) {
            [[NSNotificationCenter defaultCenter] removeObserver:observer];
            observer = nil;
        }
        if (completion) completion(ready);
    };

    observer = [[NSNotificationCenter defaultCenter] addObserverForName:@"NodeServerPortReceived"
                                                                object:nil
                                                                 queue:[NSOperationQueue mainQueue]
                                                            usingBlock:^(NSNotification * _Nonnull note) {
        NSString *type = note.userInfo[@"type"] ?: @"";
        if ([type isEqualToString:@"spider"]) {
            finish(YES);
        }
    }];

    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(30 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        finish(NO);
    });
}

- (void)stopNodeJS {
    if (!self.isRunning) return;

    self.isRunning = NO;
    self.nodeReady = NO;
    [self.webServer stop];
    self.webServer = nil;
    self.nativeServerPort = 0;
    self.spiderPort = 0;
    self.managementPort = 0;

    NSLog(@"[NodeJSManager] Node.js stopped");
}

- (void)forceResetRunningState {
    self.isRunning = NO;
    self.nodeReady = NO;
    [self.webServer stop];
    self.webServer = nil;
    self.nativeServerPort = 0;
    self.spiderPort = 0;
    self.managementPort = 0;

    NSLog(@"[NodeJSManager] Force reset running state for recovery");
}

#pragma mark - Wait for Ready (Public)

- (void)waitForNodeReady:(void (^)(BOOL ready))completion {
    if (self.nodeReady) {
        if (completion) completion(YES);
        return;
    }

    __block id observer = nil;
    __block BOOL completed = NO;

    void (^finish)(BOOL) = ^(BOOL ready) {
        @synchronized (self) {
            if (completed) return;
            completed = YES;
        }
        if (observer) {
            [[NSNotificationCenter defaultCenter] removeObserver:observer];
            observer = nil;
        }
        if (completion) completion(ready);
    };

    observer = [[NSNotificationCenter defaultCenter] addObserverForName:@"NodeReady"
                                                                object:nil
                                                                 queue:[NSOperationQueue mainQueue]
                                                            usingBlock:^(NSNotification * _Nonnull note) {
        finish(YES);
    }];

    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(kMaxStartupWaitSeconds * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        finish(NO);
    });
}

#pragma mark - Source Management

- (void)loadSourceFromURL:(NSString *)urlString
               completion:(void (^)(BOOL success, NSString * _Nullable message))completion {
    if (!urlString.length) {
        if (completion) completion(NO, @"URL is empty");
        return;
    }

    NSString *normalizedUrl = urlString;
    if ([normalizedUrl hasSuffix:@".js.md5"]) {
        normalizedUrl = [normalizedUrl substringToIndex:normalizedUrl.length - 4];
        NSLog(@"[NodeJSManager] Normalized URL (removed .md5 suffix): %@", normalizedUrl);
    }

    NSURL *url = [NSURL URLWithString:normalizedUrl];
    if (!url) {
        if (completion) completion(NO, @"Invalid URL");
        return;
    }

    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
        NSString *sourcePath = [self documentsSourcePath];
        NSString *indexJSPath = [sourcePath stringByAppendingPathComponent:@"index.js"];
        NSString *indexMd5Path = [sourcePath stringByAppendingPathComponent:@"index.js.md5"];
        NSString *configJSPath = [sourcePath stringByAppendingPathComponent:@"index.config.js"];
        NSString *configMd5Path = [sourcePath stringByAppendingPathComponent:@"index.config.js.md5"];

        NSFileManager *fm = [NSFileManager defaultManager];
        BOOL localJSExists = [fm fileExistsAtPath:indexJSPath];
        BOOL localMd5Exists = [fm fileExistsAtPath:indexMd5Path];
        NSLog(@"[NodeJSManager] Cache check: index.js exists=%d, index.js.md5 exists=%d", localJSExists, localMd5Exists);

        if (localJSExists && localMd5Exists) {
            __block NSData *remoteMd5Data = nil;
            __block BOOL md5DownloadSuccess = NO;

            dispatch_group_t md5Group = dispatch_group_create();
            dispatch_group_enter(md5Group);
            NSString *md5Url = [normalizedUrl stringByAppendingString:@".md5"];
            NSLog(@"[NodeJSManager] Cache check: downloading remote MD5: %@", md5Url);
            [[[NSURLSession sharedSession] dataTaskWithURL:[NSURL URLWithString:md5Url] completionHandler:^(NSData *data, NSURLResponse *response, NSError *error) {
                if (!error && data) {
                    remoteMd5Data = data;
                    md5DownloadSuccess = YES;
                    NSLog(@"[NodeJSManager] Remote MD5 downloaded, size: %lu bytes", (unsigned long)data.length);
                } else {
                    NSLog(@"[NodeJSManager] Remote MD5 download failed: %@", error.localizedDescription);
                }
                dispatch_group_leave(md5Group);
            }] resume];

            dispatch_group_wait(md5Group, dispatch_time(DISPATCH_TIME_NOW, 15 * NSEC_PER_SEC));

            if (md5DownloadSuccess && remoteMd5Data) {
                NSString *remoteMd5 = [[NSString alloc] initWithData:remoteMd5Data encoding:NSUTF8StringEncoding];
                remoteMd5 = [remoteMd5 stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];

                NSString *localMd5 = [[NSString alloc] initWithData:[NSData dataWithContentsOfFile:indexMd5Path] encoding:NSUTF8StringEncoding];
                localMd5 = [localMd5 stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];

                NSLog(@"[NodeJSManager] Cache MD5 comparison: local=%@, remote=%@", localMd5, remoteMd5);

                if (remoteMd5.length > 0 && [localMd5 isEqualToString:remoteMd5]) {
                    NSLog(@"[NodeJSManager] MD5 match! Using cached source, skipping download");
                    dispatch_async(dispatch_get_main_queue(), ^{
                        [self sendLoadCommandToNodeJS:sourcePath completion:completion];
                    });
                    return;
                } else {
                    NSLog(@"[NodeJSManager] MD5 mismatch or empty, need to re-download source");
                }
            } else {
                NSLog(@"[NodeJSManager] Could not download remote MD5, proceeding with full download");
            }
        }

        __block NSData *jsData = nil;
        __block NSData *md5Data = nil;
        __block NSData *configData = nil;
        __block NSData *configMd5Data = nil;
        __block NSError *jsError = nil;
        __block NSError *configError = nil;
        __block NSHTTPURLResponse *jsResponse = nil;
        __block NSHTTPURLResponse *configResponse = nil;

        dispatch_group_t group = dispatch_group_create();

        dispatch_group_enter(group);
        NSLog(@"[NodeJSManager] Downloading main source: %@", normalizedUrl);
        [[[NSURLSession sharedSession] dataTaskWithURL:[NSURL URLWithString:normalizedUrl] completionHandler:^(NSData *data, NSURLResponse *response, NSError *error) {
            jsData = data;
            jsError = error;
            jsResponse = (NSHTTPURLResponse *)response;
            if (error) {
                NSLog(@"[NodeJSManager] ERROR downloading main source: %@", error.localizedDescription);
            } else {
                NSLog(@"[NodeJSManager] Main source downloaded, status: %ld, size: %lu bytes", (long)jsResponse.statusCode, (unsigned long)data.length);
            }
            dispatch_group_leave(group);
        }] resume];

        dispatch_group_enter(group);
        NSString *md5Url = [normalizedUrl stringByAppendingString:@".md5"];
        NSLog(@"[NodeJSManager] Downloading md5: %@", md5Url);
        [[[NSURLSession sharedSession] dataTaskWithURL:[NSURL URLWithString:md5Url] completionHandler:^(NSData *data, NSURLResponse *response, NSError *error) {
            md5Data = data;
            if (error) {
                NSLog(@"[NodeJSManager] MD5 download failed (optional): %@", error.localizedDescription);
            } else {
                NSLog(@"[NodeJSManager] MD5 downloaded, size: %lu bytes", (unsigned long)data.length);
            }
            dispatch_group_leave(group);
        }] resume];

        dispatch_group_enter(group);
        NSString *configUrl = [normalizedUrl stringByReplacingOccurrencesOfString:@"/index.js" withString:@"/index.config.js"];
        NSLog(@"[NodeJSManager] Downloading config: %@", configUrl);
        [[[NSURLSession sharedSession] dataTaskWithURL:[NSURL URLWithString:configUrl] completionHandler:^(NSData *data, NSURLResponse *response, NSError *error) {
            configData = data;
            configError = error;
            configResponse = (NSHTTPURLResponse *)response;
            if (error) {
                NSLog(@"[NodeJSManager] Config download failed (optional): %@", error.localizedDescription);
            } else {
                NSLog(@"[NodeJSManager] Config downloaded, status: %ld", (long)configResponse.statusCode);
            }
            dispatch_group_leave(group);
        }] resume];

        dispatch_group_enter(group);
        NSString *configMd5Url = [configUrl stringByAppendingString:@".md5"];
        [[[NSURLSession sharedSession] dataTaskWithURL:[NSURL URLWithString:configMd5Url] completionHandler:^(NSData *data, NSURLResponse *response, NSError *error) {
            configMd5Data = data;
            dispatch_group_leave(group);
        }] resume];

        NSLog(@"[NodeJSManager] Waiting for all downloads to complete...");
        dispatch_group_wait(group, dispatch_time(DISPATCH_TIME_NOW, 60 * NSEC_PER_SEC));
        NSLog(@"[NodeJSManager] All downloads completed");

        if (jsError || !jsData) {
            NSString *errorMsg = [NSString stringWithFormat:@"Failed to download source: %@ (status: %ld)",
                                  jsError ? jsError.localizedDescription : @"no data",
                                  jsResponse ? (long)jsResponse.statusCode : -1];
            NSLog(@"[NodeJSManager] ERROR: %@", errorMsg);
            dispatch_async(dispatch_get_main_queue(), ^{
                if (completion) completion(NO, errorMsg);
            });
            return;
        }

        if (md5Data) {
            NSString *expectedMd5 = [[NSString alloc] initWithData:md5Data encoding:NSUTF8StringEncoding];
            expectedMd5 = [expectedMd5 stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
            if (expectedMd5.length > 0) {
                NSString *actualMd5 = [self md5HexOfData:jsData];
                if (![actualMd5 isEqualToString:expectedMd5]) {
                    NSLog(@"[NodeJSManager] MD5 verification failed: expected=%@, actual=%@", expectedMd5, actualMd5);
                    dispatch_async(dispatch_get_main_queue(), ^{
                        if (completion) completion(NO, @"MD5 verification failed");
                    });
                    return;
                }
                NSLog(@"[NodeJSManager] Downloaded source MD5 verified successfully");
            }
        }

        NSLog(@"[NodeJSManager] Creating directory at: %@", sourcePath);
        [fm createDirectoryAtPath:sourcePath withIntermediateDirectories:YES attributes:nil error:nil];

        NSLog(@"[NodeJSManager] Writing index.js to: %@", indexJSPath);
        BOOL writeResult = [jsData writeToFile:indexJSPath atomically:YES];
        if (!writeResult) {
            NSLog(@"[NodeJSManager] ERROR: Failed to write index.js");
        }

        if (md5Data) {
            [md5Data writeToFile:indexMd5Path atomically:YES];
            NSLog(@"[NodeJSManager] Saved index.js.md5 for future cache checks");
        }

        if (configData && !configError) {
            NSLog(@"[NodeJSManager] Writing index.config.js");
            [configData writeToFile:configJSPath atomically:YES];
            if (configMd5Data) {
                [configMd5Data writeToFile:configMd5Path atomically:YES];
            }
        } else {
            NSLog(@"[NodeJSManager] Creating default index.config.js");
            NSString *defaultConfig = @"module.exports = { color: [] };";
            [defaultConfig writeToFile:configJSPath atomically:YES encoding:NSUTF8StringEncoding error:nil];
        }

        NSLog(@"[NodeJSManager] Files saved successfully, now sending load command to Node.js with path: %@", sourcePath);
        dispatch_async(dispatch_get_main_queue(), ^{
            [self sendLoadCommandToNodeJS:sourcePath completion:completion];
        });
    });
}

- (void)sendLoadCommandToNodeJS:(NSString *)path completion:(void (^)(BOOL, NSString * _Nullable))completion {
    [self sendLoadCommandToNodeJS:path retryCount:3 completion:completion];
}

- (void)sendLoadCommandToNodeJS:(NSString *)path retryCount:(int)retryCount completion:(void (^)(BOOL, NSString * _Nullable))completion {
    NSLog(@"[NodeJSManager] sendLoadCommandToNodeJS called, managementPort: %d, retryCount: %d", self.managementPort, retryCount);

    if (self.managementPort <= 0) {
        if (retryCount > 0) {
            NSLog(@"[NodeJSManager] Management port not ready, retrying... (%d left)", retryCount);
            dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(2 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
                [self sendLoadCommandToNodeJS:path retryCount:retryCount - 1 completion:completion];
            });
            return;
        }
        NSString *errorMsg = @"Management server not ready after retries";
        NSLog(@"[NodeJSManager] ERROR: %@", errorMsg);
        if (completion) completion(NO, errorMsg);
        return;
    }

    NSString *urlString = [NSString stringWithFormat:@"http://127.0.0.1:%d/source/loadPath", self.managementPort];
    NSLog(@"[NodeJSManager] Sending request to: %@", urlString);
    NSURL *url = [NSURL URLWithString:urlString];
    NSMutableURLRequest *request = [NSMutableURLRequest requestWithURL:url];
    request.HTTPMethod = @"POST";
    [request setValue:@"application/json" forHTTPHeaderField:@"Content-Type"];
    request.timeoutInterval = 15.0;

    NSDictionary *body = @{@"path": path};
    request.HTTPBody = [NSJSONSerialization dataWithJSONObject:body options:0 error:nil];

    [[[NSURLSession sharedSession] dataTaskWithRequest:request completionHandler:^(NSData *data, NSURLResponse *response, NSError *error) {
        NSHTTPURLResponse *httpResponse = (NSHTTPURLResponse *)response;

        if (error) {
            NSLog(@"[NodeJSManager] ERROR: Load command failed with error: %@", error.localizedDescription);
            if (retryCount > 0) {
                NSLog(@"[NodeJSManager] Retrying... (%d left)", retryCount);
                dispatch_async(dispatch_get_main_queue(), ^{
                    [self sendLoadCommandToNodeJS:path retryCount:retryCount - 1 completion:completion];
                });
                return;
            }
            dispatch_async(dispatch_get_main_queue(), ^{
                if (completion) completion(NO, error.localizedDescription);
            });
            return;
        }

        NSLog(@"[NodeJSManager] Response status code: %ld", (long)httpResponse.statusCode);
        NSString *responseBody = data ? [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding] : @"";
        NSLog(@"[NodeJSManager] Response body: %@", responseBody);

        if (httpResponse.statusCode >= 400) {
            if (retryCount > 0 && httpResponse.statusCode >= 500) {
                NSLog(@"[NodeJSManager] Server error, retrying... (%d left)", retryCount);
                dispatch_async(dispatch_get_main_queue(), ^{
                    [self sendLoadCommandToNodeJS:path retryCount:retryCount - 1 completion:completion];
                });
                return;
            }
            dispatch_async(dispatch_get_main_queue(), ^{
                if (completion) completion(NO, [NSString stringWithFormat:@"Server error (%ld): %@", (long)httpResponse.statusCode, responseBody]);
            });
            return;
        }

        NSDictionary *responseDict = nil;
        if (data) {
            responseDict = [NSJSONSerialization JSONObjectWithData:data options:0 error:nil];
        }

        if (responseDict && responseDict[@"error"]) {
            NSString *errorMsg = [NSString stringWithFormat:@"Load error: %@", responseDict[@"error"]];
            NSLog(@"[NodeJSManager] ERROR: %@", errorMsg);
            dispatch_async(dispatch_get_main_queue(), ^{
                if (completion) completion(NO, errorMsg);
            });
            return;
        }

        NSLog(@"[NodeJSManager] === Source loaded successfully! ===");
        dispatch_async(dispatch_get_main_queue(), ^{
            if (completion) completion(YES, @"Source loaded successfully");
        });
    }] resume];
}

- (void)deleteSourceWithCompletion:(void (^)(BOOL success))completion {
    NSString *sourcePath = [self documentsSourcePath];
    NSFileManager *fm = [NSFileManager defaultManager];
    NSError *error = nil;
    if ([fm fileExistsAtPath:sourcePath]) {
        [fm removeItemAtPath:sourcePath error:&error];
    }
    self.spiderPort = 0;
    if (completion) completion(error == nil);
}

#pragma mark - Accessors

- (int)getNativeServerPort {
    return self.nativeServerPort;
}

- (int)getSpiderPort {
    return self.spiderPort;
}

- (int)getManagementPort {
    return self.managementPort;
}

- (NSString *)getDocumentsSourcePath {
    return [self documentsSourcePath];
}

- (BOOL)isNodeReady {
    return self.nodeReady;
}

@end
