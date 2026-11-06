import SwiftUI
import MetalKit

/// Draws a calibration image on demand. There is no display link or frame loop.
struct MetalPatternView: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView {
        guard let device = MTLCreateSystemDefaultDevice(),
              let renderer = try? PatternRenderer(device: device) else {
            let label = NSTextField(wrappingLabelWithString: L("Pattern Metal non disponibile su questa GPU."))
            label.textColor = .secondaryLabelColor
            label.alignment = .center
            return label
        }
        let view = MTKView(frame: .zero, device: device)
        view.colorPixelFormat = .bgra8Unorm
        view.framebufferOnly = true
        view.isPaused = true
        view.enableSetNeedsDisplay = true
        view.autoResizeDrawable = true
        view.clearColor = MTLClearColorMake(0.1, 0.1, 0.1, 1)
        view.delegate = renderer
        view.setAccessibilityLabel(L("Pattern di nitidezza: righe verticali, orizzontali e scacchiera da un pixel"))
        context.coordinator.renderer = renderer
        view.needsDisplay = true
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        nsView.setAccessibilityLabel(L("Pattern di nitidezza: righe verticali, orizzontali e scacchiera da un pixel"))
        if let fallback = nsView as? NSTextField {
            fallback.stringValue = L("Pattern Metal non disponibile su questa GPU.")
        }
        nsView.needsDisplay = true
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    final class Coordinator {
        var renderer: PatternRenderer?
    }
}

final class PatternRenderer: NSObject, MTKViewDelegate {
    private let queue: MTLCommandQueue
    private let pipeline: MTLRenderPipelineState

    init(device: MTLDevice) throws {
        guard let queue = device.makeCommandQueue() else {
            throw NSError(domain: "Punto.Metal", code: 1, userInfo: [NSLocalizedDescriptionKey: L("Coda Metal non disponibile.")])
        }
        self.queue = queue
        let library = try device.makeLibrary(source: Self.shader, options: nil)
        let descriptor = MTLRenderPipelineDescriptor()
        descriptor.vertexFunction = library.makeFunction(name: "patternVertex")
        descriptor.fragmentFunction = library.makeFunction(name: "patternFragment")
        descriptor.colorAttachments[0].pixelFormat = .bgra8Unorm
        pipeline = try device.makeRenderPipelineState(descriptor: descriptor)
        super.init()
    }

    func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {
        view.needsDisplay = true
    }

    func draw(in view: MTKView) {
        guard let descriptor = view.currentRenderPassDescriptor,
              let drawable = view.currentDrawable,
              let command = queue.makeCommandBuffer(),
              let encoder = command.makeRenderCommandEncoder(descriptor: descriptor) else { return }
        var size = SIMD2<Float>(Float(view.drawableSize.width), Float(view.drawableSize.height))
        encoder.setRenderPipelineState(pipeline)
        encoder.setFragmentBytes(&size, length: MemoryLayout<SIMD2<Float>>.size, index: 0)
        encoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 3)
        encoder.endEncoding()
        command.present(drawable)
        command.commit()
    }

    private static let shader = """
    #include <metal_stdlib>
    using namespace metal;
    struct Raster { float4 position [[position]]; };
    vertex Raster patternVertex(uint id [[vertex_id]]) {
        constexpr float2 p[] = {float2(-1,-1), float2(3,-1), float2(-1,3)};
        return {float4(p[id],0,1)};
    }
    fragment float4 patternFragment(Raster in [[stage_in]], constant float2 &size [[buffer(0)]]) {
        uint2 p = uint2(in.position.xy);
        float2 uv = in.position.xy / max(size, float2(1));
        if (uv.y > 0.76) {
            float v = uv.x;
            return float4(v,v,v,1);
        }
        if (uv.y > 0.63) {
            constexpr float3 bars[] = {float3(1),float3(1,1,0),float3(0,1,1),
                float3(0,1,0),float3(1,0,1),float3(1,0,0),float3(0,0,1),float3(0)};
            return float4(bars[min(uint(uv.x*8),7u)],1);
        }
        float v;
        if (uv.x < 0.3333) v = float(p.x % 2);
        else if (uv.x < 0.6667) v = float(p.y % 2);
        else v = float((p.x+p.y) % 2);
        // Thin separator lines preserve the exact one-framebuffer-pixel pattern.
        if (abs(uv.x - 0.3333) < 2.0/size.x || abs(uv.x - 0.6667) < 2.0/size.x)
            return float4(0.73,0.94,0.58,1);
        return float4(v,v,v,1);
    }
    """
}
