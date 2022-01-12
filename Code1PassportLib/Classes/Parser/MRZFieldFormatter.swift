
import Foundation
import AVFoundation

class MRZFieldFormatter {
    let ocrCorrection: Bool
    
    // 국가 리스트 로드
    lazy var nationlity: [String] = {
        if let filePath = Bundle.main.path(forResource: "nationality", ofType: "txt"), // class 파일 Path
            let nations = try? String(contentsOfFile: filePath) {
            return nations.components(separatedBy: .newlines)
        } else {
            fatalError("nationality file was not found.")
        }
    }()
    
    // 날짜, 시간, 지역 형식 지정
    fileprivate let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyyMMdd"
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(abbreviation: "GMT+0:00")
        return formatter
    }()
    
    init(ocrCorrection: Bool) {
        self.ocrCorrection = ocrCorrection
    }
    
    // 메인 함수
    func field(_ fieldType: MRZFieldType, from string: String, at startIndex: Int, length: Int, checkDigitFollows: Bool = false) -> MRZField {
        let endIndex = (startIndex + length)
        var rawValue = string.substring(startIndex, to: (endIndex - 1))
        var checkDigit = checkDigitFollows ? string.substring(endIndex, to: endIndex) : nil
        
        // 체크비트에 영어 있는 경우 숫자로 변경
        if checkDigit != nil {
            checkDigit = replaceLetters(in: checkDigit!)
        }
        
        if ocrCorrection {
            rawValue = correct(rawValue, fieldType: fieldType)
            checkDigit = (checkDigit == nil) ? nil : correct(checkDigit!, fieldType: fieldType)
        }
        
        return MRZField(value: format(rawValue, as: fieldType), rawValue: rawValue, checkDigit: checkDigit)
    }
    
    // 검증 완료 된 필드 값 포맷
    func format(_ string: String, as fieldType: MRZFieldType) -> Any? {
        switch fieldType {
        case .names:
            return names(from: string)
        case .birthdate:
            return birthdate(from: string)
        case .sex:
            return sex(from: string)
        case .expiryDate:
            return expiryDate(from: string)
        case .documentType, .documentNumber, .countryCode, .nationality, .personalNumber, .optionalData, .hash:
            return text(from: string)
        }
    }
    
    // 검출된 필드 값과 여권 형식이 맞는지 검증
    func correct(_ string: String, fieldType: MRZFieldType) -> String {
        switch fieldType {
        case .birthdate, .expiryDate, .hash: // 숫자 형식에 영어가 없는지 확인
            return replaceLetters(in: string)
        case .names, .countryCode: // 이름, 국적, 발행국에 숫자 포함됐는지 확인
            return replaceDigits(in: string)
        case .documentType:
            let temp: String = string.replace("FM", with: "PM") // 여권 타입에 불가능한 유형 제거
            return replaceDigits(in: temp)
        case .sex:
            return string.replace("P", with: "F").replace("7", with: "F") // P가 검출 될 경우 F로 보정
        case .documentNumber:
            return string
        case .nationality:
            let temp: String = nationCheck(in: string) // 국적 확인
            return replaceDigits(in: temp)
        default:
            return string
        }
    }
    
    // 이름의 Given name, Surname 분리
    private func names(from string: String) -> (primary: String, secondary: String) {
        let identifiers = string.trimmingFillers().components(separatedBy: "<<").map({ $0.replace("<", with: " ") })
        let secondaryID = identifiers.indices.contains(1) ? identifiers[1] : ""
        return (primary: identifiers[0], secondary: secondaryID)
    }
    
    // 성별 표시 변경
    private func sex(from string: String) -> String? {
        switch string {
        case "M": return "Male"
        case "F": return "Female"
        case "<": return "UNSPECIFIED" // X
        default: return nil
        }
    }
    
    // 생일 형식 포맷
    private func birthdate(from string: String) -> Date? {
        guard CharacterSet.decimalDigits.isSuperset(of: CharacterSet(charactersIn: string)) else {
            print("생일형식 체크섬")
            return nil
        }
        
        let currentYear = Calendar.current.component(.year, from: Date()) - 2000
        let parsedYear = Int(string.substring(0, to: 1))!
        let centennial = (parsedYear > currentYear) ? "19" : "20"
        
        return dateFormatter.date(from: centennial + string)
    }
    
    // 기간 만료일 포맷
    private func expiryDate(from string: String) -> Date? {
        guard CharacterSet.decimalDigits.isSuperset(of: CharacterSet(charactersIn: string)) else {
            print("기간만료일 체크섬")
            return nil
        }
        
        let parsedYear = Int(string.substring(0, to: 1))!
        let centennial = (parsedYear >= 30) ? "19" : "20"
        
        return dateFormatter.date(from: centennial + string)
    }
   
    // < 값 제거
    private func text(from string: String) -> String {
        return string.trimmingFillers().replace("<", with: " ")
    }
    
    // 숫자 -> 영어 보정
    private func replaceDigits(in string: String) -> String {
        return string
            .replace("0", with: "O")
            .replace("1", with: "I")
            .replace("2", with: "Z")
            .replace("3", with: "B")
            .replace("4", with: "A")
            .replace("8", with: "B")
    }
    // 영어 -> 숫자 보정
    private func replaceLetters(in string: String) -> String {
        return string
            .replace("O", with: "0")
            .replace("Q", with: "0")
            .replace("U", with: "0")
            .replace("D", with: "0")
            .replace("I", with: "1")
            .replace("Z", with: "2")
            .replace("B", with: "3")
            .replace("A", with: "4")
            .replace("S", with: "5")
    }
    
    // 국적 확인
    private func nationCheck(in string: String) -> String {
        // 국가명 글자 수 안맞으면 return
        if string.count != 3 { return "null" }
        
        var count: Int = 0
        var resultnationlity: String = ""
        
        // 국가명 맞는지 확인
        for nation in nationlity {
            if string == nation {
                return string
            }
        }
        
        // 앞에 두자리 맞으면 비슷한 국가 출력
        let strFront = replaceDigits(in: string).substring(0, to: 1)
        for nation in nationlity {
            if nation.count != 3 { continue }
            if count > 1 { return "null" }
            if strFront == nation.substring(0, to: 1) {
                count = count + 1
                resultnationlity = nation
            }
        }
        
        if count == 1 { return resultnationlity }
        count = 0
        resultnationlity = ""
        
        // 뒤의 두자리 맞으면 비슷한 국가 출력
        let strBack = replaceDigits(in: string).substring(1, to: 2)
        for nation in nationlity {
            if nation.count != 3 { continue }
            if count > 1 { return "null" }
            if strBack == nation.substring(1, to: 2) {
                count = count + 1
                resultnationlity = nation
            }
        }
        if count == 1 { return resultnationlity }
        count = 0
        resultnationlity = ""

      
        // 가운데 가운데 빼고 맞으면 비슷한 국가 출력
        let strMiddle = replaceDigits(in: string).substring(0, to: 0).appending(replaceDigits(in: string).substring(2, to: 2))
        for nation in nationlity {
            if nation.count != 3 { continue }
            if count > 1 { return "null" }
            if strMiddle == nation.substring(0, to: 0).appending(nation.substring(2, to: 2)) {
                count = count + 1
                resultnationlity = nation
            }
        }
        if count == 1 { return resultnationlity }
        
        print("국가명 체크섬")
        return "null"
    }
}
