

import Foundation

// MRZ 파싱 클래스
public class MRZParser {
    let formatter: MRZFieldFormatter
    
    enum MRZFormat: Int {
        case td1, td2, td3, invalid
    }
    
    public init(ocrCorrection: Bool = false) {
        formatter = MRZFieldFormatter(ocrCorrection: ocrCorrection)
    }
    
    // 형식에 맞는 MRZ로 파싱
    public func parse(mrzLines: [String]) -> MRZResult? {
        let mrzFormat = self.mrzFormat(from: mrzLines)
        
        switch mrzFormat {
        case .td1:
            return TD1(from: mrzLines, using: formatter).result
        case .td2:
            return TD2(from: mrzLines, using: formatter).result
        case .td3:
            return TD3(from: mrzLines, using: formatter).result
        case .invalid:
            print("글자수 오류")
            return nil
        }
    }
    
    // mrz가 단순 String으로 입력되면 \n 기준으로 split
    public func parse(mrzString: String) -> MRZResult? {
        return parse(mrzLines: mrzString.components(separatedBy: "\n"))
    }
    
    // MRZ의 형식 탐지
    fileprivate func mrzFormat(from mrzLines: [String]) -> MRZFormat {
        switch mrzLines.count {
        case 2:
            let lineLength = uniformedLineLength(for: mrzLines)
            let possibleFormats = [MRZFormat.td2: TD2.lineLength, .td3: TD3.lineLength]
            
            for (format, requiredLineLength) in possibleFormats where lineLength == requiredLineLength {
                return format
            }
            
            return .invalid
        case 3:
            return (uniformedLineLength(for: mrzLines) == TD1.lineLength) ? .td1 : .invalid
        default:
            return .invalid
        }
    }
    
    // mrz 라인 수 판별을 위한 메소드
    fileprivate func uniformedLineLength(for mrzLines: [String]) -> Int? {
        guard let lineLength = mrzLines.first?.count else {
            return nil
        }
        
        if mrzLines.contains(where: { $0.count != lineLength }) {
            return nil
        }
        
        return lineLength
    }
}
