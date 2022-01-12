
import Foundation

public class Code1PassportLib: UIView {
    
    public func start(father: UIViewController) {
        print("시작")
        let storyboard = UIStoryboard(name: "Live", bundle: Bundle(for: Code1PassportLib.self))
        if let vc = storyboard.instantiateViewController(withIdentifier: "View") as? InferenceController {
            father.navigationController?.pushViewController(vc,animated: true)
        }
    }

}

