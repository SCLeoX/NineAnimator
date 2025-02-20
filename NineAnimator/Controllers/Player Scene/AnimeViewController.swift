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

import AVKit
import SafariServices
import UIKit
import UserNotifications
import WebKit

/**
 NineAnimator's one and only `AnimeViewController`
 
 - important:
 Always initalize this class from storyboard and use the `setPresenting(_: AnimeLink)`
 method or the `setPresenting(episode: EpisodeLink)` method to initialize before
 presenting.
 
 ## Example Usage
 
 1. Create segues in storyboard with reference to `AnimePlayer.storyboard`.
 2. Override `prepare(for segue: UIStoryboardSegue)` method.
 3. Retrive the `AnimeViewController` from `segue.destination as? AnimeViewController`
 4. Initialize the `AnimeViewController` with either `setPresenting(_: AnimeLink)` or
    `setPresenting(episode: EpisodeLink)`.
 */
class AnimeViewController: UITableViewController, AVPlayerViewControllerDelegate, BlendInViewController {
    // MARK: - Set either one of the following item to initialize the anime view
    private var animeLink: AnimeLink?
    
    private var episodeLink: EpisodeLink? {
        didSet {
            if let episodeLink = episodeLink {
                self.animeLink = episodeLink.parent
                self.server = episodeLink.server
            }
        }
    }
    
    @IBOutlet private weak var animeHeadingView: AnimeHeadingView!
    
    @IBOutlet private weak var moreOptionsButton: UIButton!
    
    private var anime: Anime?
    
    var server: Anime.ServerIdentifier? {
        get { return anime?.currentServer }
        set {
            guard let server = newValue else { return }
            anime?.select(server: server)
        }
    }
    
    // Set episode will update the server identifier as well
    private var episode: Episode? {
        didSet {
            guard let episode = episode else { return }
            server = episode.link.server
        }
    }
    
    private var presentedSuggestingEpisode: EpisodeLink?
    
    private var selectedEpisodeCell: UITableViewCell?
    
    private var episodeRequestTask: NineAnimatorAsyncTask?
    
    private var animeRequestTask: NineAnimatorAsyncTask?
    
    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        
        // Remove lines at the end of the table
        tableView.tableFooterView = UIView()
        
        // If episode is set, use episode's anime link as the anime for display
        if let episode = episode {
            animeLink = episode.parentLink
        }
        
        guard let link = animeLink else { return }
        
        // Not updating title anymore because we are showing anime name in the heading view
//        title = link.title
        
        // Fetch anime if anime does not exists
        guard anime == nil else { return }
        
        // Set animeLink property of the heading view so proper anime information is displayed
        animeHeadingView.animeLink = link
        animeHeadingView.sizeToFit()
        view.setNeedsLayout()
        
        animeRequestTask = NineAnimator.default.anime(with: link) {
            [weak self] anime, error in
            guard let anime = anime else {
                Log.error(error)
                return DispatchQueue.main.async {
                    // Allow the user to recover the anime by searching in another source
                    if let error = error as? NineAnimatorError.ContentUnavailableError {
                        self?.presentError(error) {
                            if $0 {
                                self?.presentRecoveryOptions(for: link)
                            } else if let navigationController = self?.navigationController {
                                _ = navigationController.popViewController(animated: true)
                            } else { self?.dismiss(animated: true, completion: nil) }
                        }
                        return
                    }
                    
                    self?.presentError(error!) {
                        // If not allowed to retry, dismiss the view controller
                        guard !$0 else { return }
                        DispatchQueue.main.async {
                            guard let self = self else { return }
                            if let navigationController = self.navigationController {
                                navigationController.popViewController(animated: true)
                            } else { self.dismiss(animated: true) }
                        }
                    }
                }
            }
            self?.setPresenting(anime: anime)
            // Initiate playback if episodeLink is set
            if let episodeLink = self?.episodeLink {
                // Present the cast controller if the episode is currently playing on
                // an attached cast device
                if CastController.default.isAttached(to: episodeLink) {
                    CastController.default.presentPlaybackController()
                } else { self?.retriveAndPlay() }
            }
        }
    }
    
    override func viewDidLoad() {
        super.viewDidLoad()
        tableView.makeThemable()
        
        // Receive playback did end notification and update suggestions
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(onPlaybackDidEnd(_:)),
            name: .playbackDidEnd,
            object: nil
        )
    }
    
    override func didMove(toParent parent: UIViewController?) {
        super.didMove(toParent: parent)
        
        // Cleanup observers and tasks
        episodeRequestTask?.cancel()
        episodeRequestTask = nil
        
        // Remove tableView selections
        tableView.deselectSelectedRow()
        
        // Sets episode and server to nil
        episode = nil
    }
}

// MARK: - Receive & Present Anime
extension AnimeViewController {
    private func setPresenting(anime: Anime) {
        self.anime = anime
        
        let sectionsNeededReloading = Section.indexSet(.all)
        
        // Prepare the tracking context
        anime.prepareForTracking()
        
        // Update the AnimeLink in the info cell so we get the correct poster displayed
        self.animeLink = anime.link
        
        // Clean user notifications for this anime
        UserNotificationManager.default.clearNotifications(for: anime.link)
        
        // Push server updates to the heading view
        self.animeHeadingView.update(animated: true) { [weak self] in
            guard let self = self else { return }
            
            $0.selectedServerName = anime.servers[self.server!]
            $0.anime = anime
            
            self.tableView.beginUpdates()
            self.tableView.setNeedsLayout()
            self.tableView.reloadSections(sectionsNeededReloading, with: .automatic)
            self.tableView.endUpdates()
        }
        
        // Update history
        NineAnimator.default.user.entering(anime: anime.link)
        NineAnimator.default.user.push()
        
        // Setup userActivity
        self.prepareContinuity()
    }
}

// MARK: - Exposed Interfaces
extension AnimeViewController {
    /**
     Initialize the `AnimeViewController` with the provided
     AnimeLink.
     
     - parameters:
        - link: The `AnimeLink` object that is used to
                initialize this `AnimeViewController`
     
     By calling this method, `AnimeViewController` will use the
     Source object from this link to retrive the `Anime` object.
     */
    func setPresenting(anime link: AnimeLink) {
        self.episodeLink = nil
        self.animeLink = link
    }
    
    /**
     Initialize the `AnimeViewController` with the parent AnimeLink
     of the provided `EpisodeLink`, and immedietly starts playing
     the episode once the anime is retrived and parsed.
     
     - parameters:
        - episode: The `EpisodeLink` object that is used to
                   initialize this `AnimeViewController`
     
     `AnimeViewController` will first retrive the Anime object from
     the Source in `AnimeViewController.viewWillAppear`
     */
    func setPresenting(episode link: EpisodeLink) {
        self.episodeLink = link
    }
    
    /**
     Initialize the `AnimeViewController` with the link contained
     in the provided `AnyLink`.
     
     - parameters:
        - link: The `AnyLink` object that is used to initialize
                this `AnimeViewController`
     
     `setPresenting(_ link: AnyLink)` is a shortcut for calling
     `setPresenting(episode: EpisodeLink)` or
     `setPresenting(anime: AnimeLink)`.
     */
    func setPresenting(_ link: AnyLink) {
        switch link {
        case .anime(let animeLink): setPresenting(anime: animeLink)
        case .episode(let episodeLink): setPresenting(episode: episodeLink)
        default: Log.error("Unsupported link: %@", link)
        }
    }
}

// MARK: - Table view data source
extension AnimeViewController {
    override func numberOfSections(in tableView: UITableView) -> Int {
        return [Section].all.count
    }
    
    override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        switch Section(rawValue: section)! {
        case .suggestion, .synopsis:
            return anime == nil ? 0 : 1
        case .episodes:
            return anime?.numberOfEpisodeLinks ?? 0
        }
    }
    
    override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        switch Section(rawValue: indexPath.section)! {
        case .suggestion:
            let cell = tableView.dequeueReusableCell(withIdentifier: "anime.suggestion", for: indexPath) as! AnimePredictedEpisodeTableViewCell
            updateSuggestingEpisode(for: cell)
            cell.makeThemable()
            return cell
        case .synopsis:
            let cell = tableView.dequeueReusableCell(withIdentifier: "anime.synopsis", for: indexPath) as! AnimeSynopsisCellTableViewCell
            cell.synopsisText = anime?.description
            cell.stateChangeHandler = {
                [weak tableView] _ in
                tableView?.beginUpdates()
                tableView?.setNeedsLayout()
                tableView?.endUpdates()
            }
            return cell
        case .episodes:
            let episode = episodeLink(for: indexPath)!
            
            // Use detailed view when possible and enabled
            if NineAnimator.default.user.showEpisodeDetails,
                let detailedEpisodeInfo = anime!.attributes(for: episode) {
                let cell = tableView.dequeueReusableCell(withIdentifier: "anime.episode.detailed", for: indexPath) as! DetailedEpisodeTableViewCell
                cell.makeThemable()
                cell.episodeLink = episode
                cell.episodeInformation = detailedEpisodeInfo
                cell.onStateChange = {
                    [weak self] _ in
                    self?.tableView.beginUpdates()
                    self?.tableView.layoutIfNeeded()
                    self?.tableView.endUpdates()
                }
                return cell
            } else {
                let cell = tableView.dequeueReusableCell(withIdentifier: "anime.episode", for: indexPath) as! EpisodeTableViewCell
                cell.makeThemable()
                cell.episodeLink = episode
                return cell
            }
        }
    }
    
    override func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        guard indexPath.section == Section.episodes || indexPath.section == Section.suggestion else {
            tableView.deselectSelectedRow()
            return Log.info("A non-episode cell has been selected")
        }
        
        guard let cell = tableView.cellForRow(at: indexPath), cell != selectedEpisodeCell else {
            Log.info("A cell is either tapped twice or does not exist. Peacefully aborting task.")
            episodeRequestTask?.cancel()
            episodeRequestTask = nil
            selectedEpisodeCell = nil
            tableView.deselectSelectedRow()
            return
        }
        
        guard let episodeLink = episodeLink(for: indexPath) else {
            tableView.deselectSelectedRow()
            return Log.error("Unable to retrive episode link from pool")
        }
        
        // Scroll and highlight the cell in the episodes section
        if cell is AnimePredictedEpisodeTableViewCell,
            let destinationIndexPath = self.indexPath(for: episodeLink) {
            tableView.deselectSelectedRow()
            tableView.selectRow(at: destinationIndexPath, animated: true, scrollPosition: .middle)
        }
        
        selectedEpisodeCell = cell
        self.episodeLink = episodeLink
        
        retriveAndPlay()
    }
}

// MARK: - Initiate playback
extension AnimeViewController {
    private func retriveAndPlay() {
        guard let episodeLink = episodeLink else { return }
        
        episodeRequestTask?.cancel()
        NotificationCenter.default.removeObserver(self)
        
        let content = OfflineContentManager.shared.content(for: episodeLink)
        let trackingContext = anime?.trackingContext
        
        let clearSelection = {
            [weak self] in
            DispatchQueue.main.async {
                self?.tableView.deselectSelectedRow()
                self?.selectedEpisodeCell = nil
            }
        }
        
        // Use offline media if google cast is not setup
        if let media = content.media {
            if CastController.default.isReady {
                Log.info("Offline content is available, but Google Cast has been setup. Using online media.")
            } else {
                Log.info("Offline content is available. Using donloaded asset.")
                clearSelection()
                onPlaybackMediaRetrieved(media)
                return
            }
        }
        
        episodeRequestTask = anime!.episode(with: episodeLink) {
            [weak self, weak trackingContext] episode, error in
            guard let self = self else { return }
            guard let episode = episode else {
                // Present the error in main loop
                DispatchQueue.main.async {
                    self.presentError(error!) {
                        [weak self] _ in
                        self?.selectedEpisodeCell = nil
                        self?.tableView.deselectSelectedRow()
                    }
                }
                return Log.error(error)
            }
            self.episode = episode
            
            // Save episode to last playback
            NineAnimator.default.user.entering(episode: episodeLink)
            
            Log.info("Episode target retrived for '%@'", episode.name)
            Log.debug("- Playback target: %@", episode.target)
            
            if episode.nativePlaybackSupported {
                // Prime the HMHomeManager
                HomeController.shared.primeIfNeeded()
                
                self.episodeRequestTask = episode.retrive {
                    [weak self] media, error in
                    guard let self = self else { return }
                    
                    defer { clearSelection() }
                    
                    self.episodeRequestTask = nil
                    
                    guard let media = media else {
                        Log.error("Item not retrived: \"%@\"", error!)
                        DispatchQueue.main.async { [weak self] in
                            self?.onPlaybackMediaStall(episode.target)
                        }
                        return
                    }
                    
                    self.onPlaybackMediaRetrieved(media, episode: episode)
                }
            } else {
                // Always stall unsupported episodes and update the progress to 1.0
                self.onPlaybackMediaStall(episode.target)
                episode.update(progress: 1.0)
                // Update tracking state
                trackingContext?.endWatching(episode: episode.link)
                clearSelection()
            }
        }
    }
    
    // Handle when the link to the episode has been retrieved but no streamable link was found
    private func onPlaybackMediaStall(_ fallbackURL: URL) {
        Log.info("Playback media retrival stalled. Falling back to web access.")
        let playbackController = SFSafariViewController(url: fallbackURL)
        present(playbackController, animated: true)
    }
    
    // Handle the playback media
    private func onPlaybackMediaRetrieved(_ media: PlaybackMedia, episode: Episode? = nil) {
        // Use Google Cast if it is setup and ready
        if let episode = episode, CastController.default.isReady {
            CastController.default.initiate(playbackMedia: media, with: episode)
            CastController.default.presentPlaybackController()
        } else { NativePlayerController.default.play(media: media) }
    }
}

// MARK: - Suggesting To Watch episode
extension AnimeViewController {
    @IBAction private func onQuickJumpButtonTapped(_ sender: UIButton) {
        guard let server = server, let episodes = anime?.episodes[server] else { return }
        
        // Scroll to the suggested episode if no more than 50 episodes are available
        guard episodes.count > 50 else {
            if let suggestedEpisode = presentedSuggestingEpisode,
                let index = indexPath(for: suggestedEpisode) {
                tableView.scrollToRow(at: index, at: .middle, animated: true)
            }
            return
        }
        
        let quickJumpSheet = UIAlertController(title: "Qucik Jump", message: nil, preferredStyle: .actionSheet)
        
        if let popoverController = quickJumpSheet.popoverPresentationController {
            popoverController.sourceView = sender
        }
        
        if episodes.count <= 100 {
            quickJumpSheet.addAction({
                let index = indexPath(for: episodes[0])!
                return UIAlertAction(title: "1 - 49", style: .default) {
                    [weak self] _ in self?.tableView.scrollToRow(at: index, at: .middle, animated: true)
                }
            }())
            
            quickJumpSheet.addAction({
                let index = indexPath(for: episodes[49])!
                return UIAlertAction(title: "50 - \(episodes.count)", style: .default) {
                    [weak self] _ in self?.tableView.scrollToRow(at: index, at: .middle, animated: true)
                }
            }())
        } else {
            let episodesPerSection = 100
            let totalEpisodes = episodes.count
            let totalSections = totalEpisodes / episodesPerSection
            (0...totalSections).compactMap {
                section in
                let startEpisodeNumber = episodesPerSection * section
                let endEpisodeNumber = min(startEpisodeNumber + episodesPerSection, episodes.count)
                
                // If the start episode offset is greater than or equal to the
                // number of episodes, return nil
                guard startEpisodeNumber < totalEpisodes else { return nil }
                
                let index = indexPath(for: episodes[startEpisodeNumber])!
                return UIAlertAction(
                    title: startEpisodeNumber == endEpisodeNumber ?
                        "Episode \(startEpisodeNumber + 1)" : "Episode \(startEpisodeNumber + 1) - \(endEpisodeNumber)",
                    style: .default) {
                    [weak self] _ in self?.tableView.scrollToRow(at: index, at: .middle, animated: true)
                }
            }.forEach(quickJumpSheet.addAction)
        }
        
        if let suggestedEpisode = presentedSuggestingEpisode,
            let index = indexPath(for: suggestedEpisode) {
            let suggestedEpisodeLabel: String = {
                if let episodeNumber = anime?.episodesAttributes[suggestedEpisode]?.episodeNumber {
                    return "Episode \(episodeNumber)"
                } else { return "Episode \(suggestedEpisode.name)" }
            }()
            quickJumpSheet.addAction({
                UIAlertAction(
                    title: "Suggested: \(suggestedEpisodeLabel)",
                    style: .default) {
                    [weak self] _ in self?.tableView.scrollToRow(at: index, at: .middle, animated: true)
                }
            }())
        }
        
        quickJumpSheet.addAction(UIAlertAction(title: "Cancel", style: .cancel, handler: nil))
        
        present(quickJumpSheet, animated: true, completion: nil)
    }
    
    private func updateSuggestingEpisode(for cell: AnimePredictedEpisodeTableViewCell) {
        guard let anime = anime, let server = server else { return }
        // Search from the latest to the earliest
        guard let availableEpisodes = anime.episodes[server] else { return }
        
        DispatchQueue.global().async {
            [weak self] in
            var suggestingEpisodeLink: EpisodeLink?
            
            func update(_ link: EpisodeLink, reason: AnimePredictedEpisodeTableViewCell.SuggestionReason) {
                DispatchQueue.main.async {
                    cell.episodeLink = link
                    cell.reason = reason
                }
            }
            
            if availableEpisodes.count > 1 {
                // The policy for suggestion is:
                // 1. If an episode with a progress of 0.01...0.80 exists, suggest that episode
                // 2. If an episode with a progress greater than 0.80 exists, suggest the next
                //    episode to that eisode if it exists, or the episode itself if there is no
                //    more after that episode
                // 3. Suggest the first episode
                if let unfinishedAnimeIndex = availableEpisodes.lastIndex(where: { $0.playbackProgress > 0.01 }) {
                    let link: EpisodeLink
                    switch availableEpisodes[unfinishedAnimeIndex].playbackProgress {
                    case 0.80... where (unfinishedAnimeIndex + 1) < availableEpisodes.count:
                        link = availableEpisodes[unfinishedAnimeIndex + 1]
                        update(link, reason: .start)
                    case 0.01..<0.80:
                        link = availableEpisodes[unfinishedAnimeIndex]
                        update(link, reason: .continue)
                    default:
                        link = availableEpisodes[unfinishedAnimeIndex]
                        update(link, reason: .start)
                    }
                    suggestingEpisodeLink = link
                } else {
                    let link = availableEpisodes.first!
                    suggestingEpisodeLink = link
                    update(link, reason: .start)
                }
            } else if let link = availableEpisodes.first {
                suggestingEpisodeLink = link
                update(link, reason: link.playbackProgress > 0.01 ? .continue : .start)
            }
            
            // Store the suggested episode link
            self?.presentedSuggestingEpisode = suggestingEpisodeLink
        }
    }
    
    // Update suggestion when playback did end
    @objc private func onPlaybackDidEnd(_ notification: Notification) {
        tableView.reloadSections(Section.indexSet(.suggestion), with: .automatic)
    }
}

// MARK: - Handling events from the header view
extension AnimeViewController {
    @IBAction private func onSubscribeButtonTapped(_ sender: Any) {
        // Request permission first
        UserNotificationManager.default.requestNotificationPermissions()
        
        // Then update the heading view
        animeHeadingView.update(animated: true) {
            [weak self] _ in
            if let anime = self?.anime {
                NineAnimator.default.user.subscribe(anime: anime)
            } else if let animeLink = self?.animeLink {
                NineAnimator.default.user.subscribe(uncached: animeLink)
            }
        }
    }
    
    @IBAction private func onMoreOptionsButtonTapped(_ sender: Any) {
        guard let animeLink = animeLink else { return }
        
        let actionSheet = UIAlertController(title: nil, message: nil, preferredStyle: .actionSheet)
        
        if let popoverController = actionSheet.popoverPresentationController {
            popoverController.sourceView = moreOptionsButton
        }
        
        // If an reference is available, show option to present it
        if anime?.trackingContext.availableReferences.filter({ $0.parentService.isCapableOfListingAnimeInformation }).isEmpty == false {
            actionSheet.addAction({
                let action = UIAlertAction(title: "Show Information", style: .default) {
                    [weak self] _ in self?.performSegue(withIdentifier: "anime.information", sender: self)
                }
                action.image = #imageLiteral(resourceName: "Info")
                action.textAlignment = .left
                return action
            }())
        }
        
        actionSheet.addAction({
            let action = UIAlertAction(title: "Select Server", style: .default) {
                [weak self] _ in self?.showSelectServerDialog()
            }
            action.image = #imageLiteral(resourceName: "Server")
            action.textAlignment = .left
            return action
        }())
        
        actionSheet.addAction({
            let action = UIAlertAction(title: "Share", style: .default) {
                [weak self] _ in self?.showShareDiaglog()
            }
            action.image = #imageLiteral(resourceName: "Action")
            action.textAlignment = .left
            return action
        }())
        
        actionSheet.addAction({
            let action = UIAlertAction(title: "Setup Google Cast", style: .default) {
                _ in CastController.default.presentPlaybackController()
            }
            action.image = #imageLiteral(resourceName: "Chromecast Icon")
            action.textAlignment = .left
            return action
        }())
        
        if NineAnimator.default.user.isSubscribing(anime: animeLink) {
            actionSheet.addAction({
                let action = UIAlertAction(title: "Unsubscribe", style: .default) {
                    [weak self] _ in
                    self?.animeHeadingView.update(animated: true) {
                        _ in NineAnimator.default.user.unsubscribe(anime: animeLink)
                    }
                }
                action.image = #imageLiteral(resourceName: "Notification Disabled")
                action.textAlignment = .left
                return action
            }())
        }
        
        actionSheet.addAction({
            let action = UIAlertAction(title: "Cancel", style: .cancel, handler: nil)
//            action.textAlignment = .left
            return action
        }())
        
        present(actionSheet, animated: true, completion: nil)
    }
    
    private func showSelectServerDialog() {
        let alertView = UIAlertController(title: "Select Server", message: nil, preferredStyle: .actionSheet)
        
        if let popover = alertView.popoverPresentationController {
            popover.sourceView = moreOptionsButton
        }
        
        for server in anime!.servers {
            let action = UIAlertAction(title: server.value, style: .default) {
                [weak self] _ in self?.didSelectServer(server.key)
            }
            if self.server == server.key {
                action.setValue(true, forKey: "checked")
            }
            alertView.addAction(action)
        }
        
        alertView.addAction(UIAlertAction(title: "Cancel", style: .cancel))
        
        present(alertView, animated: true)
    }
    
    private func showShareDiaglog() {
        guard let link = animeLink else { return }
        let activityViewController = UIActivityViewController(activityItems: [link.link], applicationActivities: nil)
        
        if let popover = activityViewController.popoverPresentationController {
            popover.sourceView = moreOptionsButton
        }
        
        present(activityViewController, animated: true)
    }
    
    // Update the heading view and reload the list of episodes for the server
    private func didSelectServer(_ server: Anime.ServerIdentifier) {
        self.server = server
        tableView.reloadSections(Section.indexSet(.episodes, .suggestion), with: .automatic)
        
        NineAnimator.default.user.recentServer = server
        
        // Update headings
        animeHeadingView.update(animated: true) {
            $0.selectedServerName = self.anime!.servers[server]
        }
    }
}

// Peek preview actions
extension AnimeViewController {
    override var previewActionItems: [UIPreviewActionItem] {
        guard let animeLink = self.animeLink else { return [] }
        
        let subscriptionAction = NineAnimator.default.user.isSubscribing(anime: animeLink) ?
                UIPreviewAction(title: "Unsubscribe", style: .default) { _, _ in
                    NineAnimator.default.user.unsubscribe(anime: animeLink)
                } : UIPreviewAction(title: "Subscribe", style: .default) { [weak self] _, _ in
                    if let anime = self?.anime {
                        NineAnimator.default.user.subscribe(anime: anime)
                    } else { NineAnimator.default.user.subscribe(uncached: animeLink) }
                }
        
        return [ subscriptionAction ]
    }
}

// MARK: - Seguing
extension AnimeViewController {
    override func prepare(for segue: UIStoryboardSegue, sender: Any?) {
        // If we are presenting a reference
        if let informationViewController = segue.destination as? AnimeInformationTableViewController {
            guard let reference = anime?.trackingContext.availableReferences.first(where: { $0.parentService.isCapableOfListingAnimeInformation }) else {
                return Log.error("Attempting to present a information page without any references")
            }
            // Set reference and mark the parent view controller as matching the anime
            informationViewController.setPresenting(
                reference: reference,
                isPreviousViewControllerMatchingAnime: true
            )
        }
    }
}

// MARK: - Continuity support
extension AnimeViewController {
    private func prepareContinuity() {
        guard let anime = anime else { return }
        userActivity = Continuity.activity(for: anime)
    }
}

// MARK: - Error handling
extension AnimeViewController {
    /// Present error
    ///
    /// - parameter error: The error to present
    /// - parameter completionHandler: Called when the user selected an option.
    ///             `true` if the user wants to proceed.
    ///
    private func presentError(_ error: Error, completionHandler: ((Bool) -> Void)? = nil) {
        let alert = UIAlertController(
            error: error,
            allowRetry: error is NineAnimatorError.ContentUnavailableError, // Allow recover on ContentUnavailableError
            retryActionName: "Recover",
            source: self,
            completionHandler: completionHandler
        )
        present(alert, animated: true)
    }
    
    /// Present a list of recovery options if the anime is no longer available
    /// from this source
    private func presentRecoveryOptions(for link: AnimeLink) {
        // This may only work with the context of an navigation controller
        guard let navigationController = navigationController else {
            return dismiss(animated: true, completion: nil)
        }
        
        let alert = UIAlertController(
            title: "Recovery Options",
            message: "This anime is no longer available on \(link.source.name) from NineAnimator. You may be able to recover the item by access the web page or search on your currently selected source.",
            preferredStyle: .actionSheet
        )
        
        if let popoverController = alert.popoverPresentationController {
            popoverController.sourceView = moreOptionsButton
        }
        
        // Method 1: Accessing the page directly
        alert.addAction(UIAlertAction(
            title: "Visit Website",
            style: .default
        ) { _ in
            // Pop the current view controller
            navigationController.popViewController(animated: true)
            
            // Present the website in the next tick
            DispatchQueue.main.async {
                let pageVc = SFSafariViewController(url: link.link)
                navigationController.topViewController?.present(pageVc, animated: true, completion: nil)
            }
        })
        
        // Method 2: Search on the currently selected source
        alert.addAction(UIAlertAction(
            title: "Search on \(NineAnimator.default.user.source.name)",
            style: .default
        ) { _ in
            let searchProvider = NineAnimator.default.user.source.search(keyword: link.title)
            let searchVc = ContentListViewController.create(withProvider: searchProvider)
            navigationController.popViewController(animated: true)
            
            // Present the search view controller
            if let vc = searchVc {
                navigationController.pushViewController(vc, animated: true)
            }
        })
        
        // Cancel action
        alert.addAction(UIAlertAction(
            title: "Cancel",
            style: .cancel
        ) { _ in navigationController.popViewController(animated: true) })
        
        // Present recovery actions
        present(alert, animated: true)
    }
}

// MARK: - Helpers and stubs
fileprivate extension AnimeViewController {
    /// Retrive EpisodeLink for the specific indexPath
    private func episodeLink(for indexPath: IndexPath) -> EpisodeLink? {
        guard let episodes = anime?.episodeLinks else {
                return nil
        }
        
        switch Section(rawValue: indexPath.section)! {
        case .episodes:
            let episode: EpisodeLink
            if NineAnimator.default.user.episodeListingOrder == .reversed {
                episode = episodes[episodes.count - indexPath.item - 1]
            } else { episode = episodes[indexPath.item] }
            return episode
        case .suggestion: return presentedSuggestingEpisode
        default: return nil
        }
    }
    
    private func indexPath(for episodeLink: EpisodeLink) -> IndexPath? {
        guard var episodes = anime?.episodeLinks else {
            return nil
        }
        
        if NineAnimator.default.user.episodeListingOrder == .reversed {
            episodes = episodes.reversed()
        }
        
        if let index = episodes.firstIndex(of: episodeLink) {
            return Section.episodes[index]
        }
        
        return nil
    }
    
    // Using this enum to remind me to implement stuff when adding new sections...
    enum Section: Int, Equatable {
        case suggestion = 0
        
        case synopsis = 1
        
        case episodes = 2
        
        subscript(_ item: Int) -> IndexPath {
            return IndexPath(item: item, section: self.rawValue)
        }
        
        static func indexSet(_ sections: [Section]) -> IndexSet {
            return IndexSet(sections.map { $0.rawValue })
        }
        
        static func indexSet(_ sections: Section...) -> IndexSet {
            return IndexSet(sections.map { $0.rawValue })
        }
        
        static func == (_ lhs: Section, _ rhs: Section) -> Bool {
            return lhs.rawValue == rhs.rawValue
        }
        
        static func == (_ lhs: Int, _ rhs: Section) -> Bool {
            return lhs == rhs.rawValue
        }
        
        static func == (_ lhs: Section, _ rhs: Int) -> Bool {
            return lhs.rawValue == rhs
        }
    }
}

fileprivate extension Array where Element == AnimeViewController.Section {
    static let all: [AnimeViewController.Section] = [ .suggestion, .synopsis, .episodes ]
}
