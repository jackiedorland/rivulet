module Main where

import           Control.Monad        (foldM, unless, when)
import           System.Directory     (XdgDirectory (..),
                                       createDirectoryIfMissing, doesFileExist,
                                       getXdgDirectory)
import           System.Environment   (getArgs, getProgName, setEnv)
import           System.Exit          (ExitCode (..), exitFailure)
import           System.FilePath      ((</>))
import           System.IO            (hPutStrLn, stderr)
import           System.Posix.Process (executeFile)
import           System.Process       (readProcessWithExitCode)

data CliOptions = CliOptions
  { optDebug    :: Bool
  , optNoBanner :: Bool
  }

defaultCliOptions :: CliOptions
defaultCliOptions = CliOptions {optDebug = False, optNoBanner = False}

parseCliArgs :: [String] -> Either String CliOptions
parseCliArgs = foldM step defaultCliOptions
  where
    step opts "--debug"     = Right opts {optDebug = True}
    step opts "--no-banner" = Right opts {optNoBanner = True}
    step _ arg              = Left $ "unknown option: " <> arg

usage :: String -> String
usage prog =
  unlines
    [ "Usage: " <> prog <> " [--debug] [--no-banner]"
    , ""
    , "Options:"
    , "  --debug      Enable verbose info/event logging"
    , "  --no-banner  Suppress startup banner"
    ]

applyCliEnv :: CliOptions -> IO ()
applyCliEnv opts = do
  when (optDebug opts) $ setEnv "RIVULET_DEBUG" "1"
  when (optNoBanner opts) $ setEnv "RIVULET_BANNER" "false"

defaultConfig :: String
defaultConfig =
  unlines
    [ "import Rivulet"
    , ""
    , "main :: IO ()"
    , "main = rivulet $ do"
    , "    gaps 8"
    , "    layout [Tall]"
    ]

recompileIfStale :: FilePath -> FilePath -> IO ()
recompileIfStale src out = do
  -- this doesn't check for staleness yet, recompiles every time
  (code, _, err) <-
    readProcessWithExitCode
      "cabal"
      ["exec", "ghc", "--", "--make", src, "-o", out, "-rtsopts", "-threaded", "-XBlockArguments"]
      ""
  case code of
    ExitSuccess -> pure ()
    ExitFailure _ -> do
      hPutStrLn stderr $ "rivulet: config compilation failed:\n" <> err
      exitFailure

main :: IO ()
main = do
  args <- getArgs
  prog <- getProgName
  opts <-
    case parseCliArgs args of
      Left err -> do
        hPutStrLn stderr $ "rivulet: " <> err
        hPutStrLn stderr $ usage prog
        exitFailure
      Right o -> pure o
  applyCliEnv opts
  configDir <- getXdgDirectory XdgConfig "rivulet"
  createDirectoryIfMissing True configDir
  let configFile = configDir </> "Config.hs"
  let outputBin = configDir </> "rivulet.o"
  exists <- doesFileExist configFile
  unless exists $ writeFile configFile defaultConfig
  recompileIfStale configFile outputBin
  executeFile outputBin True [] Nothing
