// nook_adblock.h
// C ABI over brave/adblock-rust (MPL-2.0) built from Nook/ThirdParty/AdblockRustFFI.
//
// THREAD SAFETY: an engine pointer is NOT thread-safe. adblock::Engine is Send
// but not Sync (it holds a RefCell regex cache). The caller must serialize all
// calls on a given engine (e.g. confine it to one actor/queue). Distinct
// engines may be used from distinct threads concurrently.

#ifndef NOOK_ADBLOCK_H
#define NOOK_ADBLOCK_H

#include <stdbool.h>
#include <stddef.h>
#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

/// Build an engine from ABP/uBlock Origin filter-list text (UTF-8, not NUL-terminated).
/// Returns NULL on failure. Free with nook_adblock_engine_free.
void *nook_adblock_engine_from_rules(const char *rules_utf8, size_t rules_len);

/// Restore an engine from bytes produced by nook_adblock_engine_serialize.
/// Returns NULL on failure (corrupt data or version mismatch).
void *nook_adblock_engine_deserialize(const uint8_t *bytes, size_t len);

/// Serialize an engine. Writes the byte count to *out_len. Returns NULL on
/// failure. Free the buffer with nook_adblock_buffer_free.
uint8_t *nook_adblock_engine_serialize(void *engine, size_t *out_len);

/// Free a buffer returned by nook_adblock_engine_serialize. NULL is a no-op.
void nook_adblock_buffer_free(uint8_t *bytes, size_t len);

/// True if the request would be blocked (matched a block rule with no
/// exception, or an $important rule). request_type is one of adblock-rust's
/// strings: "script", "image", "stylesheet", "xmlhttprequest", "sub_frame",
/// "main_frame", "font", "media", "websocket", "ping", "object", "other".
/// Returns false on NULL engine, NULL/non-UTF-8 arguments or unparseable URLs.
bool nook_adblock_engine_matches(void *engine, const char *url, const char *source_url, const char *request_type);

/// Free an engine. NULL is a no-op.
void nook_adblock_engine_free(void *engine);

/// Convert ABP/uBlock filter text (UTF-8, not NUL-terminated) into a
/// NUL-terminated UTF-8 JSON array of WKContentRuleList rule objects.
/// Writes the converted rule count to *out_rule_count and the number of lines
/// that failed to convert to *out_error_count; either pointer may be NULL.
/// Returns NULL on a NULL or non-UTF-8 input.
/// Free the result with nook_adblock_string_free.
char *nook_adblock_convert_to_content_blocking(const char *rules_utf8, size_t rules_len, size_t *out_rule_count, size_t *out_error_count);

/// Free a string returned by any char*-returning function in this library.
/// NULL is a no-op.
void nook_adblock_string_free(char *s);

/// Cosmetic rules that apply to one URL, as a NUL-terminated UTF-8 JSON object
/// with keys hide_selectors (array of string), procedural_actions (array of
/// string, each itself a JSON object), injected_script (string), exceptions
/// (array of string) and generichide (bool).
/// Returns NULL when nothing applies, or on a NULL/non-UTF-8 argument.
///
/// `engine` must come from nook_adblock_engine_from_rules. The same thread
/// safety rule applies as for matching: serialize all calls on a given engine.
///
/// injected_script is always empty unless the engine was given scriptlet
/// resources, and Nook gives it none.
///
/// Free the result with nook_adblock_string_free.
char *nook_adblock_cosmetic_for_url(void *engine, const char *url);

#ifdef __cplusplus
}
#endif

#endif /* NOOK_ADBLOCK_H */
