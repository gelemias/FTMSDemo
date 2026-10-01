import SwiftUI

struct ConnectionView: View {
    @ObservedObject var viewModel: ConnectionViewModel

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                VStack(alignment: .leading, spacing: 12) {
                    MascotAnimation()
                        .frame(width: 150, height: 150)
                        .frame(maxWidth: .infinity)

                    Text("READY TO WORK?")
                        .font(.system(size: 34, weight: .black).italic())
                        .foregroundStyle(WorkoutTheme.orange.gradient)
                        .shadow(radius: 1.0, x: 1.0, y: 1.0)

                    Text("Connect your treadmill. Keep your eyes on the belt, not the screen.")
                        .font(.title3.weight(.medium))
                        .foregroundStyle(WorkoutTheme.paper)
                }

                VStack(alignment: .leading, spacing: 16) {
                    HStack {
                        Text("NEARBY MACHINES")
                            .font(.caption.weight(.black))
                            .tracking(1.2)
                            .foregroundStyle(WorkoutTheme.muted)
                        Spacer()
                        if viewModel.isScanning { ProgressView().controlSize(.small) }
                    }

                    if viewModel.discoveredTreadmills.isEmpty {
                        emptyState
                    } else {
                        VStack(spacing: 12) {
                            ForEach(viewModel.discoveredTreadmills) { treadmill in
                                Button { viewModel.connect(to: treadmill.id) } label: {
                                    HStack(spacing: 14) {
                                        Image(systemName: "figure.run")
                                            .font(.title3)
                                            .foregroundStyle(WorkoutTheme.controlAccent)
                                            .frame(width: 36, height: 36)
                                            .background(WorkoutTheme.controlAccent.opacity(0.12))
                                            .clipShape(RoundedRectangle(cornerRadius: 10))

                                        VStack(alignment: .leading, spacing: 4) {
                                            Text(treadmill.name)
                                                .font(.headline)
                                                .foregroundStyle(.primary)
                                            Text("Signal \(treadmill.rssi) dBm")
                                                .font(.subheadline)
                                                .foregroundStyle(.secondary)
                                        }

                                        Spacer()

                                        if viewModel.selectedTreadmillID == treadmill.id, viewModel.isConnecting {
                                            ProgressView()
                                        } else {
                                            Image(systemName: "chevron.right")
                                                .foregroundStyle(.tertiary)
                                        }
                                    }
                                    .padding()
                                    .background(WorkoutTheme.panel)
                                    .clipShape(RoundedRectangle(cornerRadius: 14))
                                    .panelNoise(cornerRadius: 14)
                                    .overlay(RoundedRectangle(cornerRadius: 14).stroke(WorkoutTheme.paper.opacity(0.08)))
                                }
                                .buttonStyle(.plain)
                                .disabled(viewModel.isConnecting)
                            }
                        }
                    }
                }

                Button {
                    guard !viewModel.isScanning, !viewModel.isConnecting else { return }
                    viewModel.startScan()
                } label: {
                    Label(viewModel.isScanning ? "Scanning..." : "Search Again", systemImage: "arrow.clockwise")
                        .font(.headline.weight(.bold))
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .tint(WorkoutTheme.orange.gradient)
                .foregroundStyle(WorkoutTheme.primaryButtonForeground)
                .controlSize(.large)
                .disabled(viewModel.isScanning || viewModel.isConnecting)
            }
            .padding()
        }
        .scrollContentBackground(.hidden)
        .safeAreaPadding(.bottom, 144)
        .toolbar(.hidden, for: .navigationBar)
    }

    private var emptyState: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(viewModel.isScanning ? "Looking for treadmills..." : "No treadmills found")
                .font(.headline)
            Text("Keep this screen open while we search nearby and make sure the treadmill is powered on and advertising over Bluetooth, then tap Search Again to try again.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .background(WorkoutTheme.panel)
        .clipShape(RoundedRectangle(cornerRadius: 18))
        .panelNoise(cornerRadius: 18)
    }
}
