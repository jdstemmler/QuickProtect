import SwiftUI
import AppKit

// MARK: - Pop-ups tab: where detection pop-ups appear, and which cameras and
// detections open one.

extension SettingsView {

    var popUpsTab: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("A camera's floating window opens when it detects something you chose, and closes again after the detection ends. A window you pinned yourself is highlighted instead, and is never closed.")
                .font(.system(size: 11))
                .foregroundColor(palette.subtext)
                .fixedSize(horizontal: false, vertical: true)
            popUpPlacementSection
            popUpTimingSection
            popUpCamerasSection
        }
    }

    private var popUpPlacementSection: some View {
        AuroraSettingsSection(String(localized: "Placement")) {
            AuroraSettingsRow(String(localized: "Display")) {
                Picker("", selection: $settings.popUpDisplay) {
                    Text("Main display").tag("")
                    ForEach(popUpDisplayNames, id: \.self) { Text($0).tag($0) }
                }
                .labelsHidden()
                .fixedSize()
            }
            AuroraSettingsRow(String(localized: "Corner")) {
                Picker("", selection: $settings.popUpCorner) {
                    ForEach(PopUpCorner.allCases, id: \.self) { Text($0.displayName).tag($0) }
                }
                .labelsHidden()
                .fixedSize()
            }
            AuroraSettingsRow(String(localized: "Size")) {
                AuroraSegmented(options: PopUpSize.allCases.map { ($0.displayName, $0) },
                                selection: $settings.popUpSize)
            }
            AuroraSettingsRow(
                String(localized: "Stack"),
                hint: String(localized: "Pop-ups line up from the corner in the order they appear, and close up when one goes away. Moving or resizing one takes it out of the line until it closes."),
                isLast: true
            ) {
                AuroraSegmented(options: PopUpDirection.allCases.map { ($0.displayName, $0) },
                                selection: $settings.popUpDirection)
            }
        }
    }

    private var popUpTimingSection: some View {
        AuroraSettingsSection {
            AuroraSettingsRow(String(localized: "Stay open after a detection ends"), labelExpands: true) {
                AuroraSegmented(
                    options: [("5 s", 5), ("15 s", 15), ("30 s", 30), ("60 s", 60)],
                    selection: $settings.popUpLingerSeconds
                )
            }
            AuroraSettingsRow(
                String(localized: "Sound"),
                hint: String(localized: "Played once when a chosen detection starts."),
                labelExpands: true
            ) {
                Picker("", selection: $settings.popUpSound) {
                    Text("None").tag("")
                    ForEach(AppSettings.popUpSoundNames, id: \.self) { Text($0).tag($0) }
                }
                .labelsHidden()
                .fixedSize()
                // Preview the choice.
                .onChange(of: settings.popUpSound) { NSSound(named: $0)?.play() }
            }
            AuroraSettingsRow(
                String(localized: "Pause pop-ups"),
                hint: String(localized: "Stops every camera's pop-ups without changing the choices below."),
                isLast: true,
                labelExpands: true
            ) {
                Toggle("", isOn: $settings.popUpsPaused)
                    .toggleStyle(.switch)
                    .labelsHidden()
            }
        }
    }

    /// The saved display stays listed while it is disconnected, so the choice
    /// isn't silently lost.
    private var popUpDisplayNames: [String] {
        var names = NSScreen.screens.map(\.localizedName)
        if !settings.popUpDisplay.isEmpty, !names.contains(settings.popUpDisplay) {
            names.append(settings.popUpDisplay)
        }
        return names
    }

    @ViewBuilder
    private var popUpCamerasSection: some View {
        let cams = settings.orderedCameras(service.cameras)
        AuroraSettingsSection(String(localized: "Cameras")) {
            if cams.isEmpty {
                AuroraSettingsRow(isLast: true) {
                    Text("No cameras discovered yet. Run Test Connection on the Connection tab.")
                        .font(.system(size: 12))
                        .foregroundColor(palette.subtext)
                }
            } else {
                ForEach(Array(cams.enumerated()), id: \.element.id) { idx, cam in
                    PopUpCameraRow(
                        camera: cam,
                        enabled: settings.popUpEnabled(for: cam.id),
                        triggers: settings.popUpTriggers(for: cam.id),
                        isLast: idx == cams.count - 1,
                        onToggle: { settings.setPopUpEnabled($0, for: cam.id) },
                        onSetTrigger: { trigger, on in
                            var triggers = settings.popUpTriggers(for: cam.id)
                            if on { triggers.insert(trigger) } else { triggers.remove(trigger) }
                            settings.setPopUpTriggers(triggers, for: cam.id)
                        }
                    )
                }
            }
        }
    }
}

// MARK: - Pop-ups tab row

/// One camera: whether detections open its window and, while on, which ones.
private struct PopUpCameraRow: View {
    let camera: Camera
    let enabled: Bool
    let triggers: Set<DetectionTrigger>
    let isLast: Bool
    let onToggle: (Bool) -> Void
    let onSetTrigger: (DetectionTrigger, Bool) -> Void

    @Environment(\.colorScheme) private var colorScheme
    private var palette: AuroraTokens.Palette { AuroraTokens.palette(for: colorScheme) }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 12) {
                    Text(camera.name)
                        .font(.system(size: 12.5, weight: .medium))
                        .foregroundColor(palette.text)
                        .lineLimit(1)
                    Spacer()
                    Toggle("", isOn: Binding(get: { enabled }, set: { onToggle($0) }))
                        .toggleStyle(.switch)
                        .labelsHidden()
                }
                if enabled {
                    HStack(spacing: 5) {
                        ForEach(DetectionTrigger.supported(by: camera), id: \.self) { trigger in
                            chip(trigger)
                        }
                    }
                }
            }
            .padding(.horizontal, 14).padding(.vertical, 9)
            if !isLast { AuroraHairline(color: palette.divider) }
        }
    }

    private func chip(_ trigger: DetectionTrigger) -> some View {
        let isOn = triggers.contains(trigger)
        return Button {
            onSetTrigger(trigger, !isOn)
        } label: {
            Text(trigger.displayName)
                .font(.system(size: 11, weight: isOn ? .medium : .regular))
                .padding(.horizontal, 8).padding(.vertical, 3)
                .foregroundColor(isOn ? Color.accentColor : palette.subtext)
                .background(Capsule().fill(isOn ? Color.accentColor.opacity(0.15) : palette.divider.opacity(0.6)))
        }
        .buttonStyle(.plain)
    }
}
