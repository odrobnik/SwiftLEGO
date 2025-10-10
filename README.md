SwiftLEGO
=========

SwiftLEGO is a native SwiftUI application and supporting Swift packages for managing LEGO® set inventories. It integrates with BrickLink to import official inventories, track owned quantities, explore minifigures, and drill into accessory sub-parts. The codebase is split between the app target (`SwiftLEGO/`) and a reusable core library (`Sources/BrickCore/`) that provides the networking and parsing logic.


Project Layout
--------------

```
SwiftLEGO/
├── SwiftLEGO/               # iOS app target (SwiftUI)
│   ├── Components/          # Shared view components (forms, cards, editors)
│   ├── Models/              # SwiftData models (BrickSet, Part, Minifigure, etc.)
│   ├── Persistence/         # Model container setup and previews
│   ├── Services/            # App-facing services (snapshot import/export, documents)
│   ├── Views/               # Screens (collection lists, detail views, navigation)
│   └── SwiftLEGOApp.swift   # App entry point
├── Sources/BrickCore/       # Reusable library for BrickLink scraping + models
│   ├── Scraper/             # HTML → Markdown DOM parser and helpers
│   ├── BrickLinkInventoryService.swift   # BrickLink integration and sub-part fetching
│   └── BrickLinkInventoryModels.swift    # Transport models exposed to callers
├── Tests/
│   ├── BrickCoreTests/      # Swift Testing suites covering BrickCore behavior
│   └── Fixtures/            # JSON fixtures for regression scenarios
├── Package.swift            # Swift Package manifest for BrickCore + tests
├── SwiftLEGO.xcodeproj      # Xcode project for the app target
└── README.md                # This overview
```


Key Concepts
------------

* **BrickCore**: A Swift package that fetches BrickLink inventories, normalises data, and exposes transport models. It recursively resolves accessory inventories, so multipack parts surface their sub-components.

* **SwiftData Models**: The app stores sets, minifigures, categories, and parts with relationships that mirror BrickLink hierarchies. `Part` records can belong to sets or minifigures and can own child parts (subparts).

* **Import/Export**: Inventory JSON snapshots serialize parts (including nested subparts) for backup and syncing. The importer walks the same hierarchy and clamps owned quantities.

* **UI Flow**: `SetCollectionView` lists sets by collection. `SetDetailView` groups parts by color, supports search and “missing only” filtering, and lets users drill into subparts. Minifigure detail screens reuse the same part row components.


BrickLink Integration
---------------------

`BrickLinkInventoryService` fetches BrickLink inventory pages, converts them to Markdown, parses the tables, and produces strongly typed `BrickLinkInventory` objects. Parts that expose “Inv” links trigger additional fetches so nested inventories (e.g., accessory bags, sprues) are captured. The app consumes these payloads via `BrickLinkService`, converting them into SwiftData models on import.


Testing
-------

BrickCore is backed by Swift Testing suites (`Tests/BrickCoreTests`). These exercises:

* Markdown conversion sanity checks (ensuring BrickLink table parsing keeps working).
* End-to-end inventory imports for known sets, including accessory bag coverage.
* Legacy JSON snapshot decoding, guaranteeing older exports remain readable.

Run the full suite with:

```
swift test
```

The app target still builds via Xcode:

```
xcodebuild -scheme SwiftLEGO -project SwiftLEGO.xcodeproj -configuration Debug build
```


Getting Started
---------------

1. Open `SwiftLEGO.xcodeproj` in Xcode 15 or later.
2. Select the *SwiftLEGO* scheme and run on an iOS 17+ simulator or device.
3. Use the “Add Set” flow to import inventories by BrickLink set number. Accessory multipacks expose their subparts from the parts list.
4. Export/import snapshots from the collection screen to sync owned quantities across installs.

For BrickCore-only work, you can develop and test with Swift Package Manager by opening the repo folder in Xcode or running `swift test` from the command line.
