// The MIT License (MIT)
//
// Copyright (c) 2015 Joakim Gyllström
//
// Permission is hereby granted, free of charge, to any person obtaining a copy
// of this software and associated documentation files (the "Software"), to deal
// in the Software without restriction, including without limitation the rights
// to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
// copies of the Software, and to permit persons to whom the Software is
// furnished to do so, subject to the following conditions:
//
// The above copyright notice and this permission notice shall be included in all
// copies or substantial portions of the Software.
//
// THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
// IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
// FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
// AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
// LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
// OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
// SOFTWARE.

import UIKit
import Photos

final class PhotosViewController : UICollectionViewController , CustomTitleViewDelegate {
    var selectionClosure: ((_ asset: PHAsset) -> Void)?
    var deselectionClosure: ((_ asset: PHAsset) -> Void)?
    var cancelClosure: ((_ assets: [PHAsset]) -> Void)?
    var finishClosure: ((_ assets: [PHAsset], _ thumb : Bool) -> Void)?
    var selectLimitReachedClosure: ((_ selectionLimit: Int) -> Void)?
    
    var cancelBarButton: UIBarButtonItem = UIBarButtonItem(barButtonSystemItem: .cancel, target: nil, action: nil)
    let titleContentView = CustomTitleView(frame: CGRect(x: 0, y: 0, width: 120, height: 34.0))
    
    var originBarButton: SSRadioButton = SSRadioButton(type: .custom)
    var doneBarButton: UIButton = UIButton(type: .custom)
    var bottomContentView : UIView = UIView()
    
    let expandAnimator = ZoomAnimator()
    let shrinkAnimator = ZoomAnimator()
    
    private var photosDataSource: PhotoCollectionViewDataSource?
    private var albumsDataSource: AlbumTableViewDataSource
    private let cameraDataSource: CameraCollectionViewDataSource
    private var composedDataSource: ComposedCollectionViewDataSource?
    private var assetStore: AssetStore
    
    let settings: BSImagePickerSettings
    
    private let doneBarButtonTitle: String = NSLocalizedString("Done", comment: "")
    private let originBarButtonTitle: String = NSLocalizedString("Origin", comment: "")
    
    lazy var albumsViewController: AlbumsViewController = {
        let vc = AlbumsViewController()
        vc.tableView.dataSource = self.albumsDataSource
        vc.tableView.delegate = self
        return vc
    }()
    
    private lazy var previewViewContoller: PreviewViewController? = {
        return PreviewViewController(nibName: nil, bundle: nil)
    }()
    
    required init(fetchResults: [PHFetchResult<PHAssetCollection>], assetStore: AssetStore, settings aSettings: BSImagePickerSettings) {
        albumsDataSource = AlbumTableViewDataSource(fetchResults: fetchResults)
        cameraDataSource = CameraCollectionViewDataSource(settings: aSettings, cameraAvailable: UIImagePickerController.isSourceTypeAvailable(.camera))
        settings = aSettings
        self.assetStore = assetStore
        
        super.init(collectionViewLayout: GridCollectionViewLayout())
        
        PHPhotoLibrary.shared().register(self)
    }

    required init?(coder aDecoder: NSCoder) {
        fatalError("b0rk: initWithCoder not implemented")
    }
    
    deinit {
        PHPhotoLibrary.shared().unregisterChangeObserver(self)
    }
    
    override func loadView() {
        super.loadView()
        
        // Setup collection view
        collectionView?.backgroundColor = settings.backgroundColor
        collectionView?.allowsMultipleSelection = true
        
        // Set button actions and add them to navigation item
        cancelBarButton.setTitleTextAttributes([NSAttributedString.Key.foregroundColor : UIColor.white], for: .normal)
        cancelBarButton.setTitleTextAttributes([NSAttributedString.Key.foregroundColor : UIColor.gray], for: .highlighted)
        cancelBarButton.target = self
        cancelBarButton.action = #selector(PhotosViewController.cancelButtonPressed(_:))
        
        titleContentView.backgroundColor = UIColor(red: 1, green: 1, blue: 1, alpha: 0.15)
        titleContentView.translatesAutoresizingMaskIntoConstraints = false
        titleContentView.titleView.text = "最近项目"
        titleContentView.layer.masksToBounds = true
        titleContentView.layer.cornerRadius = 17.5
        titleContentView.delegate = self
        
        bottomContentView.frame = self.navigationController?.toolbar.bounds ?? CGRect(x: 0, y: 0, width:  UIScreen.main.bounds.size.width, height: 49.0)
        bottomContentView.backgroundColor = UIColor.clear
        
        doneBarButton.frame = CGRect(x: 0, y: 0, width: 80, height: 30)
        doneBarButton.backgroundColor = UIColor(red: 0, green: 186.0/255.0, blue: 90.0/255.0, alpha: 1.0)
        doneBarButton.setTitleColor(UIColor.white, for: .normal)
        doneBarButton.setTitleColor(UIColor.gray, for: .disabled)
        doneBarButton.setTitle(doneBarButtonTitle, for: .normal)
        doneBarButton.setBackgroundColor(color: UIColor(red: 0, green: 186.0/255.0, blue: 90.0/255.0, alpha: 1.0), for: .normal)
        doneBarButton.setBackgroundColor(color: UIColor.darkGray, for: .disabled)
        doneBarButton.layer.masksToBounds = true
        doneBarButton.layer.cornerRadius = 5.0
        doneBarButton.center = CGPoint(x: bottomContentView.bounds.size.width - 40, y: bottomContentView.bounds.size.height/2.0)
        doneBarButton.addTarget(self, action: #selector(PhotosViewController.doneButtonPressed(_:)), for: .touchUpInside)
        
        originBarButton.frame = CGRect(x: 60, y: 0, width: 100, height: 50)
        originBarButton.setTitle(originBarButtonTitle, for: .normal)
        originBarButton.isSelected = false
        originBarButton.circleRadius = 8.0
        originBarButton.circleColor = UIColor(red: 0, green: 186.0/255.0, blue: 90.0/255.0, alpha: 1.0)
        originBarButton.center = CGPoint(x: bottomContentView.bounds.size.width/2.0, y: bottomContentView.bounds.size.height/2.0)
        originBarButton.addTarget(self, action: #selector(PhotosViewController.originButtonPressed(_:)), for: .touchUpInside)
        
        navigationItem.leftBarButtonItem = cancelBarButton
        navigationItem.titleView = titleContentView
        
        bottomContentView.addSubview(doneBarButton)
        bottomContentView.addSubview(originBarButton)
        
        if let album = albumsDataSource.fetchResults.first?.firstObject {
            initializePhotosDataSource(album)
            updateAlbumTitle(album)
            collectionView?.reloadData()
        }
        
        // Add long press recognizer
        let longPressRecognizer = UILongPressGestureRecognizer(target: self, action: #selector(PhotosViewController.collectionViewLongPressed(_:)))
        longPressRecognizer.minimumPressDuration = 0.5
        collectionView?.addGestureRecognizer(longPressRecognizer)
        
        // Set navigation controller delegate
        navigationController?.delegate = self
        
        // Register cells
        photosDataSource?.registerCellIdentifiersForCollectionView(collectionView)
        cameraDataSource.registerCellIdentifiersForCollectionView(collectionView)
    }
    
    // MARK: Appear/Disappear
    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        updateDoneButton()
    }
    
    override func viewDidAppear(_ animated: Bool) {
        self.navigationController?.setToolbarHidden(false, animated: true)
        self.navigationController?.toolbar.layoutIfNeeded()
        self.navigationController?.toolbar.addSubview(bottomContentView)
    }
    
    // MARK: Button actions
    @objc func cancelButtonPressed(_ sender: UIBarButtonItem) {
        dismiss(animated: true, completion: nil)
        cancelClosure?(assetStore.assets)
    }
    
    @objc func doneButtonPressed(_ sender: UIButton) {
        dismiss(animated: true, completion: nil)
        finishClosure?(assetStore.assets, !originBarButton.isSelected)
    }
    
    @objc func originButtonPressed(_ sender: UIButton) {
        originBarButton.isSelected = !originBarButton.isSelected
    }
    
    func customTitleViewDidAction(_ view: CustomTitleView) {
        guard let popVC = albumsViewController.popoverPresentationController else {
            return
        }
        
        popVC.permittedArrowDirections = .up
        popVC.sourceView = view
        let senderRect = view.convert(view.frame, from: view.superview)
        let sourceRect = CGRect(x: senderRect.origin.x, y: senderRect.origin.y + (view.frame.size.height / 2), width: senderRect.size.width, height: senderRect.size.height)
        popVC.sourceRect = sourceRect
        popVC.delegate = self
        albumsViewController.tableView.reloadData()
        
        present(albumsViewController, animated: true, completion: nil)
    }
    
    @objc func albumButtonPressed(_ sender: UIButton) {
        guard let popVC = albumsViewController.popoverPresentationController else {
            return
        }
        
        popVC.permittedArrowDirections = .up
        popVC.sourceView = sender
        let senderRect = sender.convert(sender.frame, from: sender.superview)
        let sourceRect = CGRect(x: senderRect.origin.x, y: senderRect.origin.y + (sender.frame.size.height / 2), width: senderRect.size.width, height: senderRect.size.height)
        popVC.sourceRect = sourceRect
        popVC.delegate = self
        albumsViewController.tableView.reloadData()
        
        present(albumsViewController, animated: true, completion: nil)
    }
    
    @objc func collectionViewLongPressed(_ sender: UIGestureRecognizer) {
        if sender.state == .began {
            // Disable recognizer while we are figuring out location and pushing preview
            sender.isEnabled = false
            collectionView?.isUserInteractionEnabled = false
            
            // Calculate which index path long press came from
            let location = sender.location(in: collectionView)
            let indexPath = collectionView?.indexPathForItem(at: location)
            
            if let vc = previewViewContoller, let indexPath = indexPath, let cell = collectionView?.cellForItem(at: indexPath) as? PhotoCell, let asset = cell.asset {
                // Setup fetch options to be synchronous
                let options = PHImageRequestOptions()
                options.isNetworkAccessAllowed = true
                
                // Load image for preview
                if let imageView = vc.imageView {
                    PHCachingImageManager.default().requestImage(for: asset, targetSize:imageView.frame.size, contentMode: .aspectFit, options: options) { (result, _) in
                        imageView.image = result
                    }
                }
                
                // Setup animation
                expandAnimator.sourceImageView = cell.imageView
                expandAnimator.destinationImageView = vc.imageView
                shrinkAnimator.sourceImageView = vc.imageView
                shrinkAnimator.destinationImageView = cell.imageView
                navigationController?.pushViewController(vc, animated: true)
                bottomContentView.removeFromSuperview()
                navigationController?.setToolbarHidden(true, animated: true)
            }
            
            // Re-enable recognizer, after animation is done
            DispatchQueue.main.asyncAfter(deadline: DispatchTime.now() + Double(Int64(expandAnimator.transitionDuration(using: nil) * Double(NSEC_PER_SEC))) / Double(NSEC_PER_SEC), execute: { () -> Void in
                sender.isEnabled = true
                self.collectionView?.isUserInteractionEnabled = true
            })
        }
    }
    
    // MARK: Private helper methods
    func updateDoneButton() {
        if assetStore.assets.count > 0 {
            doneBarButton.setTitle("\(doneBarButtonTitle)(\(assetStore.count)/\(settings.maxNumberOfSelections))", for: .normal)
            var width : CGFloat = 90.0
            switch settings.maxNumberOfSelections {
            case 0..<10:
                width = 90.0
            case 10..<100:
                width = 110.0
            case 100..<1000:
                width = 140.0
            default:
                width = 90.0
            }
            if width != doneBarButton.frame.size.width {
                doneBarButton.frame = CGRect(x: 0, y: 0, width: width, height: 30)
                doneBarButton.center = CGPoint(x: (self.navigationController?.toolbar.bounds.size.width ?? UIScreen.main.bounds.size.width) - width/2 - 10, y: (self.navigationController?.toolbar.bounds.size.height ?? 24.5)/2.0)
            }
        } else {
            doneBarButton.setTitle(doneBarButtonTitle, for: .normal)
            if 60 != doneBarButton.frame.size.width {
                doneBarButton.frame = CGRect(x: 0, y: 0, width: 60, height: 30)
                doneBarButton.center = CGPoint(x: (self.navigationController?.toolbar.bounds.size.width ?? UIScreen.main.bounds.size.width) - 40, y: (self.navigationController?.toolbar.bounds.size.height ?? 24.5)/2.0)
            }
        }

        // Enabled?
        doneBarButton.isEnabled = assetStore.assets.count > 0
    }

    func updateAlbumTitle(_ album: PHAssetCollection) {
        guard let title = album.localizedTitle else { return }
        titleContentView.titleView.text = title
    }
    
  func initializePhotosDataSource(_ album: PHAssetCollection) {
        // Set up a photo data source with album
        let fetchOptions = PHFetchOptions()      
        fetchOptions.sortDescriptors = [
            NSSortDescriptor(key: "creationDate", ascending: false)
        ]
        fetchOptions.predicate = NSPredicate(format: "mediaType = %d", PHAssetMediaType.image.rawValue)
        initializePhotosDataSourceWithFetchResult(PHAsset.fetchAssets(in: album, options: fetchOptions))
    }
    
    func initializePhotosDataSourceWithFetchResult(_ fetchResult: PHFetchResult<PHAsset>) {
        let newDataSource = PhotoCollectionViewDataSource(fetchResult: fetchResult, assetStore: assetStore, settings: settings)
        newDataSource.imageSize = imageSize()
        titleContentView.deSelectView()
        photosDataSource = newDataSource
        // Hook up data source
        composedDataSource = ComposedCollectionViewDataSource(dataSources: [cameraDataSource, newDataSource])
        collectionView?.dataSource = composedDataSource
        collectionView?.delegate = self
    }
}

// MARK: UICollectionViewDelegate
extension PhotosViewController {
    override func collectionView(_ collectionView: UICollectionView, shouldSelectItemAt indexPath: IndexPath) -> Bool {
        // NOTE: ALWAYS return false. We don't want the collectionView to be the source of thruth regarding selections
        // We can manage it ourself.

        // Camera shouldn't be selected, but pop the UIImagePickerController!
        if let composedDataSource = composedDataSource , composedDataSource.dataSources[indexPath.section].isEqual(cameraDataSource) {
            let cameraController = UIImagePickerController()
            cameraController.allowsEditing = false
            cameraController.sourceType = .camera
            cameraController.delegate = self
            
            self.present(cameraController, animated: true, completion: nil)
            
            return false
        }

        // Make sure we have a data source and that we can make selections
        guard let photosDataSource = photosDataSource, collectionView.isUserInteractionEnabled else { return false }

        // We need a cell
        guard let cell = collectionView.cellForItem(at: indexPath) as? PhotoCell else { return false }
        let asset = photosDataSource.fetchResult.object(at: indexPath.row)

        // Select or deselect?
        if assetStore.contains(asset) { // Deselect
            // Deselect asset
            assetStore.remove(asset)

            // Update done button
            updateDoneButton()

            // Get indexPaths of selected items
            let selectedIndexPaths = assetStore.assets.compactMap({ (asset) -> IndexPath? in
                let index = photosDataSource.fetchResult.index(of: asset)
                guard index != NSNotFound else { return nil }
                return IndexPath(item: index, section: 1)
            })

            // Reload selected cells to update their selection number
            UIView.setAnimationsEnabled(false)
            collectionView.reloadItems(at: selectedIndexPaths)
            UIView.setAnimationsEnabled(true)

            cell.photoSelected = false

            // Call deselection closure
            deselectionClosure?(asset)
        } else if assetStore.count < settings.maxNumberOfSelections { // Select
            // Select asset if not already selected
            assetStore.append(asset)

            // Set selection number
            if let selectionCharacter = settings.selectionCharacter {
                cell.selectionString = String(selectionCharacter)
            } else {
                cell.selectionString = String(assetStore.count)
            }

            cell.photoSelected = true

            // Update done button
            updateDoneButton()

            // Call selection closure
            selectionClosure?(asset)
        } else if assetStore.count >= settings.maxNumberOfSelections {
            selectLimitReachedClosure?(assetStore.count)
        }

        return false
    }
    
    override func collectionView(_ collectionView: UICollectionView, willDisplay cell: UICollectionViewCell, forItemAt indexPath: IndexPath) {
        guard let cell = cell as? CameraCell else {
            return
        }
        
        cell.startLiveBackground() // Start live background
    }
}

// MARK: UIPopoverPresentationControllerDelegate
extension PhotosViewController: UIPopoverPresentationControllerDelegate {
    func adaptivePresentationStyle(for controller: UIPresentationController) -> UIModalPresentationStyle {
        return .none
    }
    
    func popoverPresentationControllerShouldDismissPopover(_ popoverPresentationController: UIPopoverPresentationController) -> Bool {
        titleContentView.deSelectView()
        return true
    }
}
// MARK: UINavigationControllerDelegate
extension PhotosViewController: UINavigationControllerDelegate {
    func navigationController(_ navigationController: UINavigationController, animationControllerFor operation: UINavigationController.Operation, from fromVC: UIViewController, to toVC: UIViewController) -> UIViewControllerAnimatedTransitioning? {
        if operation == .push {
            return expandAnimator
        } else {
            navigationController.setToolbarHidden(false, animated: true)
            navigationController.toolbar.addSubview(bottomContentView)
            return shrinkAnimator
        }
    }
}

// MARK: UITableViewDelegate
extension PhotosViewController: UITableViewDelegate {
    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        // Update photos data source
        let album = albumsDataSource.fetchResults[indexPath.section][indexPath.row]
        initializePhotosDataSource(album)
        updateAlbumTitle(album)
        collectionView?.reloadData()
        
        // Dismiss album selection
        albumsViewController.dismiss(animated: true, completion: nil)
    }
}

// MARK: Traits
extension PhotosViewController {
    override func traitCollectionDidChange(_ previousTraitCollection: UITraitCollection?) {
        super.traitCollectionDidChange(previousTraitCollection)
        
        if let collectionViewFlowLayout = collectionViewLayout as? GridCollectionViewLayout {
            let itemSpacing: CGFloat = 2.0
            let cellsPerRow = settings.cellsPerRow(traitCollection.verticalSizeClass, traitCollection.horizontalSizeClass)
            
            collectionViewFlowLayout.itemSpacing = itemSpacing
            collectionViewFlowLayout.itemsPerRow = cellsPerRow
            
            photosDataSource?.imageSize = imageSize()
            
            updateDoneButton()
        }
    }

    private func imageSize() -> CGSize {
        guard let collectionViewFlowLayout = collectionViewLayout as? GridCollectionViewLayout else { return .zero }
        let scale = UIScreen.main.scale
        let itemSize = collectionViewFlowLayout.itemSize

        return CGSize(width: itemSize.width * scale, height: itemSize.height * scale)
    }
}

// MARK: UIImagePickerControllerDelegate
extension PhotosViewController: UIImagePickerControllerDelegate {
    func imagePickerController(_ picker: UIImagePickerController, didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey : Any]) {
        guard let image = info[UIImagePickerController.InfoKey.originalImage] as? UIImage else {
            picker.dismiss(animated: true, completion: nil)
            return
        }
        
        var placeholder: PHObjectPlaceholder?
        PHPhotoLibrary.shared().performChanges({
            let request = PHAssetChangeRequest.creationRequestForAsset(from: image)
            placeholder = request.placeholderForCreatedAsset
            }, completionHandler: { success, error in
                guard let placeholder = placeholder, let asset = PHAsset.fetchAssets(withLocalIdentifiers: [placeholder.localIdentifier], options: nil).firstObject, success == true else {
                    picker.dismiss(animated: true, completion: nil)
                    return
                }
                
                DispatchQueue.main.async {
                    // TODO: move to a function. this is duplicated in didSelect
                    self.assetStore.append(asset)
                    self.updateDoneButton()
                    
                    // Call selection closure
                    self.selectionClosure?(asset)
                    
                    picker.dismiss(animated: true, completion: nil)
                }
        })
    }
    
    func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
        picker.dismiss(animated: true, completion: nil)
    }
}

// MARK: PHPhotoLibraryChangeObserver
extension PhotosViewController: PHPhotoLibraryChangeObserver {
    func photoLibraryDidChange(_ changeInstance: PHChange) {
        
        DispatchQueue.main.async(execute: { () -> Void in
            guard let photosDataSource = self.photosDataSource, let collectionView = self.collectionView else {
                return
            }
            if let photosChanges = changeInstance.changeDetails(for: photosDataSource.fetchResult as! PHFetchResult<PHObject>) {
                // Update collection view
                // Alright...we get spammed with change notifications, even when there are none. So guard against it
                let removedCount = photosChanges.removedIndexes?.count ?? 0
                let insertedCount = photosChanges.insertedIndexes?.count ?? 0
                let changedCount = photosChanges.changedIndexes?.count ?? 0
                if photosChanges.hasIncrementalChanges && (removedCount > 0 || insertedCount > 0 || changedCount > 0) {
                    // Update fetch result
                    photosDataSource.fetchResult = photosChanges.fetchResultAfterChanges as! PHFetchResult<PHAsset>
                    
                    collectionView.performBatchUpdates({
                        if let removed = photosChanges.removedIndexes {
                            collectionView.deleteItems(at: removed.bs_indexPathsForSection(1))
                        }
                        
                        if let inserted = photosChanges.insertedIndexes {
                            collectionView.insertItems(at: inserted.bs_indexPathsForSection(1))
                        }
                        
                        if let changed = photosChanges.changedIndexes {
                            collectionView.reloadItems(at: changed.bs_indexPathsForSection(1))
                        }
                    })
                    
                    // Changes is causing issues right now...fix me later
                    // Example of issue:
                    // 1. Take a new photo
                    // 2. We will get a change telling to insert that asset
                    // 3. While it's being inserted we get a bunch of change request for that same asset
                    // 4. It flickers when reloading it while being inserted
                    // TODO: FIX
                    //                    if let changed = photosChanges.changedIndexes {
                    //                        print("changed")
                    //                        collectionView.reloadItemsAtIndexPaths(changed.bs_indexPathsForSection(1))
                    //                    }
                } else if photosChanges.hasIncrementalChanges == false {
                    // Update fetch result
                    photosDataSource.fetchResult = photosChanges.fetchResultAfterChanges as! PHFetchResult<PHAsset>
                    
                    // Reload view
                    collectionView.reloadData()
                }
            }
        })
        
        
        // TODO: Changes in albums
    }
}