module Fjord.Model where

import Fjord.Layout

import Foreign
import Data.Map
import Data.Set

newtype WindowId = WindowId WordPtr
newtype SeatId = SeatId WordPtr
newtype OutputId = OutputId WordPtr
newtype NodeId = NodeId WordPtr
newtype WorkspaceId = WorkspaceId Word8
newtype ShellId = ShellId WordPtr

data ObjectId
    = WindowObject WindowId
    | OutputObject OutputId
    | SeatObject SeatId
    
newtype Edges = Edges Word8

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