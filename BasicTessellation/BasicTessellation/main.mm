#import <Cocoa/Cocoa.h>
#import <QuartzCore/QuartzCore.h>
#import <Metal/Metal.h>
#import <objc/runtime.h>
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
    
        id<MTLComputePipelineState> _computePipelineQuad;
            
        id<MTLBuffer> _tessellationFactorsBuffer;
        id<MTLBuffer> _controlPointsBufferQuad;
    
        BOOL _wireframe = YES;
        MTLPatchType _patchType = MTLPatchTypeQuad;
        float _edgeFactor = 16.0;
        float _insideFactor = 16.0;
        
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
            [computeCommandEncoder setComputePipelineState:this->_computePipelineQuad];

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
                [renderCommandEncoder setVertexBuffer:this->_controlPointsBufferQuad offset:0 atIndex:0];
                
                // Enable/Disable wireframe mode
                if(this->_wireframe) {
                    [renderCommandEncoder setTriangleFillMode:MTLTriangleFillModeLines];
                }
                
                // Encode tessellation-specific commands
                [renderCommandEncoder setTessellationFactorBuffer:this->_tessellationFactorsBuffer offset:0 instanceStride:0];
                NSUInteger patchControlPoints = 4;
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
                if(lib) {
                    //NSLog(@"%@",[NSString stringWithFormat:@"%@/%@",[[NSBundle mainBundle] resourcePath],shaders[k]]);
                    this->_library.push_back(lib);
                    if(error) return false;
                }
                else {
                    return false;
                }
            }
            
            // Create compute pipeline for quad-based tessellation
            id <MTLFunction> kernelFunctionQuad = [this->_library[0] newFunctionWithName:@"tessellation_kernel_quad"];
            this->_computePipelineQuad = [this->_device newComputePipelineStateWithFunction:kernelFunctionQuad error:&error];
            if(error) return false;
            
            // Create a reusable vertex descriptor for the control point data
            // This describes the inputs to the post-tessellation vertex function, declared with the 'stage_in' qualifier
            MTLVertexDescriptor* vertexDescriptor = [MTLVertexDescriptor vertexDescriptor];
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
            
            // Create render pipeline for quad-based tessellation
            renderPipelineDescriptor.vertexFunction = [this->_library[0] newFunctionWithName:@"tessellation_vertex_quad"];
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
            
            static const float controlPointPositionsQuad[] = {
                -0.8,  0.8, 0.0, 1.0,   // upper-left
                 0.8,  0.8, 0.0, 1.0,   // upper-right
                 0.8, -0.8, 0.0, 1.0,   // lower-right
                -0.8, -0.8, 0.0, 1.0,   // lower-left
            };
            this->_controlPointsBufferQuad = [this->_device newBufferWithBytes:controlPointPositionsQuad length:sizeof(controlPointPositionsQuad) options:controlPointsBufferOptions];
            this->_controlPointsBufferQuad.label = @"Control Points Quad";
                        
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
        
        CGRect _rect = CGRectMake(0,0,1280,720);

        MetalTessellationLayer *_layer;
        
    public:
      
        App() {
        
            this->_win = [[NSWindow alloc] initWithContentRect:this->_rect styleMask:1 backing:NSBackingStoreBuffered defer:NO];
            this->_view = [[NSView alloc] initWithFrame:this->_rect];

            this->_layer = new MetalTessellationLayer();
            if(this->_layer->init(this->_rect.size.width,this->_rect.size.height,{@"TessellationFunctions.metallib"})) {
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
                            NSRect rect = [this->_win contentRectForFrameRect:this->_win.frame];
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
