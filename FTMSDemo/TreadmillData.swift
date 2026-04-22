//
//  TreadmillData.swift
//  FTMSDemo
//
//  Created by DELGADO Guillermo on 15/11/25.
//

import Foundation

struct TreadmillData: Identifiable {
    let id = UUID()

    var speedKmh: Double?
    var incline: Double?
    var cadence: Int?
    var heartRate: Int?
    var distanceMeters: Double?
}
