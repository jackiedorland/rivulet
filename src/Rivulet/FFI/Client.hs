{-# LANGUAGE CApiFFI #-}

-- | Low-level Wayland core protocol client bindings.
--
-- This module provides FFI bindings to @libwayland-client@ for connection management,
-- event dispatch, and registry access. These are the foundational building blocks
-- for higher-level protocol implementations (see "Rivulet.FFI.Protocol").
--
-- == Typical Usage
--
-- Connect to the Wayland server, retrieve the registry, and attach listeners:
--
-- > import Rivulet.FFI.Client
-- >
-- > -- Connect to display
-- > Just display <- wlDisplayConnect Nothing
-- > fd <- wlDisplayGetFd display
-- >
-- > -- Get registry for discovering globals
-- > registry <- wlDisplayGetRegistry display
-- >
-- > -- Attach listeners for global availability
-- > cleanup <- wlRegistryAddListener registry onGlobal onRemove
-- >
-- > -- Event loop
-- > wlDisplayDispatch display  -- blocks until events arrive
-- > wlDisplayFlush display     -- send pending requests
-- >
-- > -- Cleanup
-- > cleanup  -- free listeners
-- > wlDisplayDisconnect display
--
-- == Event Loop Patterns
--
-- __Blocking dispatch:__ Use 'wlDisplayDispatch' when you can afford to block.
-- 'wlDisplayDispatch' blocks until at least one event arrives, then dispatches all queued events.
--
-- __Non-blocking dispatch:__ Use 'wlDisplayDispatchPending' in a main event loop.
-- This never blocks and processes any queued events.
--
-- __Synchronous roundtrip:__ Use 'wlDisplayRoundtrip' to ensure all requests are sent
-- and all responses received. Useful for initial setup and synchronizing state.
--
-- == File Descriptors and Polling
--
-- Get the underlying file descriptor with 'wlDisplayGetFd' for integration
-- with your event loop (@select@, @epoll@, @kqueue@, etc.).
-- Monitor for readability to know when to call 'wlDisplayDispatch'.

module Rivulet.FFI.Client
    ( -- * Opaque pointer types
      WlDisplay
    , WlInterface
    , WlProxy
    , WlRegistry
      -- * Display lifecycle
    , wlDisplayConnect
    , wlDisplayDisconnect
    , wlDisplayGetFd
      -- * Event loop
    , wlDisplayDispatch
    , wlDisplayDispatchPending
    , wlDisplayFlush
    , wlDisplayRoundtrip
      -- * Registry
    , wlDisplayGetRegistry
    , wlRegistryAddListener
    , wlRegistryBind
      -- * Listener callback types
    , RegistryGlobalCallback
    , RegistryGlobalRemoveCallback
    , mkRegistryGlobalCallback
    , mkRegistryGlobalRemoveCallback
    ) where

import Foreign
import Foreign.C.String   (CString, peekCString, withCString)
import Foreign.C.Types    (CInt (..), CUInt (..))
import System.Posix.Types (Fd (..))

-- | Opaque C struct types for Wayland client library bindings.
-- These are references to server-side objects managed by the Wayland protocol.

data WlDisplay
  -- ^ The display connection object. Use 'wlDisplayConnect' to obtain.

data WlRegistry
  -- ^ Registry object for discovering available globals.
  -- Obtained via 'wlDisplayGetRegistry'.

data WlProxy
  -- ^ Base type for all Wayland protocol objects.
  -- Specific interface types (e.g., 'RiverWindowManagerV1') are newtype wrappers around this.

data WlInterface
  -- ^ Opaque interface descriptor.
  -- Produced by wayland-scanner and used during object binding.

-- | Connect to the Wayland display server.
--
-- Connects to the Wayland display, returning a pointer to the @WlDisplay@ object
-- on success. If @Nothing@ is passed, connects to the display specified by the
-- @$WAYLAND_DISPLAY@ environment variable (typically \":0\" or \":1\").
--
-- The returned @WlDisplay@ must be disconnected with 'wlDisplayDisconnect' when done.
wlDisplayConnect :: Maybe String -> IO (Maybe (Ptr WlDisplay))
wlDisplayConnect mName = do
  ptr <- case mName of
    Nothing   -> wl_display_connect nullPtr
    Just name -> withCString name wl_display_connect
  pure $ if ptr == nullPtr then Nothing else Just ptr

foreign import capi "wayland-client.h wl_display_connect"
  wl_display_connect :: CString -> IO (Ptr WlDisplay)


-- | Disconnect from the Wayland display and free associated resources.
--
-- This should be called when the display connection is no longer needed.
-- No further operations are permitted on this pointer after calling this function.
wlDisplayDisconnect :: Ptr WlDisplay -> IO ()
wlDisplayDisconnect = wl_display_disconnect

foreign import capi "wayland-client.h wl_display_disconnect"
  wl_display_disconnect :: Ptr WlDisplay -> IO ()

-- | Get the file descriptor associated with the display connection.
--
-- The returned file descriptor can be monitored for readability (e.g., with @select@ or @epoll@)
-- to know when to call 'wlDisplayDispatch'. The FD is owned by the display; do not close it.
wlDisplayGetFd :: Ptr WlDisplay -> IO Fd
wlDisplayGetFd display = Fd <$> wl_display_get_fd display

foreign import capi "wayland-client.h wl_display_get_fd"
  wl_display_get_fd :: Ptr WlDisplay -> IO CInt

-- | Block until events arrive, then dispatch them.
--
-- This is a synchronous call that blocks until at least one event is received
-- from the server. Dispatching invokes all registered event listeners.
--
-- Returns the number of events dispatched on success, or @-1@ on error.
wlDisplayDispatch :: Ptr WlDisplay -> IO CInt
wlDisplayDispatch = wl_display_dispatch

foreign import capi "wayland-client.h wl_display_dispatch"
  wl_display_dispatch :: Ptr WlDisplay -> IO CInt

-- | Dispatch any events already in the internal queue without blocking.
--
-- This is useful in non-blocking event loops. If no events are queued,
-- returns 0 immediately. Calls all registered event listeners for queued events.
--
-- Returns the number of events dispatched on success, or @-1@ on error.
wlDisplayDispatchPending :: Ptr WlDisplay -> IO CInt
wlDisplayDispatchPending = wl_display_dispatch_pending

foreign import capi "wayland-client.h wl_display_dispatch_pending"
  wl_display_dispatch_pending :: Ptr WlDisplay -> IO CInt

-- | Send all pending requests to the server.
--
-- This should be called after making requests to ensure they are transmitted
-- to the compositor. Many operations implicitly flush, but explicit flushing
-- may be needed in certain scenarios.
--
-- Returns 0 on success or @-1@ on error.
wlDisplayFlush :: Ptr WlDisplay -> IO CInt
wlDisplayFlush = wl_display_flush

foreign import capi "wayland-client.h wl_display_flush"
  wl_display_flush :: Ptr WlDisplay -> IO CInt

-- | Send all pending requests and wait until all responses are processed.
--
-- This is a synchronous call that ensures all queued requests have been sent
-- to the server and that all server responses have been received and dispatched.
-- Useful for ensuring deterministic state synchronization with the compositor.
--
-- Returns the number of events dispatched on success, or @-1@ on error.
wlDisplayRoundtrip :: Ptr WlDisplay -> IO CInt
wlDisplayRoundtrip = wl_display_roundtrip

foreign import capi "wayland-client.h wl_display_roundtrip"
  wl_display_roundtrip :: Ptr WlDisplay -> IO CInt

-- | Retrieve the registry object for this display connection.
--
-- The registry is used to discover and bind to global objects (interfaces)
-- advertised by the server. Attach a listener with 'wlRegistryAddListener'
-- to be notified when globals are available or removed.
wlDisplayGetRegistry :: Ptr WlDisplay -> IO (Ptr WlRegistry)
wlDisplayGetRegistry = wl_display_get_registry

foreign import capi "wayland-client.h wl_display_get_registry"
  wl_display_get_registry :: Ptr WlDisplay -> IO (Ptr WlRegistry)


-- | Callback type for registry global availability events.
--
-- Called when a new global object is advertised by the server.
-- The @name@ is a unique numeric identifier for this global instance,
-- used to bind to the object. The @interface@ is a string like @\"river_window_manager_v1\"@
-- or @\"wl_output\"@. The @version@ is the maximum protocol version supported by the server.
type RegistryGlobalCallback
  =  Ptr WlRegistry
  -> Word32         -- ^ Numeric name/ID of this global (used with 'wlRegistryBind')
  -> String         -- ^ Interface name, e.g., @\"river_window_manager_v1\"@
  -> Word32         -- ^ Maximum advertised protocol version
  -> IO ()

-- | Callback type for registry global removal events.
--
-- Called when a previously advertised global is no longer available.
type RegistryGlobalRemoveCallback
  =  Ptr WlRegistry
  -> Word32         -- ^ Name of the global being removed
  -> IO ()

-- Unexposed C-level callback signatures used for FFI marshaling
type RawGlobal
  =  Ptr ()         -- user data pointer (unused)
  -> Ptr WlRegistry
  -> CUInt
  -> CString
  -> CUInt
  -> IO ()

type RawGlobalRemove
  =  Ptr ()
  -> Ptr WlRegistry
  -> CUInt
  -> IO ()

-- C function pointer wrappers for callback marshaling
-- \"wrapper\" imports use @ccall@; @capi@ only applies to calling C functions,
-- not to creating Haskell-to-C function pointers
foreign import ccall "wrapper"
  mkRegistryGlobalCallback :: RawGlobal -> IO (FunPtr RawGlobal)

foreign import ccall "wrapper"
  mkRegistryGlobalRemoveCallback :: RawGlobalRemove -> IO (FunPtr RawGlobalRemove)

-- | Attach listeners to a registry object.
--
-- The callbacks will be fired during 'wlDisplayDispatch' or 'wlDisplayRoundtrip'
-- whenever globals become available or are removed.
--
-- Returns a cleanup action that frees the allocated 'FunPtr's and listener memory.
-- This action should be called when the registry is no longer needed, or upon error.
-- __Important:__ Call the returned cleanup action to prevent memory leaks.
wlRegistryAddListener
  :: Ptr WlRegistry
  -> RegistryGlobalCallback
  -> RegistryGlobalRemoveCallback
  -> IO (IO ())   -- ^ Cleanup action to free resources
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


-- | Bind to a global object.
--
-- Creates a new proxy object for the interface specified by @iface@,
-- using the numeric @name@ from the corresponding global availability callback.
-- The @version@ is the protocol version the client wishes to use;
-- this should be at most the advertised maximum version.
--
-- The returned pointer should be cast to the specific interface type
-- (e.g., @Ptr RiverWindowManagerV1@). The binding establishes a new
-- object ID in the protocol and is ready for requests and event listeners.
--
-- On protocol error (invalid name, version too high, role conflict),
-- this may fail silently or cause the server to emit a protocol error.
wlRegistryBind
  :: Ptr WlRegistry
  -> Word32         -- ^ Global name/ID from the availability callback
  -> Ptr WlInterface
  -> Word32         -- ^ Desired protocol version (typically the advertised maximum)
  -> IO (Ptr a)
wlRegistryBind registry name iface version =
  castPtr <$> wl_registry_bind registry (fromIntegral name) iface (fromIntegral version)

foreign import capi "wayland-client.h wl_registry_bind"
  wl_registry_bind :: Ptr WlRegistry -> CUInt -> Ptr WlInterface -> CUInt -> IO (Ptr WlProxy)
