module Rivulet.Types where

import Rivulet.FFI.Protocol

import Data.Map
import Data.Set             (Set)
import Foreign
import Data.Char (toUpper)
import Numeric   (showHex)

-- | Represents the arrangement of windows on a monitor.
type Arrangement = [(WindowId, Rect)]

-- | Represents a proposed arrangement of windows before finalization.
type Prearrangement = [(WindowId, Rect)]

-- | Represents margins around windows or screens.
data Margins = Margins Int Int deriving (Show) -- gap size, border width

-- | Class for layout algorithms that can propose and arrange window placements.
class Layout l where
  -- | Proposes a new arrangement of windows based on the current state.
  propose :: l -> Monitor -> Margins -> [WindowId] -> Prearrangement

  -- | Arranges windows according to the proposed dimensions.
  arrange :: l -> Monitor -> Margins -> [(WindowId, (Int, Int))] -> Arrangement

instance Layout SomeLayout where
    propose (SomeLayout l) = propose l
    arrange (SomeLayout l) = arrange l

-- | Represents a polymorphic layout that can be any instance of Layout.
data SomeLayout = forall l. Layout l => SomeLayout l

-- | Represents a rectangle with x, y coordinates and dimensions.
data Rect = Rect {
    x      :: Int,        -- X coordinate
    y      :: Int,        -- Y coordinate
    width  :: Int,    -- Width of the rectangle
    height :: Int    -- Height of the rectangle
} deriving (Show)

-- | Unique identifier for a monitor.
newtype MonitorId   = MonitorId WordPtr          deriving (Eq, Ord)
newtype WorkspaceId = WorkspaceId (MonitorId, Word8) deriving (Eq, Ord)
newtype WindowId    = WindowId WordPtr           deriving (Eq, Ord)
newtype SeatId      = SeatId WordPtr             deriving (Eq, Ord)

instance Show MonitorId   where show (MonitorId p)        = "MonitorId 0x"  <> fmap toUpper (showHex p "")
instance Show WorkspaceId where show (WorkspaceId (m, i)) = "Workspace "    <> show m <> "/" <> show i
instance Show WindowId    where show (WindowId p)         = "WindowId 0x"   <> fmap toUpper (showHex p "")
instance Show SeatId      where show (SeatId p)           = "SeatId 0x"     <> fmap toUpper (showHex p "")

-- | Default border settings with no border and transparent color.
defaultBorder :: Border
defaultBorder = Border
    { edges       = 0          -- No edges drawn
    , borderWidth = 0          -- No border width
    , color       = 0x00000000
    }

-- | Represents border settings with customizable edges and colors.
data Border = Border
  {
    edges       :: Word32,     -- Bitfield indicating which edges to draw
    borderWidth :: Int,        -- Width of the border
    color       :: Word32
  } deriving (Show)

-- | Represents an input device seat with various focus states.
data Seat = Seat {
    rawSeat         :: Ptr RiverSeatV1,        -- Raw pointer to the seat
    rawXkbSeat      :: Ptr RiverXkbBindingsSeatV1,  -- Raw pointer to the XKB seat
    xkbSeatCleanup  :: IO (),
    lastSentFocus   :: Maybe WindowId,     -- Last window that had focus
    keyboardFocus   :: Maybe WindowId,     -- Current keyboard focus
    mouseFocus      :: Maybe WindowId,      -- Current mouse focus
    pendingBindings :: [(Ptr RiverXkbBindingV1, IO ())],
    seatBindings    :: [(Ptr RiverXkbBindingV1, IO ())]
}

-- | Represents a window with various properties.
data Window = Window
    {
        rawWindow    :: Ptr RiverWindowV1,   -- Raw pointer to the window
        rawNode      :: Maybe (Ptr RiverNodeV1),  -- Cached node pointer on first render
        winGeometry  :: Rect,                 -- Geometry of the window
        winProposed  :: Maybe (Int, Int),       -- Last dimensions proposed for this window
        winWorkspace :: WorkspaceId,          -- Workspace this window belongs to
        floating     :: Bool,                 -- Whether the window is floating
        appId        :: Maybe String,          -- Application ID associated with the window
        winTitle     :: Maybe String,          -- Title of window given by river_window_v1.title
        fullscreen   :: (Bool, Maybe MonitorId),
        lastPosition :: Maybe (Int, Int)
    }

-- | Represents a phase in the sequence of managing or rendering windows.
data SequencePhase = Managing | Rendering | Idle

-- | Represents a workspace containing windows and layout information.
data Workspace = Workspace
    {
        wsName    :: String,             -- Name of the workspace
        wsWindows :: [WindowId],         -- List of window IDs in this workspace
        layouts   :: [SomeLayout]
    }

-- | Represents the state of the window manager.
data WMState = WMState {
    phase          :: SequencePhase,    -- Current phase: managing or rendering
    rawWM          :: Ptr RiverWindowManagerV1, -- Raw pointer to the window manager
    rawXkb         :: Ptr RiverXkbBindingsV1,   -- Raw pointer to the XKB bindings
    rawInput       :: Ptr RiverInputManagerV1,-- Raw pointer to the input manager
    monitors       :: Map MonitorId Monitor,     -- Map of monitor IDs to monitor state
    windows        :: Map WindowId Window,       -- Map of window IDs to window state
    seats          :: Map SeatId Seat,           -- Map of seat IDs to seat state
    workspaces     :: Map WorkspaceId Workspace,-- Map of workspace IDs to workspace state
    borders        :: (Border, Border),        -- Tuple of border settings for unfocused and focused states
    dirtyMonitors  :: Set MonitorId,         -- Set of monitors that need re-arranging
    seatCleanup    :: Map SeatId (IO ()),      -- Cleanup function for each seat
    windowCleanup  :: Map WindowId (IO ()),  -- Cleanup function for each window
    monitorCleanup :: Map MonitorId (IO ())    -- Cleanup function for each monitor
}

-- | Represents a monitor with various properties.
data Monitor = Monitor {
    rawOutput       :: Ptr RiverOutputV1,   -- Raw pointer to the output
    activeSpace     :: WorkspaceId,        -- ID of the currently active workspace on this monitor
    monitorGeometry :: Rect,                 -- Geometry of the monitor
    workArea        :: Rect                  -- Work area within the monitor's geometry
}
