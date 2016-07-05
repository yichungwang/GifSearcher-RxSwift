//
//  ViewController.swift
//  GifSearcher
//
//  Created by Daydreamer on 7/2/16.
//  Copyright © 2016 Daydreamer. All rights reserved.
//

import UIKit
import RxAlamofire
import RxCocoa
import RxSwift
import Alamofire

class GifMainViewController: UIViewController, UISearchBarDelegate, GifCollectionViewLayoutDelegate, GifNetworkModelDelegate {
    
    @IBOutlet weak var collectionView: UICollectionView!
    private var searchBar: UISearchBar!
    private var reachability: NetworkReachabilityManager!
    private let disposeBag = DisposeBag()
    private var gifNetworkModel: GifNetworkModel!
    private var gifModels = [GifModel]()
    
    // to determine when to load more cells
    static let startLoadingOffset: CGFloat = 40.0
    static func shouldLoadMore(contentOffset: CGPoint, collectionView: UICollectionView) -> Bool {
        return (contentOffset.y + collectionView.frame.size.height + startLoadingOffset > collectionView.contentSize.height) && (collectionView.contentSize.height > 0)
    }
    
    // MARK: View
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
        // search bar
        searchBar = UISearchBar()
        searchBar.placeholder = "Search"
        searchBar.delegate = self
        searchBar.barTintColor = UIColor.init(white: 0.95, alpha: 1.0)
        searchBar.tintColor = UIColor.darkGrayColor()
        searchBar.layer.borderColor = UIColor.whiteColor().CGColor
        searchBar.layer.borderWidth = 0.5
        searchBar.frame = CGRectMake(0, 64, Constants.screenWidth, 44)
        self.view.addSubview(searchBar)
        
        // collection view
        if let layout = collectionView.collectionViewLayout as? GifCollectionViewLayout {
            layout.delegate = self
        }
        collectionView.backgroundColor = UIColor.whiteColor()
        
        // reactive UI
        setupRx()
        
        // reachability
        reachability = NetworkReachabilityManager()
        reachability.startListening()
        reachability.listener = { status -> Void in
            switch status {
            case .NotReachable:
                self.updateNoInternetOverlay()
            case .Reachable(.EthernetOrWiFi), .Reachable(.WWAN):
                UIView.animateWithDuration(0.4, animations: {
                    self.noInternetOverlay.backgroundColor = Constants.Green
                    }, completion: { done -> Void in
                        UIView.animateWithDuration(0.3, animations: {
                            var rect = self.noInternetOverlay.frame
                            rect.size.height = 0
                            self.noInternetOverlay.frame = rect
                        })
                })
            default: break
            }
        }
        
    }
    
    override func viewWillLayoutSubviews() {
        super.viewWillLayoutSubviews()
        self.willRotateToInterfaceOrientation(UIApplication.sharedApplication().statusBarOrientation, duration: 0)
        collectionView.contentInset = UIEdgeInsetsMake(44 + Constants.cellPadding, Constants.cellPadding, Constants.cellPadding, Constants.cellPadding)
        collectionView.scrollIndicatorInsets = UIEdgeInsetsMake(44, 0, 0, 0)
    }
    
    override func didReceiveMemoryWarning() {
        super.didReceiveMemoryWarning()
    }
    
    // MARK: Reactive UI
    
    func setupRx() {
        
        searchBar
            .rx_text
            .subscribeNext({string in
                if string.characters.count == 0 {
                    self.title = "GifSearcher"
                } else if string.characters.count > 15 {
                    self.title = string.substringWithRange(Range<String.Index>(string.startIndex.advancedBy(0)..<string.startIndex.advancedBy(14))) + "..."
                } else {
                    self.title = string
                }
            })
            .addDisposableTo(disposeBag)
        
        let searchTerms = searchBar
            .rx_text.asDriver()
            .throttle(0.5)
            .distinctUntilChanged()
        
        let loadMoreTrigger = collectionView
            .rx_contentOffset
            .flatMap { offset in
                GifMainViewController.shouldLoadMore(offset, collectionView: self.collectionView) ? Observable.just() : Observable.empty()
        }
        
        gifNetworkModel = GifNetworkModel.init(withNameObservable: searchTerms, loadMoreObservable: loadMoreTrigger)
        gifNetworkModel.delegate = self
        
        gifNetworkModel
            .rx_gifs
            .drive(collectionView.rx_itemsWithCellFactory) { (cv, i, gif) in
                let cell = cv.dequeueReusableCellWithReuseIdentifier("cell", forIndexPath: NSIndexPath.init(forItem: i, inSection: 0)) as! GifCollectionViewCell
                cell.gif = gif
                return cell
            }
            .addDisposableTo(disposeBag)
        
        collectionView
            .rx_contentOffset
            .subscribeNext { offset in
                if self.searchBar.isFirstResponder() && self.collectionView.contentSize.height > 0 {
                    self.searchBar.showsCancelButton = false
                    self.view.endEditing(true)
                }
            }
            .addDisposableTo(disposeBag)
        
        collectionView
            .rx_itemSelected
            .subscribeNext { indexPath in
                if self.searchBar.isFirstResponder() {
                    self.searchBar.showsCancelButton = false
                    self.view.endEditing(true)
                }
            }
            .addDisposableTo(disposeBag)
        
    }
    
    // MARK: Subview & Orientation
    
    func updateNoInternetOverlay() {
        self.noInternetOverlay.backgroundColor = Constants.Red
        switch UIApplication.sharedApplication().statusBarOrientation {
        case .Portrait, .PortraitUpsideDown:
            noInternetOverlay.frame = CGRectMake(0, 64 + 44, ((Constants.screenHeight < Constants.screenWidth) ? Constants.screenHeight : Constants.screenWidth), 40)
        case .LandscapeLeft, .LandscapeRight:
            noInternetOverlay.frame = CGRectMake(0, 44 + CGRectGetHeight(self.navigationController!.navigationBar.frame) + (UIDevice.currentDevice().userInterfaceIdiom == .Pad ? 20 : 0), ((Constants.screenHeight > Constants.screenWidth) ? Constants.screenHeight : Constants.screenWidth), 40)
        default:
            break
        }
    }
    
    override func willRotateToInterfaceOrientation(toInterfaceOrientation: UIInterfaceOrientation, duration: NSTimeInterval) {
        switch UIApplication.sharedApplication().statusBarOrientation {
        case .Portrait, .PortraitUpsideDown:
            searchBar.frame = CGRectMake(0, 64, ((Constants.screenHeight < Constants.screenWidth) ? Constants.screenHeight : Constants.screenWidth), 44)
        case .LandscapeLeft, .LandscapeRight:
            searchBar.frame = CGRectMake(0, CGRectGetHeight(self.navigationController!.navigationBar.frame) + (UIDevice.currentDevice().userInterfaceIdiom == .Pad ? 20 : 0), ((Constants.screenHeight > Constants.screenWidth) ? Constants.screenHeight : Constants.screenWidth), 44)
        default:
            break
        }
        if !reachability.isReachable {
            updateNoInternetOverlay()
        }
        collectionView.collectionViewLayout.invalidateLayout()
    }
    
    // MARK: UISearchBar Delegate
    
    func searchBarSearchButtonClicked(searchBar: UISearchBar) {
        view.endEditing(true)
        searchBar.showsCancelButton = false
    }
    
    func searchBarCancelButtonClicked(searchBar: UISearchBar) {
        view.endEditing(true)
        searchBar.showsCancelButton = false
    }
    
    func searchBarShouldBeginEditing(searchBar: UISearchBar) -> Bool {
        searchBar.showsCancelButton = true
        return true
    }
    
    // MARK: GifCollectionViewLayout Delegate
    
    func collectionView(collectionView: UICollectionView, heightForGifAtIndexPath indexPath: NSIndexPath, fixedWidth: CGFloat) -> CGFloat {
        let gif = gifModels[indexPath.item]
        let gifHeight = gif.height * fixedWidth / gif.width
        return gifHeight
    }
    
    // MARK: GifNetworkModel Delegate
    
    func shouldUpdateGifModels(gifmodels: [GifModel]) {
        gifModels = gifmodels
    }
    
}

