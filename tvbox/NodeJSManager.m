#import "NodeJSManager.h"
#import <NodeMobile/NodeMobile.h>
#import <GCDWebServer/GCDWebServer.h>
#import <GCDWebServer/Responses/GCDWebServerDataResponse.h>

static const int kMaxStartupWaitSeconds = 30;

@interface NodeJSManager ()

@property (nonatomic, assign) BOOL isRunning;
@property (nonatomic, assign) BOOL nodeReady;
@property (nonatomic, strong) NSThread *nodeThread;
@property (nonatomic, strong) GCDWebServer *nativeServer;
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

- (NSString *)nodeProjectPath {
    return [[NSBundle mainBundle] pathForResource:@"nodejs-project/dist/main" ofType:@"js"];
}

- (NSString *)nodeProjectDir {
    NSString *mainJsPath = [self nodeProjectPath];
    if (!mainJsPath) return nil;
    return [[mainJsPath stringByDeletingLastPathComponent] stringByDeletingLastPathComponent];
}

- (NSString *)sourcePath {
    NSArray *paths = NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES);
    return paths.firstObject;
}

#pragma mark - Native Server

- (BOOL)startNativeServer {
    self.nativeServer = [[GCDWebServer alloc] init];

    __weak typeof(self) weakSelf = self;

    [self.nativeServer addHandlerForMethod:@"GET"
                                      path:@"/onCatPawOpenPort"
                              requestClass:[GCDWebServerRequest class]
                              processBlock:^GCDWebServerResponse *(GCDWebServerRequest *request) {
        __strong typeof(weakSelf) strongSelf = weakSelf;
        NSDictionary *query = request.query;
        NSString *type = query[@"type"];
        int port = [query[@"port"] intValue];

        if ([type isEqualToString:@"spider"]) {
            strongSelf.spiderPort = port;
            NSLog(@"[NodeJSManager] Spider port received: %d", port);
        } else if ([type isEqualToString:@"management"]) {
            strongSelf.managementPort = port;
            NSLog(@"[NodeJSManager] Management port received: %d", port);
        }

        if (strongSelf.spiderPort > 0) {
            strongSelf.nodeReady = YES;
        }

        return [GCDWebServerResponse responseWithStatusCode:200];
    }];

    [self.nativeServer addHandlerForMethod:@"POST"
                                      path:@"/onMessage"
                              requestClass:[GCDWebServerRequest class]
                              processBlock:^GCDWebServerResponse *(GCDWebServerRequest *request) {
        NSLog(@"[NodeJSManager] Message received from Node.js");
        return [GCDWebServerResponse responseWithStatusCode:200];
    }];

    [self.nativeServer startWithPort:0 bonjourName:nil];

    if (self.nativeServer.isRunning) {
        self.nativeServerPort = self.nativeServer.port;
        NSLog(@"[NodeJSManager] Native server started on port %d", self.nativeServerPort);
        return YES;
    }

    NSLog(@"[NodeJSManager] Failed to start native server");
    return NO;
}

- (void)stopNativeServer {
    if (self.nativeServer && self.nativeServer.isRunning) {
        [self.nativeServer stop];
    }
    self.nativeServer = nil;
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

    if (![self startNativeServer]) {
        if (completion) completion(NO);
        return;
    }

    self.nodeThread = [[NSThread alloc] initWithTarget:self selector:@selector(nodeMain) object:nil];
    self.nodeThread.name = @"NodeJS";
    [self.nodeThread start];

    [self waitForNodeReady:^(BOOL ready) {
        if (ready) {
            self.isRunning = YES;
        } else {
            [self stopNativeServer];
        }
        if (completion) completion(ready);
    }];
}

- (void)nodeMain {
    @autoreleasepool {
        NSString *mainJsPath = [self nodeProjectPath];
        if (!mainJsPath) {
            NSLog(@"[NodeJSManager] main.js not found in bundle");
            return;
        }

        NSString *nodeProjectDir = [self nodeProjectDir];
        NSString *sourcePath = [self sourcePath];

        NSArray *argv = @[
            @"node",
            @"--security-revert=CVE-2023-46809",
            mainJsPath,
            nodeProjectDir ?: @"",
            sourcePath,
            @"--native-port",
            [NSString stringWithFormat:@"%d", self.nativeServerPort]
        ];

        int argc = (int)argv.count;
        char **cargv = (char **)malloc(argc * sizeof(char *));
        for (int i = 0; i < argc; i++) {
            cargv[i] = (char *)[argv[i] UTF8String];
        }

        NSLog(@"[NodeJSManager] Starting Node.js with main.js: %@ --native-port %d", mainJsPath, self.nativeServerPort);
        node_start(argc, cargv);

        free(cargv);
    }
}

- (void)stopNodeJS {
    if (!self.isRunning) return;

    [self stopNativeServer];

    self.isRunning = NO;
    self.nodeReady = NO;
    self.nativeServerPort = 0;
    self.spiderPort = 0;
    self.managementPort = 0;

    NSLog(@"[NodeJSManager] Node.js stopped");
}

#pragma mark - Wait for Ready

- (void)waitForNodeReady:(void (^)(BOOL ready))completion {
    __block int elapsed = 0;
    __block int interval = 500;

    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
        while (elapsed < kMaxStartupWaitSeconds * 1000) {
            if (self.spiderPort > 0) {
                dispatch_async(dispatch_get_main_queue(), ^{
                    if (completion) completion(YES);
                });
                return;
            }
            [NSThread sleepForTimeInterval:interval / 1000.0];
            elapsed += interval;
        }
        dispatch_async(dispatch_get_main_queue(), ^{
            if (completion) completion(NO);
        });
    });
}

#pragma mark - Source Management

- (void)loadSourceFromURL:(NSString *)urlString
               completion:(void (^)(BOOL success, NSString * _Nullable message))completion {
    if (!urlString.length) {
        if (completion) completion(NO, @"URL is empty");
        return;
    }

    NSURL *url = [NSURL URLWithString:urlString];
    if (!url) {
        if (completion) completion(NO, @"Invalid URL");
        return;
    }

    NSURLSessionDataTask *task = [[NSURLSession sharedSession] dataTaskWithURL:url
                                                            completionHandler:^(NSData *data, NSURLResponse *response, NSError *error) {
        if (error) {
            dispatch_async(dispatch_get_main_queue(), ^{
                if (completion) completion(NO, error.localizedDescription);
            });
            return;
        }

        NSHTTPURLResponse *httpResponse = (NSHTTPURLResponse *)response;
        if (httpResponse.statusCode != 200) {
            dispatch_async(dispatch_get_main_queue(), ^{
                if (completion) completion(NO, [NSString stringWithFormat:@"HTTP %ld", (long)httpResponse.statusCode]);
            });
            return;
        }

        NSString *sourceDir = [self sourcePath];
        NSFileManager *fm = [NSFileManager defaultManager];
        if (![fm fileExistsAtPath:sourceDir]) {
            [fm createDirectoryAtPath:sourceDir withIntermediateDirectories:YES attributes:nil error:nil];
        }

        NSString *sourceFilePath = [sourceDir stringByAppendingPathComponent:@"source.json"];
        BOOL writeSuccess = [data writeToFile:sourceFilePath atomically:YES];

        dispatch_async(dispatch_get_main_queue(), ^{
            if (completion) {
                completion(writeSuccess, writeSuccess ? @"Source loaded" : @"Failed to write source file");
            }
        });
    }];
    [task resume];
}

- (void)deleteSourceWithCompletion:(void (^)(BOOL success))completion {
    NSString *sourceDir = [self sourcePath];
    NSFileManager *fm = [NSFileManager defaultManager];

    if (![fm fileExistsAtPath:sourceDir]) {
        if (completion) completion(YES);
        return;
    }

    NSString *sourceFilePath = [sourceDir stringByAppendingPathComponent:@"source.json"];
    NSError *error = nil;
    BOOL deleted = [fm removeItemAtPath:sourceFilePath error:&error];

    if (error) {
        NSLog(@"[NodeJSManager] Error deleting source: %@", error.localizedDescription);
    }

    if (completion) completion(deleted);
}

#pragma mark - Accessors

- (int)getSpiderPort {
    return self.spiderPort;
}

- (int)getManagementPort {
    return self.managementPort;
}

- (BOOL)isNodeReady {
    return self.nodeReady;
}

@end
