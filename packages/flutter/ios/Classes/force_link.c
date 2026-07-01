// Keep Rust/FRB symbols reachable when libnapaxi_api_bridge.a is linked statically.
// Dart FFI resolves them with dlsym at runtime, so the host app has no direct
// references unless this file creates them.
extern void frb_create_shutdown_callback(void);
extern void frb_dart_fn_deliver_output(void);
extern void frb_dart_opaque_dart2rust_encode(void);
extern void frb_dart_opaque_drop_thread_box_persistent_handle(void);
extern void frb_dart_opaque_rust2dart_decode(void);
extern void frb_free_wire_sync_rust2dart_dco(void);
extern void frb_free_wire_sync_rust2dart_sse(void);
extern void frb_get_rust_content_hash(void);
extern void frb_init_frb_dart_api_dl(void);
extern void frb_pde_ffi_dispatcher_primary(void);
extern void frb_pde_ffi_dispatcher_sync(void);
extern void frb_rust_vec_u8_free(void);
extern void frb_rust_vec_u8_new(void);
extern void frb_rust_vec_u8_resize(void);
extern void napaxi_ios_ish_register_rootfs_archive_path(void);
extern void napaxi_string_free(void);
extern void napaxi_version(void);
extern void store_dart_post_cobject(void);

__attribute__((used)) static void *napaxi_force_link_symbols[] = {
    (void *)&frb_create_shutdown_callback,
    (void *)&frb_dart_fn_deliver_output,
    (void *)&frb_dart_opaque_dart2rust_encode,
    (void *)&frb_dart_opaque_drop_thread_box_persistent_handle,
    (void *)&frb_dart_opaque_rust2dart_decode,
    (void *)&frb_free_wire_sync_rust2dart_dco,
    (void *)&frb_free_wire_sync_rust2dart_sse,
    (void *)&frb_get_rust_content_hash,
    (void *)&frb_init_frb_dart_api_dl,
    (void *)&frb_pde_ffi_dispatcher_primary,
    (void *)&frb_pde_ffi_dispatcher_sync,
    (void *)&frb_rust_vec_u8_free,
    (void *)&frb_rust_vec_u8_new,
    (void *)&frb_rust_vec_u8_resize,
    (void *)&napaxi_ios_ish_register_rootfs_archive_path,
    (void *)&napaxi_string_free,
    (void *)&napaxi_version,
    (void *)&store_dart_post_cobject,
};

void napaxi_force_link(void) {
    (void)napaxi_force_link_symbols;
}
