// The Swift Programming Language
// https://docs.swift.org/swift-book

//
//  RoomPlanMapper.swift
//  ARRoomMapper
//
//  Created by paologiua on 10/11/24.
//

import RoomPlan
import UIKit
import ARKit
import RealityKit

class RoomPlanMapper: NSObject {
    private let sceneView: ARSCNView
    private var session: ARSession?
    private var configuration: ARWorldTrackingConfiguration?
    private var currentMap: ARWorldMap?
    
    init(sceneView: ARSCNView) {
        self.sceneView = sceneView
    }
    
    private func saveWorldMap(_ worldMap: ARWorldMap, to url: URL) throws {
        let data = try NSKeyedArchiver.archivedData(withRootObject: worldMap, requiringSecureCoding: true)
        try data.write(to: url)
    }
    
    private func loadWorldMap(from url: URL) throws -> ARWorldMap {
        let data = try Data(contentsOf: url)
        guard let worldMap = try NSKeyedUnarchiver.unarchivedObject(ofClass: ARWorldMap.self, from: data) else {
            throw NSError(domain: "com.example.ARKitError", code: -1, userInfo: [NSLocalizedDescriptionKey: "Unable to load ARWorldMap."])
        }
        return worldMap
    }
    
    @MainActor
    func startScanning() {
        // Set up the ARSCNView
        sceneView.delegate = self
        sceneView.session.delegate = self
        
        // Configure the AR session
        configuration = ARWorldTrackingConfiguration()
        configuration?.isAutoFocusEnabled = true
        configuration?.planeDetection = .horizontal
        configuration?.environmentTexturing = .automatic
        
        // Start the AR session
        session = sceneView.session
        session?.run(configuration!)
    }
    
    func saveMap() {
        guard let currentMap = currentMap else {
            return
        }
        
        // Save the current map to disk
        do {
            let fileManager = FileManager.default
            let documentsURL = fileManager.urls(for: .documentDirectory, in: .userDomainMask).first!
            let mapURL = documentsURL.appendingPathComponent("saved_map.arworldmap")
            try saveWorldMap(currentMap, to: mapURL)
            print("Map saved to: \(mapURL.path)")
        } catch {
            print("Error saving map: \(error)")
        }
    }
    
    func loadMap() {
        let fileManager = FileManager.default
        let documentsURL = fileManager.urls(for: .documentDirectory, in: .userDomainMask).first!
        let mapURL = documentsURL.appendingPathComponent("saved_map.arworldmap")
        
        do {
            let savedMap = try loadWorldMap(from: mapURL)
            currentMap = savedMap
            
            // Reset the AR session and run the loaded map
            session?.pause()
            configuration = ARWorldTrackingConfiguration()
            configuration?.initialWorldMap = savedMap
            session?.run(configuration!)
            
            print("Map loaded from: \(mapURL.path)")
        } catch {
            print("Error loading map: \(error)")
        }
    }
}

// ARSCNViewDelegate implementation
extension RoomPlanMapper: ARSCNViewDelegate {
    func renderer(_ renderer: SCNSceneRenderer, didAdd node: SCNNode, for anchor: ARAnchor) {
        guard let planeAnchor = anchor as? ARPlaneAnchor else { return }
        
        // Creiamo una copia dei dati necessari da planeAnchor
        let planeAnchorCopy = ARPlaneAnchor(transform: planeAnchor.transform, center: planeAnchor.center, extent: planeAnchor.extent)
        
        Task { @MainActor in
            await self.handleAnchorUpdate(for: planeAnchorCopy, on: node)
        }
    }
    
    @MainActor
    private func handleAnchorUpdate(for planeAnchor: ARPlaneAnchor, on node: SCNNode) async {
        guard let device = sceneView.device,
              let planeGeometry = ARSCNPlaneGeometry(device: device) else {
            return
        }
        
        // Update the plane geometry with the anchor's geometry
        planeGeometry.update(from: planeAnchor.geometry)
        
        // Create a plane node and add it to the scene
        let planeNode = SCNNode(geometry: planeGeometry)
        planeNode.transform = SCNMatrix4(planeAnchor.transform)
        node.addChildNode(planeNode)
        
        // Get the current world map
        sceneView.session.getCurrentWorldMap { worldMap, error in
            if let worldMap = worldMap {
                self.currentMap = worldMap
            } else if let error = error {
                print("Error getting world map: \(error.localizedDescription)")
            }
        }
    }
}

// ARSessionDelegate implementation
extension RoomPlanMapper: ARSessionDelegate {
    func session(_ session: ARSession, didFailWithError error: Error) {
        print("AR session failed: \(error.localizedDescription)")
    }
    
    func sessionWasInterrupted(_ session: ARSession) {
        print("AR session was interrupted")
    }
    
    func sessionInterruptionEnded(_ session: ARSession) {
        print("AR session interruption ended")
    }
}
