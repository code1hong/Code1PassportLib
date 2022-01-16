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

import UIKit

class InferenceController: UIViewController {
    
    // MARK: Storyboards Connections
    @IBOutlet weak var previewView: PreviewView!
    @IBOutlet weak var overlayView: OverlayView!
    @IBOutlet weak var resumeButton: UIButton!
    @IBOutlet weak var cameraUnavailableLabel: UILabel!
    
    @IBOutlet weak var bottomSheetStateImageView: UIImageView!
    @IBOutlet weak var bottomSheetView: UIView!
    @IBOutlet weak var bottomSheetViewBottomSpace: NSLayoutConstraint!
    
    // MARK: Constants
    private let displayFont = UIFont.systemFont(ofSize: 14.0, weight: .medium)
    private let edgeOffset: CGFloat = 2.0
    private let labelOffset: CGFloat = 10.0
    private let animationDuration = 0.5
    private let collapseTransitionThreshold: CGFloat = -30.0
    private let expandTransitionThreshold: CGFloat = 30.0
    private let delayBetweenInferencesMs: Double = 200
    
    // MARK: Instance Variables
    private var initialBottomSpace: CGFloat = 0.0
    
    // Holds the results at any time
    private var result: Result?
    private var previousInferenceTimeMs: TimeInterval = Date.distantPast.timeIntervalSince1970 * 1000
    
    // MARK: Controllers that manage functionality
    private lazy var cameraFeedManager = CameraFeedManager(previewView: previewView)
    private var modelDataHandler: ModelDataHandler? =
    ModelDataHandler(modelFileInfo: YOLOv5.modelInfo, labelsFileInfo: YOLOv5.labelsInfo)

    
    // 추가
    var mrzResult: MRZResult!
    var finish = false
    var naviY: CGFloat!
    
    @IBOutlet weak var guideImage: UIImageView!
    private var guideRect: CGRect!
    private var passportFullRect: CGRect!
    private var imageScaleRatio: CGFloat!
    
    // MARK: View Handling Methods
    override func viewDidLoad() {
        super.viewDidLoad()
        
        // 라이센스 불러오기
        let filePath = Bundle.main.path(forResource: "Code1License", ofType: "lic")
        let license = try? String(contentsOfFile: filePath!).replacingOccurrences(of: "\n", with: "")

        // 번들아이디 체크
        let bundle = Bundle(for: ViewController.self).bundleIdentifier

        //복호화
        let dec = AES128Util.decrypt(encoded: license!)

//        print(AES128Util.encrypt(string: bundle!))

        // 현재는 print 문이지만 추후에 고객에 맞춰 따라 라이센스 처리 코드 작성
        if dec == bundle {print("성공")}
        else {
            print("라이센스가 유효하지 않습니다.")
        }
        
        
        previewView.frame = CGRect(x: 0 , y: (self.navigationController?.navigationBar.frame.maxY)!, width: self.view.frame.width, height: self.view.frame.width * (4032 / 3024))
        
        naviY = navigationController?.navigationBar.frame.maxY
        
        guard modelDataHandler != nil else {
            fatalError("Failed to load model")
        }
        cameraFeedManager.delegate = self
        setUI()
        
        imageScaleRatio = CGFloat(1080) / previewView.frame.width
//        overlayView.clearsContextBeforeDrawing = true
    }
    
    override func didReceiveMemoryWarning() {
        super.didReceiveMemoryWarning()
        // Dispose of any resources that can be recreated.
    }
    
    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        self.finish = false
        self.mrzResult = nil
//        changeBottomViewState()
        cameraFeedManager.checkCameraConfigurationAndStartSession()
    }
    
    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        cameraFeedManager.stopSession()
    }
    
//    override func viewDidAppear(_ animated: Bool) {
//        super.viewDidAppear(animated)
//    }
    
    override var preferredStatusBarStyle: UIStatusBarStyle {
        return .lightContent
    }
    
    // MARK: Button Actions
    @IBAction func onClickResumeButton(_ sender: Any) {
        
        cameraFeedManager.resumeInterruptedSession { (complete) in
            
            if complete {
                self.resumeButton.isHidden = true
                self.cameraUnavailableLabel.isHidden = true
            }
            else {
                self.presentUnableToResumeSessionAlert()
            }
        }
    }
    
    func presentUnableToResumeSessionAlert() {
        let alert = UIAlertController(
            title: "Unable to Resume Session",
            message: "There was an error while attempting to resume session.",
            preferredStyle: .alert
        )
        alert.addAction(UIAlertAction(title: "OK", style: .default, handler: nil))
        
        self.present(alert, animated: true)
    }

    
    // MARK: UI
    // 가이드 세팅
    func setUI() {
        
        let passportRatio = 12.5 / 8.7
        let mrzRatio = 2.3 / 8.7
        
        //뒷배경 색깔 및 투명도
        let mrzFrameColor : UIColor = UIColor.red
        let maskLayerColor: UIColor = UIColor.white
        let maskLayerAlpha: CGFloat = 1.0

        
        let passportGuideRect = CGRect(x: (view.bounds.width - guideImage.frame.width) / 2,
                                       y: naviY as CGFloat,
                                       width: guideImage.frame.width,
                                       height: guideImage.frame.height)
        
        ////////////// 영역 설정
        // 여권 가이드 박스 시작 X 좌표 = 전체 뷰 영역의 3% 위치
        let passportBoxLocationX = view.bounds.width * 0.03
        // 여권 가이드 박스 시작 Y 좌표 = 전체 뷰 영역의 30% 위치
        let passportBoxLocationY = passportGuideRect.maxY
        // 여권 가이드 박스 가로 사이즈 = 전체 영역 94%
        let passportBoxWidthSize = view.bounds.width * 0.94
        // 여권 가이드 박스 세로 사이즈 = 전체 영역 40%
        let passportBoxheightSize = passportBoxWidthSize / passportRatio
        // MRZ 가이드 시작 Y 좌표 = 여권 가이드 박스 Y 좌표 끝나는 위치에서 뷰의 10% 만큼 올라간 위치
        let mazBoxLocationY = passportBoxLocationY + passportBoxheightSize * (1 - mrzRatio)
        // MRZ 가이드 박스 세로 사이즈 = 전체 영역 10%
        let mrzBoxheightSize = passportBoxheightSize * mrzRatio
        
        let passportRect = CGRect(x: passportBoxLocationX,
                                y: passportBoxLocationY,
                                width: passportBoxWidthSize,
                                height: passportBoxheightSize)
        
        let mrzRect = CGRect(x: passportBoxLocationX,
                                y: mazBoxLocationY,
                                width: passportBoxWidthSize,
                                height: mrzBoxheightSize)
        
        
    
        // 여권 가이드 백그라운드 설정
        let backLayer = CALayer()
        backLayer.frame = view.bounds
        backLayer.backgroundColor = maskLayerColor.withAlphaComponent(maskLayerAlpha).cgColor
        
        // 여권 가이드 구역 설정
        let maskLayer = CAShapeLayer()
        let path = UIBezierPath(roundedRect: passportRect, cornerRadius: 10.0)
        path.append(UIBezierPath(rect: view.bounds))
        maskLayer.path = path.cgPath
        maskLayer.fillRule = CAShapeLayerFillRule.evenOdd
        backLayer.mask = maskLayer
        self.view.layer.addSublayer(backLayer)
        
        // 여권 가이드 이미지 등록
        let guideLayer = CALayer()
        guideLayer.frame = passportGuideRect
        guideLayer.contents = UIImage(named: "pp_guide.png")?.cgImage
        self.view.layer.addSublayer(guideLayer)

        // MRZ 가이드 설정
        let mrzLineLayer = CAShapeLayer()
        mrzLineLayer.lineWidth = 2.0
        mrzLineLayer.strokeColor = mrzFrameColor.cgColor
        mrzLineLayer.path = UIBezierPath(roundedRect: mrzRect, cornerRadius: 10.0).cgPath
        mrzLineLayer.fillColor = nil
        self.view.layer.addSublayer(mrzLineLayer)
        
        //MRZ 가이드 위치 저장
        guideRect = mrzRect
        passportFullRect = passportRect
    }
}

// MARK: CameraFeedManagerDelegate Methods
extension InferenceController: CameraFeedManagerDelegate {
    
    func didOutput(pixelBuffer: CVPixelBuffer) {
        runModel(onPixelBuffer: pixelBuffer)
    }
    
    // MARK: Session Handling Alerts
    func sessionRunTimeErrorOccurred() {
        
        // Handles session run time error by updating the UI and providing a button if session can be manually resumed.
        self.resumeButton.isHidden = false
    }
    
    func sessionWasInterrupted(canResumeManually resumeManually: Bool) {
        
        // Updates the UI when session is interrupted.
        if resumeManually {
            self.resumeButton.isHidden = false
        }
        else {
            self.cameraUnavailableLabel.isHidden = false
        }
    }
    
    func sessionInterruptionEnded() {
        
        // Updates UI once session interruption has ended.
        if !self.cameraUnavailableLabel.isHidden {
            self.cameraUnavailableLabel.isHidden = true
        }
        
        if !self.resumeButton.isHidden {
            self.resumeButton.isHidden = true
        }
    }
    
    func presentVideoConfigurationErrorAlert() {
        
        let alertController = UIAlertController(title: "Configuration Failed", message: "Configuration of camera has failed.", preferredStyle: .alert)
        let okAction = UIAlertAction(title: "OK", style: .cancel, handler: nil)
        alertController.addAction(okAction)
        
        present(alertController, animated: true, completion: nil)
    }
    
    func presentCameraPermissionsDeniedAlert() {
        
        let alertController = UIAlertController(title: "Camera Permissions Denied", message: "Camera permissions have been denied for this app. You can change this by going to Settings", preferredStyle: .alert)
        
        let cancelAction = UIAlertAction(title: "Cancel", style: .cancel, handler: nil)
        let settingsAction = UIAlertAction(title: "Settings", style: .default) { (action) in
            
            UIApplication.shared.open(URL(string: UIApplication.openSettingsURLString)!, options: [:], completionHandler: nil)
        }
        
        alertController.addAction(cancelAction)
        alertController.addAction(settingsAction)
        
        present(alertController, animated: true, completion: nil)
        
    }
    
    /** This method runs the live camera pixelBuffer through tensorFlow to get the result.
     */
    @objc func runModel(onPixelBuffer pixelBuffer: CVPixelBuffer) {
        
        // Run the live camera pixelBuffer through tensorFlow to get the result
        
        let currentTimeMs = Date().timeIntervalSince1970 * 1000
        
        guard  (currentTimeMs - previousInferenceTimeMs) >= delayBetweenInferencesMs else {
            return
        }
        
        previousInferenceTimeMs = currentTimeMs
        mrzResult = (self.modelDataHandler?.runModel(onFrame: pixelBuffer, guideRect: self.passportFullRect, imageScale: self.imageScaleRatio))
        
        // 검출 시 코드
//        DispatchQueue.main.async {
//            if self.mrzResult != nil && self.finish == false {
//                self.finish = true
//                self.performSegue(withIdentifier: "showResult", sender: self)
//            }
//        }
    }
    
    /**
     This method takes the results, translates the bounding box rects to the current view, draws the bounding boxes, classNames and confidence scores of inferences.
     */
    func drawAfterPerformingCalculations(onInferences inferences: [Inference], withImageSize imageSize:CGSize) {
        
        self.overlayView.objectOverlays = []
        self.overlayView.setNeedsDisplay()
        
        guard !inferences.isEmpty else {
            return
        }
        
        var objectOverlays: [ObjectOverlay] = []
        
        for inference in inferences {
            
            // Translates bounding box rect to current view.
            var convertedRect = inference.rect.applying(CGAffineTransform(scaleX: self.overlayView.bounds.size.width / imageSize.width, y: self.overlayView.bounds.size.height / imageSize.height))
            
            if convertedRect.origin.x < 0 {
                convertedRect.origin.x = self.edgeOffset
            }
            
            if convertedRect.origin.y < 0 {
                convertedRect.origin.y = self.edgeOffset
            }
            
            if convertedRect.maxY > self.overlayView.bounds.maxY {
                convertedRect.size.height = self.overlayView.bounds.maxY - convertedRect.origin.y - self.edgeOffset
            }
            
            if convertedRect.maxX > self.overlayView.bounds.maxX {
                convertedRect.size.width = self.overlayView.bounds.maxX - convertedRect.origin.x - self.edgeOffset
            }
            
            let confidenceValue = Int(inference.confidence * 100.0)
            let string = "\(inference.className)  (\(confidenceValue)%)"
            
            let size = string.size(usingFont: self.displayFont)
            
            let objectOverlay = ObjectOverlay(name: string, borderRect: convertedRect, nameStringSize: size, color: inference.displayColor, font: self.displayFont)
            
            objectOverlays.append(objectOverlay)
        }
        
        // Hands off drawing to the OverlayView
        self.draw(objectOverlays: objectOverlays)
        
    }
    
    /** Calls methods to update overlay view with detected bounding boxes and class names.
     */
    func draw(objectOverlays: [ObjectOverlay]) {
        
        self.overlayView.objectOverlays = objectOverlays
        self.overlayView.setNeedsDisplay()
    }
    
}
