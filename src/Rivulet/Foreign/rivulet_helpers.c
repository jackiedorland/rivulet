#include "rivulet_helpers.h"

int rivulet_proxy_add_listener(struct wl_proxy *proxy, void **impl, void *data)
{
    return wl_proxy_add_listener(proxy, (void (**)(void)) impl, data);
}
