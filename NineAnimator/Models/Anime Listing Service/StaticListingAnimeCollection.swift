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

import Foundation

struct StaticListingAnimeCollection: ListingAnimeCollection {
    let parentService: ListingService
    
    /// The "user friendly" name of this collection
    let title: String
    
    /// Internal identifier of this collection unique to the parent service
    let identifier: String
    
    /// The list of anime references
    let collection: [ListingAnimeReference]
    
    var userInfo: [String: Any]
    
    init(_ parent: ListingService,
         name: String,
         identifier: String,
         collection: [ListingAnimeReference],
         userInfo: [String: Any] = [:]) {
        self.parentService = parent
        self.title = name
        self.identifier = identifier
        self.collection = collection
        self.userInfo = userInfo
    }
}

extension StaticListingAnimeCollection {
    var totalPages: Int? { return 1 }
    var availablePages: Int { return 1 }
    var moreAvailable: Bool { return false }
    
    var delegate: ContentProviderDelegate? {
        get { return nil }
        set { newValue?.pageIncoming(0, from: self) }
    }
    
    func links(on page: Int) -> [AnyLink] {
        return collection.map { .listingReference($0) }
    }
    
    func more() { }
}
