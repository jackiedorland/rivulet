module Rivulet.Manager.Callbacks where

import Control.Concurrent.STM
import Control.Monad          (when)
import Control.Monad.Reader
import Data.Foldable
import Data.Map.Strict        qualified as Map
import Data.Maybe
import Data.Set               qualified as Set
import Data.Word
import Foreign
import Rivulet.DSL            (Config (..))
import Rivulet.DSL.Keys
import Rivulet.DSL.Layout
import Rivulet.FFI.Protocol
import Rivulet.Manager.Log    (logEvent, logFail, logInfo)
import Rivulet.Monad
import Rivulet.Types
import System.Exit
import UnliftIO               (forConcurrently)

-- helpers
ptrId :: Ptr a -> WordPtr
ptrId = ptrToWordPtr

defaultLayouts :: [SomeLayout]
defaultLayouts = [SomeLayout Tall]

defaultWorkspaceNames :: [String]
defaultWorkspaceNames = map show ([1 .. 9] :: [Int])

findLayerShellOutputMonitorId :: WMState -> Ptr RiverLayerShellOutputV1 -> Maybe MonitorId
findLayerShellOutputMonitorId state lsOutPtr =
    fst
        <$> find
            ((== lsOutPtr) . layerShellOutputPtr . snd)
            (Map.toList (layerShellOutputs (layerShell state)))

findLayerShellSeatId :: WMState -> Ptr RiverLayerShellSeatV1 -> Maybe SeatId
findLayerShellSeatId state lsSeatPtr =
    fst
        <$> find
            ((== lsSeatPtr) . layerShellSeatPtr . snd)
            (Map.toList (layerShellSeats (layerShell state)))

handleLayerShellOutNonExclusiveArea ::
    Runtime -> Ptr RiverLayerShellOutputV1 -> Int -> Int -> Int -> Int -> IO ()
handleLayerShellOutNonExclusiveArea runtime lsOutPtr x y w h = do
    let logger = rtLogger runtime
        wmState = rtState runtime
        w' = max 0 w
        h' = max 0 h
    state <- readTVarIO wmState
    case findLayerShellOutputMonitorId state lsOutPtr of
        Nothing ->
            logEvent logger "layer-shell" $ "non_exclusive_area unknown-output rect=" <> show (x, y, w', h')
        Just monId -> do
            logEvent logger "layer-shell" $ show monId <> " non_exclusive_area=" <> show (x, y, w', h')
            updateState wmState $ \s ->
                s
                    { monitors =
                        Map.adjust
                            (\m -> m{workArea = Rect x y w' h'})
                            monId
                            (monitors s)
                    , dirtyMonitors = Set.insert monId (dirtyMonitors s)
                    }

logLayerShellSeatFocusEvent :: Runtime -> String -> Ptr RiverLayerShellSeatV1 -> IO ()
logLayerShellSeatFocusEvent runtime eventName lsSeatPtr = do
    let logger = rtLogger runtime
        wmState = rtState runtime
    state <- readTVarIO wmState
    case findLayerShellSeatId state lsSeatPtr of
        Nothing     -> logEvent logger "layer-shell" $ eventName <> " unknown-seat"
        Just seatId -> logEvent logger "layer-shell" $ eventName <> " " <> show seatId

handleLayerShellSeatFocusExclusive :: Runtime -> Ptr RiverLayerShellSeatV1 -> IO ()
handleLayerShellSeatFocusExclusive runtime lsSeatPtr = do
    logLayerShellSeatFocusEvent runtime "focus_exclusive" lsSeatPtr
    let wmState = rtState runtime
    state <- readTVarIO wmState
    case findLayerShellSeatId state lsSeatPtr of
        Nothing -> pure ()
        Just seatId ->
            updateState wmState $ \s ->
                s
                    { layerShell =
                        let ls = layerShell s
                         in ls
                                { layerShellSeats =
                                    Map.adjust
                                        (\lsSeat -> lsSeat{layerShellSeatExclusiveFocus = True})
                                        seatId
                                        (layerShellSeats ls)
                                }
                    }

handleLayerShellSeatFocusNonExclusive :: Runtime -> Ptr RiverLayerShellSeatV1 -> IO ()
handleLayerShellSeatFocusNonExclusive runtime lsSeatPtr = do
    logLayerShellSeatFocusEvent runtime "focus_non_exclusive" lsSeatPtr
    let wmState = rtState runtime
    state <- readTVarIO wmState
    case findLayerShellSeatId state lsSeatPtr of
        Nothing -> pure ()
        Just seatId ->
            updateState wmState $ \s ->
                s
                    { layerShell =
                        let ls = layerShell s
                         in ls
                                { layerShellSeats =
                                    Map.adjust
                                        (\lsSeat -> lsSeat{layerShellSeatExclusiveFocus = False})
                                        seatId
                                        (layerShellSeats ls)
                                }
                    }

handleLayerShellSeatFocusNone :: Runtime -> Ptr RiverLayerShellSeatV1 -> IO ()
handleLayerShellSeatFocusNone runtime lsSeatPtr = do
    logLayerShellSeatFocusEvent runtime "focus_none" lsSeatPtr
    let wmState = rtState runtime
    state <- readTVarIO wmState
    case findLayerShellSeatId state lsSeatPtr of
        Nothing -> pure ()
        Just seatId ->
            updateState wmState $ \s ->
                s
                    { layerShell =
                        let ls = layerShell s
                         in ls
                                { layerShellSeats =
                                    Map.adjust
                                        (\lsSeat -> lsSeat{layerShellSeatExclusiveFocus = False})
                                        seatId
                                        (layerShellSeats ls)
                                }
                    , seats =
                        Map.adjust
                            (\seat -> seat{lastSentFocus = Nothing})
                            seatId
                            (seats s)
                    }

focusedWorkspaceId :: WMState -> Maybe WorkspaceId
focusedWorkspaceId s =
    listToMaybe
        [ winWorkspace win
        | seat <- Map.elems (seats s)
        , winId <- maybeToList (keyboardFocus seat)
        , win <- maybeToList (Map.lookup winId (windows s))
        ]

workspaceNamesForSlot :: Config -> Int -> [String]
workspaceNamesForSlot config slot =
    case drop slot (cfgMonitors config) of
        (_, names) : _ | not (null names) -> names
        _                                 -> defaultWorkspaceNames

uniqueWorkspaceNames :: Set.Set String -> Int -> [String] -> ([String], [(String, String)])
uniqueWorkspaceNames existing slot = go existing [] []
  where
    go _ acc renames [] = (reverse acc, reverse renames)
    go used acc renames (name : rest)
        | Set.notMember name used =
            go (Set.insert name used) (name : acc) renames rest
        | otherwise =
            let unique = firstAvailable used (0 :: Int)
             in go (Set.insert unique used) (unique : acc) ((name, unique) : renames) rest
      where
        candidate :: Int -> String
        base = name <> "@" <> show slot
        candidate 0 = base
        candidate n = base <> "-" <> show n
        firstAvailable :: Set.Set String -> Int -> String
        firstAvailable usedNames n =
            let c = candidate n
             in if Set.member c usedNames
                    then firstAvailable usedNames (n + 1)
                    else c

-- Window Manager callbacks
onWmUnavailable :: Runtime -> Config -> Ptr RiverWindowManagerV1 -> IO ()
onWmUnavailable runtime _ _ =
    logFail (rtLogger runtime) "river-window-management-v1 Wayland extension is unavailable... is River running?"

onWmFinished :: Runtime -> Config -> Ptr RiverWindowManagerV1 -> IO ()
onWmFinished runtime _ _ = do
    logInfo (rtLogger runtime) "Wayland/River session finished; exiting..."
    exitSuccess

onWmSessionLocked :: TVar WMState -> Config -> Ptr RiverWindowManagerV1 -> IO ()
onWmSessionLocked _ _ _ = pure ()

onWmSessionUnlocked ::
    TVar WMState -> Config -> Ptr RiverWindowManagerV1 -> IO ()
onWmSessionUnlocked _ _ _ = pure ()

onWmWindow ::
    Runtime ->
    Config ->
    WindowListener ->
    Ptr RiverWindowManagerV1 ->
    Ptr RiverWindowV1 ->
    IO ()
onWmWindow runtime _ listener _ winPtr = do
    let logger = rtLogger runtime
        wmState = rtState runtime
    let winId = WindowId (ptrId winPtr)
    logEvent logger "window" $ show winId <> " -> created"
    node <- riverWindowV1GetNode winPtr
    updateState wmState $ \s ->
        let defaultWsId =
                case focusedWorkspaceId s of
                    Just wsId -> wsId
                    Nothing ->
                        case Map.lookupMin (monitors s) of
                            Just (_, mon) -> activeSpace mon
                            Nothing       -> WorkspaceId (MonitorId 0, 0)
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
                        (\ws -> ws{wsWindows = wsWindows ws ++ [winId]})
                        defaultWsId
                        (workspaces s)
                }
    cleanup <- riverWindowV1AddListener winPtr listener
    registerCleanup wmState (CleanupWindow winId) cleanup

onWmOutput ::
    Runtime ->
    Config ->
    OutputListener ->
    Ptr RiverWindowManagerV1 ->
    Ptr RiverOutputV1 ->
    IO ()
onWmOutput runtime config listener _ outPtr = do
    let logger = rtLogger runtime
        wmState = rtState runtime
    let monId = MonitorId (ptrId outPtr)
        monitorCleanupRef = CleanupMonitor monId
        layerOutputCleanupRef = CleanupLayerShellOutput monId
    state <- readTVarIO wmState
    mLayerShellOutput <- do
        lsOutPtr <- riverLayerShellV1GetOutput (layerShellManager (layerShell state)) outPtr
        if lsOutPtr == nullPtr
            then do
                logInfo logger $ "output " <> show monId <> " did not create river_layer_shell_output_v1"
                pure Nothing
            else do
                lsCleanup <-
                    riverLayerShellOutputV1AddListener lsOutPtr $
                        LayerShellOutputListener
                            { onLayerShellOutNonExclusiveArea =
                                handleLayerShellOutNonExclusiveArea runtime
                            }
                registerCleanup wmState layerOutputCleanupRef lsCleanup
                pure $
                    Just
                        LayerShellOutputState
                            { layerShellOutputPtr = lsOutPtr
                            , layerShellOutputCleanupRef = layerOutputCleanupRef
                            }
    let slot = Map.size (monitors state)
        requestedNames = workspaceNamesForSlot config slot
        maxWorkspaces = fromIntegral (maxBound :: Word8) + 1
        limitedNames = take maxWorkspaces requestedNames
        existingNames = Set.fromList (map wsName (Map.elems (workspaces state)))
        (workspaceNames, renamedNames) = uniqueWorkspaceNames existingNames slot limitedNames
        wsEntries =
            [ ( WorkspaceId (monId, ix)
              , Workspace
                    { wsName = name
                    , wsWindows = []
                    , layouts = fromMaybe defaultLayouts (cfgLayouts config)
                    }
              )
            | (ix, name) <- zip ([0 ..] :: [Word8]) workspaceNames
            ]
        wsId =
            case wsEntries of
                ((firstWsId, _) : _) -> firstWsId
                []                   -> WorkspaceId (monId, 0)
        mon =
            Monitor
                { rawOutput = outPtr
                , activeSpace = wsId
                , monitorGeometry = Rect 0 0 0 0
                , workArea = Rect 0 0 0 0
                }
    logEvent logger "output" $ show monId <> " -> connected"
    -- river-output events currently do not expose a stable output name in these bindings,
    -- so cfgMonitors is matched by connection order for now.
    when (null (cfgMonitors config)) $
        logInfo logger $
            "output "
                <> show monId
                <> " has no monitor workspace config; using defaults "
                <> show defaultWorkspaceNames
    when (length requestedNames > maxWorkspaces) $
        logInfo logger $
            "output "
                <> show monId
                <> " requested "
                <> show (length requestedNames)
                <> " workspaces; truncating to "
                <> show maxWorkspaces
    mapM_
        ( \(original, renamed) ->
            logInfo logger $
                "workspace name conflict: "
                    <> show original
                    <> " renamed to "
                    <> show renamed
        )
        renamedNames
    updateState wmState $ \s ->
        let updatedState =
                s
                    { monitors = Map.insert monId mon (monitors s)
                    , workspaces = foldr (\(wId, ws) acc -> Map.insert wId ws acc) (workspaces s) wsEntries
                    }
         in case mLayerShellOutput of
                Nothing -> updatedState
                Just lsOutputState ->
                    updatedState
                        { layerShell =
                            let ls = layerShell updatedState
                             in ls
                                    { layerShellOutputs =
                                        Map.insert monId lsOutputState (layerShellOutputs ls)
                                    }
                        }
    cleanup <- riverOutputV1AddListener outPtr listener
    registerCleanup wmState monitorCleanupRef cleanup

onWmSeat ::
    Runtime ->
    Config ->
    SeatListener ->
    Ptr RiverWindowManagerV1 ->
    Ptr RiverSeatV1 ->
    IO ()
onWmSeat runtime config listener _ seatPtr = do
    let logger = rtLogger runtime
        wmState = rtState runtime
    let sid = SeatId (ptrId seatPtr)
        seatCleanupRef = CleanupSeat sid
        layerSeatCleanupRef = CleanupLayerShellSeat sid
    state <- readTVarIO wmState -- bind state so we can use it
    mLayerShellSeat <- do
        lsSeatPtr <- riverLayerShellV1GetSeat (layerShellManager (layerShell state)) seatPtr
        if lsSeatPtr == nullPtr
            then do
                logInfo logger $ "seat " <> show sid <> " did not create river_layer_shell_seat_v1"
                pure Nothing
            else do
                lsCleanup <-
                    riverLayerShellSeatV1AddListener lsSeatPtr $
                        LayerShellSeatListener
                            { onLayerShellSeatFocusExclusive =
                                handleLayerShellSeatFocusExclusive runtime
                            , onLayerShellSeatFocusNonExclusive =
                                handleLayerShellSeatFocusNonExclusive runtime
                            , onLayerShellSeatFocusNone =
                                handleLayerShellSeatFocusNone runtime
                            }
                registerCleanup wmState layerSeatCleanupRef lsCleanup
                pure $
                    Just
                        LayerShellSeatState
                            { layerShellSeatPtr = lsSeatPtr
                            , layerShellSeatCleanupRef = layerSeatCleanupRef
                            , layerShellSeatExclusiveFocus = False
                            }
    xkbSeatPtr <- riverXkbBindingsV1GetSeat (rawXkb state) seatPtr -- bind the xkbSeatPtr
    -- need best way to most efficiently map over the keybindings in Cfg riverXkbBindingsV1GetXkbBinding? this should work i think
    newBindings <-
        forConcurrently (cfgKeybindings config) $ \(Chord modifiers (Keysym keysym), action) -> do
            let modifiersWord = modifiersMask modifiers
                xkbListener =
                    XkbBindingListener
                        { onXkbPressed = \_ -> runReaderT action wmState
                        , onXkbReleased = \_ -> pure ()
                        , onXkbStopRepeat = \_ -> pure ()
                        }
            binding <- riverXkbBindingsV1GetXkbBinding (rawXkb state) seatPtr keysym modifiersWord -- bind each key
            cleanup <- riverXkbBindingV1AddListener binding xkbListener -- get the listener for the binding
            pure (binding, cleanup) -- store as (binding, cleanup action)
            -- bind the SeatListener
    cleaner0 <-
        riverXkbBindingsSeatV1AddListener xkbSeatPtr $
            XkbBindingsSeatListener
                { Rivulet.FFI.Protocol.onXkbSeatAteUnboundKey = \_ -> pure ()
                }
    let seat =
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
    logEvent logger "seat" $
        show sid <> " -> connected, bindings=" <> show (length newBindings)
    updateState wmState $ \s ->
        let updatedState = s{seats = Map.insert sid seat (seats s)}
         in case mLayerShellSeat of
                Nothing -> updatedState
                Just lsSeatState ->
                    updatedState
                        { layerShell =
                            let ls = layerShell updatedState
                             in ls
                                    { layerShellSeats =
                                        Map.insert sid lsSeatState (layerShellSeats ls)
                                    }
                        }
    cleaner1 <- riverSeatV1AddListener seatPtr listener
    registerCleanup wmState seatCleanupRef cleaner1

-- Output listener callbacks
onOutRemoved :: TVar WMState -> Ptr RiverOutputV1 -> IO ()
onOutRemoved wmState outPtr = do
    let monId = MonitorId (ptrId outPtr)
    runCleanup wmState (CleanupMonitor monId)
    runCleanup wmState (CleanupLayerShellOutput monId)
    state <- readTVarIO wmState
    for_
        (Map.lookup monId (layerShellOutputs (layerShell state)))
        (riverLayerShellOutputV1Destroy . layerShellOutputPtr)
    updateState wmState $ \s ->
        s
            { layerShell =
                let ls = layerShell s
                 in ls{layerShellOutputs = Map.delete monId (layerShellOutputs ls)}
            }
    riverOutputV1Destroy outPtr
    updateState wmState $ \s ->
        let removedWsIds =
                [ wsId
                | wsId@(WorkspaceId (mId, _)) <- Map.keys (workspaces s)
                , mId == monId
                ]
            removedWsSet = Set.fromList removedWsIds
            clearSeatFocus seat =
                case keyboardFocus seat >>= (\wId -> Map.lookup wId (windows s)) of
                    Just win
                        | Set.member (winWorkspace win) removedWsSet ->
                            seat{keyboardFocus = Nothing}
                    _ -> seat
         in s
                { monitors = Map.delete monId (monitors s)
                , workspaces = foldr Map.delete (workspaces s) removedWsIds
                , dirtyMonitors = Set.delete monId (dirtyMonitors s)
                , lastVisibleWindows = Map.delete monId (lastVisibleWindows s)
                , seats = Map.map clearSeatFocus (seats s)
                }

onOutWlOutput :: TVar WMState -> Ptr RiverOutputV1 -> Word32 -> IO ()
onOutWlOutput _ _ _ = pure ()

onOutPosition :: TVar WMState -> Ptr RiverOutputV1 -> Int -> Int -> IO ()
onOutPosition wmState outPtr x y = do
    let monId = MonitorId (ptrId outPtr)
    modifyMonitor wmState monId $ \m ->
        let geo = monitorGeometry m
         in m{monitorGeometry = geo{x = x, y = y}}

onOutDimensions :: Runtime -> Ptr RiverOutputV1 -> Int -> Int -> IO ()
onOutDimensions runtime outPtr w h = do
    let logger = rtLogger runtime
        wmState = rtState runtime
    let monId = MonitorId (ptrId outPtr)
    logEvent logger "output" $ show monId <> " size=" <> show w <> "×" <> show h
    modifyMonitor wmState monId $ \m ->
        let geo = monitorGeometry m
         in m
                { monitorGeometry = geo{width = w, height = h}
                , workArea = geo{width = w, height = h}
                }

-- Seat listener callbacks
onSeatRemoved :: TVar WMState -> Ptr RiverSeatV1 -> IO ()
onSeatRemoved wmState seatPtr = do
    let seatId = SeatId (ptrId seatPtr)
    runCleanup wmState (CleanupSeat seatId)
    runCleanup wmState (CleanupLayerShellSeat seatId)
    state <- readTVarIO wmState
    for_
        (Map.lookup seatId (layerShellSeats (layerShell state)))
        (riverLayerShellSeatV1Destroy . layerShellSeatPtr)
    updateState wmState $ \s ->
        s
            { layerShell =
                let ls = layerShell s
                 in ls{layerShellSeats = Map.delete seatId (layerShellSeats ls)}
            }
    riverSeatV1Destroy seatPtr
    updateState wmState $ \s -> s{seats = Map.delete seatId (seats s)}

onSeatWlSeat :: TVar WMState -> Ptr RiverSeatV1 -> Word32 -> IO ()
onSeatWlSeat _ _ _ = pure ()

onSeatPointerEnter ::
    TVar WMState -> Ptr RiverSeatV1 -> Ptr RiverWindowV1 -> IO ()
onSeatPointerEnter wmState seatPtr winPtr = do
    let seatId = SeatId (ptrId seatPtr)
    let winId = WindowId (ptrId winPtr)
    modifySeat wmState seatId $ \s -> s{mouseFocus = Just winId}

onSeatPointerLeave :: TVar WMState -> Ptr RiverSeatV1 -> IO ()
onSeatPointerLeave wmState seatPtr = do
    let seatId = SeatId (ptrId seatPtr)
    modifySeat wmState seatId $ \s -> s{mouseFocus = Nothing}

onSeatWindowInteraction ::
    Runtime ->
    Ptr RiverWindowManagerV1 ->
    Ptr RiverSeatV1 ->
    Ptr RiverWindowV1 ->
    IO ()
onSeatWindowInteraction runtime wmPtr seatPtr winPtr = do
    let wmState = rtState runtime
    let seatId = SeatId (ptrId seatPtr)
        winId = WindowId (ptrId winPtr)
    changed <-
        atomically $ do
            state <- readTVar wmState
            case Map.lookup seatId (seats state) of
                Nothing -> pure False
                Just seat ->
                    let exclusiveLayerFocus =
                            maybe
                                False
                                layerShellSeatExclusiveFocus
                                (Map.lookup seatId (layerShellSeats (layerShell state)))
                     in if exclusiveLayerFocus || (keyboardFocus seat == Just winId)
                            then pure False
                            else do
                                modifyTVar wmState $ \s ->
                                    s
                                        { seats =
                                            Map.adjust
                                                (\se -> se{keyboardFocus = Just winId})
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
    logEvent logger "window" $ show winId <> " -> closed"
    runCleanup wmState (CleanupWindow winId)
    riverWindowV1Destroy winPtr
    updateState wmState $ \s ->
        let win = Map.lookup winId (windows s)
            monId =
                fmap
                    ( \w ->
                        let WorkspaceId (mId, _) = winWorkspace w
                         in mId
                    )
                    win
            clearFocusForClosedWindow seat =
                seat
                    { keyboardFocus =
                        if keyboardFocus seat == Just winId
                            then Nothing
                            else keyboardFocus seat
                    , mouseFocus =
                        if mouseFocus seat == Just winId
                            then Nothing
                            else mouseFocus seat
                    }
         in s
                { windows = Map.delete winId (windows s)
                , workspaces =
                    Map.map
                        (\ws -> ws{wsWindows = filter (/= winId) (wsWindows ws)})
                        (workspaces s)
                , dirtyMonitors =
                    case monId of
                        Nothing  -> dirtyMonitors s
                        Just mId -> Set.insert mId (dirtyMonitors s)
                , lastVisibleWindows =
                    Map.map (Set.delete winId) (lastVisibleWindows s)
                , seats =
                    Map.map clearFocusForClosedWindow (seats s)
                }

onWinDimensionsHint ::
    TVar WMState -> Ptr RiverWindowV1 -> Int -> Int -> Int -> Int -> IO ()
onWinDimensionsHint _ _ _ _ _ _ = pure ()

onWinDimensions :: TVar WMState -> Ptr RiverWindowV1 -> Int -> Int -> IO ()
onWinDimensions wmState winPtr width height = do
    let winId = WindowId (ptrId winPtr)
    modifyWindow wmState winId $ \w ->
        let geo = winGeometry w
         in w{winGeometry = geo{width = width, height = height}}

onWinAppId :: Runtime -> Ptr RiverWindowV1 -> Maybe String -> IO ()
onWinAppId runtime winPtr mAppId = do
    let logger = rtLogger runtime
        wmState = rtState runtime
    let winId = WindowId (ptrId winPtr)
    logEvent logger "window" $ show winId <> " appId=" <> show mAppId
    modifyWindow wmState winId $ \w -> w{appId = mAppId}

onWinTitle :: TVar WMState -> Ptr RiverWindowV1 -> Maybe String -> IO ()
onWinTitle wmState winPtr mTitle = do
    let winId = WindowId (ptrId winPtr)
    modifyWindow wmState winId $ \w -> w{winTitle = mTitle}

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
    let monId = fmap (MonitorId . ptrId) mOutPtr
    modifyWindow wmState winId $ \w -> w{fullscreen = (True, monId)}

onWinExitFullscreenReq :: TVar WMState -> Ptr RiverWindowV1 -> IO ()
onWinExitFullscreenReq wmState winPtr = do
    let winId = WindowId (ptrId winPtr)
    modifyWindow wmState winId $ \w -> w{fullscreen = (False, Nothing)}

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
