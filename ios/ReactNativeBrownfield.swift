import UIKit
internal import React
internal import React_RCTAppDelegate
internal import ReactAppDependencyProvider

class ReactNativeBrownfieldDelegate: RCTDefaultReactNativeFactoryDelegate {
  var entryFile = "index"
  var bundlePath = "main.jsbundle"
  var bundle = Bundle.main
  // MARK: - RCTReactNativeFactoryDelegate Methods

  override func sourceURL(for bridge: RCTBridge) -> URL? {
    return bundleURL()
  }

  public override func bundleURL() -> URL? {
    #if DEBUG
      return RCTBundleURLProvider.sharedSettings().jsBundleURL(forBundleRoot: entryFile)
    #else
      let resourceURLComponents = bundlePath.components(separatedBy: ".")
      let withoutLast = resourceURLComponents[..<(resourceURLComponents.count - 1)]
      let resourceName = withoutLast.joined()
      let fileExtension = resourceURLComponents.last ?? ""

      return bundle.url(forResource: resourceName, withExtension: fileExtension)
    #endif
  }
}

@objc public class ReactNativeBrownfield: NSObject {
  public static let shared = ReactNativeBrownfield()
  private var onBundleLoaded: (() -> Void)?
  private var delegate = ReactNativeBrownfieldDelegate()
  private var jsLoadedObserver: NSObjectProtocol?
  private var isTransitioning = false

  // MARK: - Bundle State
  @objc public enum BundleStateSwift: Int {
    case notLoaded
    case loading
    case loaded
    case error
  }

  public enum BundleState {
    case notLoaded
    case loading
    case loaded
    case error(Error)

    var bridged: BundleStateSwift {
      switch self {
      case .notLoaded: return .notLoaded
      case .loading: return .loading
      case .loaded: return .loaded
      case .error: return .error
      }
    }
  }

  @objc public private(set) var bundleStateObjC: BundleStateSwift = .notLoaded
  public private(set) var bundleState: BundleState = .notLoaded {
    didSet { bundleStateObjC = bundleState.bridged }
  }

  // MARK: - Configurable Properties

  /**
   * Path to JavaScript root.
   * Default value: "index"
   */
  @objc public var entryFile: String = "index" {
    didSet {
      delegate.entryFile = entryFile
    }
  }
  /**
   * Path to bundle fallback resource.
   * Default value: nil
   */
  @objc public var fallbackResource: String? = nil
  /**
   * Path to JavaScript bundle file.
   * Default value: "main.jsbundle"
   */
  @objc public var bundlePath: String = "main.jsbundle" {
    didSet {
      delegate.bundlePath = bundlePath
    }
  }
  /**
   * Bundle instance to lookup the JavaScript bundle.
   * Default value: Bundle.main
   */
  @objc public var bundle: Bundle = Bundle.main {
    didSet {
      delegate.bundle = bundle
    }
  }
  /**
   * React Native factory instance created when starting React Native.
   * Default value: nil
   */
  private var reactNativeFactory: RCTReactNativeFactory? = nil
  /**
   * Root view factory used to create React Native views.
   */
  lazy private var rootViewFactory: RCTRootViewFactory? = {
    return reactNativeFactory?.rootViewFactory
  }()

  // MARK: - Status

  /**
   * Returns true if React Native is loaded and ready.
   */
  @objc public var isLoaded: Bool {
    return reactNativeFactory != nil
  }

  // MARK: - Public API

  /**
   * Starts React Native with default parameters.
   */
  @objc public func startReactNative() {
    startReactNative(onBundleLoaded: nil)
  }

  @objc public func view(
    moduleName: String,
    initialProps: [AnyHashable: Any]?,
    launchOptions: [AnyHashable: Any]? = nil
  ) -> UIView? {
    rootViewFactory?.view(
      withModuleName: moduleName,
      initialProperties: initialProps,
      launchOptions: launchOptions
    )
  }

  /**
   * Starts React Native with optional callback when bundle is loaded.
   *
   * @param onBundleLoaded Optional callback invoked after JS bundle is fully loaded.
   */
  @objc public func startReactNative(onBundleLoaded: (() -> Void)?) {
    startReactNative(onBundleLoaded: onBundleLoaded, launchOptions: nil)
  }

  /**
   * Starts React Native with optional callback and launch options.
   *
   * @param onBundleLoaded Optional callback invoked after JS bundle is fully loaded.
   * @param launchOptions Launch options, typically passed from AppDelegate.
   */
  @objc public func startReactNative(
    onBundleLoaded: (() -> Void)?, launchOptions: [AnyHashable: Any]?
  ) {
    // Ensure on main thread
    guard Thread.isMainThread else {
      DispatchQueue.main.async { [weak self] in
        self?.startReactNative(onBundleLoaded: onBundleLoaded, launchOptions: launchOptions)
      }
      return
    }

    // Prevent multiple simultaneous starts
    guard !isTransitioning else {
      print("ReactNativeBrownfield: Cannot start - already transitioning")
      return
    }

    // Sequential loading: stop if already active
    if reactNativeFactory != nil {
      print("ReactNativeBrownfield: Stopping existing instance before starting new one")
      stopReactNative()
      
      // Give bridge time to tear down
      DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { [weak self] in
        self?.performStart(onBundleLoaded: onBundleLoaded, launchOptions: launchOptions)
      }
      return
    }

    performStart(onBundleLoaded: onBundleLoaded, launchOptions: launchOptions)
  }

  private func performStart(onBundleLoaded: (() -> Void)?, launchOptions: [AnyHashable: Any]?) {
    isTransitioning = true
    bundleState = .loading

    delegate.dependencyProvider = RCTAppDependencyProvider()
    self.reactNativeFactory = RCTReactNativeFactory(delegate: delegate)

    if let onBundleLoaded {
      self.onBundleLoaded = {
        self.bundleState = .loaded
        self.isTransitioning = false
        onBundleLoaded()
      }
      
      let notificationName = RCTIsNewArchEnabled() 
        ? NSNotification.Name("RCTInstanceDidLoadBundle")
        : NSNotification.Name("RCTJavaScriptDidLoadNotification")
      
      // Store observer token so we can remove only this specific observer
      jsLoadedObserver = NotificationCenter.default.addObserver(
        forName: notificationName,
        object: nil,
        queue: .main
      ) { [weak self] notification in
        self?.jsLoaded(notification)
      }
    } else {
      bundleState = .loaded
      isTransitioning = false
    }
  }

  @objc private func jsLoaded(_ notification: Notification) {
    // Remove only our specific observer
    if let observer = jsLoadedObserver {
      NotificationCenter.default.removeObserver(observer)
      jsLoadedObserver = nil
    }
    
    onBundleLoaded?()
    onBundleLoaded = nil
  }

  /**
   * Stops React Native and unloads the bridge.
   * Safe to call multiple times - no-op if already stopped.
   */
  @objc public func stopReactNative() {
    // Ensure on main thread
    guard Thread.isMainThread else {
      DispatchQueue.main.sync { [weak self] in
        self?.stopReactNative()
      }
      return
    }

    guard reactNativeFactory != nil else { return }

    bundleState = .notLoaded
    isTransitioning = false

    // Remove specific observer if it exists
    if let observer = jsLoadedObserver {
      NotificationCenter.default.removeObserver(observer)
      jsLoadedObserver = nil
    }

    reactNativeFactory = nil
    rootViewFactory = nil
    onBundleLoaded = nil

    NotificationCenter.default.post(name: .reactNativeStopped, object: nil)
  }

  /**
   * Switches to a different bundle (sequential loading).
   * Stops current bridge if active, then loads new bundle configuration.
   *
   * @param entryFile Entry file name (e.g. "index")
   * @param bundlePath Bundle file name (e.g. "main.jsbundle")
   * @param bundle Bundle instance to load from
   * @param onLoaded Optional callback when new bundle is loaded
   */
  @objc public func switchBundle(
    entryFile: String,
    bundlePath: String,
    bundle: Bundle = .main,
    onLoaded: (() -> Void)? = nil
  ) {
    // Ensure on main thread
    guard Thread.isMainThread else {
      DispatchQueue.main.async { [weak self] in
        self?.switchBundle(entryFile: entryFile, bundlePath: bundlePath, bundle: bundle, onLoaded: onLoaded)
      }
      return
    }

    guard !isTransitioning else {
      print("ReactNativeBrownfield: Cannot switch bundle - already transitioning")
      return
    }

    self.entryFile = entryFile
    self.bundlePath = bundlePath
    self.bundle = bundle

    if reactNativeFactory != nil {
      stopReactNative()
      // Give bridge time to tear down before starting new one
      DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { [weak self] in
        self?.startReactNative(onBundleLoaded: onLoaded)
      }
    } else {
      startReactNative(onBundleLoaded: onLoaded)
    }
  }

  /**
   * Reloads the current bundle configuration.
   * Useful for development/debugging.
   *
   * @param onLoaded Optional callback when bundle is reloaded
   */
  @objc public func reloadBundle(onLoaded: (() -> Void)? = nil) {
    // Ensure on main thread
    guard Thread.isMainThread else {
      DispatchQueue.main.async { [weak self] in
        self?.reloadBundle(onLoaded: onLoaded)
      }
      return
    }

    guard !isTransitioning else {
      print("ReactNativeBrownfield: Cannot reload - already transitioning")
      return
    }

    let currentEntry = entryFile
    let currentPath = bundlePath
    let currentBundle = bundle

    if reactNativeFactory != nil {
      stopReactNative()
    }

    // Delay to ensure cleanup completes
    DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { [weak self] in
      guard let self = self else { return }

      self.entryFile = currentEntry
      self.bundlePath = currentPath
      self.bundle = currentBundle

      self.startReactNative(onBundleLoaded: onLoaded)
    }
  }
}

// MARK: - Feature Module Protocol

/**
 * Protocol for React Native feature modules packaged as .xcframework.
 * Conforming types provide bundle location and configuration.
 */
public protocol ReactFeatureModule {
  /// The Bundle containing the React Native bundle for this feature
  static var bundle: Bundle { get }
  /// Entry file name (e.g., "index")
  static var entryFile: String { get }
  /// Bundle file name (e.g., "main.jsbundle")
  static var bundlePath: String { get }
  /// Initial module name to display
  static var initialModule: String { get }
}

/// Provide default implementations
public extension ReactFeatureModule {
  static var entryFile: String { "index" }
  static var bundlePath: String { "main.jsbundle" }
}

// MARK: - Feature Module Extension

public extension ReactNativeBrownfield {
  /**
   * Switches to a feature module conforming to ReactFeatureModule protocol.
   *
   * @param feature The feature module type
   * @param onLoaded Optional callback when feature is loaded
   */
  func switchToFeature<T: ReactFeatureModule>(
    _ feature: T.Type,
    onLoaded: (() -> Void)? = nil
  ) {
    switchBundle(
      entryFile: feature.entryFile,
      bundlePath: feature.bundlePath,
      bundle: feature.bundle,
      onLoaded: onLoaded
    )
  }

  /**
   * Gets the initial module name for a feature.
   *
   * @param feature The feature module type
   * @return The initial module name
   */
  func initialModule<T: ReactFeatureModule>(for feature: T.Type) -> String {
    return feature.initialModule
  }
}

extension Notification.Name {
  /**
   * Notification sent when React Native wants to navigate back to native screen.
   */
  public static let popToNative = Notification.Name("PopToNativeNotification")
  /**
   * Notification sent to enable/disable the pop gesture recognizer.
   */
  public static let togglePopGestureRecognizer = Notification.Name(
    "TogglePopGestureRecognizerNotification")
  /**
   * Notification sent when React Native is stopped and bridge is unloaded.
   */
  public static let reactNativeStopped = Notification.Name("ReactNativeStoppedNotification")
}
