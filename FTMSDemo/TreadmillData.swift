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
    var cadenceSpm: Int?
    var paceMinPerKm: Double?
    var heartRate: Int?
    var distanceMeters: Double?

    var distanceKilometers: Double {
        (distanceMeters ?? 0) / 1000.0
    }
}
