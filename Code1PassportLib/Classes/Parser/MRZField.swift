
import Foundation

enum MRZFieldType {
    case documentType, countryCode, names, documentNumber, nationality, birthdate, sex, expiryDate, personalNumber, optionalData, hash
}

struct MRZField {
    let value: Any?
    let rawValue: String
    let checkDigit: String?
    let isValid: Bool?
    
    init(value: Any?, rawValue: String, checkDigit: String?) {
        self.value = value
        self.rawValue = rawValue
        self.checkDigit = checkDigit
        self.isValid = (checkDigit == nil) ? nil : MRZField.isValueValid(rawValue, checkDigit: checkDigit!)
    }
    
    // MRZ 유효 체크섬
    static func isValueValid(_ value: String, checkDigit: String) -> Bool {
        guard let numericCheckDigit = Int(checkDigit) else {
            if checkDigit == "<" {
                return value.trimmingFillers().isEmpty
            }
            print("mrz 유효 체크섬")
            return false
        }
        
        // 7, 3, 1 가중치 계산
        let uppercaseLetters = CharacterSet.uppercaseLetters
        let digits = CharacterSet.decimalDigits
        let weights = [7, 3, 1]
        var total = 0
        
        for (index, character) in value.enumerated() {
            let unicodeScalar = character.unicodeScalars.first!
            let charValue: Int
            
            if uppercaseLetters.contains(unicodeScalar) {
                charValue = Int(10 + unicodeScalar.value) - 65
            }
            else if digits.contains(unicodeScalar) {
                charValue = Int(String(character))!
            }
            else if character == "<" {
                charValue = 0
            }
            else {
                print("에러")
                return false
            }
            
            total += (charValue * weights[index % 3])
        }
        return (total % 10 == numericCheckDigit)
    }
}
