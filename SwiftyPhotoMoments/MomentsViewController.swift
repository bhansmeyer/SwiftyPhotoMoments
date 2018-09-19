//
//  MomentsViewController.swift
//  SwiftyPhotoMoments
//
//  Created by Becky Hansmeyer on 9/19/18.
//  Copyright © 2018 Becky Hansmeyer. All rights reserved.
//

import UIKit
import Photos

class MomentsViewController: UIViewController {
    
    let reuseIdentifier = "Cell"
    
    let numberOfThumbnailsPerRow: CGFloat = 4.0
    let spaceBetweenThumbnails: CGFloat = 2.0
    var thumbnailSize: CGSize!
    var previousPreheatRect: CGRect = CGRect.zero
    
    var collectionFetchResult: PHFetchResult<PHAssetCollection>?
    var momentsFetchResults: [PHFetchResult<PHAsset>?] = []
    var imageManager: PHCachingImageManager!
    
    var backgroundFetchInProgress = false
    var completedBackgroundFetch = false
    var batchSize: Int = 25
    var scrollFlag: Bool = true

    @IBOutlet weak var collectionView: UICollectionView!
    @IBOutlet weak var collectionViewFlowLayout: UICollectionViewFlowLayout!
    
    
    // MARK: - ViewController Life Cycle
    
    override func viewDidLoad() {
        super.viewDidLoad()

        PHPhotoLibrary.shared().register(self)
        collectionView.delegate = self
        collectionView.dataSource = self
        
        collectionView?.allowsMultipleSelection = true
        collectionView.isAccessibilityElement = false
        collectionView.shouldGroupAccessibilityChildren = true
        
    }
    
    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        
        DispatchQueue.main.async {
            self.requestPhotoLibraryAuthorization()
        }
        
    }
    
    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        updateCachedAssets()
    }
    
    
    deinit {
        PHPhotoLibrary.shared().unregisterChangeObserver(self)
    }
    
    // MARK: - Asset fetching
    
    func requestPhotoLibraryAuthorization() {
        if PHPhotoLibrary.authorizationStatus() == PHAuthorizationStatus.authorized {
            print("Authorized")
            self.imageManager = PHCachingImageManager()
            fetchPhotoLibrary()
        } else if PHPhotoLibrary.authorizationStatus() == PHAuthorizationStatus.notDetermined {
            PHPhotoLibrary.requestAuthorization({ (status) -> Void in
                self.imageManager = PHCachingImageManager()
                if status == PHAuthorizationStatus.authorized {
                    self.fetchPhotoLibrary()
                }
            })
        } else {
            print("Photo library access not authorized.")
        }
    }
    
    func fetchPhotoLibrary() {
        
        // Determine what size thumbnails to request
        let scale = UIScreen.main.scale
        let cellSize = (self.collectionViewFlowLayout as UICollectionViewFlowLayout).itemSize
        thumbnailSize = CGSize(width: cellSize.width * scale, height: cellSize.height * scale)
        
        // Fetch Moment titles and location information
        fetchMomentCollections()
        
        // Fetch assets for each moment collection if needed
        if !backgroundFetchInProgress && !completedBackgroundFetch {
            
            // Fetch first 25 moments
            fetchMostRecentMoments {
                self.collectionView?.reloadData()
                self.updateCachedAssets()
                self.checkScrollPosition()
                
                // Start a background fetch for the rest of the user's moments
                self.fetchAllMoments()
            }
        }
    }
    
    func fetchMomentCollections() {
        print("Fetching moment collections...")
        let momentCollections = PHAssetCollection.fetchMoments(with: nil)
        self.collectionFetchResult = momentCollections
        self.momentsFetchResults = [PHFetchResult<PHAsset>?](repeating: nil, count: momentCollections.count)
    }
    
    func fetchMostRecentMoments(completion: @escaping () -> Void) {
        guard let momentCollections = self.collectionFetchResult else { return }
        print("Fetching most recent moments...")
        let count = (momentCollections.count > batchSize) ? (momentCollections.count - batchSize) : 0
        DispatchQueue.main.async {
            for i in (count..<momentCollections.count).reversed() {
                let moment = momentCollections[i]
                let assets = PHAsset.fetchAssets(in: moment, options: nil)
                self.momentsFetchResults.remove(at: i)
                self.momentsFetchResults.insert(assets, at: i)
            }
            completion()
        }
    }
    
    func fetchAllMoments() {
        self.collectionView.performBatchUpdates({
            self.performBackgroundFetch {
                print("Completed background fetch.")
                self.backgroundFetchInProgress = false
                self.completedBackgroundFetch = true
                self.reloadDataAndRestoreScrollPosition()
            }
        }, completion: { (completed) in
            if completed {
                print("Completed batch updates.")
            }
        })
    }
    
    func performBackgroundFetch(completion: @escaping () -> Void) {
        guard let momentCollections = collectionFetchResult else { return }
        let momentsRemaining = (momentCollections.count > batchSize) ? (momentCollections.count - batchSize) : momentCollections.count
        
        guard momentsRemaining != 0 else { return }
        
        backgroundFetchInProgress = true
        
        DispatchQueue.global(qos: .userInitiated).async {
            for i in (0..<momentsRemaining).reversed() {
                let moment = momentCollections[i]
                let assets = PHAsset.fetchAssets(in: moment, options: nil)
                self.momentsFetchResults.remove(at: i)
                self.momentsFetchResults.insert(assets, at: i)
            }
            DispatchQueue.main.async {
                completion()
            }
        }
    }
    
    // MARK: - Scrolling
    
    func checkScrollPosition() {
        if self.scrollFlag {
            self.scrollToBottom()
        }
    }
    
    func scrollToBottom() {
        // This determines the last section that actually has assets in it. If you use a predicate when fetching, some sections may be empty.
        
        guard collectionView.numberOfSections > 0 else { return }
        var lastSection: Int = 0
        if collectionView.numberOfSections > 1 {
            for (index, fetchResult) in momentsFetchResults.enumerated().reversed() {
                if (fetchResult?.count ?? 0) > 0 && index < collectionView.numberOfSections {
                    lastSection = index
                    print("Last section = \(lastSection)")
                    break
                }
            }
        }
        guard collectionView.numberOfItems(inSection: lastSection) > 0 else { return }
        
        print("Scrolling to bottom...")
        let lastItemIndexPath = IndexPath(item: collectionView.numberOfItems(inSection: lastSection) - 1, section: lastSection)
        collectionView.scrollToItem(at: lastItemIndexPath, at: .bottom, animated: false)
    }
    
    func reloadDataAndRestoreScrollPosition() {
        // Attempts to restore the user's scroll position if they're scrolling when the background fetch completes and makes sure items stay selected
        let indexPath = self.collectionView.indexPathsForVisibleItems.last
        let selectedIndexPaths = self.collectionView.indexPathsForSelectedItems
        self.collectionView.reloadData()
        if selectedIndexPaths != nil && (selectedIndexPaths?.count)! > 0 {
            for index in selectedIndexPaths! {
                collectionView.selectItem(at: index, animated: false, scrollPosition: [])
            }
        }
        if indexPath != nil {
            self.collectionView.scrollToItem(at: indexPath!, at: .bottom, animated: false)
            self.updateCachedAssets()
        }
    }
    
    
}




extension MomentsViewController: UICollectionViewDataSource, UICollectionViewDelegate {
    
    func numberOfSections(in collectionView: UICollectionView) -> Int {
        if let collections = self.collectionFetchResult {
            return collections.count
        } else {
            return 0
        }
    }
    
    func collectionView(_ collectionView: UICollectionView, numberOfItemsInSection section: Int) -> Int {
        return momentsFetchResults[section]?.count ?? 0
    }
    
    func collectionView(_ collectionView: UICollectionView, cellForItemAt indexPath: IndexPath) -> UICollectionViewCell {
        
        let cell = collectionView.dequeueReusableCell(withReuseIdentifier: reuseIdentifier, for: indexPath) as! AssetCollectionViewCell
        
        guard let moment = self.momentsFetchResults[indexPath.section] else { return cell }
        
        let asset = moment[indexPath.item]
        cell.assetID = asset.localIdentifier
        
        
        self.imageManager.requestImage(for: asset, targetSize: self.thumbnailSize, contentMode: PHImageContentMode.aspectFit, options: nil, resultHandler: {
            result, info in
            
            if cell.assetID == asset.localIdentifier {
                cell.imageView.image = result
            }
        })
        
        return cell
    }
    
    func collectionView(_ collectionView: UICollectionView, viewForSupplementaryElementOfKind kind: String, at indexPath: IndexPath) -> UICollectionReusableView {
        
        if let sectionHeader = collectionView.dequeueReusableSupplementaryView(ofKind: kind, withReuseIdentifier: "sectionHeader", for: indexPath) as? MomentCollectionReusableView {
            var startDateString: String?
            var longDateString = ""
            
            if let startDate = collectionFetchResult?[indexPath.section].startDate {
                startDateString = DateFormatter.localizedString(from: startDate, dateStyle: .medium, timeStyle: .none)
                longDateString = DateFormatter.localizedString(from: startDate, dateStyle: .long, timeStyle: .none)
            }
            sectionHeader.titleLabel.text = collectionFetchResult?[indexPath.section].localizedTitle ?? longDateString
            var dateString: String?
            if startDateString != nil {
                dateString = startDateString!
            }
            let locations = collectionFetchResult?[indexPath.section].localizedLocationNames.joined(separator: ", ")
            var separatorString: String?
            if locations != "" {
                separatorString = " ・ "
            }
            sectionHeader.locationLabel.text =  (dateString ?? "") + (separatorString ?? "") + (locations ?? "")
            return sectionHeader
        }
        
        return UICollectionReusableView()
    }
    
}


extension MomentsViewController: UICollectionViewDelegateFlowLayout {
    
    func collectionView(_ collectionView: UICollectionView, layout collectionViewLayout: UICollectionViewLayout, sizeForItemAt indexPath: IndexPath) -> CGSize {
        let interiorPadding = spaceBetweenThumbnails * (numberOfThumbnailsPerRow - 1)
        let sideSize = (UIScreen.main.bounds.width - interiorPadding) / numberOfThumbnailsPerRow
        return CGSize(width: sideSize, height: sideSize)
    }
    
}


extension MomentsViewController: UIScrollViewDelegate {
    
    func scrollViewDidScroll(_ scrollView: UIScrollView) {
        updateCachedAssets()
        
        // If a user scrolls to the top while Moments are still being fetched, reload the collection view and attempt to restore their scroll position
        guard scrollView.contentOffset.y == 0, backgroundFetchInProgress else { return }
        DispatchQueue.main.async {
            self.reloadDataAndRestoreScrollPosition()
        }
    }
    
}


extension MomentsViewController: PHPhotoLibraryChangeObserver {
    
    func photoLibraryDidChange(_ changeInstance: PHChange) {
        
        // Implentation needed here
    }
    
}

extension MomentsViewController {
    
    // MARK: - Image Caching
    
    func resetCachedAssets() {
        self.imageManager.stopCachingImagesForAllAssets()
        self.previousPreheatRect = CGRect.zero
    }
    
    func updateCachedAssets() {
        
        let isViewVisible = self.isViewLoaded && self.view.window != nil
        if !isViewVisible {
            return
        }
        
        // Preheat rect is 2x the height of visible rect
        var preheatRect: CGRect = self.collectionView!.bounds
        preheatRect = preheatRect.insetBy(dx: 0.0, dy: -0.5 * preheatRect.height)
        
        // Check to see if collection view rect is way different than preheated area
        let delta = abs(preheatRect.midY - self.previousPreheatRect.midY)
        if (delta > self.collectionView!.bounds.height / 3.0) {
            
            // Figure out which assets to start/stop caching
            var addedIndexPaths: Array<IndexPath> = []
            var removedIndexPaths: Array<IndexPath> = []
            
            self.computeDifferenceBetweenRect(self.previousPreheatRect, newRect: preheatRect, removedHandler: {
                rect in
                
                if let indexPaths = self.collectionView!.indexPathsForElementsInRect(rect) {
                    removedIndexPaths.append(contentsOf: indexPaths)
                }
                
            }, addedHandler: {
                rect in
                
                if let indexPaths = self.collectionView!.indexPathsForElementsInRect(rect) {
                    addedIndexPaths.append(contentsOf: indexPaths)
                }
            })
            
            // Update the assets for PHCachingImageManager
            if let assetsToStartCaching = self.assetsAtIndexPaths(addedIndexPaths) {
                self.imageManager.startCachingImages(for: assetsToStartCaching , targetSize: thumbnailSize, contentMode: .aspectFit, options: nil)
            }
            if let assetsToStopCaching = self.assetsAtIndexPaths(removedIndexPaths) {
                self.imageManager.stopCachingImages(for: assetsToStopCaching , targetSize: thumbnailSize, contentMode: .aspectFit, options: nil)
            }
            
            // Store new preheat rect to compare against
            self.previousPreheatRect = preheatRect
        }
    }
    
    func computeDifferenceBetweenRect(_ oldRect: CGRect, newRect: CGRect, removedHandler: (_ removedRect:CGRect) -> Void, addedHandler: (_ addedRect: CGRect) -> Void) {
        if newRect.intersects(oldRect) {
            let oldMaxY = oldRect.maxY
            let oldMinY = oldRect.minY
            let newMaxY = newRect.maxY
            let newMinY = newRect.minY
            
            if (newMaxY > oldMaxY) {
                let rectToAdd = CGRect(x: newRect.origin.x, y: oldMaxY, width: newRect.size.width, height: (newMaxY - oldMaxY))
                addedHandler(rectToAdd)
            }
            
            if (oldMinY > newMinY) {
                let rectToAdd = CGRect(x: newRect.origin.x, y: newMinY, width: newRect.size.width, height: (oldMinY - newMinY))
                addedHandler(rectToAdd)
            }
            
            if (newMaxY < oldMaxY) {
                let rectToRemove = CGRect(x: newRect.origin.x, y: newMaxY, width: newRect.size.width, height: (oldMaxY - newMaxY))
                removedHandler(rectToRemove)
            }
            
            if (oldMinY < newMinY) {
                let rectToRemove = CGRect(x: newRect.origin.x, y: oldMinY, width: newRect.size.width, height: (newMinY - oldMinY))
                removedHandler(rectToRemove)
            }
            
        } else {
            addedHandler(newRect)
            removedHandler(oldRect)
        }
    }
    
    func assetsAtIndexPaths(_ indexPaths: Array<IndexPath>) -> Array<PHAsset>? {
        if (indexPaths.count == 0) {
            return nil
        }
        var assets: Array<PHAsset> = []
        for indexPath in indexPaths {
            if indexPath.section < momentsFetchResults.count {
                if let moment = momentsFetchResults[indexPath.section] {
                    let asset: PHAsset = moment[indexPath.item]
                    assets.append(asset)
                }
            }
        }
        return assets
    }
}
