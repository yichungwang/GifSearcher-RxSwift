//
//  GifNewworkModel.swift
//  GifSearcher
//
//  Created by Daydreamer on 7/4/16.
//  Copyright © 2016 Daydreamer. All rights reserved.
//

import Foundation
import RxAlamofire
import RxCocoa
import RxSwift
import SwiftyJSON

protocol GifNetworkModelDelegate { // use to track gif size dynamically
    func shouldUpdateGifModels(gifmodels: [GifModel])
}

enum SearchGifsResponse { // result response type
    case Gifs(gifs: [GifModel])
    case ServiceOfflineOrError
}

class GifNetworkModel {
    
    var delegate: GifNetworkModelDelegate!
    var rx_gifs: Driver<[GifModel]>!
    let activityIndicator = ActivityIndicator()
    private var searchTerms: Driver<String>
    private let baseURL = "https://api.giphy.com/"
    private let giphyAPIKey = "dc6zaTOxFJmzC"
    private let limit = 25
    private var currentOffset = 0
    private var previousOffset = -1
    private let reachabilityService: ReachabilityService = try! DefaultReachabilityService()
    
    init(withNameObservable nameObservable: Driver<String>, loadMoreObservable: Observable<Void>) {
        searchTerms = nameObservable
        rx_gifs = fetchGifs(loadMoreObservable)
    }
    
    func fetchGifs(loadMoreObservable: Observable<Void>) -> Driver<[GifModel]> {
        
        return searchTerms
            .flatMapLatest { terms -> Driver<[GifModel]> in
                return self.initload(terms, loadMoreTrigger: loadMoreObservable).asDriver(onErrorJustReturn: [])
            }
        
    }
    
    private func initload(terms: String, loadMoreTrigger: Observable<Void>) -> Observable<[GifModel]> {
        
        // refresh everytime search terms changed
        previousOffset = -1
        currentOffset = 0
        return load([], terms: terms, loadMoreTrigger: loadMoreTrigger).startWith([])
        
    }
    
    private func load(loadedGifs: [GifModel], terms: String, loadMoreTrigger: Observable<Void>) -> Observable<[GifModel]> {
        
        return request(terms).flatMapLatest { searchResponse -> Observable<[GifModel]> in
            
            switch searchResponse {
                
            case .ServiceOfflineOrError:
                // something is wrong return just loaded gifs so far
                return Observable.just(loadedGifs)
                
            case .Gifs(let gifs):
                
                var newgifs = gifs
                // filter out duplicate
                for newgif in newgifs {
                    if loadedGifs.contains({ $0.id == newgif.id }) {
                        if let i = newgifs.indexOf({ $0.id == newgif.id }) {
                            newgifs.removeAtIndex(i)
                        }
                    }
                }
                
                self.previousOffset = self.currentOffset
                self.currentOffset = self.currentOffset + newgifs.count
                var loadedgifs = loadedGifs
                loadedgifs.appendContentsOf(newgifs)
                
                self.delegate.shouldUpdateGifModels(loadedgifs)
                
                guard self.currentOffset <= Constants.searchResultsLimit && self.previousOffset != self.currentOffset else {
                    return Observable.just(loadedgifs)
                }
                
                return [
                    Observable.just(loadedgifs),
                    Observable.never().takeUntil(loadMoreTrigger),
                    // load more gifs if triggers
                    self.load(loadedgifs, terms: terms, loadMoreTrigger: loadMoreTrigger)
                    ].concat()
                
            }
            
        }
        
    }
    
    private func request(terms: String) -> Observable<SearchGifsResponse> {
        
        return RxAlamofire
            .requestJSON(.GET, self.baseURL + ((terms == "") ? "v1/gifs/trending" : "v1/gifs/search"), parameters: ["api_key" : self.giphyAPIKey, "limit" : "\(self.limit)", "offset" : "\(self.currentOffset)", "rating": ((terms == "") ? "" : Constants.preferredSearchRating), "q" : terms], encoding: .URL, headers: nil)
            .retry(3)
            .debug()
            // track sequence computation from RXSwift example
            .trackActivity(self.activityIndicator)
            // make sure the request don't block UI
            .observeOn(ConcurrentDispatchQueueScheduler(globalConcurrentQueueQOS: .Background))
            .map { (response, json) -> SearchGifsResponse in
                let resultJSON = JSON.init(json)
                if let gifdata = resultJSON["data"].array {
                    var gifs = [GifModel]()
                    for gifJSON in gifdata {
                        let gif = GifModel.init(data: gifJSON)
                        gifs.append(gif)
                    }
                    return .Gifs(gifs: gifs)
                } else {
                    return .Gifs(gifs: [])
                }
            }
            // retryOnBecomesReachable from RXSwift example
            .retryOnBecomesReachable(.ServiceOfflineOrError , reachabilityService: reachabilityService)
        
    }
    
}