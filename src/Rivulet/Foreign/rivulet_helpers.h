#pragma once
#include <wayland-client.h>

int rivulet_proxy_add_listener(struct wl_proxy *proxy, void **impl, void *data);
