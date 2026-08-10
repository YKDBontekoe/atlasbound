import SwiftUI
import MapboxMaps

/// Shared Mapbox presentation for the Atlasbound atlas.
///
/// The basemap provides orientation only. Gameplay overlays own the visual
/// hierarchy, so commercial POIs, transit labels, and landmark icons stay out
/// of the way while roads, parks, water, and major place labels remain useful.
enum AtlasMapStyle {
    static func standard(for colorScheme: ColorScheme) -> MapStyle {
        .standard(
            theme: .faded,
            // Dusk made the light-mode atlas look muddy and pushed the gameplay
            // colors into the same purple/gray range as the basemap. Keep the
            // standard 3D treatment, but use a clean daylight canvas so hexes
            // and territory accents carry the visual hierarchy.
            lightPreset: colorScheme == .dark ? .night : .day,
            showPointOfInterestLabels: false,
            showTransitLabels: false,
            showPlaceLabels: true,
            showRoadLabels: false,
            showPedestrianRoads: false,
            show3dObjects: true,
            show3dBuildings: true,
            show3dFacades: true,
            show3dLandmarks: false,
            show3dTrees: true,
            showLandmarkIconLabels: false,
            showLandmarkIcons: false
        )
    }
}
