// Copyright 2019 The TensorFlow Authors. All Rights Reserved.
//
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.
// You may obtain a copy of the License at
//
//    http://www.apache.org/licenses/LICENSE-2.0
//
// Unless required by applicable law or agreed to in writing, software
// distributed under the License is distributed on an "AS IS" BASIS,
// WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
// See the License for the specific language governing permissions and
// limitations under the License.

import CoreImage
import TensorFlowLite
import UIKit
import Accelerate
import Photos

/// Stores results for a particular frame that was successfully run through the `Interpreter`.
struct Result {
    let inferenceTime: Double
    let inferences: [Inference]
}

struct InferenceResult {
    var resultText: String
    var score: Float
}

/// Stores one formatted inference.
struct Inference {
    let confidence: Float
    let className: String
    let rect: CGRect
    let displayColor: UIColor
}

/// Information about a model file or labels file.
typealias FileInfo = (name: String, extension: String)

enum YOLOv5 {
    static let modelInfo: FileInfo = (name: "passport_s-fp16", extension: "tflite")
    static let labelsInfo: FileInfo = (name: "classes", extension: "txt")
}

/// This class handles all data preprocessing and makes calls to run inference on a given frame
/// by invoking the `Interpreter`. It then formats the inferences obtained and returns the top N
/// results for a successful inference.
class ModelDataHandler: NSObject {
    
    // MARK: - Internal Properties
    /// The current thread count used by the TensorFlow Lite Interpreter.
    let threadCount: Int
    let threadCountLimit = 10
    
    let threshold: Float = 0.25
    
    // MARK: Model parameters
    let batchSize = 1
    let inputChannels = 3
    let inputWidth = 640
    let inputHeight = 640
    
    // image mean and std for floating model, should be consistent with parameters used in model training
    let imageMean: Float = 127.5
    let imageStd:  Float = 127.5
    
    // MARK: Private properties
    private var labels: [String] = []
    
    /// TensorFlow Lite `Interpreter` object for performing inference on a given model.
    private var interpreter: Interpreter
    
    private let bgraPixel = (channels: 4, alphaComponent: 3, lastBgrComponent: 2)
    private let rgbPixelChannels = 3
    private let colorStrideValue = 10
    private let colors = [
        UIColor.red,
        UIColor(displayP3Red: 90.0/255.0, green: 200.0/255.0, blue: 250.0/255.0, alpha: 1.0),
        UIColor.green,
        UIColor.orange,
        UIColor.blue,
        UIColor.purple,
        UIColor.magenta,
        UIColor.yellow,
        UIColor.cyan,
        UIColor.brown
    ]
    
    // 추가
    private var mrzResult: MRZResult!
    
    // MARK: - Initialization
    
    /// A failable initializer for `ModelDataHandler`. A new instance is created if the model and
    /// labels files are successfully loaded from the app's main bundle. Default `threadCount` is 1.
    init?(modelFileInfo: FileInfo, labelsFileInfo: FileInfo, threadCount: Int = 4) {
        let modelFilename = modelFileInfo.name
        
        // Construct the path to the model file.
        guard let modelPath = Bundle.main.path(
            forResource: modelFilename,
            ofType: modelFileInfo.extension
        ) else {
            print("Failed to load the model file with name: \(modelFilename).")
            return nil
        }
        
        // Specify the options for the `Interpreter`.
        self.threadCount = threadCount
        var options = Interpreter.Options()
        options.threadCount = threadCount
        do {
            // Create the `Interpreter`.
            interpreter = try Interpreter(modelPath: modelPath, options: options)
            // Allocate memory for the model's input `Tensor`s.
            try interpreter.allocateTensors()
        } catch let error {
            print("Failed to create the interpreter with error: \(error.localizedDescription)")
            return nil
        }
        
        super.init()
        
        // Load the classes listed in the labels file.
        loadLabels(fileInfo: labelsFileInfo)
    }
    
    /// This class handles all data preprocessing and makes calls to run inference on a given frame
    /// through the `Interpreter`. It then formats the inferences obtained and returns the top N
    /// results for a successful inference.
    func runModel(onFrame pixelBuffer: CVPixelBuffer, guideRect: CGRect, imageScale: CGFloat) -> MRZResult? {
        
        let w = guideRect.width * imageScale
        let h = guideRect.width * imageScale
        let x = guideRect.minX * imageScale
        let y = guideRect.minY * imageScale - (guideRect.width * imageScale - guideRect.height * imageScale) / 2
   
        // 테스트
        let newPixelBuffer = pixelBuffer.crop(to: CGRect(x: x, y: y, width: w, height: h))!
        
        let imageWidth = CVPixelBufferGetWidth(newPixelBuffer)
        let imageHeight = CVPixelBufferGetHeight(newPixelBuffer)
        let sourcePixelFormat = CVPixelBufferGetPixelFormatType(newPixelBuffer)
        assert(sourcePixelFormat == kCVPixelFormatType_32ARGB ||
               sourcePixelFormat == kCVPixelFormatType_32BGRA ||
               sourcePixelFormat == kCVPixelFormatType_32RGBA)
        
        
        let imageChannels = 4
        assert(imageChannels >= inputChannels)
        
        // Crops the image to the biggest square in the center and scales it down to model dimensions.
        let scaledSize = CGSize(width: inputWidth, height: inputHeight)
        guard let scaledPixelBuffer = newPixelBuffer.resized(to: scaledSize) else {
            return nil
        }
        
////        // 앨범 저장 코드
//        let uiImage = UIUtilities.createUIImage(from: scaledPixelBuffer, orientation: UIImage.Orientation.right)
//        PHPhotoLibrary.requestAuthorization { status in
//                    guard status == .authorized, let image = uiImage else { return }
//                    PHPhotoLibrary.shared().performChanges({
//                        PHAssetChangeRequest.creationRequestForAsset(from: image)
//                    }, completionHandler: nil)
//                }
//

        let outputBoundingBox: Tensor

        do {
            let inputTensor = try interpreter.input(at: 0)
            
            // Remove the alpha component from the image buffer to get the RGB data.
            guard let rgbData = rgbDataFromBuffer(
                scaledPixelBuffer,
                byteCount: batchSize * inputWidth * inputHeight * inputChannels,
                isModelQuantized: inputTensor.dataType == .uInt8
            ) else {
                print("Failed to convert the image buffer to RGB data.")
                return nil
            }
            // Copy the RGB data to the input `Tensor`.
            try interpreter.copy(rgbData, toInputAt: 0)
            // Run inference by invoking the `Interpreter`.
            let startDate = Date()
            try interpreter.invoke()
//            interval = Date().timeIntervalSince(startDate) * 1000
            outputBoundingBox = try interpreter.output(at: 0)

        } catch let error {
            print("Failed to invoke the interpreter with error: \(error.localizedDescription)")
            return nil
        }
        
        
        let outputs = ([Float](unsafeData: outputBoundingBox.data) ?? []) as [NSNumber]
        
        let nmsPredictions = PrePostProcessor.outputsToNMSPredictions(outputs: outputs)

        let _ = createMRZ(predictions: nmsPredictions)
    
        return mrzResult
    }
    
    /// Filters out all the results with confidence score < threshold and returns the top N results
    /// sorted in descending order.
    func formatResults(boundingBox: [Float], outputClasses: [Float], outputScores: [Float], outputCount: Int, width: CGFloat, height: CGFloat) -> [Inference]{
        var resultsArray: [Inference] = []
        if (outputCount == 0) {
            return resultsArray
        }
        for i in 0...outputCount - 1 {
            
            let score = outputScores[i]
            
            // Filters results with confidence < threshold.
            guard score >= threshold else {
                continue
            }
            
            // Gets the output class names for detected classes from labels list.
            let outputClassIndex = Int(outputClasses[i])
            let outputClass = labels[outputClassIndex + 1]
            
            var rect: CGRect = CGRect.zero
            
            // Translates the detected bounding box to CGRect.
            rect.origin.y = CGFloat(boundingBox[4*i])
            rect.origin.x = CGFloat(boundingBox[4*i+1])
            rect.size.height = CGFloat(boundingBox[4*i+2]) - rect.origin.y
            rect.size.width = CGFloat(boundingBox[4*i+3]) - rect.origin.x
            
            // The detected corners are for model dimensions. So we scale the rect with respect to the
            // actual image dimensions.
            let newRect = rect.applying(CGAffineTransform(scaleX: width, y: height))
            
            // Gets the color assigned for the class
            let colorToAssign = colorForClass(withIndex: outputClassIndex + 1)
            let inference = Inference(confidence: score,
                                      className: outputClass,
                                      rect: newRect,
                                      displayColor: colorToAssign)
            resultsArray.append(inference)
        }
        
        // Sort results in descending order of confidence.
        resultsArray.sort { (first, second) -> Bool in
            return first.confidence  > second.confidence
        }
        
        return resultsArray
    }
    
    /// Loads the labels from the labels file and stores them in the `labels` property.
    private func loadLabels(fileInfo: FileInfo) {
        let filename = fileInfo.name
        let fileExtension = fileInfo.extension
        guard let fileURL = Bundle.main.url(forResource: filename, withExtension: fileExtension) else {
            fatalError("Labels file not found in bundle. Please add a labels file with name " +
                       "\(filename).\(fileExtension) and try again.")
        }
        do {
            let contents = try String(contentsOf: fileURL, encoding: .utf8)
            labels = contents.components(separatedBy: .newlines)
        } catch {
            fatalError("Labels file named \(filename).\(fileExtension) cannot be read. Please add a " +
                       "valid labels file and try again.")
        }
    }
    
    /// Returns the RGB data representation of the given image buffer with the specified `byteCount`.
    ///
    /// - Parameters
    ///   - buffer: The BGRA pixel buffer to convert to RGB data.
    ///   - byteCount: The expected byte count for the RGB data calculated using the values that the
    ///       model was trained on: `batchSize * imageWidth * imageHeight * componentsCount`.
    ///   - isModelQuantized: Whether the model is quantized (i.e. fixed point values rather than
    ///       floating point values).
    /// - Returns: The RGB data representation of the image buffer or `nil` if the buffer could not be
    ///     converted.
    private func rgbDataFromBuffer(
        _ buffer: CVPixelBuffer,
        byteCount: Int,
        isModelQuantized: Bool
    ) -> Data? {
        CVPixelBufferLockBaseAddress(buffer, .readOnly)
        defer {
            CVPixelBufferUnlockBaseAddress(buffer, .readOnly)
        }
        guard let sourceData = CVPixelBufferGetBaseAddress(buffer) else {
            return nil
        }
        
        let width = CVPixelBufferGetWidth(buffer)
        let height = CVPixelBufferGetHeight(buffer)
        let sourceBytesPerRow = CVPixelBufferGetBytesPerRow(buffer)
        let destinationChannelCount = 3
        let destinationBytesPerRow = destinationChannelCount * width
        
        var sourceBuffer = vImage_Buffer(data: sourceData,
                                         height: vImagePixelCount(height),
                                         width: vImagePixelCount(width),
                                         rowBytes: sourceBytesPerRow)
        
        guard let destinationData = malloc(height * destinationBytesPerRow) else {
            print("Error: out of memory")
            return nil
        }
        
        defer {
            free(destinationData)
        }
        
        var destinationBuffer = vImage_Buffer(data: destinationData,
                                              height: vImagePixelCount(height),
                                              width: vImagePixelCount(width),
                                              rowBytes: destinationBytesPerRow)
        
        if (CVPixelBufferGetPixelFormatType(buffer) == kCVPixelFormatType_32BGRA){
            vImageConvert_BGRA8888toRGB888(&sourceBuffer, &destinationBuffer, UInt32(kvImageNoFlags))
        } else if (CVPixelBufferGetPixelFormatType(buffer) == kCVPixelFormatType_32ARGB) {
            vImageConvert_ARGB8888toRGB888(&sourceBuffer, &destinationBuffer, UInt32(kvImageNoFlags))
        }
        
        let byteData = Data(bytes: destinationBuffer.data, count: destinationBuffer.rowBytes * height)
        if isModelQuantized {
            return byteData
        }
        
        // Not quantized, convert to floats
        let bytes = Array<UInt8>(unsafeData: byteData)!
        var floats = [Float]()
        for i in 0..<bytes.count {
            floats.append((Float(bytes[i]) - imageMean) / imageStd)
        }
        return Data(copyingBufferOf: floats)
    }
    
    /// This assigns color for a particular class.
    private func colorForClass(withIndex index: Int) -> UIColor {
        
        // We have a set of colors and the depending upon a stride, it assigns variations to of the base
        // colors to each object based on its index.
        let baseColor = colors[index % colors.count]
        
        var colorToAssign = baseColor
        
        let percentage = CGFloat((colorStrideValue / 2 - index / colors.count) * colorStrideValue)
        
        if let modifiedColor = baseColor.getModified(byPercentage: percentage) {
            colorToAssign = modifiedColor
        }
        
        return colorToAssign
    }


    // 추가
    // MRZ 생성
    private func createMRZ(predictions: [Prediction]) -> Bool{
        let result: InferenceResult = sortMRZ(predictions: predictions)
        if result.resultText.count == 0 { return false }
        guard let mrzResult: MRZResult = mrz(result: result.resultText, score: result.score) else { return false }
        if mrzValidation(mrzResult: mrzResult, resultText: result.resultText) {
            self.mrzResult = mrzResult
            return true
        }
        return false
    }

    // Object Detection 결과 MRZ 형태로 정렬
    private func sortMRZ(predictions: [Prediction]) -> InferenceResult {
        var index: Int = 0
        var score: Float = 0
        var resultText: String = ""
        var firstLine: [Prediction]! = [Prediction]()
        var secondLine: [Prediction]! = [Prediction]()
        var result: InferenceResult = InferenceResult(resultText: "", score: 0)
        
        let sortPrediction = predictions.sorted{$0.rect.origin.y < $1.rect.origin.y}
        
        // 첫번째 줄 첫번째 글자 체크 (mrz 아닌 글자 검출 위해)
        var tempNum: Prediction? = nil
        if(predictions.count > 1){
            let temp = predictions.sorted{$0.rect.origin.x < $1.rect.origin.x}
            if temp[0].rect.origin.y > temp[1].rect.origin.y { tempNum = temp[1] }
            else { tempNum = temp[0] }
        }
                
        for cls in sortPrediction{
            // 첫번째 줄 위에 mrz 아닌 글자 있으면 검출 x
            if tempNum != nil && tempNum!.rect.origin.y - 20 > cls.rect.origin.y { continue }

            if cls.classIndex != 37 {
                if index < 44 {firstLine.append(cls)}
                else {secondLine.append(cls)}
                    
                index = index + 1
                score = score + cls.score
            }
        }
        if firstLine != nil && secondLine != nil && firstLine.count != 0 && secondLine.count != 0 {
            let resultY1 = firstLine.sorted{$0.rect.origin.x < $1.rect.origin.x}
            let resultY2 = secondLine.sorted{$0.rect.origin.x < $1.rect.origin.x}
            
            
//            let ratio = CGFloat(742.0/640.0)
//            print("가이드: (\(mrzRegion.minY*ratio), \(mrzRegion.maxY*ratio))")
//            print(" \(resultY1[0].rect.minY)")
//            print(" \(resultY2[0].rect.maxY)")
            // 가이드에서만 mrz 검출되게 하기 위한 코드
//            if cls.classIndex == 37 {
//                let ratio = ((view.bounds.maxY)/640)
//                let guideY = mrzRegion.minY*ratio
//                let mrzY = cls.rect.minY
//                print("가이드: (\(mrzRegion.minY*ratio), \(mrzRegion.maxY*ratio))")
//                print("MRZ : (\(cls.rect.minY), \(cls.rect.maxY))")
//                if mrzY < guideY {break}
//            }
            
            for i in 0...resultY1.count - 1{resultText.append(labels[resultY1[i].classIndex])}
            resultText = resultText + "\n"
            for i in 0...resultY2.count - 1{resultText.append(labels[resultY2[i].classIndex])}
        }
        
        resultText = resultText.replacingOccurrences(of: "sign", with: "<")
        resultText = resultText.replacingOccurrences(of: "mrz", with: "")
        
        result.resultText = resultText
        result.score = score
        
        print(result.resultText)
        return result
    }
    
    // MRZ 결과 추출
    private func mrz(result: String!, score: Float) -> MRZResult? {
        guard verificationDetectionResults(result: result, score: score) else { return nil }
        let mrzParser = MRZParser(ocrCorrection: true)
        if let string = result, let mrzLines = mrzLines(from: string) {
            return mrzParser.parse(mrzLines: mrzLines)
        }
        return nil
    }
    
    // MRZ 후처리
    private func mrzLines(from recognizedText: String) -> [String]? {
        let mrzString = recognizedText.replacingOccurrences(of: " ", with: "")
        var mrzLines = mrzString.components(separatedBy: "\n").filter({ !$0.isEmpty })
        // 앞 뒤 가비지 문자열 제거
        if !mrzLines.isEmpty {
            let averageLineLength = (mrzLines.reduce(0, { $0 + $1.count }) / mrzLines.count)
            mrzLines = mrzLines.filter({ $0.count >= averageLineLength })
        }
        
        return mrzLines.isEmpty ? nil : mrzLines
    }
    
    //검출 결과 검증
    private func verificationDetectionResults(result: String, score: Float) -> Bool{
        // 검출 조건 88개 이상 검출되야 넘어가게 함 정확도 90% 이상
        
//        print(result)
        
        guard (result.count) > 88 && score > 0.88 else { return false }
        return true
    }
    
    // MRZ 검증
    private func mrzValidation(mrzResult: MRZResult, resultText: String) -> Bool{
        if mrzResult.sex == "null" { return false }
        if mrzResult.nationalityCountryCode == "null" { return false }
        if mrzResult.birthdate == nil { return false }
        if mrzResult.expiryDate == nil { return false }
        // 첫번째 줄에 숫자 제거
        for i in 0...9 {
            if mrzResult.surnames.contains(String(i)) { return false }
            if mrzResult.givenNames.contains(String(i)) { return false }
            if mrzResult.nationalityCountryCode.contains(String(i)) { return false }
        }
    
        // mrz 체크비트 검사
        let documentNumberTemp = mrzResult.documentNumber
        let check: [Int] = [7, 3, 1]
        var index: Int = 0
        var sum: Int = 0
        for s in documentNumberTemp {
            if index > 2 {index = 0}
            // "<" 이면 0이라 계산 안함
            if s != "<"{
                if Int(s.unicodeScalars.first!.value) >= 65
                { sum = sum + (Int(s.unicodeScalars.first!.value) - 55) * check[index] }
                else
                { sum = sum + (Int(s.unicodeScalars.first!.value) - 48) * check[index] }
            }
            index = index + 1
        }
        if sum % 10 != Int(resultText.substring(54, to: 54)) { return false }
    
        return true
    }



}

// MARK: - Extensions

extension Data {
    /// Creates a new buffer by copying the buffer pointer of the given array.
    ///
    /// - Warning: The given array's element type `T` must be trivial in that it can be copied bit
    ///     for bit with no indirection or reference-counting operations; otherwise, reinterpreting
    ///     data from the resulting buffer has undefined behavior.
    /// - Parameter array: An array with elements of type `T`.
    init<T>(copyingBufferOf array: [T]) {
        self = array.withUnsafeBufferPointer(Data.init)
    }
}

extension Array {
    /// Creates a new array from the bytes of the given unsafe data.
    ///
    /// - Warning: The array's `Element` type must be trivial in that it can be copied bit for bit
    ///     with no indirection or reference-counting operations; otherwise, copying the raw bytes in
    ///     the `unsafeData`'s buffer to a new array returns an unsafe copy.
    /// - Note: Returns `nil` if `unsafeData.count` is not a multiple of
    ///     `MemoryLayout<Element>.stride`.
    /// - Parameter unsafeData: The data containing the bytes to turn into an array.
    init?(unsafeData: Data) {
        guard unsafeData.count % MemoryLayout<Element>.stride == 0 else { return nil }
#if swift(>=5.0)
        self = unsafeData.withUnsafeBytes { .init($0.bindMemory(to: Element.self)) }
#else
        self = unsafeData.withUnsafeBytes {
            .init(UnsafeBufferPointer<Element>(
                start: $0,
                count: unsafeData.count / MemoryLayout<Element>.stride
            ))
        }
#endif  // swift(>=5.0)
    }
}

