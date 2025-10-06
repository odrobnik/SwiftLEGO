SwiftLEGO – MVP Specification

Date: October 6, 2025
Platform: iPad (iPadOS 18+)
Frameworks: SwiftUI, SwiftData
Purpose: Assist LEGO collectors in organizing and rebuilding sets from mixed part collections.

⸻

1. Concept

SwiftLEGO is a SwiftUI app that helps users catalog LEGO sets from used or mixed collections.
It allows users to maintain lists of sets, import data from BrickLink via scraping, and locally store all information about sets and their parts.

The MVP focuses on list and set management — establishing the app’s foundational data structure and UI.

⸻

2. Core Features

2.1 Lists
	•	A List represents a collection grouping (e.g., “Used Collection #3” or “Friends Hotel Lot”).
	•	Users can:
	•	Add a new list and name it
	•	Rename an existing list
	•	Delete a list
	•	Each list contains multiple sets.

2.2 Sets
	•	A Set represents an individual LEGO set identified by its BrickLink ID.
	•	Users can:
	•	Add a new set by entering its BrickLink ID
	•	Edit the set name
	•	Delete a set from a list
	•	When a set is added:
	•	The app checks if its data exists locally
	•	If not, it fetches and parses BrickLink data:
	•	Set name
	•	Thumbnail URL
	•	Parts list (with part ID, color ID, and quantity)
	•	Sets display placeholder thumbnails if images aren’t available.

2.3 Parts
	•	Each set stores its parts, grouped by color.
	•	Each part record contains:
	•	Part ID
	•	Color ID
	•	Quantity needed
	•	Quantity owned (default 0)
	•	The MVP includes data storage for parts but no UI yet.

⸻

3. User Interface
	•	Primary Navigation:
NavigationSplitView
	•	Sidebar: Lists
	•	Content Area: Sets for selected list
	•	List View:
Displays all user-defined lists with options to add, rename, or delete.
	•	Set View:
Displays all sets within a selected list using cards or grid layout with:
	•	Set number
	•	Set name
	•	Placeholder thumbnail
	•	Minimalistic design emphasizing clarity and speed:
	•	Rounded cards
	•	SF Symbols for icons
	•	Light/Dark mode compatible

⸻

4. Data Model (SwiftData)

Entity	Attributes	Relationships
List	id, name	has many Sets
Set	id, setNumber, name, thumbnailURL	belongs to List, has many Parts
Part	id, partID, colorID, quantityNeeded, quantityHave	belongs to Set

All data persists locally using SwiftData with automatic updates reflected in the UI.

⸻

5. Scraping Subsystem

Purpose: Retrieve set metadata and part lists from BrickLink.

Workflow:
	1.	User enters a BrickLink set ID.
	2.	App fetches the set’s BrickLink page HTML.
	3.	A DOM parser extracts:
	•	Set name
	•	Thumbnail image URL
	•	Parts table (part ID, color ID, quantity)
	4.	Parsed data is stored in SwiftData.

Scope:
Scraping occurs on-demand when a set is added. Cached data prevents redundant requests.

⸻

6. Definition of Done (MVP)

✅ Add, rename, and delete lists
✅ Add, rename, and delete sets within lists
✅ Fetch and store set details from BrickLink
✅ Store structured part data locally
✅ Persist all data using SwiftData
✅ Display sets with placeholder thumbnails
✅ Clean SwiftUI navigation and consistent UI interactions

⸻

Would you like this rewritten as a developer handoff document next — including brief implementation notes and structure for files/folders (e.g., Models, Views, Services, Persistence)? That would make it ready for immediate Xcode setup.