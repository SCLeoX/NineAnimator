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

extension MyAnimeList {
    class MyAnimeListListingAnimeInformation: ListingAnimeInformation {
        var reference: ListingAnimeReference
        var name: ListingAnimeName
        var artwork: URL
        var wallpapers: [URL]
        var siteUrl: URL
        var description: String
        var information: [String: String]
        
        private var _meanRatings: Double?
        private var _numRatings: Int?
        private var _relatedAnimeReferences: [ListingAnimeReference]
        private var _numEpisodes: Int?

        var characters: NineAnimatorPromise<[ListingAnimeCharacter]> { return .fail(.unknownError) }
        var reviews: NineAnimatorPromise<[ListingAnimeReview]> { return .fail(.unknownError) }
        var relatedReferences: NineAnimatorPromise<[ListingAnimeReference]> { return .success(_relatedAnimeReferences) }
        
        var statistics: NineAnimatorPromise<ListingAnimeStatistics> {
            return NineAnimatorPromise.firstly {
                [weak self] in
                guard let self = self,
                    let mean = self._meanRatings,
                    let n = self._numRatings else { return nil }
                
                // Generate 100 data points for the ratings
                let numArtificialDataPoints = 20
                let maxRatings = 10.0
                // Assuming the distribution is normal, in reality is probably isn't.
//                let porportions = mean / maxRatings
//                let standardDeviation = sqrt(porportions * (1.0 - porportions) / Double(n)) * maxRatings
                let standardDeviation = 2.0
                let generatedDataPoints = (0...numArtificialDataPoints).map {
                    index -> (Double, Double) in
                    let x = Double(index) / Double(numArtificialDataPoints) * maxRatings
                    return (x, pow(M_E, -pow(x - mean, 2) / (2 * pow(standardDeviation, 2))) /
                        (standardDeviation * sqrt(2 * .pi)))
                }
                
                // Construct the statistics object
                return ListingAnimeStatistics(
                    ratingsDistribution: Dictionary(uniqueKeysWithValues: generatedDataPoints),
                    numberOfRatings: n,
                    episodesCount: self._numEpisodes
                )
            }
        }
        
        init(_ animeEntry: NSDictionary, withReference reference: ListingAnimeReference) throws {
            let numberFormatter = NumberFormatter()
            numberFormatter.numberStyle = .decimal
            numberFormatter.maximumFractionDigits = 2
            
            let jsonDateRetriever = ISO8601DateFormatter()
            let dateFormatter = DateFormatter()
            dateFormatter.dateStyle = .long
            dateFormatter.timeStyle = .none
            
            self.reference = reference
            self.name = ListingAnimeName(
                default: try animeEntry.value(at: "title", type: String.self),
                english: try animeEntry.value(at: "alternative_titles.en", type: String.self),
                romaji: try animeEntry.value(at: "title", type: String.self),
                native: try animeEntry.value(at: "alternative_titles.ja", type: String.self)
            )
            let preferredArtwork: URL = {
                if let artworkUrlString = animeEntry.valueIfPresent(at: "main_picture.large", type: String.self) ??
                    animeEntry.valueIfPresent(at: "main_picture.medium", type: String.self),
                    let artworkUrl = URL(string: artworkUrlString) {
                    return artworkUrl
                } else { return NineAnimator.placeholderArtworkUrl }
            }()
            self.artwork = preferredArtwork
            self.wallpapers = [ preferredArtwork ]
            self.siteUrl = try URL(string: "https://myanimelist.net/anime/\(reference.uniqueIdentifier)").tryUnwrap(.urlError)
            self.description = try animeEntry.value(at: "synopsis", type: String.self)
            
            // Decode additional information
            var animeInformation = [String: CustomStringConvertible]()
            
            if let averageDurationSeconds = animeEntry.valueIfPresent(at: "average_episode_duration", type: Int.self),
                let formattedAverageDuration = numberFormatter.string(from: NSNumber(value: Double(averageDurationSeconds) / 60)) {
                animeInformation["Episode Duration"] = "\(formattedAverageDuration) Minutes"
            }
            
            if let createdDateString = animeEntry.valueIfPresent(at: "created_at", type: String.self),
                let createdDate = jsonDateRetriever.date(from: createdDateString) {
                animeInformation["Created At"] = dateFormatter.string(from: createdDate)
            }
            
            animeInformation["Start Date"] = animeEntry.valueIfPresent(at: "start_date", type: String.self)
            animeInformation["End Date"] = animeEntry.valueIfPresent(at: "end_date", type: String.self)
            animeInformation["Popularity"] = animeEntry.valueIfPresent(at: "popularity", type: Int.self)
            animeInformation["Rank"] = animeEntry.valueIfPresent(at: "rank", type: Int.self)
            animeInformation["Media Type"] = animeEntry.valueIfPresent(at: "media_type", type: String.self)
            animeInformation["Number of Ratings"] = animeEntry.valueIfPresent(at: "num_scoring_users", type: Int.self)
            animeInformation["NSFW"] = animeEntry.valueIfPresent(at: "nsfw", type: String.self)
            
            self.information = animeInformation.mapValues { $0.description }
            
            // Additional information
            self._meanRatings = animeEntry.valueIfPresent(at: "mean", type: Double.self)
            self._numRatings = animeEntry.valueIfPresent(at: "num_scoring_users", type: Int.self)
            self._numEpisodes = animeEntry.valueIfPresent(at: "num_episodes", type: Int.self)
            self._relatedAnimeReferences = try animeEntry.value(
                at: "related_anime",
                type: [NSDictionary].self
            ) .compactMap { $0["node"] as? NSDictionary }
                .map { try ListingAnimeReference(reference.parentService as! MyAnimeList, withAnimeNode: $0) }
        }
    }
    
    func listingAnime(from reference: ListingAnimeReference) -> NineAnimatorPromise<ListingAnimeInformation> {
        return apiRequest("/anime/\(reference.uniqueIdentifier)", query: [
            "fields": "alternative_titles,average_episode_duration,broadcast,created_at,end_date,main_picture,mean,media_type,nsfw,num_scoring_users,popularity,rank,synopsis,title,background,related_anime,related_anime{node{my_list_status{start_date,finish_date}}},num_episodes,start_date"
        ]).then {
            response in
            guard let animeEntry = response.data.first else {
                throw NineAnimatorError.responseError("Cannot find the information related to this anime")
            }
            
            // Construct the listing anime information
            return try MyAnimeListListingAnimeInformation(animeEntry, withReference: reference)
        }
    }
}
