module Rivulet.Manager.Runtime where

import           Rivulet.DSL               (Config (..), ConfigM)
import           Rivulet.DSL.Layout        (Tall (..))
import           Rivulet.FFI.Client
import           Rivulet.FFI.Protocol
import qualified Rivulet.Manager           as Manager
import qualified Rivulet.Manager.Callbacks as Callbacks
import           Rivulet.Manager.Log       (Logger, banner, logError, logEvent,
                                            logFail, logInfo, separator,
                                            withLogger)
import           Rivulet.Monad
import           Rivulet.Types

import           Control.Concurrent.STM
import           Control.Exception         (finally)
import           Control.Monad.Writer      (execWriterT)
import           Data.Char                 (toLower)
import           Data.Functor.Identity     (runIdentity)
import           Data.IORef
import qualified Data.Map.Strict           as Map
import           Data.Maybe                (fromMaybe)
import qualified Data.Set                  as Set
import           Data.Word
import           Foreign
import           System.Environment        (lookupEnv)
import           System.Process            (spawnProcess)

readBoolEnv :: String -> Maybe Bool
readBoolEnv raw =
  case map toLower raw of
    "1"     -> Just True
    "true"  -> Just True
    "yes"   -> Just True
    "on"    -> Just True
    "0"     -> Just False
    "false" -> Just False
    "no"    -> Just False
    "off"   -> Just False
    _       -> Nothing

-- helpers
lookup3 :: String -> [(Word32, String, Word32)] -> Maybe (Word32, Word32)
lookup3 iface xs =
  case filter (\(_, i, _) -> i == iface) xs of
    (name, _, ver):_ -> Just (name, ver)
    []               -> Nothing

ptrId :: Ptr a -> Word32
ptrId = fromIntegral . ptrToWordPtr

activeLayout :: Workspace -> SomeLayout
activeLayout ws =
  case layouts ws of
    (l:_) -> l
    []    -> SomeLayout Tall

marginsFromConfig :: Config -> Margins
marginsFromConfig config =
  let gap = fromMaybe 0 (cfgGaps config)
      bw = maybe 0 (borderWidth . fst) (cfgBorders config)
   in Margins gap bw

-- connect
connect :: Logger -> IO (Ptr WlDisplay, Ptr WlRegistry)
connect logger = do
  mDisplay <- wlDisplayConnect Nothing
  display <-
    case mDisplay of
      Nothing ->
        logFail
          logger
          "could not connect to Wayland display ... is WAYLAND_DISPLAY set?"
      Just d -> pure d
  registry <- wlDisplayGetRegistry display
  pure (display, registry)

-- enumerateGlobals
enumerateGlobals ::
     Logger -> Ptr WlDisplay -> Ptr WlRegistry -> IO [(Word32, String, Word32)]
enumerateGlobals logger display registry = do
  globalsRef <- newIORef ([] :: [(Word32, String, Word32)])
  logInfo logger "adding registry listener..."
  cleanup0 <-
    wlRegistryAddListener
      registry
      (\_ name iface ver -> do
         logEvent logger "registry"
           $ iface <> " v" <> show ver <> " (name=" <> show name <> ")"
         modifyIORef globalsRef ((name, iface, ver) :))
      (\_ name -> logEvent logger "registry" $ "removed: name=" <> show name)
  logInfo logger "registry listener added"
  logInfo logger "roundtrip #1 → enumerating globals"
  _ <- wlDisplayRoundtrip display
  logInfo logger "roundtrip #1 → done"
  globals <- readIORef globalsRef
  separator logger
  let riverGlobals = filter (\(_, iface, _) -> take 5 iface == "river") globals
  logInfo logger
    $ "found "
        <> show (length globals)
        <> " globals ("
        <> show (length riverGlobals)
        <> " river)"
  mapM_
    (\(n, i, v) ->
       logInfo logger
         $ "  · " <> i <> " v" <> show v <> " (name=" <> show n <> ")")
    riverGlobals
  cleanup0
  pure globals

-- setup
setup :: Logger -> Ptr WlRegistry -> [(Word32, String, Word32)] -> IO WMState
setup logger registry globals = do
  wm <- bindProtocol "river_window_manager_v1" riverWindowManagerV1Interface 4
  xkb <- bindProtocol "river_xkb_bindings_v1" riverXkbBindingsV1Interface 2
  input <- bindProtocol "river_input_manager_v1" riverInputManagerV1Interface 1
  pure $ initialState wm xkb input
  where
    bindProtocol name iface ver =
      case lookup3 name globals of
        Nothing -> logFail logger $ name <> " not found ... is River running?"
        Just (n, v) -> do
          let v' = min v ver
          logInfo logger $ "bound " <> name <> " v" <> show v'
          wlRegistryBind registry n iface v'

-- initialState
initialState ::
     Ptr RiverWindowManagerV1
  -> Ptr RiverXkbBindingsV1
  -> Ptr RiverInputManagerV1
  -> WMState
initialState windowManager xkbBindings inputManager =
  WMState
    { phase = Managing
    , rawWM = windowManager
    , rawXkb = xkbBindings
    , rawInput = inputManager
    , monitors = Map.empty
    , windows = Map.empty
    , seats = Map.empty
    , workspaces = Map.empty
    , borders = (defaultBorder, defaultBorder)
    , dirtyMonitors = Set.empty
    , seatCleanup = Map.empty
    , windowCleanup = Map.empty
    , monitorCleanup = Map.empty
    }

-- initialize
initialize :: Runtime -> Config -> IO (IO ())
initialize runtime config = do
  let logger = rtLogger runtime
      wmState = rtState runtime
    -- apply cfgBorders & cfgGaps from the config -> the TVar
  case cfgBorders config of
    Just b  -> updateState wmState $ \s -> s {borders = b}
    Nothing -> pure ()
  logInfo logger
    $ "config: gaps="
        <> maybe "off" show (cfgGaps config)
        <> " debug="
        <> show (fromMaybe False (cfgDebug config))
        <> " borders="
        <> maybe "off" (show . borderWidth . fst) (cfgBorders config)
        <> " layouts="
        <> show (maybe 0 length (cfgLayouts config))
        <> " keybindings="
        <> show (length (cfgKeybindings config))
        <> " rules="
        <> show (length (cfgRules config))
        <> " autostarts="
        <> show (length (cfgAutostart config))
  state <- readTVarIO wmState
  let wmPtr = rawWM state
    -- attach listener for seat events
  let seatListener =
        SeatListener
          { onSeatRemoved = Callbacks.onSeatRemoved wmState
          , onSeatWlSeat = Callbacks.onSeatWlSeat wmState
          , onSeatPointerEnter = Callbacks.onSeatPointerEnter wmState
          , onSeatPointerLeave = Callbacks.onSeatPointerLeave wmState
          , onSeatWindowInteraction =
              Callbacks.onSeatWindowInteraction runtime wmPtr
          , onSeatShellInteraction = Callbacks.onSeatShellInteraction wmState
          , onSeatOpDelta = Callbacks.onSeatOpDelta wmState
          , onSeatOpRelease = Callbacks.onSeatOpRelease wmState
          , onSeatPointerPosition = Callbacks.onSeatPointerPosition wmState
          }
    -- attach the listener for the outputs
  let outListener =
        OutputListener
          { onOutRemoved = Callbacks.onOutRemoved wmState
          , onOutDimensions = Callbacks.onOutDimensions runtime
          , onOutPosition = Callbacks.onOutPosition wmState
          , onOutWlOutput = Callbacks.onOutWlOutput wmState
          }
    -- attach the listener for individual windows
  let windowListener =
        WindowListener
          { onWinClosed = Callbacks.onWinClosed runtime
          , onWinDimensionsHint = Callbacks.onWinDimensionsHint wmState
          , onWinDimensions = Callbacks.onWinDimensions wmState
          , onWinAppId = Callbacks.onWinAppId runtime
          , onWinTitle = Callbacks.onWinTitle wmState
          , onWinParent = Callbacks.onWinParent wmState
          , onWinDecorationHint = Callbacks.onWinDecorationHint wmState
          , onWinPointerMoveReq = Callbacks.onWinPointerMoveReq wmState
          , onWinPointerResizeReq = Callbacks.onWinPointerResizeReq wmState
          , onWinShowMenuReq = Callbacks.onWinShowMenuReq wmState
          , onWinMaximizeReq = Callbacks.onWinMaximizeReq wmState
          , onWinUnmaximizeReq = Callbacks.onWinUnmaximizeReq wmState
          , onWinFullscreenReq = Callbacks.onWinFullscreenReq wmState
          , onWinExitFullscreenReq = Callbacks.onWinExitFullscreenReq wmState
          , onWinMinimizeReq = Callbacks.onWinMinimizeReq wmState
          , onWinUnreliablePid = Callbacks.onWinUnreliablePid wmState
          , onWinPresentationHint = Callbacks.onWinPresentationHint wmState
          , onWinIdentifier = Callbacks.onWinIdentifier wmState
          }
    -- attach the listener for the window manager
  let wmListener =
        WindowManagerListener
          { onWmUnavailable = Callbacks.onWmUnavailable runtime config
          , onWmFinished = Callbacks.onWmFinished runtime config
          , onWmManageStart = Manager.onWmManageStart runtime config
          , onWmRenderStart = Manager.onWmRenderStart runtime config
          , onWmSessionLocked = Callbacks.onWmSessionLocked wmState config
          , onWmSessionUnlocked = Callbacks.onWmSessionUnlocked wmState config
          , onWmWindow = Callbacks.onWmWindow runtime config windowListener
          , onWmOutput = Callbacks.onWmOutput runtime config outListener
          , onWmSeat = Callbacks.onWmSeat runtime config seatListener
          }
  result <- riverWindowManagerV1AddListener wmPtr wmListener
  logInfo logger "listeners attached"
  pure result

-- runAutostart
runAutostart :: Logger -> Config -> IO ()
runAutostart logger config = mapM_ launch (cfgAutostart config)
  where
    launch (_, cmd) = do
      logInfo logger $ "autostart: " <> cmd
      let (exe:args) = words cmd
      _ <- spawnProcess exe args
      pure ()

-- eventLoop
eventLoop :: Logger -> Ptr WlDisplay -> IO ()
eventLoop logger display = do
  result <- wlDisplayDispatch display
  if result < 0
    then logError logger "dispatch failed, exiting"
    else do
      _ <- wlDisplayFlush display
      eventLoop logger display

-- entry point
rivulet :: ConfigM () -> IO ()
rivulet configM = do
  let config = runIdentity (execWriterT configM)
      debugFromConfig = fromMaybe False (cfgDebug config)
  banner
  mLogPath <- lookupEnv "RIVULET_LOG"
  mDebug <- lookupEnv "RIVULET_DEBUG"
  let debugEnabled = fromMaybe debugFromConfig (mDebug >>= readBoolEnv)
  withLogger debugEnabled mLogPath $ \logger -> do
    logInfo logger "rivulet starting..."
    (display, registry) <- connect logger
    globals <- enumerateGlobals logger display registry
    wmState <- setup logger registry globals
    stateVar <- newTVarIO wmState
    let runtime = Runtime {rtLogger = logger, rtState = stateVar}
    cleanupWM <- initialize runtime config
    runAutostart logger config
    finally (eventLoop logger display) cleanupWM
