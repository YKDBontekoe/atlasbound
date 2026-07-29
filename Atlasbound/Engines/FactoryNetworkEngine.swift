import Foundation

struct FactoryNetworkSnapshot: Sendable, Equatable, Identifiable {
    let id: String
    let roadTileIDs: Set<String>
    let buildingTileIDs: Set<String>
    let totalRoadCapacity: Int
}

struct FactoryNetworkEngine: Sendable {
    func networks(
        structures: [String: PlacedFactoryStructure],
        tileEngine: TileEngine
    ) -> [FactoryNetworkSnapshot] {
        let roadIDs = Set(structures.values.compactMap { structure -> String? in
            FactoryCatalog.byID[structure.definitionID]?.kind == .road ? structure.tileID : nil
        })
        var remaining = roadIDs
        var output: [FactoryNetworkSnapshot] = []

        while let start = remaining.sorted().first {
            var queue = [start]
            var component: Set<String> = []
            remaining.remove(start)
            while !queue.isEmpty {
                let current = queue.removeFirst()
                component.insert(current)
                guard let axial = tileEngine.parseTileID(current) else { continue }
                for neighbor in tileEngine.neighbors(of: axial) {
                    let id = TileEngine.makeTileID(q: neighbor.q, r: neighbor.r, sizeMeters: tileEngine.tileSizeMeters)
                    if remaining.remove(id) != nil {
                        queue.append(id)
                    }
                }
            }

            var buildings: Set<String> = []
            for roadID in component {
                guard let axial = tileEngine.parseTileID(roadID) else { continue }
                for neighbor in tileEngine.neighbors(of: axial) {
                    let id = TileEngine.makeTileID(q: neighbor.q, r: neighbor.r, sizeMeters: tileEngine.tileSizeMeters)
                    if let structure = structures[id],
                       FactoryCatalog.byID[structure.definitionID]?.kind != .road {
                        buildings.insert(id)
                    }
                }
            }

            let capacity = component.reduce(0) { partial, tileID in
                guard let structure = structures[tileID],
                      let tier = FactoryCatalog.byID[structure.definitionID]?.roadTier else { return partial }
                return partial + tier.capacityPerMinute
            }
            output.append(
                FactoryNetworkSnapshot(
                    id: component.sorted().first ?? start,
                    roadTileIDs: component,
                    buildingTileIDs: buildings,
                    totalRoadCapacity: capacity
                )
            )
        }
        return output.sorted { $0.id < $1.id }
    }

    func shortestRoadPath(
        fromBuildingID: String,
        toBuildingID: String,
        network: FactoryNetworkSnapshot,
        tileEngine: TileEngine
    ) -> [String]? {
        guard let from = tileEngine.parseTileID(fromBuildingID),
              let to = tileEngine.parseTileID(toBuildingID) else { return nil }
        let starts = adjacentRoadIDs(to: from, in: network.roadTileIDs, tileEngine: tileEngine)
        let goals = Set(adjacentRoadIDs(to: to, in: network.roadTileIDs, tileEngine: tileEngine))
        guard !starts.isEmpty, !goals.isEmpty else { return nil }

        var queue = starts.sorted()
        var visited = Set(queue)
        var previous: [String: String] = [:]
        var found: String?
        while !queue.isEmpty {
            let current = queue.removeFirst()
            if goals.contains(current) {
                found = current
                break
            }
            guard let axial = tileEngine.parseTileID(current) else { continue }
            let neighbors = tileEngine.neighbors(of: axial)
                .map { TileEngine.makeTileID(q: $0.q, r: $0.r, sizeMeters: tileEngine.tileSizeMeters) }
                .filter { network.roadTileIDs.contains($0) }
                .sorted()
            for next in neighbors where visited.insert(next).inserted {
                previous[next] = current
                queue.append(next)
            }
        }
        guard var cursor = found else { return nil }
        var path = [cursor]
        while let prior = previous[cursor] {
            path.append(prior)
            cursor = prior
        }
        return path.reversed()
    }

    private func adjacentRoadIDs(
        to coordinate: TileCoordinate,
        in roads: Set<String>,
        tileEngine: TileEngine
    ) -> [String] {
        tileEngine.neighbors(of: coordinate)
            .map { TileEngine.makeTileID(q: $0.q, r: $0.r, sizeMeters: tileEngine.tileSizeMeters) }
            .filter { roads.contains($0) }
    }
}

