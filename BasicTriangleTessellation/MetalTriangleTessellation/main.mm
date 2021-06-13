#import <Cocoa/Cocoa.h>
#import <QuartzCore/QuartzCore.h>
#import <Metal/Metal.h>
#import <vector>

class MetalTessellationLayer {
    
    protected:
                
        CAMetalLayer *_metalLayer;
        MTLRenderPassDescriptor *_renderPassDescriptor;
        
        id<MTLDevice> _device;
        id<MTLCommandQueue> _commandQueue;
        
        id<CAMetalDrawable> _metalDrawable;
        id<MTLTexture> _drawabletexture;
        
        std::vector<id<MTLLibrary>> _library;
        std::vector<id<MTLRenderPipelineState>> _renderPipelineState;
        std::vector<MTLRenderPipelineDescriptor *> _renderPipelineDescriptor;
    
        id<MTLComputePipelineState> _computePipelineTriangle;
            
        id<MTLBuffer> _tessellationFactorsBuffer;
        id<MTLBuffer> _controlPointsBufferTriangle;
    
        BOOL _wireframe = NO;
        float _edgeFactor = 8.0;
        float _insideFactor = 8.0;
        
        bool _isInit = false;
            
        int _width;
        int _height;
    
        CGRect _frame;

    public:
                
        MetalTessellationLayer() {
        }

        ~MetalTessellationLayer() {
        }
    
        void edgeFactor(int n) {
            this->_edgeFactor = n;
        }
    
        void insideFactor(int n) {
            this->_insideFactor = n;
        }
     
        id<MTLCommandBuffer> setupCommandBuffer(unsigned int mode=0) {
            
            // Create a new command buffer for each tessellation pass
            id<MTLCommandBuffer> commandBuffer = [this->_commandQueue commandBuffer];
            MTLRenderPassColorAttachmentDescriptor *colorAttachment = this->_renderPassDescriptor.colorAttachments[0];
            colorAttachment.texture = this->_metalDrawable.texture;
            colorAttachment.loadAction  = MTLLoadActionClear;
            colorAttachment.clearColor  = MTLClearColorMake(0.0f,0.0f,0.0f,1.0f);
            colorAttachment.storeAction = MTLStoreActionStore;
            
            commandBuffer.label = @"Tessellation Pass";
            
            // Create a compute command encoder
            id<MTLComputeCommandEncoder> computeCommandEncoder = [commandBuffer computeCommandEncoder];
            computeCommandEncoder.label = @"Compute Command Encoder";
            
            // Begin encoding compute commands
            [computeCommandEncoder pushDebugGroup:@"Compute Tessellation Factors"];
            
            // Set the correct compute pipeline
            [computeCommandEncoder setComputePipelineState:this->_computePipelineTriangle];

            // Bind the user-selected edge and inside factor values to the compute kernel
            [computeCommandEncoder setBytes:&this->_edgeFactor length:sizeof(float) atIndex:0];
            [computeCommandEncoder setBytes:&this->_insideFactor length:sizeof(float) atIndex:1];
            
            // Bind the tessellation factors buffer to the compute kernel
            [computeCommandEncoder setBuffer:this->_tessellationFactorsBuffer offset:0 atIndex:2];
            
            // Dispatch threadgroups
            [computeCommandEncoder dispatchThreadgroups:MTLSizeMake(1,1,1) threadsPerThreadgroup:MTLSizeMake(1,1,1)];
            
            // All compute commands have been encoded
            [computeCommandEncoder popDebugGroup];
            [computeCommandEncoder endEncoding];
            
            MTLRenderPassDescriptor *renderPassDescriptor = this->_renderPassDescriptor;
            
            // If the renderPassDescriptor is valid, begin the commands to render into its drawable
            if(renderPassDescriptor != nil) {
                // Create a render command encoder
                id<MTLRenderCommandEncoder> renderCommandEncoder = [commandBuffer renderCommandEncoderWithDescriptor:renderPassDescriptor];
                renderCommandEncoder.label = @"Render Command Encoder";
                
                // Begin encoding render commands, including commands for the tessellator
                [renderCommandEncoder pushDebugGroup:@"Tessellate and Render"];
                
                // Set the correct render pipeline and bind the correct control points buffer
                [renderCommandEncoder setRenderPipelineState:this->_renderPipelineState[0]];
                [renderCommandEncoder setVertexBuffer:this->_controlPointsBufferTriangle offset:0 atIndex:0];
                
                // Enable/Disable wireframe mode
                if(this->_wireframe) {
                    [renderCommandEncoder setTriangleFillMode:MTLTriangleFillModeLines];
                }
                
                // Encode tessellation-specific commands
                [renderCommandEncoder setTessellationFactorBuffer:this->_tessellationFactorsBuffer offset:0 instanceStride:0];
                NSUInteger patchControlPoints = 3;
                [renderCommandEncoder drawPatches:patchControlPoints patchStart:0 patchCount:1 patchIndexBuffer:NULL patchIndexBufferOffset:0 instanceCount:1 baseInstance:0];
                
                // All render commands have been encoded
                [renderCommandEncoder popDebugGroup];
                [renderCommandEncoder endEncoding];
                [commandBuffer presentDrawable:this->_metalDrawable];

                this->_drawabletexture = this->_metalDrawable.texture;
            }
            
            return commandBuffer;

        }
        
        bool init(int width,int height,std::vector<NSString *> shaders={@"default.metallib"}) {
            
            this->_frame.size.width  = this->_width  = width;
            this->_frame.size.height = this->_height = height;
            if(this->_metalLayer==nil) {
                this->_metalLayer = [CAMetalLayer layer];
            }
            this->_device = MTLCreateSystemDefaultDevice();
            this->_metalLayer.device = this->_device;
            this->_metalLayer.pixelFormat = MTLPixelFormatBGRA8Unorm;

#if TARGET_OS_OSX

            this->_metalLayer.colorspace = [[NSScreen mainScreen] colorSpace].CGColorSpace;//CGColorSpaceCreateDeviceRGB();
            this->_metalLayer.displaySyncEnabled = YES;
            
#else
            this->_metalLayer.colorspace = CGColorSpaceCreateDeviceRGB();
#endif
                        
            this->_metalLayer.opaque = NO;
            this->_metalLayer.framebufferOnly = NO;

            this->_metalLayer.drawableSize = CGSizeMake(this->_width,this->_height);
            this->_commandQueue = [this->_device newCommandQueue];
            if(!this->_commandQueue) return false;
            NSError *error = nil;
            for(int k=0; k<shaders.size(); k++) {
                id<MTLLibrary> lib= [this->_device newLibraryWithFile:[NSString stringWithFormat:@"%@/%@",[[NSBundle mainBundle] resourcePath],shaders[k]] error:&error];
                
                //NSLog(@"%@",[NSString stringWithFormat:@"%@/%@",[[NSBundle mainBundle] resourcePath],shaders[k]]);

                if(lib) {
                    this->_library.push_back(lib);
                    if(error) return false;
                }
                else {
                    return false;
                }
            }
            
            // Create compute pipeline for triangle-based tessellation
            id <MTLFunction> kernelFunctionTriangle  = [this->_library[0] newFunctionWithName:@"tessellation_kernel_triangle"];
            this->_computePipelineTriangle = [this->_device newComputePipelineStateWithFunction:kernelFunctionTriangle error:&error];
            if(error) return false;
            
            // Create a reusable vertex descriptor for the control point data
            // This describes the inputs to the post-tessellation vertex function, declared with the 'stage_in' qualifier
            MTLVertexDescriptor *vertexDescriptor = [MTLVertexDescriptor vertexDescriptor];
            vertexDescriptor.attributes[0].format = MTLVertexFormatFloat4;
            vertexDescriptor.attributes[0].offset = 0;
            vertexDescriptor.attributes[0].bufferIndex = 0;
            vertexDescriptor.layouts[0].stepFunction = MTLVertexStepFunctionPerPatchControlPoint;
            vertexDescriptor.layouts[0].stepRate = 1;
            vertexDescriptor.layouts[0].stride = 4.0*sizeof(float);
            
            // Create a reusable render pipeline descriptor
            MTLRenderPipelineDescriptor *renderPipelineDescriptor = [MTLRenderPipelineDescriptor new];
            
            // Configure common render properties
            renderPipelineDescriptor.vertexDescriptor = vertexDescriptor;
            renderPipelineDescriptor.sampleCount = 1;
            renderPipelineDescriptor.colorAttachments[0].pixelFormat = MTLPixelFormatBGRA8Unorm;
            renderPipelineDescriptor.fragmentFunction = [this->_library[0] newFunctionWithName:@"tessellation_fragment"];
            
            // Configure common tessellation properties
            renderPipelineDescriptor.tessellationFactorScaleEnabled = NO;
            renderPipelineDescriptor.tessellationFactorFormat = MTLTessellationFactorFormatHalf;
            renderPipelineDescriptor.tessellationControlPointIndexType = MTLTessellationControlPointIndexTypeNone;
            renderPipelineDescriptor.tessellationFactorStepFunction = MTLTessellationFactorStepFunctionConstant;
            renderPipelineDescriptor.tessellationOutputWindingOrder = MTLWindingClockwise;
            renderPipelineDescriptor.tessellationPartitionMode = MTLTessellationPartitionModeFractionalEven;
            
            // In OS X, the maximum tessellation factor is 64
            renderPipelineDescriptor.maxTessellationFactor = 64;
            
            // Create render pipeline for triangle-based tessellation
            renderPipelineDescriptor.vertexFunction = [this->_library[0] newFunctionWithName:@"tessellation_vertex_triangle"];
            this->_renderPipelineState.push_back([this->_device newRenderPipelineStateWithDescriptor:renderPipelineDescriptor error:&error]);
            if(error) return false;
            
            // Allocate memory for the tessellation factors buffer
            // This is a private buffer whose contents are later populated by the GPU (compute kernel)
            this->_tessellationFactorsBuffer = [this->_device newBufferWithLength:256 options:MTLResourceStorageModePrivate];
            this->_tessellationFactorsBuffer.label = @"Tessellation Factors";
            
            // Allocate memory for the control points buffers
            // These are shared or managed buffers whose contents are immediately populated by the CPU
            MTLResourceOptions controlPointsBufferOptions;

            // In OS X, the storage mode can be shared or managed, but managed may yield better performance
            controlPointsBufferOptions = MTLResourceStorageModeManaged;
            
            static const float controlPointPositionsTriangle[] = {
                -1.0, -1.0, 0.0, 1.0,   // lower-left
                 0.0,  1.0, 0.0, 1.0,   // upper-middle
                 1.0, -1.0, 0.0, 1.0,   // lower-right
            };
            
            this->_controlPointsBufferTriangle = [this->_device newBufferWithBytes:controlPointPositionsTriangle length:sizeof(controlPointPositionsTriangle) options:controlPointsBufferOptions];
            this->_controlPointsBufferTriangle.label = @"Control Points Triangle";
                        
            this->_isInit = true;
            return this->_isInit;
        }
        
        bool isInit() {
            return this->_isInit;
        }

        id<MTLTexture> drawableTexture() {
            return this->_drawabletexture;
        }
        
        void cleanup() {
            this->_metalDrawable = nil;
        }
        
        void resize(CGRect frame) {
            this->_frame = frame;
        }
        
        id<MTLCommandBuffer> prepareCommandBuffer(unsigned int mode) {
            if(!this->_metalDrawable) {
                this->_metalDrawable = [this->_metalLayer nextDrawable];
            }
            if(!this->_metalDrawable) {
                this->_renderPassDescriptor = nil;
            }
            else {
                if(this->_renderPassDescriptor==nil) this->_renderPassDescriptor = [MTLRenderPassDescriptor renderPassDescriptor];
            }
            if(this->_metalDrawable&&this->_renderPassDescriptor) {
                return this->setupCommandBuffer(mode);
            }
            return nil;
        }
        
        void update(void (^onComplete)(id<MTLCommandBuffer>)) {
            
            if(this->_isInit==false) return;
                        
            if(this->_renderPipelineState[0]) {
                id<MTLCommandBuffer> commandBuffer = this->prepareCommandBuffer(0);
                if(commandBuffer) {
                    [commandBuffer addCompletedHandler:onComplete];
                    [commandBuffer commit];
                    [commandBuffer waitUntilCompleted];
                }
            }
        }
        
        CAMetalLayer *layer() {
            return this->_metalLayer;
        }
};

class App {
    
    private:
    
        NSWindow *_win;
        NSView *_view;
        dispatch_source_t timer;
        
        CGRect _rect = CGRectMake(0,0,512,512);

        MetalTessellationLayer *_layer;
        
    public:
      
        App() {
        
            this->_win = [[NSWindow alloc] initWithContentRect:this->_rect styleMask:1 backing:NSBackingStoreBuffered defer:NO];
            this->_view = [[NSView alloc] initWithFrame:this->_rect];

            this->_layer = new MetalTessellationLayer();
            if(this->_layer->init(this->_rect.size.width,this->_rect.size.height,{@"default.metallib"})) {
                this->_layer->resize(this->_rect);
                [this->_view setWantsLayer:YES];
                this->_view.layer = this->_layer->layer();
                [[this->_win contentView] addSubview:this->_view];
            }
            
            [[this->_win contentView] addSubview:this->_view];
            
            this->timer = dispatch_source_create(DISPATCH_SOURCE_TYPE_TIMER,0,0,dispatch_queue_create("ENTER_FRAME",0));
            dispatch_source_set_timer(this->timer,dispatch_time(0,0),(1.0/30)*1000000000,0);
            dispatch_source_set_event_handler(this->timer,^{
                
                this->_layer->update(^(id<MTLCommandBuffer> commandBuffer){
                
                    this->_layer->cleanup();
                    
                    static dispatch_once_t oncePredicate;
                    dispatch_once(&oncePredicate,^{
                        dispatch_async(dispatch_get_main_queue(),^{
                            CGRect screen = [[NSScreen mainScreen] frame];
                            NSRect rect = this->_win.frame;
                            CGRect center = CGRectMake(
                                (screen.size.width-rect.size.width)*.5,
                                (screen.size.height-(rect.size.height))*.5,
                                rect.size.width,rect.size.height
                            );
                            [this->_win setFrame:center display:YES];
                            [this->_win makeKeyAndOrderFront:nil];

                        });
                    });
                
                });
            });
            if(this->timer) dispatch_resume(this->timer);
        }

        ~App() {
            
            if(this->_win) {
                [this->_win setReleasedWhenClosed:NO];
                [this->_win close];
                this->_win = nil;
            }
            
        }
        
};

#pragma mark AppDelegate

@interface AppDelegate:NSObject <NSApplicationDelegate> {
    App *app;
}
@end

@implementation AppDelegate
-(void)applicationDidFinishLaunching:(NSNotification*)aNotification {
    app = new App();
}
-(void)applicationWillTerminate:(NSNotification *)aNotification {
    delete app;
}
@end

int main(int argc, char *argv[]) {
    @autoreleasepool {
        id app = [NSApplication sharedApplication];
        id delegat = [AppDelegate alloc];
        [app setDelegate:delegat];
        [app run];
    }
}



/*
#import <Cocoa/Cocoa.h>
#import <MetalKit/MetalKit.h>
#import <objc/runtime.h>

@interface AAPLTessellationPipeline : NSObject <MTKViewDelegate>

@property (readwrite) BOOL wireframe;
@property (readwrite) float edgeFactor;
@property (readwrite) float insideFactor;

-(nullable instancetype)initWithMTKView:(nonnull MTKView *)mtkView;

@end

@implementation AAPLTessellationPipeline {
    id <MTLDevice> _device;
    id <MTLCommandQueue> _commandQueue;
    id <MTLLibrary> _library;
    id <MTLComputePipelineState> _computePipelineTriangle;
    id <MTLRenderPipelineState> _renderPipelineTriangle;
    id <MTLBuffer> _tessellationFactorsBuffer;
    id <MTLBuffer> _controlPointsBufferTriangle;
}

-(nullable instancetype)initWithMTKView:(nonnull MTKView *)view {
    
    self = [super init];
    if(self) {
        // Initialize properties
        _wireframe = YES;
        _edgeFactor = _insideFactor = 8.0;
        
        // Setup Metal
        if(![self didSetupMetal]) return nil;
        
        // Assign device and delegate to MTKView
        view.device = _device;
        view.delegate = self;
        
        // Setup compute pipelines
        if(![self didSetupComputePipelines]) return nil;
        
        // Setup render pipelines
        if(![self didSetupRenderPipelinesWithMTKView:view]) return nil;
        
        [self setupBuffers];
    }
    return self;
}

#pragma mark Setup methods

-(BOOL)didSetupMetal {
    
    // Use the default device
    _device = MTLCreateSystemDefaultDevice();
    // Create a new command queue
    _commandQueue = [_device newCommandQueue];
    
    // Load the default library
    _library = [_device newDefaultLibrary];
    
    return YES;
}

-(BOOL)didSetupComputePipelines {
    
    NSError *computePipelineError;
    
    // Create compute pipeline for triangle-based tessellation
    id <MTLFunction> kernelFunctionTriangle = [_library newFunctionWithName:@"tessellation_kernel_triangle"];
    _computePipelineTriangle = [_device newComputePipelineStateWithFunction:kernelFunctionTriangle
                                                                      error:&computePipelineError];
    if(!_computePipelineTriangle) {
        NSLog(@"Failed to create compute pipeline (TRIANGLE), error: %@", computePipelineError);
        return NO;
    }
        
    return YES;
}

- (BOOL)didSetupRenderPipelinesWithMTKView:(nonnull MTKView *)view {
    
    NSError *renderPipelineError = nil;
    
    // Create a reusable vertex descriptor for the control point data
    // This describes the inputs to the post-tessellation vertex function, declared with the 'stage_in' qualifier
    MTLVertexDescriptor *vertexDescriptor = [MTLVertexDescriptor vertexDescriptor];
    vertexDescriptor.attributes[0].format = MTLVertexFormatFloat4;
    vertexDescriptor.attributes[0].offset = 0;
    vertexDescriptor.attributes[0].bufferIndex = 0;
    vertexDescriptor.layouts[0].stepFunction = MTLVertexStepFunctionPerPatchControlPoint;
    vertexDescriptor.layouts[0].stepRate = 1;
    vertexDescriptor.layouts[0].stride = 4.0*sizeof(float);
    
    // Create a reusable render pipeline descriptor
    MTLRenderPipelineDescriptor *renderPipelineDescriptor = [MTLRenderPipelineDescriptor new];
    
    // Configure common render properties
    renderPipelineDescriptor.vertexDescriptor = vertexDescriptor;
    renderPipelineDescriptor.sampleCount = view.sampleCount;
    renderPipelineDescriptor.colorAttachments[0].pixelFormat = view.colorPixelFormat;
    renderPipelineDescriptor.fragmentFunction = [_library newFunctionWithName:@"tessellation_fragment"];
    
    // Configure common tessellation properties
    renderPipelineDescriptor.tessellationFactorScaleEnabled = NO;
    renderPipelineDescriptor.tessellationFactorFormat = MTLTessellationFactorFormatHalf;
    renderPipelineDescriptor.tessellationControlPointIndexType = MTLTessellationControlPointIndexTypeNone;
    renderPipelineDescriptor.tessellationFactorStepFunction = MTLTessellationFactorStepFunctionConstant;
    renderPipelineDescriptor.tessellationOutputWindingOrder = MTLWindingClockwise;
    renderPipelineDescriptor.tessellationPartitionMode = MTLTessellationPartitionModeFractionalEven;
    
    // In OS X, the maximum tessellation factor is 64
    renderPipelineDescriptor.maxTessellationFactor = 64;
    
    // Create render pipeline for triangle-based tessellation
    renderPipelineDescriptor.vertexFunction = [_library newFunctionWithName:@"tessellation_vertex_triangle"];
    _renderPipelineTriangle = [_device newRenderPipelineStateWithDescriptor:renderPipelineDescriptor
                                                                      error:&renderPipelineError];
    if(!_renderPipelineTriangle){
        NSLog(@"Failed to create render pipeline (TRIANGLE), error %@", renderPipelineError);
        return NO;
    }
    
    return YES;
}

-(void)setupBuffers {
    // Allocate memory for the tessellation factors buffer
    // This is a private buffer whose contents are later populated by the GPU (compute kernel)
    _tessellationFactorsBuffer = [_device newBufferWithLength:256 options:MTLResourceStorageModePrivate];
    _tessellationFactorsBuffer.label = @"Tessellation Factors";
    
    // Allocate memory for the control points buffers
    // These are shared or managed buffers whose contents are immediately populated by the CPU
    MTLResourceOptions controlPointsBufferOptions;

    // In OS X, the storage mode can be shared or managed, but managed may yield better performance
    controlPointsBufferOptions = MTLResourceStorageModeManaged;
    
    static const float controlPointPositionsTriangle[] = {
        -1.0, -1.0, 0.0, 1.0,   // lower-left
         0.0,  1.0, 0.0, 1.0,   // upper-middle
         1.0, -1.0, 0.0, 1.0,   // lower-right
    };
    _controlPointsBufferTriangle = [_device newBufferWithBytes:controlPointPositionsTriangle length:sizeof(controlPointPositionsTriangle) options:controlPointsBufferOptions];
    _controlPointsBufferTriangle.label = @"Control Points Triangle";
    
    
    // More sophisticated tessellation passes might have additional buffers for per-patch user data
}

#pragma mark Compute/Render methods

-(void)computeTessellationFactorsWithCommandBuffer:(id<MTLCommandBuffer>)commandBuffer {
    // Create a compute command encoder
    id <MTLComputeCommandEncoder> computeCommandEncoder = [commandBuffer computeCommandEncoder];
    computeCommandEncoder.label = @"Compute Command Encoder";
    
    // Begin encoding compute commands
    [computeCommandEncoder pushDebugGroup:@"Compute Tessellation Factors"];
    
    // Set the correct compute pipeline
    [computeCommandEncoder setComputePipelineState:_computePipelineTriangle];
    
    // Bind the user-selected edge and inside factor values to the compute kernel
    [computeCommandEncoder setBytes:&_edgeFactor length:sizeof(float) atIndex:0];
    [computeCommandEncoder setBytes:&_insideFactor length:sizeof(float) atIndex:1];
    
    // Bind the tessellation factors buffer to the compute kernel
    [computeCommandEncoder setBuffer:_tessellationFactorsBuffer offset:0 atIndex:2];
    
    // Dispatch threadgroups
    [computeCommandEncoder dispatchThreadgroups:MTLSizeMake(1,1,1) threadsPerThreadgroup:MTLSizeMake(1,1,1)];
    
    // All compute commands have been encoded
    [computeCommandEncoder popDebugGroup];
    [computeCommandEncoder endEncoding];
}

-(void)tessellateAndRenderInMTKView:(nonnull MTKView *)view withCommandBuffer:(id<MTLCommandBuffer>)commandBuffer {
    // Obtain a renderPassDescriptor generated from the view's drawable
    MTLRenderPassDescriptor* renderPassDescriptor = view.currentRenderPassDescriptor;
    
    // If the renderPassDescriptor is valid, begin the commands to render into its drawable
    if(renderPassDescriptor != nil) {
        // Create a render command encoder
        id <MTLRenderCommandEncoder> renderCommandEncoder = [commandBuffer renderCommandEncoderWithDescriptor:renderPassDescriptor];
        renderCommandEncoder.label = @"Render Command Encoder";
        
        // Begin encoding render commands, including commands for the tessellator
        [renderCommandEncoder pushDebugGroup:@"Tessellate and Render"];
        
        // Set the correct render pipeline and bind the correct control points buffer
        [renderCommandEncoder setRenderPipelineState:_renderPipelineTriangle];
        [renderCommandEncoder setVertexBuffer:_controlPointsBufferTriangle offset:0 atIndex:0];
        
        // Enable/Disable wireframe mode
        if(self.wireframe) {
            [renderCommandEncoder setTriangleFillMode:MTLTriangleFillModeLines];
        }
        
        // Encode tessellation-specific commands
        [renderCommandEncoder setTessellationFactorBuffer:_tessellationFactorsBuffer offset:0 instanceStride:0];
        [renderCommandEncoder drawPatches:3 patchStart:0 patchCount:1 patchIndexBuffer:NULL patchIndexBufferOffset:0 instanceCount:1 baseInstance:0];
        
        // All render commands have been encoded
        [renderCommandEncoder popDebugGroup];
        [renderCommandEncoder endEncoding];
        
        // Schedule a present once the drawable has been completely rendered to
        [commandBuffer presentDrawable:view.currentDrawable];
    }
}

// Called whenever view changes orientation or layout is changed
-(void)mtkView:(nonnull MTKView *)view drawableSizeWillChange:(CGSize)size {}

// Called whenever the view needs to render
-(void)drawInMTKView:(nonnull MTKView *)view {
    @autoreleasepool {
        // Create a new command buffer for each tessellation pass
        id <MTLCommandBuffer> commandBuffer = [_commandQueue commandBuffer];
        commandBuffer.label = @"Tessellation Pass";
        
        [self computeTessellationFactorsWithCommandBuffer:commandBuffer];
        [self tessellateAndRenderInMTKView:view withCommandBuffer:commandBuffer];
        
        // Finalize tessellation pass and commit the command buffer to the GPU
        [commandBuffer commit];
    }
}
@end

class App {
    
    private:
        
        NSWindow *win;
        MTKView *view;
    
        id<MTLDevice> _device;
        id<MTKViewDelegate> _delegate;
    
        AAPLTessellationPipeline *tessellationPipeline;

        dispatch_source_t timer;
    
    public:
        
        App() {
            
            this->win = [[NSWindow alloc] initWithContentRect:CGRectMake(0,0,512,512) styleMask:1|1<<2 backing:NSBackingStoreBuffered defer:NO];
            [this->win center];
            [this->win makeKeyAndOrderFront:nil];
            
            this->_device = MTLCreateSystemDefaultDevice();
            view = [[MTKView alloc] initWithFrame:CGRectMake(0,0,512,512)];
            view.device = this->_device;
           
            [this->view.layer setBackgroundColor:[NSColor grayColor].CGColor];

            this->view.paused = YES;
            this->view.enableSetNeedsDisplay = YES;
            this->view.framebufferOnly = NO;
            this->view.colorPixelFormat = MTLPixelFormatBGRA8Unorm;
            this->view.sampleCount = 1;
            this->view.drawableSize = (CGSize){512,512};
          
            this->tessellationPipeline = [[AAPLTessellationPipeline alloc] initWithMTKView:this->view];
            
            this->timer = dispatch_source_create(DISPATCH_SOURCE_TYPE_TIMER,0,0,dispatch_queue_create("ENTER_FRAME",0));
            dispatch_source_set_timer(this->timer,dispatch_time(0,0),(1.0/30)*1000000000,0);
            dispatch_source_set_event_handler(this->timer,^{
                
                [this->view draw];
            
            });
            if(this->timer) dispatch_resume(this->timer);
            
            [[this->win contentView] addSubview:view];
        }
    
        ~App() {
            
            [this->win setReleasedWhenClosed:NO];
            [this->win close];
            this->win = nil;
        }
};

#pragma mark AppDelegate

@interface AppDelegate:NSObject <NSApplicationDelegate> {
    App *app;
}
@end

@implementation AppDelegate
-(void)applicationDidFinishLaunching:(NSNotification*)aNotification {
    app = new App();
}
-(void)applicationWillTerminate:(NSNotification *)aNotification {
    delete app;
}
@end

int main(int argc, char *argv[]) {
    @autoreleasepool {
        id app = [NSApplication sharedApplication];
        id delegat = [AppDelegate alloc];
        [app setDelegate:delegat];
        [app run];
    }
}
*/