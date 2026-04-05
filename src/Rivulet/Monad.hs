module Rivulet.Monad where

import           Rivulet.Manager.Log    (Logger)
import           Rivulet.Types

import           Control.Concurrent.STM
import           Control.Monad.Reader
import qualified Data.Map.Strict        as Map

data Runtime = Runtime
  { rtLogger :: Logger
  , rtState  :: TVar WMState
  }

type RivuletAction = Rivulet ()

type Rivulet a = ReaderT (TVar WMState) IO a

update :: (WMState -> WMState) -> Rivulet ()
update f = ask >>= \var -> liftIO $ updateState var f

getState :: Rivulet WMState
getState = ask >>= \var -> liftIO $ readTVarIO var

updateState :: TVar WMState -> (WMState -> WMState) -> IO ()
updateState var f = atomically $ modifyTVar var f

modifyMonitor :: TVar WMState -> MonitorId -> (Monitor -> Monitor) -> IO ()
modifyMonitor wmState monId f =
  updateState wmState $ \s -> s {monitors = Map.adjust f monId (monitors s)}

modifyWindow :: TVar WMState -> WindowId -> (Window -> Window) -> IO ()
modifyWindow wmState winId f =
  updateState wmState $ \s -> s {windows = Map.adjust f winId (windows s)}

modifySeat :: TVar WMState -> SeatId -> (Seat -> Seat) -> IO ()
modifySeat wmState seatId f =
  updateState wmState $ \s -> s {seats = Map.adjust f seatId (seats s)}
