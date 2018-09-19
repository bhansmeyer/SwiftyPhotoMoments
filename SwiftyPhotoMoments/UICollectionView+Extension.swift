//
//  UICollectionView+Extension.swift
//  SwiftyPhotoMoments
//
//  Created by Becky Hansmeyer on 9/19/18.
//  Copyright © 2018 Becky Hansmeyer. All rights reserved.
//

import UIKit

extension UICollectionView {
    
    func indexPathsForElementsInRect(_ rect: CGRect) -> Array<IndexPath>? {
        
        let allLayoutAttributes = self.collectionViewLayout.layoutAttributesForElements(in: rect)
        if allLayoutAttributes!.count == 0 {
            return nil
        }
        
        var indexPaths: Array<IndexPath> = []
        for layoutAttributes in allLayoutAttributes! {
            let indexPath = layoutAttributes.indexPath
            indexPaths.append(indexPath)
        }
        
        return indexPaths
        
    }
    
}

