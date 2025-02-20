//
//  This file is part of the NineAnimator project.
//
//  Copyright © 2018-2019 Marcus Zhou. All rights reserved.
//
//  NineAnimator is free software: you can redistribute it and/or modify
//  it under the terms of the GNU General Public License as published by
//  the Free Software Foundation, either version 3 of the License, or
//  (at your option) any later version.
//
//  NineAnimator is distributed in the hope that it will be useful,
//  but WITHOUT ANY WARRANTY; without even the implied warranty of
//  MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
//  GNU General Public License for more details.
//
//  You should have received a copy of the GNU General Public License
//  along with NineAnimator.  If not, see <http://www.gnu.org/licenses/>.
//

import UIKit

extension UIAlertAction {
    enum TextAlignment {
        case left
        case center
        case right
    }
    
    var image: UIImage? {
        get { return self.value(forKey: "image") as? UIImage }
        set { return self.setValue(newValue, forKey: "image") }
    }
    
    var textAlignment: CATextLayerAlignmentMode {
        get { return self.value(forKey: "titleTextAlignment") as? CATextLayerAlignmentMode ?? .center }
        set { self.setValue(newValue, forKey: "titleTextAlignment") }
    }
    
    var isChecked: Bool {
        get { return self.value(forKey: "checked") as? Bool ?? false }
        set { self.setValue(newValue, forKey: "checked") }
    }
}
