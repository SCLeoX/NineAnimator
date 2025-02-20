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

protocol BlendInViewController { }

protocol DontBotherViewController { }

class ApplicationNavigationController: UINavigationController, UINavigationControllerDelegate, Themable {
    override var supportedInterfaceOrientations: UIInterfaceOrientationMask {
        return topViewController?.supportedInterfaceOrientations ?? super.supportedInterfaceOrientations
    }
    
    override var shouldAutorotate: Bool {
        return topViewController?.shouldAutorotate ?? super.shouldAutorotate
    }
    
    override func viewDidLoad() {
        super.viewDidLoad()
        Theme.provision(self)
        delegate = self
    }
    
    func theme(didUpdate theme: Theme) {
        view.tintColor = theme.tint
        view.backgroundColor = theme.background
        navigationBar.barStyle = theme.barStyle
        
        guard !(topViewController is DontBotherViewController) else { return }
        
        navigationBar.tintColor = theme.tint
        navigationBar.barTintColor = theme.translucentBackground
        navigationBar.layoutIfNeeded()
    }
    
    func navigationController(_ navigationController: UINavigationController,
                              didShow viewController: UIViewController,
                              animated: Bool) {
        // Don't bother DontBotherViewController
        guard !(viewController is DontBotherViewController) else { return }
        
//        UIView.animate(withDuration: 0.2) {
//            [unowned navigationBar] in
//            // Disable shadow image and set to not translucent when trying to blend in
//            // the navigation bar and the contents
//            navigationBar.backgroundColor = nil
//            navigationBar.setBackgroundImage(nil, for: .default)
//            navigationBar.shadowImage = viewController is BlendInViewController ? UIImage() : nil
//            navigationBar.isTranslucent = !(viewController is BlendInViewController)
//            navigationBar.barTintColor = (viewController is BlendInViewController) ? Theme.current.background : nil
//            navigationBar.tintColor = Theme.current.tint
//        }
        
        navigationBar.shadowImage = UIImage()
        navigationBar.isTranslucent = true
        navigationBar.setBackgroundImage(nil, for: .default)
        navigationBar.backgroundColor = nil
        
        UIView.animate(withDuration: 0.2) {
            [navigationBar] in
            navigationBar.barTintColor = Theme.current.translucentBackground
            navigationBar.tintColor = Theme.current.tint
            navigationBar.layoutIfNeeded()
        }
    }
}
