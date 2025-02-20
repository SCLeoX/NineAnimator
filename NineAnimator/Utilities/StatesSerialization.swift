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

private struct StateSerializationFile: Codable {
    let history: [AnimeLink]
    
    let progresses: [String: Float]
    
    let exportedDate: Date
}

/**
 Creating the .naconfig file for sharing and backing up anime watching
 histories.
 */
func export(_ configuration: NineAnimatorUser) -> URL? {
    do {
        let file = StateSerializationFile(
            history: configuration.recentAnimes,
            progresses: configuration.persistedProgresses,
            exportedDate: Date()
        )
        
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US")
        formatter.dateFormat = "MMMM dd yyy HH-mm-ss"
        
        let fileName = "\(formatter.string(from: file.exportedDate)).naconfig"
        let fs = FileManager.default
        let url = fs.temporaryDirectory.appendingPathComponent(fileName)
        
        try PropertyListEncoder().encode(file).write(to: url)
        
        return url
    } catch { Log.error(error) }
    
    return nil
}

func merge(_ configuration: NineAnimatorUser, with fileUrl: URL, policy: NineAnimatorUser.MergePiority) -> Bool {
    do {
        // Read the contents of the configuration file
        _ = fileUrl.startAccessingSecurityScopedResource()
        let serializedConfiguration = try Data(contentsOf: fileUrl)
        fileUrl.stopAccessingSecurityScopedResource()
        
        let preservedStates = try PropertyListDecoder().decode(StateSerializationFile.self, from: serializedConfiguration)
        
        let piorityHistory = policy == .localFirst ? configuration.recentAnimes : preservedStates.history
        let secondaryHistory = policy == .localFirst ? preservedStates.history : configuration.recentAnimes
        
        configuration.recentAnimes = piorityHistory + secondaryHistory.filter {
            item in !piorityHistory.contains { $0 == item }
        }
        
        let piroityPersistedProgresses = policy == .localFirst ? configuration.persistedProgresses : preservedStates.progresses
        let secondaryPersistedProgresses = policy == .localFirst ? preservedStates.progresses : configuration.persistedProgresses
        
        configuration.persistedProgresses = piroityPersistedProgresses
            .merging(secondaryPersistedProgresses) { piority, _ in piority }
        
        return true
    } catch { Log.error(error) }
    return false
}

func replace(_ configuration: NineAnimatorUser, with fileUrl: URL) -> Bool {
    do {
        _ = fileUrl.startAccessingSecurityScopedResource()
        let serializedConfiguration = try Data(contentsOf: fileUrl)
        fileUrl.stopAccessingSecurityScopedResource()
        
        let preservedStates = try PropertyListDecoder().decode(StateSerializationFile.self, from: serializedConfiguration)
        
        configuration.recentAnimes = preservedStates.history
        configuration.persistedProgresses = preservedStates.progresses
        
        return true
    } catch { Log.error(error) }
    return false
}
