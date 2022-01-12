
import Foundation

// MRZ 결과 구조체
public struct MRZResult {
    public let documentType: String
    public let countryCode: String
    public let surnames: String
    public let givenNames: String
    public let documentNumber: String
    public let nationalityCountryCode: String
    public let birthdate: Date? // 형식에 맞지 않으면 nil 값
    public let sex: String? // 형식에 맞지 않으면 nil 값
    public let expiryDate: Date? // nul
    public let personalNumber: String
    public let personalNumber2: String? // 공란일 경우 nil 값 가능
    
    public let isDocumentNumberValid: Bool
    public let isBirthdateValid: Bool
    public let isExpiryDateValid: Bool
    public let isPersonalNumberValid: Bool?
    public let allCheckDigitsValid: Bool
}
