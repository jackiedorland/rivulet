{-# LANGUAGE OverloadedStrings #-}
module Fjord.Log where

import Fjord.Types

import Data.Text (Text, pack)
import Data.Text.IO
import System.IO (stdout, stderr)
import System.Exit
import Control.Concurrent.STM

logMsg :: Runtime -> Msg -> IO ()
logMsg rt msg = atomically $
    writeTQueue (logs rt) msg

info :: Runtime -> Text -> IO ()
info rt =
    logMsg rt . Log Info

debug :: Runtime -> Text -> IO ()
debug rt =
    logMsg rt . Log Debug

warn :: Runtime -> Text -> IO ()
warn rt =
    logMsg rt . Warn

fatal :: Runtime -> Text -> IO ()
fatal rt =
    logMsg rt . Fatal

emit :: Level -> Msg -> IO ()
emit l m = do
    case m of 
        Event e -> hPutStrLn stdout ("[Event] " <> prettyPrint e)
        Log _l t -> if _l >= l then 
            do hPutStrLn stdout ("[Log] " <> t)
            else pure ()
        Warn t -> hPutStrLn stderr ("[Warn] " <> t) 
        Fatal t -> do 
            hPutStrLn stderr ("[FATAL] " <> t)
            exitFailure

prettyPrint :: Event -> Text
prettyPrint e = case e of
    RiverUnavailable ->
        "Server sent RiverUnavailable ... is another client already connected via the river_window_management_v1 protocol?"

    RiverFinished ->
        "Server sent RiverFinished ... shutting down"

    RiverLocked ->
        "WM locked"

    RiverUnlocked ->
        "WM unlocked"

    WinCreated wid ->
        "Window registered -> " <> showt wid

    OutputCreated oid ->
        "Output registered -> " <> showt oid

    SeatCreated sid ->
        "Seat registered -> " <> showt sid

    WinClosed wid ->
        "Window closed: " <> showt wid

    WinDimensionsHint wid minW maxW minH maxH ->
        "New preferred window dimensions for window "
            <> showt wid
            <> " \nmin=(" <> showt minW <> "," <> showt minH <> ")"
            <> " \nmax=(" <> showt maxW <> "," <> showt maxH <> ")"

    WinDimensions wid w h ->
        "New dimensions for window "
            <> showt wid
            <> "-> "
            <> showt w
            <> "x"
            <> showt h

    WinSetAppId wid appId ->
        "Window "
            <> showt wid
            <> " set appId to "
            <> maybe "<NULL>" pack appId

    WinSetTitle wid title ->
        "Window "
            <> showt wid
            <> " set title to "
            <> maybe "<NULL>" pack title

    WinSetParent wid parent ->
        "Window "
            <> showt wid
            <> " has new parent "
            <> maybe "<NULL>" showt parent

    WinDecorationHint wid hint ->
        "Window "
            <> showt wid
            <> " requests decorations "
            <> showt hint

    WinPtrMoveReq wid sid ->
        "Window pointer move request for "
            <> showt wid
            <> " seat="
            <> showt sid

    WinPtrResizeReq wid sid edges ->
        "Window pointer resize request for "
            <> showt wid
            <> " seat="
            <> showt sid
            <> " edges="
            <> showt edges

    WinShowDecorationMenu wid x y ->
        "Window "
            <> showt wid
            <> " requests decoration menu at ("
            <> showt x
            <> ", "
            <> showt y
            <> ")"

    WinMaximizeReq wid ->
        "Window " <> showt wid <> " requests maximize"

    WinUnmaximizeReq wid ->
        "Window " <> showt wid <> " requests un-maximize"

    WinFullscreenReq wid out ->
        "Window "
            <> showt wid
            <> " requests fullscreen on output "
            <> maybe "<NULL>" showt out

    WinExitFullscreenReq wid ->
        "Window " <> showt wid <> " wants to leave fullscreen"

    WinMinimizeReq wid ->
        "Window " <> showt wid <> " requests minimize"

    WinUnreliablePID wid pid ->
        "Window "
            <> showt wid
            <> " asserts unreliable pid="
            <> showt pid

    OutRemoved oid ->
        "Output removed -> " <> showt oid

    OutWlName oid name ->
        "Output "
            <> showt oid
            <> " asserts Wayland name: "
            <> showt name

    OutPosition oid x y ->
        "Output "
            <> showt oid
            <> " asserts position ("
            <> showt x
            <> ", "
            <> showt y
            <> ")"

    OutDimensions oid w h ->
        "Output "
            <> showt oid
            <> " asserts dimensions "
            <> showt w
            <> "x"
            <> showt h

    SeatRemoved sid ->
        "Seat removed -> " <> showt sid

    SeatWlName sid name ->
        "Seat "
            <> showt sid
            <> " asserts Wayland name: "
            <> showt name

    SeatPtrEnter sid wid ->
        "Pointer entered Window "
            <> showt wid
            <> " on Seat "
            <> showt sid

    SeatPtrLeave sid ->
        "Pointer left previous window on Seat "
            <> showt sid

    SeatWinInteraction sid wid ->
        "Window "
            <> showt wid
            <> " on Seat "
            <> showt sid

    SeatShellInteraction sid shid ->
        "Seat "
            <> showt sid
            <> " interacted with Shell Surface "
            <> showt shid

    SeatOpDelta sid dx dy ->
        "Seat "
            <> showt sid
            <> " began OpΔ=("
            <> showt dx
            <> ", "
            <> showt dy
            <> ")"

    SeatOpRelease sid ->
        "Seat "
            <> showt sid
            <> " ended OpΔ"

    SeatPtrPos sid x y -> "Seat " <> showt sid <> " moved pointer to (" <> showt x <> ", " <> showt y <> ")" 

showt :: Show a => a -> Text
showt = pack . show 
