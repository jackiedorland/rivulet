{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE TemplateHaskell   #-}

module Rivulet.Manager.Log
  ( Logger
  , withLogger
  , logInfo
  , logError
  , logEvent
  , logFail
  , separator
  , banner
  ) where

import           Colog              (LogAction (..), logTextHandle, (<&))
import           Colog.Concurrent   (defCapacity, withBackgroundLogger)
import           Control.Exception  (throwIO)
import           Control.Monad      (when)
import           Data.Char          (toLower)
import           Data.Text          (Text)
import qualified Data.Text          as T
import           Data.Version       (showVersion)
import           Paths_rivulet      (version)
import           System.Environment (lookupEnv)
import           System.IO          (hIsTerminalDevice, hPutStr, stderr)

type Logger = (Bool, LogAction IO Text)

withLogger :: Bool -> Maybe FilePath -> (Logger -> IO a) -> IO a
withLogger debugEnabled _ k = do
  isTTY <- hIsTerminalDevice stderr
  hasTerm <- (/= Nothing) <$> lookupEnv "TERM"
  let sink =
        if isTTY || hasTerm
          then LogAction $ \msg ->
                 unLogAction (logTextHandle stderr) (fmtColor msg)
          else logTextHandle stderr
  withBackgroundLogger defCapacity sink (pure ()) $ \action ->
    k (debugEnabled, action)

emit :: Logger -> Text -> IO ()
emit (_, action) msg = action <& msg

isDebugEnabled :: Logger -> Bool
isDebugEnabled = fst

fmtColor :: Text -> Text
fmtColor msg =
  let (tag, rest) = T.breakOn "] " msg
      tagColor
        | "[rivulet:error]" `T.isPrefixOf` msg = "\ESC[1;31m"
        | "[rivulet:" `T.isPrefixOf` msg = "\ESC[2m"
        | otherwise = "\ESC[0m"
   in tagColor <> tag <> "]\ESC[0m " <> T.drop 2 rest

logInfo :: Logger -> String -> IO ()
logInfo logger msg =
  when (isDebugEnabled logger) $ emit logger (T.pack ("[rivulet] " <> msg))

logError :: Logger -> String -> IO ()
logError logger msg = emit logger (T.pack ("[rivulet:error] " <> msg))

logFail :: Logger -> String -> IO a
logFail logger msg = do
  logError logger ("FATAL! " <> msg)
  throwIO $ userError msg

separator :: Logger -> IO ()
separator logger =
  when (isDebugEnabled logger)
    $ emit logger (T.pack ("[rivulet] " <> replicate 40 '─'))

logEvent :: Logger -> String -> String -> IO ()
logEvent logger ctx msg =
  when (isDebugEnabled logger)
    $ emit logger (T.pack ("[rivulet:" <> ctx <> "] " <> msg))

banner :: IO ()
banner = do
  showBanner <-
    (/= Just "false") . fmap (map toLower) <$> lookupEnv "RIVULET_BANNER"
  when showBanner
    $ hPutStr stderr
    $ "\ESC[97m"
        <> unlines
             [ ""
             , "                                  ▄▄"
             , "▄▄  ▄▄             ▀▀             ██        ██"
             , " ▀█▄ ▀█▄     ████▄ ██ ██ ██ ██ ██ ██ ▄█▀█▄ ▀██▀▀"
             , "  ▄█▀ ▄█▀    ██ ▀▀ ██ ██▄██ ██ ██ ██ ██▄█▀  ██"
             , "▄█▀ ▄█▀ ██   ██    ██▄ ▀█▀  ▀██▀█ ██ ▀█▄▄▄  ██"
             , ""
             , "  v" <> showVersion version
             , ""
             ]
        <> "\ESC[0m"
