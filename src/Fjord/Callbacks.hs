{-# LANGUAGE OverloadedStrings #-}
module Fjord.Callbacks where

import Fjord.Model

import Foreign
import Control.Concurrent.STM
import Data.Map qualified as Map
import Data.IORef
import Fjord.FFI.Protocol
import Fjord.Log

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


newtype Destructor = Destructor (IO ())

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
        writeTQueue q $ RiverUnavailable

handleWmFinished :: TQueue Event -> Ptr RiverWindowManagerV1 -> IO ()
handleWmFinished q _ = do
    atomically $ 
        writeTQueue q $ RiverFinished 

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
        writeTQueue q $ RiverLocked

handleWmSessionUnlocked :: TQueue Event -> Ptr RiverWindowManagerV1 -> IO ()
handleWmSessionUnlocked q wm = do
    atomically $ 
        writeTQueue q $ RiverUnlocked

{- object creation -}

handleWmWindow :: TQueue Event -> IORef (Map.Map ObjectId Destructor) -> Ptr RiverWindowManagerV1 -> Ptr RiverWindowV1 -> IO ()
handleWmWindow q dt wm win = do
    let wid = fromPtr win

    cleanupPtr <- riverWindowV1AddListener win $ initWindowListener q dt 

    modifyIORef' dt $ 
        Map.insert (WindowObject wid) (Destructor cleanupPtr) 

    atomically $ 
        writeTQueue q $ WinCreated wid

handleWmOutput :: TQueue Event -> IORef (Map.Map ObjectId Destructor) -> Ptr RiverWindowManagerV1 -> Ptr RiverOutputV1 -> IO ()
handleWmOutput q dt wm out = do
    let oid = fromPtr out

    cleanupPtr <- riverOutputV1AddListener out $ initOutputListener q dt 

    modifyIORef' dt $ 
        Map.insert (OutputObject oid) (Destructor cleanupPtr) 

    atomically $ 
        writeTQueue q $ OutputCreated oid

handleWmSeat :: TQueue Event -> IORef (Map.Map ObjectId Destructor) -> Ptr RiverWindowManagerV1 -> Ptr RiverSeatV1 -> IO ()
handleWmSeat q dt wm seat = do
    let sid = fromPtr seat

    cleanupPtr <- riverSeatV1AddListener seat $ initSeatListener q dt 

    modifyIORef' dt $ 
        Map.insert (SeatObject sid) (Destructor cleanupPtr) 

    atomically $ 
        writeTQueue q $ SeatCreated sid

{- window handlers -}

handleWinClosed :: TQueue Event -> Ptr RiverWindowV1 -> IO ()
handleWinClosed q win = atomically $
    writeTQueue q $ WinClosed (fromPtr win)

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