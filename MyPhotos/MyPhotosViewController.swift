//
//  MyPhotosViewController.swift
//  MyPhotos
//
//  Created by Yun Ha on 2024/09/07.
//

import UIKit
import Photos
import PhotosUI

final class MyPhotosViewController: UIViewController {

    @IBOutlet weak var photosRequestButton: UIButton!
    @IBOutlet weak var columnChangeButton: UIButton!
    @IBOutlet weak var imageScrollView: UIScrollView!
    @IBOutlet weak var imageView: UIImageView!
    @IBOutlet weak var collectionView: UICollectionView!
    
    private let collectionViewSpacing: CGFloat = 2
    private var columnCount: Int = 3
    
    private var fetchResult = PHFetchResult<PHAsset>()
    private let imageManager = PHCachingImageManager()
    private let fetchOptions: PHFetchOptions = {
        let fetchOptions = PHFetchOptions()
        fetchOptions.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: false)]
        return fetchOptions
    }()
    private var photoAccessStatus: PhotoAccessStatus?
    private var checkedPhotoAuthorization = false
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
        initImageScrollView()
        initCollectionView()
        initColumnChangeButton()
        initPhotoLibrary()
    }
    
    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        checkPhotoAuthorizationAndFetchPhotosIfNeeded()
        updatePhotosRequestButton()
        if photoAccessStatus == .notDetermined {
            requestPhotoAuthorizationAndFetchPhotos()
        }
    }
    
    private func initImageScrollView() {
        imageScrollView.delegate = self
        imageScrollView.minimumZoomScale = 1
        imageScrollView.maximumZoomScale = 2
    }

    private func initCollectionView() {
        collectionView.register(ThumbnailCell.self, forCellWithReuseIdentifier: ThumbnailCell.defaultReuseIdentifier)
        collectionView.dataSource = self
        collectionView.delegate = self
    }
    
    private func initColumnChangeButton() {
        let actions: [UIAction] = [3, 4, 5]
            .map { column in
                return UIAction(title: "\(column)단 보기") { _ in
                    self.changeColumnCountAndReload(column: column)
                }
            }
        columnChangeButton.menu = UIMenu(children: actions)
        columnChangeButton.showsMenuAsPrimaryAction = true
    }
    
    private func initPhotoLibrary() {
        PHPhotoLibrary.shared().register(self)
    }
    
    private func changeColumnCountAndReload(column: Int) {
        DispatchQueue.main.async {
            self.columnCount = column
            self.collectionView.reloadData()
        }
    }
    
    private func checkPhotoAuthorizationAndFetchPhotosIfNeeded() {
        let readWriteStatus = PHPhotoLibrary.authorizationStatus(for: .readWrite)
        switch readWriteStatus {
        case .notDetermined:
            photoAccessStatus = .notDetermined
        case .restricted, .denied:
            photoAccessStatus = .notAllow
        case .authorized:
            photoAccessStatus = .allow
            fetchPhotos()
        case .limited:
            photoAccessStatus = .limited
            if checkedPhotoAuthorization == false { // 처음 이후에는 photoLibraryDidChange에서 감지
                fetchPhotos()
            }
        @unknown default:
            photoAccessStatus = .notAllow
        }
        
        checkedPhotoAuthorization = true
    }
    
    private func updatePhotosRequestButton() {
        guard let photoAccessStatus = photoAccessStatus else { return }
        
        switch photoAccessStatus {
        case .notDetermined:
            photosRequestButton.setTitle("사진 가져오기", for: .normal)
        case .allow:
            break
        case .limited:
            photosRequestButton.setTitle("사진 추가하기", for: .normal)
        case .notAllow:
            photosRequestButton.setTitle("권한 설정하기", for: .normal)
        }
        photosRequestButton.isHidden = photoAccessStatus == .allow
    }
    
    private func requestPhotoAuthorizationAndFetchPhotos() {
        PHPhotoLibrary.requestAuthorization(for: .readWrite) { status in
            switch status {
            case .notDetermined:
                self.photoAccessStatus = .notDetermined
            case .restricted, .denied:
                self.photoAccessStatus = .notAllow
            case .authorized:
                self.photoAccessStatus = .allow
            case .limited:
                self.photoAccessStatus = .limited
            @unknown default:
                fatalError()
            }
            DispatchQueue.main.async {
                self.updatePhotosRequestButton()
            }
            
            if status == .authorized || status == .limited {
                self.fetchPhotos()
            }
        }
    }
    
    private func presentLimitedLibraryPickerAndFetchPhotos() {
        PHPhotoLibrary.shared().presentLimitedLibraryPicker(from: self)
    }
    
    private func openPhotosSettings() {
        guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
        UIApplication.shared.open(url)
    }
    
    @IBAction func photosRequestButtonDidTap(_ sender: UIButton) {
        guard let photoAccessStatus = photoAccessStatus else { return }
        
        switch photoAccessStatus {
        case .notDetermined:
            requestPhotoAuthorizationAndFetchPhotos()
        case .allow:
            break
        case .limited:
            presentLimitedLibraryPickerAndFetchPhotos()
        case .notAllow:
            openPhotosSettings()
        }
    }
    
    private func fetchPhotos() {
        DispatchQueue.main.async {
            self.fetchResult = PHAsset.fetchAssets(with: .image, options: self.fetchOptions)
            self.collectionView.reloadData()
        }
    }
}


// MARK: - UICollectionViewDataSource

extension MyPhotosViewController: UICollectionViewDataSource {
    
    func collectionView(_ collectionView: UICollectionView, numberOfItemsInSection section: Int) -> Int {
        return fetchResult.count
    }
    
    func collectionView(_ collectionView: UICollectionView, cellForItemAt indexPath: IndexPath) -> UICollectionViewCell {
        let cell = collectionView.dequeueReusableCell(withReuseIdentifier: ThumbnailCell.defaultReuseIdentifier, for: indexPath) as! ThumbnailCell
        
        let asset = fetchResult[indexPath.item]
        imageManager.requestImage(for: asset, targetSize: cell.bounds.size, contentMode: .aspectFill, options: nil) { image, _ in
            cell.setImage(image)
        }
        
        return cell
    }
}


// MARK: - UICollectionViewDelegateFlowLayout

extension MyPhotosViewController: UICollectionViewDelegateFlowLayout {
    
    func collectionView(_ collectionView: UICollectionView, didSelectItemAt indexPath: IndexPath) {
        let asset = fetchResult[indexPath.item]
        imageManager.requestImage(for: asset, targetSize: imageView.bounds.size, contentMode: .aspectFill, options: nil) { [weak self] image, _ in
            self?.imageView.image = image
        }
        imageScrollView.zoomScale = 1
    }
    
    func collectionView(_ collectionView: UICollectionView, layout collectionViewLayout: UICollectionViewLayout, sizeForItemAt indexPath: IndexPath) -> CGSize {
        let spacing: CGFloat = collectionViewSpacing * CGFloat(columnCount - 1)
        let width = (view.frame.width - spacing - 0.5) / CGFloat(columnCount)
        return CGSize(width: width, height: width)
    }
    
    func collectionView(_ collectionView: UICollectionView, layout collectionViewLayout: UICollectionViewLayout, minimumInteritemSpacingForSectionAt section: Int) -> CGFloat {
        return collectionViewSpacing
    }
    
    func collectionView(_ collectionView: UICollectionView, layout collectionViewLayout: UICollectionViewLayout, minimumLineSpacingForSectionAt section: Int) -> CGFloat {
        return collectionViewSpacing
    }
}


// MARK: - PHPhotoLibraryChangeObserver

extension MyPhotosViewController: PHPhotoLibraryChangeObserver {
    
    func photoLibraryDidChange(_ changeInstance: PHChange) {
        guard let changeDetails = changeInstance.changeDetails(for: fetchResult) else { return }
        
        DispatchQueue.main.async {
            self.fetchResult = changeDetails.fetchResultAfterChanges
            self.collectionView.reloadData()
        }
    }
}


// MARK: - UIScrollViewDelegate

extension MyPhotosViewController: UIScrollViewDelegate {
    
    func viewForZooming(in scrollView: UIScrollView) -> UIView? {
        return imageView
    }
}


// MARK: - PhotoAccessStatus

extension MyPhotosViewController {
    
    enum PhotoAccessStatus {
        case notDetermined
        case allow
        case limited
        case notAllow
    }
}
