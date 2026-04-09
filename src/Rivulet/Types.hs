module Rivulet.Types where

import Rivulet.FFI.Protocol

import Data.Char            (toUpper)
import Data.Map
import Data.Set             (Set)
import Foreign
import Numeric              (showHex)

type Arrangement = [(WindowId, Rect)]

type Prearrangement = [(WindowId, Rect)]

data Margins = Margins Int Int deriving (Show)

class Layout l where
    propose :: l -> Monitor -> Margins -> [WindowId] -> Prearrangement

    arrange :: l -> Monitor -> Margins -> [(WindowId, (Int, Int))] -> Arrangement

instance Layout SomeLayout where
    propose (SomeLayout l) = propose l
    arrange (SomeLayout l) = arrange l

data SomeLayout = forall l. (Layout l) => SomeLayout l

data Rect = Rect
    { x      :: Int
    , y      :: Int
    , width  :: Int
    , height :: Int
    }
    deriving (Show)

newtype MonitorId = MonitorId WordPtr deriving (Eq, Ord)

newtype WorkspaceId = WorkspaceId (MonitorId, Word8) deriving (Eq, Ord)
newtype WindowId = WindowId WordPtr deriving (Eq, Ord)
newtype SeatId = SeatId WordPtr deriving (Eq, Ord)

data CleanupRef
    = CleanupSeat SeatId
    | CleanupWindow WindowId
    | CleanupMonitor MonitorId
    | CleanupLayerShellOutput MonitorId
    | CleanupLayerShellSeat SeatId
    deriving (Eq, Ord, Show)

instance Show MonitorId where show (MonitorId p) = "MonitorId 0x" <> fmap toUpper (showHex p "")
instance Show WorkspaceId where show (WorkspaceId (m, i)) = "Workspace " <> show m <> "/" <> show i
instance Show WindowId where show (WindowId p) = "WindowId 0x" <> fmap toUpper (showHex p "")
instance Show SeatId where show (SeatId p) = "SeatId 0x" <> fmap toUpper (showHex p "")

defaultBorder :: Border
defaultBorder =
    Border
        { edges = 0
        , borderWidth = 0
        , color = 0x00000000
        }

data Border = Border
    { edges       :: Word32
    , borderWidth :: Int
    , color       :: Word32
    }
    deriving (Show)

data Seat = Seat
    { rawSeat         :: Ptr RiverSeatV1
    , rawXkbSeat      :: Ptr RiverXkbBindingsSeatV1
    , xkbSeatCleanup  :: IO ()
    , lastSentFocus   :: Maybe WindowId
    , keyboardFocus   :: Maybe WindowId
    , mouseFocus      :: Maybe WindowId
    , pendingBindings :: [(Ptr RiverXkbBindingV1, IO ())]
    , seatBindings    :: [(Ptr RiverXkbBindingV1, IO ())]
    }

data Window = Window
    { rawWindow    :: Ptr RiverWindowV1
    , rawNode      :: Maybe (Ptr RiverNodeV1)
    , winGeometry  :: Rect
    , winProposed  :: Maybe (Int, Int)
    , winWorkspace :: WorkspaceId
    , floating     :: Bool
    , appId        :: Maybe String
    , winTitle     :: Maybe String
    , fullscreen   :: (Bool, Maybe MonitorId)
    , lastPosition :: Maybe (Int, Int)
    }

data SequencePhase = Managing | Rendering | Idle

data Workspace = Workspace
    { wsName    :: String
    , wsWindows :: [WindowId]
    , layouts   :: [SomeLayout]
    }

data LayerShellOutputState = LayerShellOutputState
    { layerShellOutputPtr        :: Ptr RiverLayerShellOutputV1
    , layerShellOutputCleanupRef :: CleanupRef
    }

data LayerShellSeatState = LayerShellSeatState
    { layerShellSeatPtr            :: Ptr RiverLayerShellSeatV1
    , layerShellSeatCleanupRef     :: CleanupRef
    , layerShellSeatExclusiveFocus :: Bool
    }

data LayerShellState = LayerShellState
    { layerShellManager :: Ptr RiverLayerShellV1
    , layerShellOutputs :: Map MonitorId LayerShellOutputState
    , layerShellSeats   :: Map SeatId LayerShellSeatState
    }

data WMState = WMState
    { phase              :: SequencePhase
    , rawWM              :: Ptr RiverWindowManagerV1
    , rawXkb             :: Ptr RiverXkbBindingsV1
    , rawInput           :: Ptr RiverInputManagerV1
    , layerShell         :: LayerShellState
    , monitors           :: Map MonitorId Monitor
    , windows            :: Map WindowId Window
    , seats              :: Map SeatId Seat
    , workspaces         :: Map WorkspaceId Workspace
    , borders            :: (Border, Border)
    , dirtyMonitors      :: Set MonitorId
    , lastVisibleWindows :: Map MonitorId (Set WindowId)
    , cleanupRegistry    :: Map CleanupRef (IO ())
    }

data Monitor = Monitor
    { rawOutput       :: Ptr RiverOutputV1
    , activeSpace     :: WorkspaceId
    , monitorGeometry :: Rect
    , workArea        :: Rect
    }
