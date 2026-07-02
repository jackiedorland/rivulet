{-# LANGUAGE GeneralizedNewtypeDeriving #-}
module Fjord.Model where

import Fjord.Layout

import Foreign
import Data.Map
import Data.Set
import Numeric (showHex)

newtype WindowId    = WindowId WordPtr deriving (Ord, Eq)
newtype SeatId      = SeatId WordPtr deriving (Ord, Eq)
newtype OutputId    = OutputId WordPtr deriving (Ord, Eq)
newtype NodeId      = NodeId WordPtr
newtype WorkspaceId = WorkspaceId Word8 deriving Show
newtype ShellId     = ShellId WordPtr

showPtr :: (Integral a) => a -> String
showPtr x = "0x" ++ showHex x ""

instance Show WindowId where
    show (WindowId x) = showPtr x

instance Show SeatId where
    show (SeatId x) = showPtr x

instance Show OutputId where
    show (OutputId x) = showPtr x

instance Show NodeId where
    show (NodeId x) = showPtr x

instance Show ShellId where
    show (ShellId x) = showPtr x

data ObjectId
    = WindowObject WindowId
    | OutputObject OutputId
    | SeatObject SeatId
    deriving (Show, Ord, Eq)
    
newtype Edges = Edges Word8 deriving (Show)

data Event -- river_window_manager_v1
           = RiverUnavailable 
           | RiverFinished
           | RiverLocked
           | RiverUnlocked
           | WinCreated WindowId
           | OutputCreated OutputId
           | SeatCreated SeatId
           -- river_window_v1
           | WinClosed WindowId 
           | WinDimensionsHint WindowId Word Word Word Word -- min_width, max_width, max_width, max_height
           | WinDimensions WindowId Word Word -- width, height
           | WinSetAppId WindowId (Maybe String)
           | WinSetTitle WindowId (Maybe String)
           | WinSetParent WindowId (Maybe WindowId) -- ID of parent window
           | WinDecorationHint WindowId Word8
           | WinPtrMoveReq WindowId SeatId -- ID of seat where pointer move has been requested; wm should call river_seat_v1.op_start_pointer
           | WinPtrResizeReq WindowId SeatId Edges -- see above ^, also edges bitfield 
           | WinShowDecorationMenu WindowId Int Int -- likely ignored
           | WinMaximizeReq WindowId 
           | WinUnmaximizeReq WindowId 
           | WinFullscreenReq WindowId (Maybe OutputId) -- output where the window wants to be fullscreened
           | WinExitFullscreenReq WindowId 
           | WinMinimizeReq WindowId 
           | WinUnreliablePID WindowId Word -- pid of software
           -- river_output_v1
           | OutRemoved OutputId 
           | OutWlName OutputId Word -- Wayland internal name (or uint id)
           | OutPosition OutputId Int Int -- x, y
           | OutDimensions OutputId Word Word -- width, height
           -- river_seat_v1
           | SeatRemoved SeatId
           | SeatWlName SeatId Word -- Wayland internal name (or uint id)
           | SeatPtrEnter SeatId WindowId -- window that pointer entered
           | SeatPtrLeave SeatId -- see above
           | SeatWinInteraction SeatId WindowId -- Window that pointer interacted with
           | SeatShellInteraction SeatId ShellId -- shell surface that pointer interacted with
           | SeatOpDelta SeatId Int Int -- Δx, Δy
           | SeatOpRelease SeatId
           | SeatPtrPos SeatId Int Int

data Color = Color Word32 Word32 Word32 Word32 -- R G B A, all 32-bit uint for some reason.. freaky!
data Border = Border Edges Word16 Color  -- edges bitfield, width, then RGBA hex value

newtype Ratio = Ratio Word16 deriving Show
data Tree a
    = Empty
    | Leaf a
    | Split Ratio Direction (Tree a) (Tree a)
    deriving (Show)

data Direction = Horizontal | Vertical deriving Show

data Window = Window {    
    -- object identification + node
    windowId :: WindowId
  , node :: NodeId

    -- (kind of) identification info
  , app_id :: Maybe String
  , parent :: Maybe WindowId
  , title :: Maybe String
  , wl_name :: Maybe Word

    -- flags
  , hidden :: Bool
  , fullscreen :: Bool
  , csd :: Bool

    -- geometry
  , dim :: Rectangle
  , border :: Border
}

data Seat = Seat {
    seatId :: SeatId

  , wl_name :: Maybe Word
  , opDelta :: (Int, Int) -- dx, dy
  , ptrPos  :: (Int, Int) -- x, y
}

data Workspace = Workspace { 
    tree :: Tree WindowId
  , focusedWindow :: WindowId
}

data Output = Output {
    -- monitor ID + internal Wayland object name
    outputId :: OutputId
  , wl_name :: Maybe Word

    -- geometry
  , dim :: Rectangle
  , usable :: Rectangle -- dim - shell surfaces - gaps
  , workspace :: WorkspaceId
}

data State = State { -- maybe now i'll keep formatting consistent lol
    windows       :: Map WindowId Window
  , outputs       :: Map OutputId Output
  , seats         :: Map SeatId Seat
  , workspaces    :: Map Workspace Workspace
  , shells        :: Set ShellId
}