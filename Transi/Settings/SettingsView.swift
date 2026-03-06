//
//  SettingsView.swift
//  Transi
//
//  Created by magic_sk on 27/02/2026.
//

import SwiftUI

struct SettingsView: View {
    @Environment(\.dismiss) var dismiss
    @StateObject var stopsListProvider = GlobalController.stopsListProvider
    @StateObject var timetableDatabase = GlobalController.timetableDatabase

    @AppStorage(Stored.displayClockOnTable) var displayClockOnTable = true
    @AppStorage(Stored.displaySocketStatus) var displaySocketStatus = true
    @AppStorage(Stored.defaultStopId) var defaultStopId = -1
    @AppStorage(Stored.liveActivitiesSounds) var liveActivitiesSounds = true
    @AppStorage(Stored.liveActivityThreshold) var liveActivityThreshold = 200
    @AppStorage(Stored.notifyOnTimeChange) var notifyOnTimeChange = true
    @AppStorage(Stored.notifyOnDelayChange) var notifyOnDelayChange = true
    @AppStorage(Stored.notifyOnPositionChange) var notifyOnPositionChange = true
    @AppStorage(Stored.offlineTimetables) var offlineTimetables = false
    @AppStorage(Stored.tripMaxWalkDuration) var tripMaxWalkDuration = 15
    @AppStorage(Stored.tripMaxTransfers) var tripMaxTransfers = 3
    @AppStorage(Stored.tripSaveDuration) var tripSaveDuration = -1
    @AppStorage(Stored.offlineTripPlanner) var offlineTripPlanner = false
    @AppStorage(Stored.magicApiUrlOverride) var magicApiUrlOverride = ""

    @State private var showStopPicker = false
    @State private var pickedStop: Stop = .empty

    private var defaultStopName: String {
        if defaultStopId <= 0 { return "Actual location" }
        return stopsListProvider.stops.first(where: { $0.id == defaultStopId })?.name ?? "Unknown stop"
    }

    private var thresholdText: String {
        let minutes = liveActivityThreshold / 60
        let seconds = liveActivityThreshold % 60
        if minutes > 0, seconds > 0 {
            return "\(minutes) min \(seconds) sec"
        } else if minutes > 0 {
            return "\(minutes) min"
        } else {
            return "\(seconds) sec"
        }
    }

    var body: some View {
        NavigationStack {
            Form {
                displaySection
                liveActivitySection
                notificationTriggersSection
                timetablesSection
                tripPlannerSection
                developerSection
            }
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
        .sheet(isPresented: $showStopPicker) {
            StopListView(stop: $pickedStop, isPresented: $showStopPicker)
        }
        .onChange(of: pickedStop) { stop in
            if stop.id != Stop.empty.id {
                defaultStopId = stop.id
            }
        }
    }

    // MARK: - General

    private var displaySection: some View {
        Section {
            Toggle("Table clock", isOn: $displayClockOnTable)
            Toggle("Connection status bar", isOn: $displaySocketStatus)
            Button {
                showStopPicker = true
            } label: {
                HStack {
                    Text("Default stop")
                        .foregroundColor(.primary)
                    Spacer()
                    Text(defaultStopName)
                        .foregroundColor(.secondary)
                }
            }
        } header: {
            Text("General")
        } footer: {
            Text("The stop shown when the app opens.")
        }
    }

    // MARK: - Live Activity

    private var liveActivitySection: some View {
        Section("Live activity") {
            Toggle("Sound effects", isOn: $liveActivitiesSounds)
            Stepper("Notification threshold: \(thresholdText)", value: $liveActivityThreshold, in: 30...600, step: 30)
        }
    }

    // MARK: - Notification Triggers

    private var notificationTriggersSection: some View {
        Section("Notification triggers") {
            Toggle("Departure time change", isOn: $notifyOnTimeChange)
            Toggle("Delay change", isOn: $notifyOnDelayChange)
            Toggle("Vehicle position change", isOn: $notifyOnPositionChange)
        }
    }

    // MARK: - Timetables

    private var timetablesSection: some View {
        Section("Timetables") {
            Toggle("Offline timetables", isOn: $offlineTimetables)
                .onChange(of: offlineTimetables) { enabled in
                    if enabled {
                        _ = timetableDatabase.openDatabases()
                        timetableDatabase.checkAndUpdate()
                    } else {
                        timetableDatabase.closeDatabases()
                    }
                }
            Button(role: .destructive) {
                timetableDatabase.deleteDatabases()
                offlineTimetables = false
            } label: {
                Text("Delete database")
            }
        }
    }

    // MARK: - Trip Planner

    private var tripPlannerSection: some View {
        Section("Trip planner") {
            Stepper("Max walking: \(tripMaxWalkDuration) min", value: $tripMaxWalkDuration, in: 0...60)
            Stepper("Max transfers: \(tripMaxTransfers)", value: $tripMaxTransfers, in: 0...10)
            Picker("Save searched trip", selection: $tripSaveDuration) {
                Text("Until app restart").tag(0)
                Text("For 1 hour").tag(1)
                Text("For 2 hours").tag(2)
                Text("For 6 hours").tag(6)
                Text("For 12 hours").tag(12)
                Text("For a day").tag(24)
                Text("For a week").tag(168)
                Text("Forever").tag(-1)
            }
            Toggle("Offline trip planner", isOn: $offlineTripPlanner)
                .disabled(true)
            Text("Coming soon")
                .font(.caption)
                .foregroundColor(.secondary)
        }
    }
    // MARK: - Developer

    private var developerSection: some View {
        Section {
            TextField("API URL", text: $magicApiUrlOverride)
                .keyboardType(.URL)
                .textContentType(.URL)
                .autocapitalization(.none)
                .disableAutocorrection(true)
            if !magicApiUrlOverride.isEmpty {
                Button("Reset to default", role: .destructive) {
                    magicApiUrlOverride = ""
                }
            }
        } header: {
            Text("Developer")
        } footer: {
            Text("Override the Magic API base URL (e.g. http://localhost:3000). Leave empty to use the default.")
        }
    }
}

#Preview {
    SettingsView()
}
