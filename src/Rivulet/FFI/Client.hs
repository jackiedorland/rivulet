{-# LANGUAGE CApiFFI #-}

module Rivulet.FFI.Client (
    WlDisplay,
    WlInterface,
    WlProxy,
    WlRegistry,

    wlDisplayConnect,
    wlDisplayDisconnect,
    wlDisplayGetFd,

    wlDisplayDispatch,
    wlDisplayDispatchPending,
    wlDisplayFlush,
    wlDisplayRoundtrip,

    wlDisplayGetRegistry,
    wlRegistryAddListener,
    wlRegistryBind,

    RegistryGlobalCallback,
    RegistryGlobalRemoveCallback,
    mkRegistryGlobalCallback,
    mkRegistryGlobalRemoveCallback,
) where

import Foreign
import Foreign.C.String (CString, peekCString, withCString)
import Foreign.C.Types (CInt (..), CUInt (..))
import System.Posix.Types (Fd (..))

data WlDisplay


data WlRegistry

data WlProxy

data WlInterface

wlDisplayConnect :: Maybe String -> IO (Maybe (Ptr WlDisplay))
wlDisplayConnect mName = do
    ptr <- case mName of
        Nothing -> wl_display_connect nullPtr
        Just name -> withCString name wl_display_connect
    pure $ if ptr == nullPtr then Nothing else Just ptr

foreign import capi "wayland-client.h wl_display_connect"
    wl_display_connect :: CString -> IO (Ptr WlDisplay)

wlDisplayDisconnect :: Ptr WlDisplay -> IO ()
wlDisplayDisconnect = wl_display_disconnect

foreign import capi "wayland-client.h wl_display_disconnect"
    wl_display_disconnect :: Ptr WlDisplay -> IO ()

wlDisplayGetFd :: Ptr WlDisplay -> IO Fd
wlDisplayGetFd display = Fd <$> wl_display_get_fd display

foreign import capi "wayland-client.h wl_display_get_fd"
    wl_display_get_fd :: Ptr WlDisplay -> IO CInt

wlDisplayDispatch :: Ptr WlDisplay -> IO CInt
wlDisplayDispatch = wl_display_dispatch

foreign import capi "wayland-client.h wl_display_dispatch"
    wl_display_dispatch :: Ptr WlDisplay -> IO CInt

wlDisplayDispatchPending :: Ptr WlDisplay -> IO CInt
wlDisplayDispatchPending = wl_display_dispatch_pending

foreign import capi "wayland-client.h wl_display_dispatch_pending"
    wl_display_dispatch_pending :: Ptr WlDisplay -> IO CInt

wlDisplayFlush :: Ptr WlDisplay -> IO CInt
wlDisplayFlush = wl_display_flush

foreign import capi "wayland-client.h wl_display_flush"
    wl_display_flush :: Ptr WlDisplay -> IO CInt

wlDisplayRoundtrip :: Ptr WlDisplay -> IO CInt
wlDisplayRoundtrip = wl_display_roundtrip

foreign import capi "wayland-client.h wl_display_roundtrip"
    wl_display_roundtrip :: Ptr WlDisplay -> IO CInt

wlDisplayGetRegistry :: Ptr WlDisplay -> IO (Ptr WlRegistry)
wlDisplayGetRegistry = wl_display_get_registry

foreign import capi "wayland-client.h wl_display_get_registry"
    wl_display_get_registry :: Ptr WlDisplay -> IO (Ptr WlRegistry)

type RegistryGlobalCallback =
    Ptr WlRegistry ->
    Word32 ->
    String ->
    Word32 ->
    IO ()

type RegistryGlobalRemoveCallback =
    Ptr WlRegistry ->
    Word32 ->
    IO ()

-- Unexposed C-level callback signatures used for FFI marshaling
type RawGlobal =
    Ptr () -> -- user data pointer (unused)
    Ptr WlRegistry ->
    CUInt ->
    CString ->
    CUInt ->
    IO ()

type RawGlobalRemove =
    Ptr () ->
    Ptr WlRegistry ->
    CUInt ->
    IO ()

-- C function pointer wrappers for callback marshaling
-- \"wrapper\" imports use @ccall@; @capi@ only applies to calling C functions,
-- not to creating Haskell-to-C function pointers
foreign import ccall "wrapper"
    mkRegistryGlobalCallback :: RawGlobal -> IO (FunPtr RawGlobal)

foreign import ccall "wrapper"
    mkRegistryGlobalRemoveCallback :: RawGlobalRemove -> IO (FunPtr RawGlobalRemove)

wlRegistryAddListener ::
    Ptr WlRegistry ->
    RegistryGlobalCallback ->
    RegistryGlobalRemoveCallback ->
    IO (IO ())
wlRegistryAddListener registry onGlobal onRemove = do
    globalFp <- mkRegistryGlobalCallback $ \_ reg name iface ver -> do
        ifaceStr <- peekCString iface
        onGlobal reg (fromIntegral name) ifaceStr (fromIntegral ver)
    removeFp <- mkRegistryGlobalRemoveCallback $ \_ reg name ->
        onRemove reg (fromIntegral name)
    listenerPtr <- mallocBytes (2 * sizeOf (undefined :: FunPtr ()))
    pokeElemOff listenerPtr 0 (castFunPtr globalFp :: FunPtr ())
    pokeElemOff listenerPtr 1 (castFunPtr removeFp :: FunPtr ())
    _ <- wl_registry_add_listener registry (castPtr listenerPtr) nullPtr
    pure $ do
        freeHaskellFunPtr globalFp
        freeHaskellFunPtr removeFp
        free listenerPtr

foreign import capi "wayland-client.h wl_registry_add_listener"
    wl_registry_add_listener :: Ptr WlRegistry -> Ptr () -> Ptr () -> IO CInt

wlRegistryBind ::
    Ptr WlRegistry ->
    Word32 ->
    Ptr WlInterface ->
    Word32 ->
    IO (Ptr a)
wlRegistryBind registry name iface version =
    castPtr <$> wl_registry_bind registry (fromIntegral name) iface (fromIntegral version)

foreign import capi "wayland-client.h wl_registry_bind"
    wl_registry_bind :: Ptr WlRegistry -> CUInt -> Ptr WlInterface -> CUInt -> IO (Ptr WlProxy)
