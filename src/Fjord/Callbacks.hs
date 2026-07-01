module Fjord.Callbacks where

import Fjord.Model

import Foreign
import Control.Concurrent.STM
import Data.Map
import Data.IORef
import Fjord.FFI.Protocol

newtype Destructor = Destructor (IO ())

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

initWindowListener :: TQueue Event -> IORef (Map ObjectId Destructor) -> WindowListener
initWindowListener q dt =
    WindowListener
        { onWinClosed            = handleWinClosed q
        , onWinDimensionsHint    = handleWinDimensionsHint q
        , onWinDimensions        = handleWinDimensions q
        , onWinAppId             = handleWinAppId q
        , onWinTitle             = handleWinTitle q
        , onWinParent            = handleWinParent q
        , onWinDecorationHint    = handleWinDecorationHint q
        , onWinPointerMoveReq    = handleWinPointerMoveReq q
        , onWinPointerResizeReq  = handleWinPointerResizeReq q
        , onWinShowMenuReq       = handleWinShowMenuReq q
        , onWinMaximizeReq       = handleWinMaximizeReq q
        , onWinUnmaximizeReq     = handleWinUnmaximizeReq q
        , onWinFullscreenReq     = handleWinFullscreenReq q
        , onWinExitFullscreenReq = handleWinExitFullscreenReq q
        , onWinMinimizeReq       = handleWinMinimizeReq q
        , onWinUnreliablePid     = handleWinUnreliablePid q
        , onWinPresentationHint  = \_ _ -> pure ()
        , onWinIdentifier        = \_ _ -> pure ()
        }

initOutputListener :: TQueue Event -> IORef (Map ObjectId Destructor) -> OutputListener
initOutputListener q dt =
    OutputListener
        { onOutRemoved    = handleOutRemoved q
        , onOutWlOutput   = handleOutWlOutput q
        , onOutPosition   = handleOutPosition q
        , onOutDimensions = handleOutDimensions q
        }

initSeatListener :: TQueue Event -> IORef (Map ObjectId Destructor) -> SeatListener
initSeatListener q dt =
    SeatListener
        { onSeatRemoved           = handleSeatRemoved q
        , onSeatWlSeat            = handleSeatWlSeat q
        , onSeatPointerEnter      = handleSeatPointerEnter q
        , onSeatPointerLeave      = handleSeatPointerLeave q
        , onSeatWindowInteraction = handleSeatWindowInteraction q
        , onSeatShellInteraction  = handleSeatShellInteraction q
        , onSeatOpDelta           = handleSeatOpDelta q
        , onSeatOpRelease         = handleSeatOpRelease q
        , onSeatPointerPosition   = handleSeatPointerPosition q
        }

initWindowManagerListener :: TQueue Event -> IORef (Map ObjectId Destructor) -> WindowManagerListener
initWindowManagerListener q dt =
    WindowManagerListener
        { onWmUnavailable     = handleWmUnavailable
        , onWmFinished        = handleWmFinished q
        , onWmManageStart     = handleWmManageStart q
        , onWmRenderStart     = handleWmRenderStart q
        , onWmSessionLocked   = handleWmSessionLocked q
        , onWmSessionUnlocked = handleWmSessionUnlocked q
        , onWmWindow          = handleWmWindow q dt
        , onWmOutput          = handleWmOutput q dt
        , onWmSeat            = handleWmSeat q dt
        }

{- top-level river handlers -}

handleWmUnavailable :: IORef (Map ObjectId Destructor) -> Ptr RiverWindowManagerV1 -> IO ()
handleWmUnavailable ptr = do
    
    pure ()

handleWmFinished :: TQueue Event -> Ptr RiverWindowManagerV1 -> IO ()
handleWmFinished q wm = do
    -- enqueue RiverFinished
    pure ()

handleWmManageStart :: TQueue Event -> Ptr RiverWindowManagerV1 -> IO ()
handleWmManageStart q wm = do
    -- manage transaction begins
    pure ()

handleWmRenderStart :: TQueue Event -> Ptr RiverWindowManagerV1 -> IO ()
handleWmRenderStart q wm = do
    -- render transaction begins
    pure ()

handleWmSessionLocked :: TQueue Event -> Ptr RiverWindowManagerV1 -> IO ()
handleWmSessionLocked q wm = do
    -- enqueue RiverLocked
    pure ()

handleWmSessionUnlocked :: TQueue Event -> Ptr RiverWindowManagerV1 -> IO ()
handleWmSessionUnlocked q wm = do
    -- enqueue RiverUnlocked
    pure ()

{- object creation -}

handleWmWindow :: TQueue Event -> IORef (Map ObjectId Destructor) -> Ptr RiverWindowManagerV1 -> Ptr RiverWindowV1 -> IO ()
handleWmWindow q dt wm win = do
    let wid = WindowId $
            ptrToWordPtr $
                castPtr win

    -- install window listener

    -- register destructor

    -- enqueue WinCreated wid

    pure ()

handleWmOutput :: TQueue Event -> IORef (Map ObjectId Destructor) -> Ptr RiverWindowManagerV1 -> Ptr RiverOutputV1 -> IO ()
handleWmOutput q dt wm out = do
    let oid = OutputId $
            ptrToWordPtr $
                castPtr out

    -- install output listener

    -- register destructor

    -- enqueue OutputCreated oid

    pure ()

handleWmSeat :: TQueue Event -> IORef (Map ObjectId Destructor) -> Ptr RiverWindowManagerV1 -> Ptr RiverSeatV1 -> IO ()
handleWmSeat q dt wm seat = do
    let sid = SeatId $
            ptrToWordPtr $
                castPtr seat

    -- install seat listener

    -- register destructor

    -- enqueue SeatCreated sid

    pure ()

{- window handlers -}

handleWinClosed :: TQueue Event -> Ptr RiverWindowV1 -> IO ()
handleWinClosed q win = do
    pure ()

handleWinDimensionsHint :: TQueue Event -> Ptr RiverWindowV1 -> Int -> Int -> Int -> Int -> IO ()
handleWinDimensionsHint q win minW minH maxW maxH = do
    pure ()

handleWinDimensions :: TQueue Event -> Ptr RiverWindowV1 -> Int -> Int -> IO ()
handleWinDimensions q win w h = do
    pure ()

handleWinAppId :: TQueue Event -> Ptr RiverWindowV1 -> Maybe String -> IO ()
handleWinAppId q win appId = do
    pure ()

handleWinTitle :: TQueue Event -> Ptr RiverWindowV1 -> Maybe String -> IO ()
handleWinTitle q win title = do
    pure ()

handleWinParent :: TQueue Event -> Ptr RiverWindowV1 -> Maybe (Ptr RiverWindowV1) -> IO ()
handleWinParent q win parent = do
    pure ()

handleWinDecorationHint :: TQueue Event -> Ptr RiverWindowV1 -> Word32 -> IO ()
handleWinDecorationHint q win hint = do
    pure ()

handleWinPointerMoveReq :: TQueue Event -> Ptr RiverWindowV1 -> Ptr RiverSeatV1 -> IO ()
handleWinPointerMoveReq q win seat = do
    pure ()

handleWinPointerResizeReq :: TQueue Event -> Ptr RiverWindowV1 -> Ptr RiverSeatV1 -> Word32 -> IO ()
handleWinPointerResizeReq q win seat edges = do
    pure ()

handleWinShowMenuReq :: TQueue Event -> Ptr RiverWindowV1 -> Int -> Int -> IO ()
handleWinShowMenuReq q win x y = do
    pure ()

handleWinMaximizeReq :: TQueue Event -> Ptr RiverWindowV1 -> IO ()
handleWinMaximizeReq q win = do
    pure ()

handleWinUnmaximizeReq :: TQueue Event -> Ptr RiverWindowV1 -> IO ()
handleWinUnmaximizeReq q win = do
    pure ()

handleWinFullscreenReq :: TQueue Event -> Ptr RiverWindowV1 -> Maybe (Ptr RiverOutputV1) -> IO ()
handleWinFullscreenReq q win output = do
    pure ()

handleWinExitFullscreenReq :: TQueue Event -> Ptr RiverWindowV1 -> IO ()
handleWinExitFullscreenReq q win = do
    pure ()

handleWinMinimizeReq :: TQueue Event -> Ptr RiverWindowV1 -> IO ()
handleWinMinimizeReq q win = do
    pure ()

handleWinUnreliablePid :: TQueue Event -> Ptr RiverWindowV1 -> Int -> IO ()
handleWinUnreliablePid q win pid = do
    pure ()

{- outputs -}

handleOutRemoved :: TQueue Event -> Ptr RiverOutputV1 -> IO ()
handleOutRemoved q out = do
    pure ()

handleOutWlOutput :: TQueue Event -> Ptr RiverOutputV1 -> Word32 -> IO ()
handleOutWlOutput q out wl = do
    pure ()

handleOutPosition :: TQueue Event -> Ptr RiverOutputV1 -> Int -> Int -> IO ()
handleOutPosition q out x y = do
    pure ()

handleOutDimensions :: TQueue Event -> Ptr RiverOutputV1 -> Int -> Int -> IO ()
handleOutDimensions q out w h = do
    pure ()

{- seats -}

handleSeatRemoved :: TQueue Event -> Ptr RiverSeatV1 -> IO ()
handleSeatRemoved q seat = do
    pure ()

handleSeatWlSeat :: TQueue Event -> Ptr RiverSeatV1 -> Word32 -> IO ()
handleSeatWlSeat q seat wl = do
    pure ()

handleSeatPointerEnter :: TQueue Event -> Ptr RiverSeatV1 -> Ptr RiverWindowV1 -> IO ()
handleSeatPointerEnter q seat win = do
    pure ()

handleSeatPointerLeave :: TQueue Event -> Ptr RiverSeatV1 -> IO ()
handleSeatPointerLeave q seat = do
    pure ()

handleSeatWindowInteraction :: TQueue Event -> Ptr RiverSeatV1 -> Ptr RiverWindowV1 -> IO ()
handleSeatWindowInteraction q seat win = do
    pure ()

handleSeatShellInteraction :: TQueue Event -> Ptr RiverSeatV1 -> Ptr RiverShellSurfaceV1 -> IO ()
handleSeatShellInteraction q seat shell = do
    pure ()

handleSeatOpDelta :: TQueue Event -> Ptr RiverSeatV1 -> Int -> Int -> IO ()
handleSeatOpDelta q seat dx dy = do
    pure ()

handleSeatOpRelease :: TQueue Event -> Ptr RiverSeatV1 -> IO ()
handleSeatOpRelease q seat = do
    pure ()

handleSeatPointerPosition :: TQueue Event -> Ptr RiverSeatV1 -> Int -> Int -> IO ()
handleSeatPointerPosition q seat x y = do
    pure ()