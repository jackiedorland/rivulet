module Rivulet.Manager.Callbacks where

import           Control.Concurrent.STM
import           Control.Monad          (forM, when)
import           Control.Monad.Reader
import qualified Data.Map.Strict        as Map
import           Data.Maybe
import qualified Data.Set               as Set
import           Data.Word
import           Foreign
import           Rivulet.DSL            (Config (..))
import           Rivulet.DSL.Keys
import           Rivulet.DSL.Layout
import           Rivulet.FFI.Protocol
import           Rivulet.Manager.Log    (logEvent, logFail, logInfo)
import           Rivulet.Monad
import           Rivulet.Types
import           System.Exit

-- helpers
ptrId :: Ptr a -> Word32
ptrId = fromIntegral . ptrToWordPtr

defaultLayouts :: [SomeLayout]
defaultLayouts = [SomeLayout Tall]

-- Window Manager callbacks
onWmUnavailable :: Runtime -> Config -> Ptr RiverWindowManagerV1 -> IO ()
onWmUnavailable runtime _ _ =
  logFail
    (rtLogger runtime)
    "River-window-management-v1 Wayland extension is unavailable... is River running?"

onWmFinished :: Runtime -> Config -> Ptr RiverWindowManagerV1 -> IO ()
onWmFinished runtime _ _ = do
  logInfo (rtLogger runtime) "Wayland/River session finished. Exiting..."
  exitSuccess

onWmSessionLocked :: TVar WMState -> Config -> Ptr RiverWindowManagerV1 -> IO ()
onWmSessionLocked _ _ _ = pure ()

onWmSessionUnlocked ::
     TVar WMState -> Config -> Ptr RiverWindowManagerV1 -> IO ()
onWmSessionUnlocked _ _ _ = pure ()

onWmWindow ::
     Runtime
  -> Config
  -> WindowListener
  -> Ptr RiverWindowManagerV1
  -> Ptr RiverWindowV1
  -> IO ()
onWmWindow runtime _ listener _ winPtr = do
  let logger = rtLogger runtime
      wmState = rtState runtime
  let winId = WindowId (ptrId winPtr)
  logEvent logger "window" $ "new: " <> show winId
  node <- riverWindowV1GetNode winPtr
  updateState wmState $ \s ->
    let defaultWsId =
          case Map.elems (monitors s) of
            []    -> WorkspaceId (MonitorId 0, 0)
            (m:_) -> activeSpace m
        WorkspaceId (monId, _) = defaultWsId
        win =
          Window
            { rawWindow = winPtr
            , rawNode = Just node
            , winGeometry = Rect 0 0 0 0
            , winProposed = Nothing
            , winWorkspace = defaultWsId
            , floating = False
            , appId = Nothing
            , winTitle = Nothing
            , fullscreen = (False, Nothing)
            , lastPosition = Nothing
            }
     in s
          { windows = Map.insert winId win (windows s)
          , dirtyMonitors = Set.insert monId (dirtyMonitors s)
          , workspaces =
              Map.adjust
                (\ws -> ws {wsWindows = wsWindows ws ++ [winId]})
                defaultWsId
                (workspaces s)
          }
  cleanup <- riverWindowV1AddListener winPtr listener
  updateState wmState $ \s ->
    s {windowCleanup = Map.insert winId cleanup (windowCleanup s)}

onWmOutput ::
     Runtime
  -> Config
  -> OutputListener
  -> Ptr RiverWindowManagerV1
  -> Ptr RiverOutputV1
  -> IO ()
onWmOutput runtime config listener _ outPtr = do
  let logger = rtLogger runtime
      wmState = rtState runtime
  let monId = MonitorId (fromIntegral (ptrId outPtr))
      wsId = WorkspaceId (monId, 0)
      mon =
        Monitor
          { rawOutput = outPtr
          , activeSpace = wsId
          , monitorGeometry = Rect 0 0 0 0
          , workArea = Rect 0 0 0 0
          }
      ws =
        Workspace
          { wsName = "1"
          , wsWindows = []
          , layouts = fromMaybe defaultLayouts (cfgLayouts config)
          }
  logEvent logger "output" $ "new: " <> show monId
  updateState wmState $ \s ->
    s
      { monitors = Map.insert monId mon (monitors s)
      , workspaces = Map.insert wsId ws (workspaces s)
      }
  cleanup <- riverOutputV1AddListener outPtr listener
  updateState wmState $ \s ->
    s {monitorCleanup = Map.insert monId cleanup (monitorCleanup s)}

onWmSeat ::
     Runtime
  -> Config
  -> SeatListener
  -> Ptr RiverWindowManagerV1
  -> Ptr RiverSeatV1
  -> IO ()
onWmSeat runtime config listener _ seatPtr = do
  let logger = rtLogger runtime
      wmState = rtState runtime
  state <- readTVarIO wmState -- bind state so we can use it
  xkbSeatPtr <- riverXkbBindingsV1GetSeat (rawXkb state) seatPtr -- bind the xkbSeatPtr
  -- need best way to most efficiently map over the keybindings in Cfg riverXkbBindingsV1GetXkbBinding? this should work
  newBindings <-
    forM (cfgKeybindings config) $ \(Chord modifiers (Keysym keysym), action) -> do
      let modifiersWord = modifiersMask modifiers
          xkbListener =
            XkbBindingListener
              { onXkbPressed = \_ -> runReaderT action wmState
              , onXkbReleased = \_ -> pure ()
              , onXkbStopRepeat = \_ -> pure ()
              }
      binding <-
        riverXkbBindingsV1GetXkbBinding
          (rawXkb state)
          seatPtr
          keysym
          modifiersWord -- bind each key
      cleanup <- riverXkbBindingV1AddListener binding xkbListener -- get the listener for the binding
      pure (binding, cleanup) -- store as (binding, cleanup action)
  -- bind the SeatListener
  cleaner0 <-
    riverXkbBindingsSeatV1AddListener xkbSeatPtr
      $ XkbBindingsSeatListener
          {Rivulet.FFI.Protocol.onXkbSeatAteUnboundKey = \_ -> pure ()}
  let sid = SeatId (fromIntegral (ptrId seatPtr))
      seat =
        Seat
          { rawSeat = seatPtr
          , rawXkbSeat = xkbSeatPtr
          , xkbSeatCleanup = cleaner0
          , lastSentFocus = Nothing
          , mouseFocus = Nothing
          , keyboardFocus = Nothing
          , seatBindings = []
          , pendingBindings = newBindings
          }
  logEvent logger "seat"
    $ "new: " <> show sid <> " bindings=" <> show (length newBindings)
  updateState wmState $ \s -> s {seats = Map.insert sid seat (seats s)}
  cleaner1 <- riverSeatV1AddListener seatPtr listener
  updateState wmState $ \s ->
    s {seatCleanup = Map.insert sid cleaner1 (seatCleanup s)}

-- Output listener callbacks
onOutRemoved :: TVar WMState -> Ptr RiverOutputV1 -> IO ()
onOutRemoved wmState outPtr = do
  let monId = MonitorId (fromIntegral (ptrId outPtr))
  state <- readTVarIO wmState
  sequence_ $ Map.lookup monId (monitorCleanup state)
  updateState wmState $ \s ->
    s {monitorCleanup = Map.delete monId (monitorCleanup s)}
  riverOutputV1Destroy outPtr
  updateState wmState $ \s -> s {monitors = Map.delete monId (monitors s)}

onOutWlOutput :: TVar WMState -> Ptr RiverOutputV1 -> Word32 -> IO ()
onOutWlOutput _ _ _ = pure ()

onOutPosition :: TVar WMState -> Ptr RiverOutputV1 -> Int -> Int -> IO ()
onOutPosition wmState outPtr x y = do
  let monId = MonitorId (fromIntegral (ptrId outPtr))
  modifyMonitor wmState monId $ \m ->
    let geo = monitorGeometry m
     in m {monitorGeometry = geo {x = x, y = y}}

onOutDimensions :: Runtime -> Ptr RiverOutputV1 -> Int -> Int -> IO ()
onOutDimensions runtime outPtr w h = do
  let logger = rtLogger runtime
      wmState = rtState runtime
  let monId = MonitorId (fromIntegral (ptrId outPtr))
  logEvent logger "output" $ show monId <> " " <> show w <> "×" <> show h
  modifyMonitor wmState monId $ \m ->
    let geo = monitorGeometry m
     in m
          { monitorGeometry = geo {width = w, height = h}
          , workArea = geo {width = w, height = h}
          }

-- Seat listener callbacks
onSeatRemoved :: TVar WMState -> Ptr RiverSeatV1 -> IO ()
onSeatRemoved wmState seatPtr = do
  let seatId = SeatId (fromIntegral (ptrId seatPtr))
  state <- readTVarIO wmState
  sequence_ $ Map.lookup seatId (seatCleanup state)
  updateState wmState $ \s ->
    s {seatCleanup = Map.delete seatId (seatCleanup s)}
  riverSeatV1Destroy seatPtr
  updateState wmState $ \s -> s {seats = Map.delete seatId (seats s)}

onSeatWlSeat :: TVar WMState -> Ptr RiverSeatV1 -> Word32 -> IO ()
onSeatWlSeat _ _ _ = pure ()

onSeatPointerEnter ::
     TVar WMState -> Ptr RiverSeatV1 -> Ptr RiverWindowV1 -> IO ()
onSeatPointerEnter wmState seatPtr winPtr = do
  let seatId = SeatId (fromIntegral (ptrId seatPtr))
  let winId = WindowId (ptrId winPtr)
  modifySeat wmState seatId $ \s -> s {mouseFocus = Just winId}

onSeatPointerLeave :: TVar WMState -> Ptr RiverSeatV1 -> IO ()
onSeatPointerLeave wmState seatPtr = do
  let seatId = SeatId (fromIntegral (ptrId seatPtr))
  modifySeat wmState seatId $ \s -> s {mouseFocus = Nothing}

onSeatWindowInteraction ::
     Runtime
  -> Ptr RiverWindowManagerV1
  -> Ptr RiverSeatV1
  -> Ptr RiverWindowV1
  -> IO ()
onSeatWindowInteraction runtime wmPtr seatPtr winPtr = do
  let wmState = rtState runtime
  let seatId = SeatId (fromIntegral (ptrId seatPtr))
      winId = WindowId (ptrId winPtr)
  changed <-
    atomically $ do
      state <- readTVar wmState
      case Map.lookup seatId (seats state) of
        Nothing -> pure False
        Just seat ->
          if keyboardFocus seat == Just winId
            then pure False
            else do
              modifyTVar wmState $ \s ->
                s
                  { seats =
                      Map.adjust
                        (\se -> se {keyboardFocus = Just winId})
                        seatId
                        (seats s)
                  }
              pure True
  when changed $ riverWindowManagerV1ManageDirty wmPtr

onSeatShellInteraction ::
     TVar WMState -> Ptr RiverSeatV1 -> Ptr RiverShellSurfaceV1 -> IO ()
onSeatShellInteraction _ _ _ = pure ()

onSeatOpDelta :: TVar WMState -> Ptr RiverSeatV1 -> Int -> Int -> IO ()
onSeatOpDelta _ _ _ _ = pure ()

onSeatOpRelease :: TVar WMState -> Ptr RiverSeatV1 -> IO ()
onSeatOpRelease _ _ = pure ()

onSeatPointerPosition :: TVar WMState -> Ptr RiverSeatV1 -> Int -> Int -> IO ()
onSeatPointerPosition _ _ _ _ = pure ()

-- Window listener callbacks
onWinClosed :: Runtime -> Ptr RiverWindowV1 -> IO ()
onWinClosed runtime winPtr = do
  let logger = rtLogger runtime
      wmState = rtState runtime
  let winId = WindowId (ptrId winPtr)
  logEvent logger "window" $ "closed: " <> show winId
  state <- readTVarIO wmState
  sequence_ $ Map.lookup winId (windowCleanup state)
  updateState wmState $ \s ->
    s {windowCleanup = Map.delete winId (windowCleanup s)}
  riverWindowV1Destroy winPtr
  updateState wmState $ \s ->
    let win = Map.lookup winId (windows s)
        monId =
          fmap
            (\w ->
               let WorkspaceId (mId, _) = winWorkspace w
                in mId)
            win
        wsId = fmap winWorkspace win
     in s
          { windows = Map.delete winId (windows s)
          , workspaces =
              case wsId of
                Nothing -> workspaces s
                Just wId ->
                  Map.adjust
                    (\ws -> ws {wsWindows = filter (/= winId) (wsWindows ws)})
                    wId
                    (workspaces s)
          , dirtyMonitors =
              case monId of
                Nothing  -> dirtyMonitors s
                Just mId -> Set.insert mId (dirtyMonitors s)
          , seats =
              Map.map
                (\seat ->
                   if keyboardFocus seat == Just winId
                     then seat {keyboardFocus = Nothing}
                     else seat)
                (seats s)
          }

onWinDimensionsHint ::
     TVar WMState -> Ptr RiverWindowV1 -> Int -> Int -> Int -> Int -> IO ()
onWinDimensionsHint _ _ _ _ _ _ = pure ()

onWinDimensions :: TVar WMState -> Ptr RiverWindowV1 -> Int -> Int -> IO ()
onWinDimensions wmState winPtr width height = do
  let winId = WindowId (ptrId winPtr)
  modifyWindow wmState winId $ \w ->
    let geo = winGeometry w
     in w {winGeometry = geo {width = width, height = height}}

onWinAppId :: Runtime -> Ptr RiverWindowV1 -> Maybe String -> IO ()
onWinAppId runtime winPtr mAppId = do
  let logger = rtLogger runtime
      wmState = rtState runtime
  let winId = WindowId (ptrId winPtr)
  logEvent logger "window" $ show winId <> " appId=" <> show mAppId
  modifyWindow wmState winId $ \w -> w {appId = mAppId}

onWinTitle :: TVar WMState -> Ptr RiverWindowV1 -> Maybe String -> IO ()
onWinTitle wmState winPtr mTitle = do
  let winId = WindowId (ptrId winPtr)
  modifyWindow wmState winId $ \w -> w {winTitle = mTitle}

onWinParent ::
     TVar WMState -> Ptr RiverWindowV1 -> Maybe (Ptr RiverWindowV1) -> IO ()
onWinParent wmState winPtr mParentPtr = do
  pure ()

onWinDecorationHint :: TVar WMState -> Ptr RiverWindowV1 -> Word32 -> IO ()
onWinDecorationHint wmState winPtr hint = do
  pure ()

onWinPointerMoveReq ::
     TVar WMState -> Ptr RiverWindowV1 -> Ptr RiverSeatV1 -> IO ()
onWinPointerMoveReq wmState winPtr seatPtr = do
  pure ()

onWinPointerResizeReq ::
     TVar WMState -> Ptr RiverWindowV1 -> Ptr RiverSeatV1 -> Word32 -> IO ()
onWinPointerResizeReq wmState winPtr seatPtr edges = do
  pure ()

onWinShowMenuReq :: TVar WMState -> Ptr RiverWindowV1 -> Int -> Int -> IO ()
onWinShowMenuReq wmState winPtr x y = do
  pure ()

onWinMaximizeReq :: TVar WMState -> Ptr RiverWindowV1 -> IO ()
onWinMaximizeReq wmState winPtr = do
  pure ()

onWinUnmaximizeReq :: TVar WMState -> Ptr RiverWindowV1 -> IO ()
onWinUnmaximizeReq wmState winPtr = do
  pure ()

onWinFullscreenReq ::
     TVar WMState -> Ptr RiverWindowV1 -> Maybe (Ptr RiverOutputV1) -> IO ()
onWinFullscreenReq wmState winPtr mOutPtr = do
  let winId = WindowId (ptrId winPtr)
  let monId = fmap (MonitorId . fromIntegral . ptrId) mOutPtr
  modifyWindow wmState winId $ \w -> w {fullscreen = (True, monId)}

onWinExitFullscreenReq :: TVar WMState -> Ptr RiverWindowV1 -> IO ()
onWinExitFullscreenReq wmState winPtr = do
  let winId = WindowId (ptrId winPtr)
  modifyWindow wmState winId $ \w -> w {fullscreen = (False, Nothing)}

onWinMinimizeReq :: TVar WMState -> Ptr RiverWindowV1 -> IO ()
onWinMinimizeReq wmState winPtr = do
  pure ()

onWinUnreliablePid :: TVar WMState -> Ptr RiverWindowV1 -> Int -> IO ()
onWinUnreliablePid wmState winPtr pid = do
  pure ()

onWinPresentationHint :: TVar WMState -> Ptr RiverWindowV1 -> Word32 -> IO ()
onWinPresentationHint wmState winPtr hint = do
  pure ()

onWinIdentifier :: TVar WMState -> Ptr RiverWindowV1 -> String -> IO ()
onWinIdentifier wmState winPtr ident = do
  pure ()

-- XKB bindings seat listener callbacks
onXkbSeatAteUnboundKey :: TVar WMState -> Ptr RiverXkbBindingsSeatV1 -> IO ()
onXkbSeatAteUnboundKey wmState xkbSeatPtr = do
  pure ()

-- Input manager listener callbacks
onImFinished :: TVar WMState -> Ptr RiverInputManagerV1 -> IO ()
onImFinished wmState imPtr = do
  pure ()

onImInputDevice ::
     TVar WMState -> Ptr RiverInputManagerV1 -> Ptr RiverInputDeviceV1 -> IO ()
onImInputDevice wmState imPtr devPtr = do
  pure ()

-- Input device listener callbacks
onDevRemoved :: TVar WMState -> Ptr RiverInputDeviceV1 -> IO ()
onDevRemoved wmState devPtr = do
  pure ()

onDevType :: TVar WMState -> Ptr RiverInputDeviceV1 -> Word32 -> IO ()
onDevType wmState devPtr devType = do
  pure ()

onDevName :: TVar WMState -> Ptr RiverInputDeviceV1 -> String -> IO ()
onDevName wmState devPtr name = do
  pure ()
