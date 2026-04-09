module Rivulet.Monad where

import Rivulet.Manager.Log (Logger)
import Rivulet.Types

import Control.Concurrent.STM
import Control.Monad.Reader
import Data.Map.Strict qualified as Map
import Data.Maybe (listToMaybe, maybeToList)

data Runtime = Runtime
    { rtLogger :: Logger
    , rtState :: TVar WMState
    }

type Action = Rivulet ()

type Rivulet a = ReaderT (TVar WMState) IO a

update :: (WMState -> WMState) -> Rivulet ()
update f = ask >>= \var -> liftIO $ updateState var f

getState :: Rivulet WMState
getState = ask >>= \var -> liftIO $ readTVarIO var

updateState :: TVar WMState -> (WMState -> WMState) -> IO ()
updateState var f = atomically $ modifyTVar var f

modifyMonitor :: TVar WMState -> MonitorId -> (Monitor -> Monitor) -> IO ()
modifyMonitor wmState monId f =
    updateState wmState $ \s -> s{monitors = Map.adjust f monId (monitors s)}

modifyWindow :: TVar WMState -> WindowId -> (Window -> Window) -> IO ()
modifyWindow wmState winId f =
    updateState wmState $ \s -> s{windows = Map.adjust f winId (windows s)}

modifySeat :: TVar WMState -> SeatId -> (Seat -> Seat) -> IO ()
modifySeat wmState seatId f =
    updateState wmState $ \s -> s{seats = Map.adjust f seatId (seats s)}

withFocused :: (WindowId -> Window -> Rivulet ()) -> Rivulet ()
withFocused f = do
    state <- getState
    let mFocused =
            listToMaybe
                [ (winId, win)
                | seat <- Map.elems (seats state)
                , winId <- maybeToList (keyboardFocus seat)
                , win <- maybeToList (Map.lookup winId (windows state))
                ]
    case mFocused of
        Nothing -> pure ()
        Just (winId, win) -> f winId win
