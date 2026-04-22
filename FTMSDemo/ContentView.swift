//
//  ContentView.swift
//  FTMSDemo
//
//  Created by DELGADO Guillermo on 15/11/25.
//

import SwiftUI

struct ContentView: View {

    @StateObject var ftms = FTMSManager()

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    HStack {
                        if ftms.isLoading {
                            ProgressView()
                        }
                        Text(ftms.statusMessage)
                            .font(.headline)
                    }
                    
                    Divider()
                    
                    Group {
                        DataRow(label: "Distance", value: ftms.treadmillData.distanceMeters, unit: "m")
                        DataRow(label: "Speed", value: ftms.treadmillData.speedKmh, unit: "km/h")
                        DataRow(label: "Incline", value: ftms.treadmillData.incline, unit: "%")
                        DataRow(label: "Cadence", value: ftms.treadmillData.cadence, unit: "spm")
                        DataRow(label: "Heart Rate", value: ftms.treadmillData.heartRate, unit: "bpm")
                    }

                    Divider()
                    
                    VStack(spacing: 40) {
                        HStack(spacing: 60) {
                            Button(action: { ftms.sendTargetSpeed(kmh: 10) }) {
                                Image(systemName: "10.square")
                                    .resizable()
                                    .scaledToFit()
                                    .frame(width: 120)
                                    .tint(.green)
                            }
                            Button(action: { ftms.sendTargetSpeed(kmh: 12) }) {
                                Image(systemName: "12.square")
                                    .resizable()
                                    .scaledToFit()
                                    .frame(width: 120)
                                    .tint(.yellow)
                            }
                        }
                        HStack(spacing:60) {
                            Button(action: { ftms.sendTargetSpeed(kmh: 14) }) {
                                Image(systemName: "14.square")
                                    .resizable()
                                    .scaledToFit()
                                    .frame(width: 120)
                                    .tint(.orange)
                            }
                            Button(action: { ftms.sendTargetSpeed(kmh: 16) }) {
                                Image(systemName: "16.square")
                                    .resizable()
                                    .scaledToFit()
                                    .frame(width: 120)
                                    .tint(.red)
                                
                            }
                        }
                    }
                    
                    Spacer()
                    
                    Divider().padding()
                    
                    HStack(spacing: 120) {
                        Button(action: { ftms.startTreadmill() }) {
                            Image(systemName: "play.fill")
                                .resizable()
                                .scaledToFit()
                                .frame(width: 40)
                        }
                        .disabled(!ftms.controlPointReady)
                        Button(action: { ftms.stopTreadmill() }) {
                            Image(systemName: "stop.fill")
                                .resizable()
                                .scaledToFit()
                                .frame(width: 40)
                        }
                        .disabled(!ftms.controlPointReady)
                    }
                }
                .padding()
            }
            .navigationTitle("Hello")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .principal) {
                    VStack {
                        Text("FTMS Demo")
                            .font(.title)
                            .fontWeight(.bold)
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        ftms.startScan()
                    } label: {
                        Image(systemName: "power")
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(ftms.controlPointReady)
                }
            }
        }
    }
}

struct DataRow: View {
    let label: String
    let value: Double?
    let unit: String

    init(label: String, value: Double?, unit: String) {
        self.label = label
        self.value = value
        self.unit = unit
    }
    init(label: String, value: Int?, unit: String) {
        self.label = label
        if let v = value { self.value = Double(v) } else { self.value = nil }
        self.unit = unit
    }

    var body: some View {
        HStack {
            Text(label)
            Spacer()
            if let value = value {
                Text(String(format: "%.1f %@", value, unit))
                    .font(.headline)
                    .bold()
            } else {
                Text("--")
            }
        }
        .font(.system(size: 18))
    }
}

#Preview {
    ContentView()
}
