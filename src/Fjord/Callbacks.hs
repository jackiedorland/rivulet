{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE LambdaCase #-}
module Fjord.Callbacks where

import Fjord.Types

import Foreign
import Control.Concurrent.STM
import Data.Map qualified as Map
import Data.IORef
import Fjord.FFI.Protocol

infixl 1 <<<
(<<<) :: TQueue a -> a -> STM ()
(<<<) = writeTQueue

fi :: (Integral a, Num b) => a -> b
fi a = fromIntegral a

class FromPtr a p where
    fromPtr :: Ptr p -> a

instance FromPtr WindowId RiverWindowV1 where
    fromPtr =
        WindowId . ptrToWordPtr . castPtr

instance FromPtr OutputId RiverOutputV1 where
    fromPtr =
        OutputId . ptrToWordPtr . castPtr

instance FromPtr SeatId RiverSeatV1 where
    fromPtr =
        SeatId . ptrToWordPtr . castPtr

instance FromPtr ShellId RiverShellSurfaceV1 where
    fromPtr =
        ShellId . ptrToWordPtr . castPtr

initWindowListener :: TQueue Event -> IORef (Map.Map ObjectId Destructor) -> WindowListener
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

initOutputListener :: TQueue Event -> IORef (Map.Map ObjectId Destructor) -> OutputListener
initOutputListener q dt =
    OutputListener
        { onOutRemoved    = handleOutRemoved q
        , onOutWlOutput   = handleOutWlOutput q
        , onOutPosition   = handleOutPosition q
        , onOutDimensions = handleOutDimensions q
        }

initSeatListener :: TQueue Event -> IORef (Map.Map ObjectId Destructor) -> SeatListener
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

initWindowManagerListener :: TQueue Event -> IORef (Map.Map ObjectId Destructor) -> WindowManagerListener
initWindowManagerListener q dt =
    WindowManagerListener
        { onWmUnavailable     = handleWmUnavailable q
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

handleWmUnavailable :: TQueue Event -> Ptr RiverWindowManagerV1 -> IO ()
handleWmUnavailable q _ = do
    atomically $ 
        q <<< RiverUnavailable

handleWmFinished :: TQueue Event -> Ptr RiverWindowManagerV1 -> IO ()
handleWmFinished q _ = do
    atomically $ 
        q <<< RiverFinished 

handleWmManageStart :: TQueue Event -> Ptr RiverWindowManagerV1 -> IO ()
handleWmManageStart q wm = do
    -- manage transaction begins
    pure ()

handleWmRenderStart :: TQueue Event -> Ptr RiverWindowManagerV1 -> IO ()
handleWmRenderStart q wm = do
    -- render transaction begins
    pure ()

handleWmSessionLocked :: TQueue Event -> Ptr RiverWindowManagerV1 -> IO ()
handleWmSessionLocked q _ = do
    atomically $
        q <<< RiverLocked

handleWmSessionUnlocked :: TQueue Event -> Ptr RiverWindowManagerV1 -> IO ()
handleWmSessionUnlocked q wm = do
    atomically $ 
        q <<< RiverUnlocked

{- object creation -}

handleWmWindow :: TQueue Event -> IORef (Map.Map ObjectId Destructor) -> Ptr RiverWindowManagerV1 -> Ptr RiverWindowV1 -> IO ()
handleWmWindow q dt wm win = do
    let wid = fromPtr win

    cleanupPtr <- riverWindowV1AddListener win $ initWindowListener q dt 

    modifyIORef' dt $ 
        Map.insert (WindowObject wid) (Destructor cleanupPtr) 

    atomically $ 
        q <<< WinCreated wid

handleWmOutput :: TQueue Event -> IORef (Map.Map ObjectId Destructor) -> Ptr RiverWindowManagerV1 -> Ptr RiverOutputV1 -> IO ()
handleWmOutput q dt wm out = do
    let oid = fromPtr out

    cleanupPtr <- riverOutputV1AddListener out $ initOutputListener q dt 

    modifyIORef' dt $ 
        Map.insert (OutputObject oid) (Destructor cleanupPtr) 

    atomically $ 
        q <<< OutputCreated oid

handleWmSeat :: TQueue Event -> IORef (Map.Map ObjectId Destructor) -> Ptr RiverWindowManagerV1 -> Ptr RiverSeatV1 -> IO ()
handleWmSeat q dt wm seat = do
    let sid = fromPtr seat

    cleanupPtr <- riverSeatV1AddListener seat $ initSeatListener q dt 

    modifyIORef' dt $ 
        Map.insert (SeatObject sid) (Destructor cleanupPtr) 

    atomically $ 
        q <<< SeatCreated sid

{- window handlers -}

handleWinClosed :: TQueue Event -> Ptr RiverWindowV1 -> IO ()
handleWinClosed q win = atomically $
    q <<< WinClosed (fromPtr win)

handleWinDimensionsHint :: TQueue Event -> Ptr RiverWindowV1 -> Int -> Int -> Int -> Int -> IO ()
handleWinDimensionsHint q win minW minH maxW maxH = atomically $
        q <<< WinDimensionsHint (fromPtr win) 
            (fi minW)
            (fi minH)
            (fi maxW)
            (fi maxH)

handleWinDimensions :: TQueue Event -> Ptr RiverWindowV1 -> Int -> Int -> IO ()
handleWinDimensions q win w h = atomically $
    q <<< WinDimensions (fromPtr win) (fi w) (fi h)

handleWinAppId :: TQueue Event -> Ptr RiverWindowV1 -> Maybe String -> IO ()
handleWinAppId q win appId = atomically $
    q <<< WinSetAppId (fromPtr win) appId

handleWinTitle :: TQueue Event -> Ptr RiverWindowV1 -> Maybe String -> IO ()
handleWinTitle q win title = atomically $
    q <<< WinSetTitle (fromPtr win) title

handleWinParent :: TQueue Event -> Ptr RiverWindowV1 -> Maybe (Ptr RiverWindowV1) -> IO ()
handleWinParent q win parent = atomically $
    q <<< WinSetParent (fromPtr win) (fromPtr <$> parent)

handleWinDecorationHint :: TQueue Event -> Ptr RiverWindowV1 -> Word32 -> IO ()
handleWinDecorationHint q win hint = atomically $
    q <<< WinDecorationHint (fromPtr win) (
        case hint of
            0 -> Just NoDecoration
            1 -> Just ClientDecoration
            2 -> Just ServerDecoration
            3 -> Just BothDecorations
            _ -> Nothing
        )

handleWinPointerMoveReq :: TQueue Event -> Ptr RiverWindowV1 -> Ptr RiverSeatV1 -> IO ()
handleWinPointerMoveReq q win seat = atomically $
    q <<< WinPtrMoveReq (fromPtr win) (fromPtr seat)

decodeEdges :: Word32 -> [Edge]
decodeEdges x =
    concat
        [ [Top       | x .&. 1 /= 0]
        , [Bottom    | x .&. 2 /= 0]
        , [LeftEdge  | x .&. 4 /= 0]
        , [RightEdge | x .&. 8 /= 0]
        ]

handleWinPointerResizeReq :: TQueue Event -> Ptr RiverWindowV1 -> Ptr RiverSeatV1 -> Word32 -> IO ()
handleWinPointerResizeReq q win seat edges = atomically $
    q <<< WinPtrResizeReq (fromPtr win) (fromPtr seat) (decodeEdges edges)

handleWinShowMenuReq :: TQueue Event -> Ptr RiverWindowV1 -> Int -> Int -> IO ()
handleWinShowMenuReq q win x y = do
    pure () -- i don't care

handleWinMaximizeReq :: TQueue Event -> Ptr RiverWindowV1 -> IO ()
handleWinMaximizeReq q win = atomically $
    q <<< WinMaximizeReq (fromPtr win)

handleWinUnmaximizeReq :: TQueue Event -> Ptr RiverWindowV1 -> IO ()
handleWinUnmaximizeReq q win = atomically $
    q <<< WinUnmaximizeReq (fromPtr win)

handleWinFullscreenReq :: TQueue Event -> Ptr RiverWindowV1 -> Maybe (Ptr RiverOutputV1) -> IO ()
handleWinFullscreenReq q win output = atomically $
    q <<< WinFullscreenReq (fromPtr win) (fromPtr <$> output)

handleWinExitFullscreenReq :: TQueue Event -> Ptr RiverWindowV1 -> IO ()
handleWinExitFullscreenReq q win = atomically $
    q <<< WinExitFullscreenReq (fromPtr win)

handleWinMinimizeReq :: TQueue Event -> Ptr RiverWindowV1 -> IO ()
handleWinMinimizeReq q win = atomically $
    q <<< WinMinimizeReq (fromPtr win)

handleWinUnreliablePid :: TQueue Event -> Ptr RiverWindowV1 -> Int -> IO ()
handleWinUnreliablePid q win pid = atomically $
    q <<< WinUnreliablePID (fromPtr win) (fi pid)

{- outputs -}

handleOutRemoved :: TQueue Event -> Ptr RiverOutputV1 -> IO ()
handleOutRemoved q out = atomically $
    q <<< OutRemoved (fromPtr out)

handleOutWlOutput :: TQueue Event -> Ptr RiverOutputV1 -> Word32 -> IO ()
handleOutWlOutput q out wl = atomically $
    q <<< OutWlName (fromPtr out) (fi wl)

handleOutPosition :: TQueue Event -> Ptr RiverOutputV1 -> Int -> Int -> IO ()
handleOutPosition q out x y = atomically $
    q <<< OutPosition (fromPtr out) (fi x) (fi y)

handleOutDimensions :: TQueue Event -> Ptr RiverOutputV1 -> Int -> Int -> IO ()
handleOutDimensions q out w h = atomically $
    q <<< OutDimensions (fromPtr out) (fi w) (fi h)

{- seats -}

handleSeatRemoved :: TQueue Event -> Ptr RiverSeatV1 -> IO ()
handleSeatRemoved q seat = atomically $
    q <<< SeatRemoved (fromPtr seat)

handleSeatWlSeat :: TQueue Event -> Ptr RiverSeatV1 -> Word32 -> IO ()
handleSeatWlSeat q seat wl = atomically $
    q <<< SeatWlName (fromPtr seat) (fi wl)

handleSeatPointerEnter :: TQueue Event -> Ptr RiverSeatV1 -> Ptr RiverWindowV1 -> IO ()
handleSeatPointerEnter q seat win = atomically $
    q <<< SeatPtrEnter (fromPtr seat) (fromPtr win)

handleSeatPointerLeave :: TQueue Event -> Ptr RiverSeatV1 -> IO ()
handleSeatPointerLeave q seat = atomically $
    q <<< SeatPtrLeave (fromPtr seat)

handleSeatWindowInteraction :: TQueue Event -> Ptr RiverSeatV1 -> Ptr RiverWindowV1 -> IO ()
handleSeatWindowInteraction q seat win = atomically $
    q <<< SeatWinInteraction (fromPtr seat) (fromPtr win)

handleSeatShellInteraction :: TQueue Event -> Ptr RiverSeatV1 -> Ptr RiverShellSurfaceV1 -> IO ()
handleSeatShellInteraction q seat shell = atomically $
    q <<< SeatShellInteraction (fromPtr seat) (fromPtr shell)

handleSeatOpDelta :: TQueue Event -> Ptr RiverSeatV1 -> Int -> Int -> IO ()
handleSeatOpDelta q seat dx dy = atomically $
    q <<< SeatOpDelta (fromPtr seat) (fi dx) (fi dy)

handleSeatOpRelease :: TQueue Event -> Ptr RiverSeatV1 -> IO ()
handleSeatOpRelease q seat = atomically $
    q <<< SeatOpRelease (fromPtr seat)

handleSeatPointerPosition :: TQueue Event -> Ptr RiverSeatV1 -> Int -> Int -> IO ()
handleSeatPointerPosition q seat x y = atomically $
    q <<< SeatPtrPos (fromPtr seat) (fi x) (fi y)
