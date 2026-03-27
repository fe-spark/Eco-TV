import UIKit
import Flutter
import AVFAudio
import AVKit

@main
@objc class AppDelegate: FlutterAppDelegate {
  private let audioSessionChannelName = "bracket/audio_session"
  private let orientationChannelName = "bracket/orientation"
  private let airPlayRoutePickerViewType = "bracket/airplay_route_picker"
  private var orientationLockMask: UIInterfaceOrientationMask?

  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    GeneratedPluginRegistrant.register(with: self)

    guard let registrar = self.registrar(forPlugin: "BracketPlatformChannels") else {
      return super.application(application, didFinishLaunchingWithOptions: launchOptions)
    }
    registrar.register(AirPlayRoutePickerFactory(), withId: airPlayRoutePickerViewType)

    let channel = FlutterMethodChannel(
      name: audioSessionChannelName,
      binaryMessenger: registrar.messenger()
    )
    channel.setMethodCallHandler { [weak self] (call: FlutterMethodCall, result: @escaping FlutterResult) in
      guard let self else {
        result(FlutterError(code: "unavailable", message: "AppDelegate released", details: nil))
        return
      }

      switch call.method {
      case "ensurePlaybackSession":
        do {
          result(try self.configurePlaybackAudioSession())
        } catch {
          result(
            FlutterError(
              code: "audio_session_error",
              message: error.localizedDescription,
              details: nil
            )
          )
        }
      default:
        result(FlutterMethodNotImplemented)
      }
    }

    let orientationChannel = FlutterMethodChannel(
      name: orientationChannelName,
      binaryMessenger: registrar.messenger()
    )
    orientationChannel.setMethodCallHandler { [weak self] (call: FlutterMethodCall, result: @escaping FlutterResult) in
      guard let self else {
        result(FlutterError(code: "unavailable", message: "AppDelegate released", details: nil))
        return
      }

      switch call.method {
      case "getCurrentDeviceOrientation":
        result(self.currentDeviceOrientation())
      case "lockCurrentOrientation":
        self.lockCurrentOrientation()
        result(nil)
      case "clearOrientationLock":
        self.clearOrientationLock()
        result(nil)
      default:
        result(FlutterMethodNotImplemented)
      }
    }

    do {
      _ = try configurePlaybackAudioSession()
    } catch {
      print("Failed to configure AVAudioSession: \(error)")
    }

    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  override func application(
    _ application: UIApplication,
    supportedInterfaceOrientationsFor window: UIWindow?
  ) -> UIInterfaceOrientationMask {
    orientationLockMask ?? defaultOrientationMask()
  }

  private func configurePlaybackAudioSession() throws -> [String: Any] {
    let session = AVAudioSession.sharedInstance()
    try session.setCategory(.playback, mode: .moviePlayback, options: [.allowAirPlay])
    try session.setActive(true)
    let outputs = session.currentRoute.outputs.map(\.portType.rawValue)
    return [
      "category": session.category.rawValue,
      "mode": session.mode.rawValue,
      "outputs": outputs,
    ]
  }

  private func currentDeviceOrientation() -> String? {
    guard
      let windowScene = activeWindowScene()
    else {
      return nil
    }

    switch windowScene.interfaceOrientation {
    case .portrait:
      return "portraitUp"
    case .portraitUpsideDown:
      return "portraitDown"
    case .landscapeLeft:
      return "landscapeLeft"
    case .landscapeRight:
      return "landscapeRight"
    default:
      return nil
    }
  }

  private func lockCurrentOrientation() {
    guard let orientation = currentInterfaceOrientation() else {
      return
    }

    switch orientation {
    case .portrait:
      orientationLockMask = .portrait
    case .portraitUpsideDown:
      orientationLockMask = .portraitUpsideDown
    case .landscapeLeft:
      orientationLockMask = .landscapeLeft
    case .landscapeRight:
      orientationLockMask = .landscapeRight
    default:
      orientationLockMask = nil
    }

    updateSupportedOrientations(preferredOrientation: orientation)
  }

  private func clearOrientationLock() {
    orientationLockMask = nil
    updateSupportedOrientations(preferredOrientation: nil)
  }

  private func currentInterfaceOrientation() -> UIInterfaceOrientation? {
    guard
      let windowScene = activeWindowScene()
    else {
      return nil
    }
    return windowScene.interfaceOrientation
  }

  private func activeWindowScene() -> UIWindowScene? {
    let windowScenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
    if let activeScene = windowScenes.first(where: { $0.activationState == .foregroundActive }) {
      return activeScene
    }
    if let inactiveScene = windowScenes.first(where: { $0.activationState == .foregroundInactive }) {
      return inactiveScene
    }
    return windowScenes.first
  }

  private func updateSupportedOrientations(preferredOrientation: UIInterfaceOrientation?) {
    guard let windowScene = activeWindowScene() else {
      UIViewController.attemptRotationToDeviceOrientation()
      return
    }

    if #available(iOS 16.0, *) {
      windowScene.keyWindow?.rootViewController?.setNeedsUpdateOfSupportedInterfaceOrientations()
      let preferences = UIWindowScene.GeometryPreferences.iOS(
        interfaceOrientations: orientationLockMask ?? defaultOrientationMask()
      )
      windowScene.requestGeometryUpdate(preferences) { error in
        print("Failed to update supported orientations: \(error)")
      }
      return
    }

    if let preferredOrientation {
      UIDevice.current.setValue(preferredOrientation.rawValue, forKey: "orientation")
    }
    UIViewController.attemptRotationToDeviceOrientation()
  }

  private func defaultOrientationMask() -> UIInterfaceOrientationMask {
    if UIDevice.current.userInterfaceIdiom == .pad {
      return [.portrait, .portraitUpsideDown, .landscapeLeft, .landscapeRight]
    }
    return [.portrait, .landscapeLeft, .landscapeRight]
  }
}

final class AirPlayRoutePickerFactory: NSObject, FlutterPlatformViewFactory {
  override init() {
    super.init()
  }

  func createArgsCodec() -> (FlutterMessageCodec & NSObjectProtocol) {
    FlutterStandardMessageCodec.sharedInstance()
  }

  func create(
    withFrame frame: CGRect,
    viewIdentifier viewId: Int64,
    arguments args: Any?
  ) -> FlutterPlatformView {
    AirPlayRoutePickerPlatformView(frame: frame, args: args)
  }
}

final class AirPlayRoutePickerPlatformView: NSObject, FlutterPlatformView {
  private let containerView: AirPlayRoutePickerContainerView
  private let routePickerView: AVRoutePickerView
  private let iconScale: CGFloat

  init(frame: CGRect, args: Any?) {
    containerView = AirPlayRoutePickerContainerView(frame: frame)
    routePickerView = AVRoutePickerView(frame: frame)
    iconScale = Self.resolveIconScale(from: args)
    super.init()

    containerView.backgroundColor = .clear
    containerView.clipsToBounds = false
    routePickerView.backgroundColor = .clear
    routePickerView.prioritizesVideoDevices = true
    routePickerView.translatesAutoresizingMaskIntoConstraints = false
    routePickerView.tintColor = Self.resolveColor(
      from: args,
      key: "tintColor",
      fallback: .white
    )
    routePickerView.activeTintColor = Self.resolveColor(
      from: args,
      key: "activeTintColor",
      fallback: routePickerView.tintColor
    )

    containerView.embed(routePickerView, iconScale: iconScale)
  }

  func view() -> UIView {
    containerView
  }

  private static func resolveColor(
    from args: Any?,
    key: String,
    fallback: UIColor
  ) -> UIColor {
    guard
      let parameters = args as? [String: Any],
      let number = parameters[key] as? NSNumber
    else {
      return fallback
    }

    let value = number.uint32Value
    let alpha = CGFloat((value >> 24) & 0xFF) / 255.0
    let red = CGFloat((value >> 16) & 0xFF) / 255.0
    let green = CGFloat((value >> 8) & 0xFF) / 255.0
    let blue = CGFloat(value & 0xFF) / 255.0
    return UIColor(red: red, green: green, blue: blue, alpha: alpha)
  }

  private static func resolveIconScale(from args: Any?) -> CGFloat {
    guard
      let parameters = args as? [String: Any],
      let number = parameters["iconScale"] as? NSNumber
    else {
      return 1.0
    }

    return CGFloat(number.doubleValue).clamped(to: 0.6...1.0)
  }
}

final class AirPlayRoutePickerContainerView: UIView {
  private weak var hostedPickerView: AVRoutePickerView?
  private var iconScale: CGFloat = 1.0

  func embed(_ pickerView: AVRoutePickerView, iconScale: CGFloat) {
    hostedPickerView?.removeFromSuperview()
    hostedPickerView = pickerView
    self.iconScale = iconScale

    addSubview(pickerView)
    NSLayoutConstraint.activate([
      pickerView.leadingAnchor.constraint(equalTo: leadingAnchor),
      pickerView.trailingAnchor.constraint(equalTo: trailingAnchor),
      pickerView.topAnchor.constraint(equalTo: topAnchor),
      pickerView.bottomAnchor.constraint(equalTo: bottomAnchor),
    ])
  }

  override func layoutSubviews() {
    super.layoutSubviews()
    refreshHostedPickerLayout()
  }

  override func didMoveToWindow() {
    super.didMoveToWindow()
    DispatchQueue.main.async { [weak self] in
      self?.refreshHostedPickerLayout()
    }
  }

  private func refreshHostedPickerLayout() {
    hostedPickerView?.setNeedsLayout()
    hostedPickerView?.layoutIfNeeded()
    guard let button = hostedPickerView?.firstDescendant(of: UIButton.self) else {
      return
    }
    if button.transform.a != iconScale || button.transform.d != iconScale {
      button.transform = CGAffineTransform(scaleX: iconScale, y: iconScale)
    }
  }
}

private extension UIWindowScene {
  var keyWindow: UIWindow? {
    windows.first(where: \.isKeyWindow)
  }
}

private extension UIView {
  func firstDescendant<T: UIView>(of type: T.Type) -> T? {
    for subview in subviews {
      if let match = subview as? T {
        return match
      }
      if let nestedMatch = subview.firstDescendant(of: type) {
        return nestedMatch
      }
    }
    return nil
  }
}

private extension Comparable {
  func clamped(to limits: ClosedRange<Self>) -> Self {
    min(max(self, limits.lowerBound), limits.upperBound)
  }
}
