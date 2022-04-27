import MetalKit
import MetalPerformanceShaders


final class FileHandleBuffer {
  // https://stackoverflow.com/a/70006560
  let fileHandle: FileHandle
  let size: Int
  private var buffer: Data
  
  init(fileHandle: FileHandle, size: Int = 1024 * 1024) {
    self.fileHandle = fileHandle
    self.size = size
    self.buffer = Data(capacity: size)
  }
  
  deinit { try! flush() }
  
  func flush() throws {
    try fileHandle.write(contentsOf: buffer)
    buffer = Data(capacity: size)
  }
  
  func write(_ data: Data) throws {
    buffer.append(data)
    if buffer.count > size {
      try flush()
    }
  }
}


public typealias float2 = SIMD2<Float>

public class ImageMean: Renderable {
  private var _texture: MTLTexture!
  
  public var texture: MTLTexture! {
    set {
      self._texture = newValue
      runMPS(texture: newValue)
    }
    get {
      return self._texture
    }
  }
  public static var threshold: Float = 0.02
  public static var activeAreaHeightFractionRange: ClosedRange<Float> = 0.04...0.06
  
  func activeAreaHeightRange(imageHeight: Int) -> ClosedRange<Int> {
    let fraction = Self.activeAreaHeightFractionRange
    return Int(floor(fraction.lowerBound * Float(imageHeight)))...Int(ceil(fraction.upperBound * Float(imageHeight)))
  }
  
  var computedTexture: MTLTexture!
  
  
  var squashTextureBuffer: MTLTexture?
  var sobelTextureBuffer: MTLTexture?
  var cpuImageColumnBuffer: UnsafeMutablePointer<SIMD4<UInt8>>?
  
  let pipelineState: MTLRenderPipelineState
  var threshold: Float = 0
  
  let activeAreaSelector = ActiveAreaSelector()
  
  public static var activeArea: [float2] = []
    
  let fileUrl = URL.init(fileURLWithPath: "/Users/rioog/Documents/activearea.csv")
  let buffer: FileHandleBuffer?
  init() {
    let textureLoader = MTKTextureLoader(device: Renderer.device)
    
    
    var header = (0..<720).reduce("", { "\($0)\($1), " }) + "activeArea\n"

    FileManager.default.createFile(atPath: fileUrl.path, contents: nil)
    // Create the file if it does not yet exist

    if let fileHandle = try? FileHandle(forWritingTo: fileUrl) {
      buffer = FileHandleBuffer(fileHandle: fileHandle)
      try? buffer!.write(header.data(using: .ascii)!)
    } else {
      buffer = nil
    }
    
    
    do {
      _texture = try textureLoader.newTexture(
        name: "test", // File in .xcassets texture set
        scaleFactor: 1.0,
        bundle: Bundle.main,
        options: nil
      )
    } catch let error { fatalError(error.localizedDescription) }
    pipelineState = Self.makePipeline()
    runMPS(texture: _texture)
  }
  
  
  func makeImageBuffers(texture: MTLTexture) {
    let descriptor = MTLTextureDescriptor.texture2DDescriptor(
      pixelFormat: texture.pixelFormat,
      width: 1,
      height: texture.height,
      mipmapped: false
    )
    descriptor.usage = [.shaderWrite, .shaderRead]
    
    guard let squashTextureBuffer = Renderer.device.makeTexture(descriptor: descriptor),
          let  sobelTextureBuffer = Renderer.device.makeTexture(descriptor: descriptor)
    else { fatalError() }
    
    squashTextureBuffer.label = "Squash texture buffer"
    sobelTextureBuffer.label = "Sobel texture buffer"
    self.squashTextureBuffer = squashTextureBuffer
    self.sobelTextureBuffer = sobelTextureBuffer
    
    cpuImageColumnBuffer = UnsafeMutablePointer<SIMD4<UInt8>>.allocate(capacity: texture.height)
  }
  
  func runMPS(texture: MTLTexture) {
    let startTime = CFAbsoluteTimeGetCurrent()
    guard let commandBuffer = Renderer.commandQueue.makeCommandBuffer()
    else { fatalError() }
    commandBuffer.label = "Active area detection"
    if squashTextureBuffer == nil || squashTextureBuffer?.height != texture.height {
      makeImageBuffers(texture: texture)
    }

    commandBuffer.pushDebugGroup("MPS row reduce + sobel")
    let squashShader: MPSUnaryImageKernel = MPSImageReduceRowMean(device: Renderer.device)
    squashShader.encode(
      commandBuffer: commandBuffer,
      sourceTexture: texture,
      destinationTexture: squashTextureBuffer!
    )
    
    let derivativeShader = MPSImageSobel(device: Renderer.device)
    derivativeShader.encode(
      commandBuffer: commandBuffer,
      sourceTexture: squashTextureBuffer!,
      destinationTexture: sobelTextureBuffer!
    )
    
    commandBuffer.commit()
    
    commandBuffer.waitUntilCompleted()
    commandBuffer.popDebugGroup()
    // Squash + Sobel + simple symmetry compute: ~1.3 ms
//    print("GPU Full Pipeline Duration:", CFAbsoluteTimeGetCurrent() - startTime)
    
    
    Self.copyTexture(source: sobelTextureBuffer!, destination: cpuImageColumnBuffer!)

    let sobelOutputFloat: [Float] = Self.copyPixelsToArray(
      source: cpuImageColumnBuffer!,
      length: texture.height
    ).map {
      var float: SIMD4<Float> = SIMD4<Float>($0)
      float.w = 0
      float /= 255
      return dot(float, float)
    }
    
    Self.copyTexture(source: squashTextureBuffer!, destination: cpuImageColumnBuffer!)
    
    let squashOutput4UInt8: [SIMD4<UInt8>] = Self.copyPixelsToArray(
      source: cpuImageColumnBuffer!,
      length: texture.height
    )
    
    // Normalize brightness to [0, 1]
    let squashOutputFloat: [Float] = squashOutput4UInt8.map {
      var float: SIMD4<Float> = SIMD4<Float>($0)
      float.w = 0
      float /= 255
      return dot(float, float) / 3
    }
    

    let sizeRange = self.activeAreaHeightRange(imageHeight: texture.height)
    let candidateAreas = ActiveAreaDetector.detectCandidateAreas(
      sobelOutput: sobelOutputFloat,
      squashOutput: squashOutputFloat,
      threshold: Self.threshold,
      sizeRange: sizeRange
    )
    
    activeAreaSelector.update(candidates: candidateAreas, sizeRange: sizeRange)
    let currentBestGuess = activeAreaSelector.getActiveArea()
    
    if currentBestGuess == nil {
      Self.activeArea = []
    } else {
      var line = squashOutputFloat.reduce("", { "\($0)\(String(format: "%.5f", $1)), " })
      line += "\(currentBestGuess!.x2)\n"
      try? buffer?.write(line.data(using: .ascii)!)
      Self.activeArea = activeAreaSelector.getAllAreasSorted().map {[
        $0[0] / Float(sobelOutputFloat.count),
        $0[1] / Float(sobelOutputFloat.count)
//        ($0[1] + ($0[1] - $0[0]) * GestureRecognizer().activeAreaFudgeScale) / Float(sobelOutputFloat.count)
      ]}
    }
  }
  
  // Copies single column image from MTLTexture to a CPU buffer with the correct amount of memory allocated
  static func copyTexture(source: MTLTexture, destination: UnsafeMutablePointer<SIMD4<UInt8>>) {
    // https://developer.apple.com/documentation/metal/mtltexture/1515751-getbytes
    source.getBytes(
      destination,
      bytesPerRow: MemoryLayout<SIMD4<UInt8>>.stride,
      from: MTLRegion(
        origin: MTLOrigin(x: 0, y: 0, z: 0),
        size: MTLSize(width: 1, height: source.height, depth: 1)
      ),
      mipmapLevel: 0
    )
  }
  
  static func copyPixelsToArray<T>(source: UnsafeMutablePointer<T>, length: Int) -> [T] {
    var output: [T] = []
    var pointer = source
    
    for _ in 0..<length {
      output.append(pointer.pointee)
      pointer = pointer.advanced(by: 1)
    }
    
    return output
  }
  
 
  
  static func makePipeline() -> MTLRenderPipelineState {
    let pipelineDescriptor = buildPartialPipelineDescriptor(
      vertex: "vertex_plonk_texture_mirrored_horizontal",
      fragment: "fragment_image_mean"
    )
    do {
      let pipelineState = try Renderer.device.makeRenderPipelineState(descriptor: pipelineDescriptor)
      return pipelineState
    } catch let error { fatalError(error.localizedDescription) }
  }
  
  
  
  public func draw(renderEncoder: MTLRenderCommandEncoder) {
    renderEncoder.setRenderPipelineState(pipelineState)
    
    renderEncoder.setTriangleFillMode(.fill)
    renderEncoder.setFragmentTexture(squashTextureBuffer, index: 1)
    renderEncoder.setFragmentTexture(sobelTextureBuffer, index: 2)
    
    renderEncoder.setFragmentBytes(
      &Self.threshold,
      length: MemoryLayout<Float>.stride,
      index: 3
    )
    
    if Self.activeArea.isEmpty {
      Self.activeArea = [[-1, -1]]
      // Dies if empty array passed. Not sure how to solve it
    }
    
    renderEncoder.setFragmentTexture(texture, index: 0)
        
    
    renderEncoder.setFragmentBytes(
      &Self.activeArea,
      length: MemoryLayout<float2>.stride * Self.activeArea.count,
      index: 4
    )
    
    var count: Int = Self.activeArea.count
    renderEncoder.setFragmentBytes(
      &count,
      length: MemoryLayout<Int>.stride,
      index: 5
    )
   
    
    renderEncoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 6)
  }
}
