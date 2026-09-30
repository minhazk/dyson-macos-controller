import AppKit
import SceneKit
import SwiftUI

/// A small, noninteractive scene; the SwiftUI dial owns the orientation.
struct PurifierModelView: NSViewRepresentable {
    let angle: Double

    func makeNSView(context: Context) -> SCNView {
        let view = SCNView(frame: .zero)
        view.backgroundColor = .clear
        view.antialiasingMode = .multisampling4X
        view.allowsCameraControl = false
        view.rendersContinuously = false
        let scene = SCNScene()
        view.scene = scene

        let camera = SCNNode()
        camera.camera = SCNCamera()
        camera.camera?.usesOrthographicProjection = true
        camera.camera?.orthographicScale = 87
        camera.camera?.zFar = 600
        camera.position = SCNVector3(0, 28, 280)
        camera.look(at: SCNVector3(0, 0, 0))
        scene.rootNode.addChildNode(camera)
        view.pointOfView = camera

        addLight(to: scene, type: .ambient, intensity: 250, position: SCNVector3(0, 0, 0))
        addLight(to: scene, type: .directional, intensity: 900, position: SCNVector3(-90, 120, 160))
        addLight(to: scene, type: .directional, intensity: 350, position: SCNVector3(90, 20, -100))

        let model = makePurifier()
        model.name = "purifier"
        scene.rootNode.addChildNode(model)
        updateNSView(view, context: context)
        return view
    }

    func updateNSView(_ view: SCNView, context: Context) {
        SCNTransaction.begin()
        SCNTransaction.disableActions = true
        // Dial angles run clockwise; SceneKit's positive yaw turns the front to the right.
        view.scene?.rootNode.childNode(withName: "purifier", recursively: false)?.eulerAngles.y = CGFloat((180 - angle) * .pi / 180)
        SCNTransaction.commit()
        view.needsDisplay = true
    }

    private func makePurifier() -> SCNNode {
        let model = SCNNode()
        let silver = material(.init(white: 0.79, alpha: 1), metalness: 0.65, roughness: 0.30)
        let pearl = material(.init(white: 0.94, alpha: 1), metalness: 0.3, roughness: 0.24)
        let dark = material(.init(white: 0.075, alpha: 1), metalness: 0.2, roughness: 0.6)

        let foot = SCNCylinder(radius: 26, height: 5)
        foot.radialSegmentCount = 72
        add(foot, material: dark, at: SCNVector3(0, -70, 0), to: model)
        let base = SCNCylinder(radius: 25, height: 44)
        base.radialSegmentCount = 72
        add(base, material: silver, at: SCNVector3(0, -46, 0), to: model)
        let collar = SCNCylinder(radius: 24.5, height: 5)
        collar.radialSegmentCount = 72
        add(collar, material: pearl, at: SCNVector3(0, -22, 0), to: model)

        // Fine perforations around the entire filter, including the back.
        let vent = SCNSphere(radius: 0.55)
        vent.segmentCount = 6
        vent.firstMaterial = dark
        for row in 0..<10 {
            for column in 0..<48 {
                let theta = Double(column) / 48 * .pi * 2 + (row.isMultiple(of: 2) ? 0 : .pi / 48)
                let node = SCNNode(geometry: vent)
                node.position = SCNVector3(25 * sin(theta), -64 + Double(row) * 3.4, 25 * cos(theta))
                model.addChildNode(node)
            }
        }

        let neck = SCNBox(width: 15, height: 12, length: 14, chamferRadius: 3)
        add(neck, material: pearl, at: SCNVector3(0, -16, 0), to: model)

        let loopPath = NSBezierPath(roundedRect: NSRect(x: -28, y: -13, width: 56, height: 91), xRadius: 24, yRadius: 24)
        let opening = NSBezierPath(roundedRect: NSRect(x: -18, y: -2, width: 36, height: 69), xRadius: 15, yRadius: 15)
        loopPath.append(opening.reversed)
        loopPath.flatness = 0.15
        let loop = SCNShape(path: loopPath, extrusionDepth: 15)
        loop.chamferRadius = 1.6
        add(loop, material: pearl, at: SCNVector3(0, 0, 0), to: model)

        let innerPath = NSBezierPath(roundedRect: NSRect(x: -20, y: -4, width: 40, height: 73), xRadius: 17, yRadius: 17)
        innerPath.append(opening.reversed)
        innerPath.flatness = 0.15
        let lining = SCNShape(path: innerPath, extrusionDepth: 0.7)
        lining.chamferRadius = 0.25
        let blue = material(.init(red: 0.23, green: 0.40, blue: 0.49, alpha: 1), metalness: 0.6, roughness: 0.3)
        add(lining, material: blue, at: SCNVector3(0, 0, 7.6), to: model)

        let display = SCNBox(width: 11, height: 9, length: 1.4, chamferRadius: 3)
        add(display, material: dark, at: SCNVector3(0, -32, 24), to: model)
        let indicator = SCNBox(width: 4, height: 1, length: 0.3, chamferRadius: 0.3)
        let cyan = material(.cyan, metalness: 0, roughness: 0.4)
        cyan.emission.contents = NSColor.cyan.withAlphaComponent(0.5)
        add(indicator, material: cyan, at: SCNVector3(0, -32, 25), to: model)
        return model
    }

    private func material(_ color: NSColor, metalness: CGFloat, roughness: CGFloat) -> SCNMaterial {
        let material = SCNMaterial()
        material.lightingModel = .physicallyBased
        material.diffuse.contents = color
        material.metalness.contents = metalness
        material.roughness.contents = roughness
        return material
    }

    private func add(_ geometry: SCNGeometry, material: SCNMaterial, at position: SCNVector3, to parent: SCNNode) {
        geometry.firstMaterial = material
        let node = SCNNode(geometry: geometry)
        node.position = position
        parent.addChildNode(node)
    }

    private func addLight(to scene: SCNScene, type: SCNLight.LightType, intensity: CGFloat, position: SCNVector3) {
        let node = SCNNode()
        node.light = SCNLight()
        node.light?.type = type
        node.light?.intensity = intensity
        node.position = position
        if type == .directional { node.look(at: SCNVector3(0, 0, 0)) }
        scene.rootNode.addChildNode(node)
    }
}
