// Ghostty embedding API. The documentation for the embedding API is
// only within the Zig source files that define the implementations. This
// isn't meant to be a general purpose embedding API (yet) so there hasn't
// been documentation or example work beyond that.
//
// The only consumer of this API is the macOS app, but the API is built to
// be more general purpose.
#ifndef GHOSTTY_H
#define GHOSTTY_H

#ifdef __cplusplus
extern "C" {
#endif

#include <stdbool.h>
#include <stddef.h>
#include <stdint.h>
#include <sys/types.h>

//-------------------------------------------------------------------
// Macros

#define GHOSTTY_SUCCESS 0

//-------------------------------------------------------------------
// Types

// Opaque types
typedef void* ghostty_app_t;
typedef void* ghostty_config_t;
typedef void* ghostty_surface_t;
typedef void* ghostty_inspector_t;

// All the types below are fully defined and must be kept in sync with
// their Zig counterparts. Any changes to these types MUST have an associated
// Zig change.
typedef enum {
  GHOSTTY_PLATFORM_INVALID,
  GHOSTTY_PLATFORM_MACOS,
  GHOSTTY_PLATFORM_IOS,
} ghostty_platform_e;

typedef enum {
  GHOSTTY_CLIPBOARD_STANDARD,
  GHOSTTY_CLIPBOARD_SELECTION,
} ghostty_clipboard_e;

typedef enum {
  GHOSTTY_CLIPBOARD_REQUEST_PASTE,
  GHOSTTY_CLIPBOARD_REQUEST_OSC_52_READ,
  GHOSTTY_CLIPBOARD_REQUEST_OSC_52_WRITE,
} ghostty_clipboard_request_e;

typedef enum {
  GHOSTTY_MOUSE_RELEASE,
  GHOSTTY_MOUSE_PRESS,
} ghostty_input_mouse_state_e;

typedef enum {
  GHOSTTY_MOUSE_UNKNOWN,
  GHOSTTY_MOUSE_LEFT,
  GHOSTTY_MOUSE_RIGHT,
  GHOSTTY_MOUSE_MIDDLE,
} ghostty_input_mouse_button_e;

typedef enum {
  GHOSTTY_MOUSE_MOMENTUM_NONE,
  GHOSTTY_MOUSE_MOMENTUM_BEGAN,
  GHOSTTY_MOUSE_MOMENTUM_STATIONARY,
  GHOSTTY_MOUSE_MOMENTUM_CHANGED,
  GHOSTTY_MOUSE_MOMENTUM_ENDED,
  GHOSTTY_MOUSE_MOMENTUM_CANCELLED,
  GHOSTTY_MOUSE_MOMENTUM_MAY_BEGIN,
} ghostty_input_mouse_momentum_e;

typedef enum {
  GHOSTTY_COLOR_SCHEME_LIGHT = 0,
  GHOSTTY_COLOR_SCHEME_DARK = 1,
} ghostty_color_scheme_e;

// This is a packed struct (see src/input/mouse.zig) but the C standard
// afaik doesn't let us reliably define packed structs so we build it up
// from scratch.
typedef int ghostty_input_scroll_mods_t;

typedef enum {
  GHOSTTY_MODS_NONE = 0,
  GHOSTTY_MODS_SHIFT = 1 << 0,
  GHOSTTY_MODS_CTRL = 1 << 1,
  GHOSTTY_MODS_ALT = 1 << 2,
  GHOSTTY_MODS_SUPER = 1 << 3,
  GHOSTTY_MODS_CAPS = 1 << 4,
  GHOSTTY_MODS_NUM = 1 << 5,
  GHOSTTY_MODS_SHIFT_RIGHT = 1 << 6,
  GHOSTTY_MODS_CTRL_RIGHT = 1 << 7,
  GHOSTTY_MODS_ALT_RIGHT = 1 << 8,
  GHOSTTY_MODS_SUPER_RIGHT = 1 << 9,
} ghostty_input_mods_e;

typedef enum {
  GHOSTTY_ACTION_RELEASE,
  GHOSTTY_ACTION_PRESS,
  GHOSTTY_ACTION_REPEAT,
} ghostty_input_action_e;

typedef enum {
  GHOSTTY_KEY_INVALID,

  // a-z
  GHOSTTY_KEY_A,
  GHOSTTY_KEY_B,
  GHOSTTY_KEY_C,
  GHOSTTY_KEY_D,
  GHOSTTY_KEY_E,
  GHOSTTY_KEY_F,
  GHOSTTY_KEY_G,
  GHOSTTY_KEY_H,
  GHOSTTY_KEY_I,
  GHOSTTY_KEY_J,
  GHOSTTY_KEY_K,
  GHOSTTY_KEY_L,
  GHOSTTY_KEY_M,
  GHOSTTY_KEY_N,
  GHOSTTY_KEY_O,
  GHOSTTY_KEY_P,
  GHOSTTY_KEY_Q,
  GHOSTTY_KEY_R,
  GHOSTTY_KEY_S,
  GHOSTTY_KEY_T,
  GHOSTTY_KEY_U,
  GHOSTTY_KEY_V,
  GHOSTTY_KEY_W,
  GHOSTTY_KEY_X,
  GHOSTTY_KEY_Y,
  GHOSTTY_KEY_Z,

  // numbers
  GHOSTTY_KEY_ZERO,
  GHOSTTY_KEY_ONE,
  GHOSTTY_KEY_TWO,
  GHOSTTY_KEY_THREE,
  GHOSTTY_KEY_FOUR,
  GHOSTTY_KEY_FIVE,
  GHOSTTY_KEY_SIX,
  GHOSTTY_KEY_SEVEN,
  GHOSTTY_KEY_EIGHT,
  GHOSTTY_KEY_NINE,

  // puncuation
  GHOSTTY_KEY_SEMICOLON,
  GHOSTTY_KEY_SPACE,
  GHOSTTY_KEY_APOSTROPHE,
  GHOSTTY_KEY_COMMA,
  GHOSTTY_KEY_GRAVE_ACCENT,  // `
  GHOSTTY_KEY_PERIOD,
  GHOSTTY_KEY_SLASH,
  GHOSTTY_KEY_MINUS,
  GHOSTTY_KEY_PLUS,
  GHOSTTY_KEY_EQUAL,
  GHOSTTY_KEY_LEFT_BRACKET,   // [
  GHOSTTY_KEY_RIGHT_BRACKET,  // ]
  GHOSTTY_KEY_BACKSLASH,      // /

  // control
  GHOSTTY_KEY_UP,
  GHOSTTY_KEY_DOWN,
  GHOSTTY_KEY_RIGHT,
  GHOSTTY_KEY_LEFT,
  GHOSTTY_KEY_HOME,
  GHOSTTY_KEY_END,
  GHOSTTY_KEY_INSERT,
  GHOSTTY_KEY_DELETE,
  GHOSTTY_KEY_CAPS_LOCK,
  GHOSTTY_KEY_SCROLL_LOCK,
  GHOSTTY_KEY_NUM_LOCK,
  GHOSTTY_KEY_PAGE_UP,
  GHOSTTY_KEY_PAGE_DOWN,
  GHOSTTY_KEY_ESCAPE,
  GHOSTTY_KEY_ENTER,
  GHOSTTY_KEY_TAB,
  GHOSTTY_KEY_BACKSPACE,
  GHOSTTY_KEY_PRINT_SCREEN,
  GHOSTTY_KEY_PAUSE,

  // function keys
  GHOSTTY_KEY_F1,
  GHOSTTY_KEY_F2,
  GHOSTTY_KEY_F3,
  GHOSTTY_KEY_F4,
  GHOSTTY_KEY_F5,
  GHOSTTY_KEY_F6,
  GHOSTTY_KEY_F7,
  GHOSTTY_KEY_F8,
  GHOSTTY_KEY_F9,
  GHOSTTY_KEY_F10,
  GHOSTTY_KEY_F11,
  GHOSTTY_KEY_F12,
  GHOSTTY_KEY_F13,
  GHOSTTY_KEY_F14,
  GHOSTTY_KEY_F15,
  GHOSTTY_KEY_F16,
  GHOSTTY_KEY_F17,
  GHOSTTY_KEY_F18,
  GHOSTTY_KEY_F19,
  GHOSTTY_KEY_F20,
  GHOSTTY_KEY_F21,
  GHOSTTY_KEY_F22,
  GHOSTTY_KEY_F23,
  GHOSTTY_KEY_F24,
  GHOSTTY_KEY_F25,

  // keypad
  GHOSTTY_KEY_KP_0,
  GHOSTTY_KEY_KP_1,
  GHOSTTY_KEY_KP_2,
  GHOSTTY_KEY_KP_3,
  GHOSTTY_KEY_KP_4,
  GHOSTTY_KEY_KP_5,
  GHOSTTY_KEY_KP_6,
  GHOSTTY_KEY_KP_7,
  GHOSTTY_KEY_KP_8,
  GHOSTTY_KEY_KP_9,
  GHOSTTY_KEY_KP_DECIMAL,
  GHOSTTY_KEY_KP_DIVIDE,
  GHOSTTY_KEY_KP_MULTIPLY,
  GHOSTTY_KEY_KP_SUBTRACT,
  GHOSTTY_KEY_KP_ADD,
  GHOSTTY_KEY_KP_ENTER,
  GHOSTTY_KEY_KP_EQUAL,
  GHOSTTY_KEY_KP_SEPARATOR,
  GHOSTTY_KEY_KP_LEFT,
  GHOSTTY_KEY_KP_RIGHT,
  GHOSTTY_KEY_KP_UP,
  GHOSTTY_KEY_KP_DOWN,
  GHOSTTY_KEY_KP_PAGE_UP,
  GHOSTTY_KEY_KP_PAGE_DOWN,
  GHOSTTY_KEY_KP_HOME,
  GHOSTTY_KEY_KP_END,
  GHOSTTY_KEY_KP_INSERT,
  GHOSTTY_KEY_KP_DELETE,
  GHOSTTY_KEY_KP_BEGIN,

  // modifiers
  GHOSTTY_KEY_LEFT_SHIFT,
  GHOSTTY_KEY_LEFT_CONTROL,
  GHOSTTY_KEY_LEFT_ALT,
  GHOSTTY_KEY_LEFT_SUPER,
  GHOSTTY_KEY_RIGHT_SHIFT,
  GHOSTTY_KEY_RIGHT_CONTROL,
  GHOSTTY_KEY_RIGHT_ALT,
  GHOSTTY_KEY_RIGHT_SUPER,
} ghostty_input_key_e;

typedef struct {
  ghostty_input_action_e action;
  ghostty_input_mods_e mods;
  uint32_t keycode;
  const char* text;
  bool composing;
} ghostty_input_key_s;

typedef enum {
  GHOSTTY_TRIGGER_TRANSLATED,
  GHOSTTY_TRIGGER_PHYSICAL,
  GHOSTTY_TRIGGER_UNICODE,
} ghostty_input_trigger_tag_e;

typedef union {
  ghostty_input_key_e translated;
  ghostty_input_key_e physical;
  uint32_t unicode;
} ghostty_input_trigger_key_u;

typedef struct {
  ghostty_input_trigger_tag_e tag;
  ghostty_input_trigger_key_u key;
  ghostty_input_mods_e mods;
} ghostty_input_trigger_s;

typedef enum {
  GHOSTTY_BUILD_MODE_DEBUG,
  GHOSTTY_BUILD_MODE_RELEASE_SAFE,
  GHOSTTY_BUILD_MODE_RELEASE_FAST,
  GHOSTTY_BUILD_MODE_RELEASE_SMALL,
} ghostty_build_mode_e;

typedef struct {
  ghostty_build_mode_e build_mode;
  const char* version;
  uintptr_t version_len;
} ghostty_info_s;

typedef struct {
  const char* message;
} ghostty_diagnostic_s;

typedef struct {
  double tl_px_x;
  double tl_px_y;
  uint32_t offset_start;
  uint32_t offset_len;
} ghostty_selection_s;

typedef struct {
  void* nsview;
} ghostty_platform_macos_s;

typedef struct {
  void* uiview;
} ghostty_platform_ios_s;

typedef union {
  ghostty_platform_macos_s macos;
  ghostty_platform_ios_s ios;
} ghostty_platform_u;

typedef struct {
  ghostty_platform_e platform_tag;
  ghostty_platform_u platform;
  void* userdata;
  double scale_factor;
  float font_size;
  const char* working_directory;
  const char* command;
} ghostty_surface_config_s;

typedef struct {
  uint16_t columns;
  uint16_t rows;
  uint32_t width_px;
  uint32_t height_px;
  uint32_t cell_width_px;
  uint32_t cell_height_px;
} ghostty_surface_size_s;

// Config types

// config.Color
typedef struct {
  uint8_t r;
  uint8_t g;
  uint8_t b;
} ghostty_config_color_s;

// config.ColorList
typedef struct {
  const ghostty_config_color_s* colors;
  size_t len;
} ghostty_config_color_list_s;

// apprt.Target.Key
typedef enum {
  GHOSTTY_TARGET_APP,
  GHOSTTY_TARGET_SURFACE,
} ghostty_target_tag_e;

typedef union {
  ghostty_surface_t surface;
} ghostty_target_u;

typedef struct {
  ghostty_target_tag_e tag;
  ghostty_target_u target;
} ghostty_target_s;

// apprt.action.SplitDirection
typedef enum {
  GHOSTTY_SPLIT_DIRECTION_RIGHT,
  GHOSTTY_SPLIT_DIRECTION_DOWN,
  GHOSTTY_SPLIT_DIRECTION_LEFT,
  GHOSTTY_SPLIT_DIRECTION_UP,
} ghostty_action_split_direction_e;

// apprt.action.GotoSplit
typedef enum {
  GHOSTTY_GOTO_SPLIT_PREVIOUS,
  GHOSTTY_GOTO_SPLIT_NEXT,
  GHOSTTY_GOTO_SPLIT_UP,
  GHOSTTY_GOTO_SPLIT_LEFT,
  GHOSTTY_GOTO_SPLIT_DOWN,
  GHOSTTY_GOTO_SPLIT_RIGHT,
} ghostty_action_goto_split_e;

// apprt.action.ResizeSplit.Direction
typedef enum {
  GHOSTTY_RESIZE_SPLIT_UP,
  GHOSTTY_RESIZE_SPLIT_DOWN,
  GHOSTTY_RESIZE_SPLIT_LEFT,
  GHOSTTY_RESIZE_SPLIT_RIGHT,
} ghostty_action_resize_split_direction_e;

// apprt.action.ResizeSplit
typedef struct {
  uint16_t amount;
  ghostty_action_resize_split_direction_e direction;
} ghostty_action_resize_split_s;

// apprt.action.MoveTab
typedef struct {
  ssize_t amount;
} ghostty_action_move_tab_s;

// apprt.action.GotoTab
typedef enum {
  GHOSTTY_GOTO_TAB_PREVIOUS = -1,
  GHOSTTY_GOTO_TAB_NEXT = -2,
  GHOSTTY_GOTO_TAB_LAST = -3,
} ghostty_action_goto_tab_e;

// apprt.action.Fullscreen
typedef enum {
  GHOSTTY_FULLSCREEN_NATIVE,
  GHOSTTY_FULLSCREEN_NON_NATIVE,
  GHOSTTY_FULLSCREEN_NON_NATIVE_VISIBLE_MENU,
} ghostty_action_fullscreen_e;

// apprt.action.SecureInput
typedef enum {
  GHOSTTY_SECURE_INPUT_ON,
  GHOSTTY_SECURE_INPUT_OFF,
  GHOSTTY_SECURE_INPUT_TOGGLE,
} ghostty_action_secure_input_e;

// apprt.action.Inspector
typedef enum {
  GHOSTTY_INSPECTOR_TOGGLE,
  GHOSTTY_INSPECTOR_SHOW,
  GHOSTTY_INSPECTOR_HIDE,
} ghostty_action_inspector_e;

// apprt.action.QuitTimer
typedef enum {
  GHOSTTY_QUIT_TIMER_START,
  GHOSTTY_QUIT_TIMER_STOP,
} ghostty_action_quit_timer_e;

// apprt.action.DesktopNotification.C
typedef struct {
  const char* title;
  const char* body;
} ghostty_action_desktop_notification_s;

// apprt.action.SetTitle.C
typedef struct {
  const char* title;
} ghostty_action_set_title_s;

// apprt.action.Pwd.C
typedef struct {
  const char* pwd;
} ghostty_action_pwd_s;

// terminal.MouseShape
typedef enum {
  GHOSTTY_MOUSE_SHAPE_DEFAULT,
  GHOSTTY_MOUSE_SHAPE_CONTEXT_MENU,
  GHOSTTY_MOUSE_SHAPE_HELP,
  GHOSTTY_MOUSE_SHAPE_POINTER,
  GHOSTTY_MOUSE_SHAPE_PROGRESS,
  GHOSTTY_MOUSE_SHAPE_WAIT,
  GHOSTTY_MOUSE_SHAPE_CELL,
  GHOSTTY_MOUSE_SHAPE_CROSSHAIR,
  GHOSTTY_MOUSE_SHAPE_TEXT,
  GHOSTTY_MOUSE_SHAPE_VERTICAL_TEXT,
  GHOSTTY_MOUSE_SHAPE_ALIAS,
  GHOSTTY_MOUSE_SHAPE_COPY,
  GHOSTTY_MOUSE_SHAPE_MOVE,
  GHOSTTY_MOUSE_SHAPE_NO_DROP,
  GHOSTTY_MOUSE_SHAPE_NOT_ALLOWED,
  GHOSTTY_MOUSE_SHAPE_GRAB,
  GHOSTTY_MOUSE_SHAPE_GRABBING,
  GHOSTTY_MOUSE_SHAPE_ALL_SCROLL,
  GHOSTTY_MOUSE_SHAPE_COL_RESIZE,
  GHOSTTY_MOUSE_SHAPE_ROW_RESIZE,
  GHOSTTY_MOUSE_SHAPE_N_RESIZE,
  GHOSTTY_MOUSE_SHAPE_E_RESIZE,
  GHOSTTY_MOUSE_SHAPE_S_RESIZE,
  GHOSTTY_MOUSE_SHAPE_W_RESIZE,
  GHOSTTY_MOUSE_SHAPE_NE_RESIZE,
  GHOSTTY_MOUSE_SHAPE_NW_RESIZE,
  GHOSTTY_MOUSE_SHAPE_SE_RESIZE,
  GHOSTTY_MOUSE_SHAPE_SW_RESIZE,
  GHOSTTY_MOUSE_SHAPE_EW_RESIZE,
  GHOSTTY_MOUSE_SHAPE_NS_RESIZE,
  GHOSTTY_MOUSE_SHAPE_NESW_RESIZE,
  GHOSTTY_MOUSE_SHAPE_NWSE_RESIZE,
  GHOSTTY_MOUSE_SHAPE_ZOOM_IN,
  GHOSTTY_MOUSE_SHAPE_ZOOM_OUT,
} ghostty_action_mouse_shape_e;

// apprt.action.MouseVisibility
typedef enum {
  GHOSTTY_MOUSE_VISIBLE,
  GHOSTTY_MOUSE_HIDDEN,
} ghostty_action_mouse_visibility_e;

// apprt.action.MouseOverLink
typedef struct {
  const char* url;
  size_t len;
} ghostty_action_mouse_over_link_s;

// apprt.action.SizeLimit
typedef struct {
  uint32_t min_width;
  uint32_t min_height;
  uint32_t max_width;
  uint32_t max_height;
} ghostty_action_size_limit_s;

// apprt.action.InitialSize
typedef struct {
  uint32_t width;
  uint32_t height;
} ghostty_action_initial_size_s;

// apprt.action.CellSize
typedef struct {
  uint32_t width;
  uint32_t height;
} ghostty_action_cell_size_s;

// renderer.Health
typedef enum {
  GHOSTTY_RENDERER_HEALTH_OK,
  GHOSTTY_RENDERER_HEALTH_UNHEALTHY,
} ghostty_action_renderer_health_e;

// apprt.action.KeySequence
typedef struct {
  bool active;
  ghostty_input_trigger_s trigger;
} ghostty_action_key_sequence_s;

// apprt.action.ColorKind
typedef enum {
  GHOSTTY_ACTION_COLOR_KIND_FOREGROUND = -1,
  GHOSTTY_ACTION_COLOR_KIND_BACKGROUND = -2,
  GHOSTTY_ACTION_COLOR_KIND_CURSOR = -3,
} ghostty_action_color_kind_e;

// apprt.action.ColorChange
typedef struct {
  ghostty_action_color_kind_e kind;
  uint8_t r;
  uint8_t g;
  uint8_t b;
} ghostty_action_color_change_s;

// apprt.action.ConfigChange
typedef struct {
  ghostty_config_t config;
} ghostty_action_config_change_s;

// apprt.action.ReloadConfig
typedef struct {
  bool soft;
} ghostty_action_reload_config_s;

// apprt.Action.Key
typedef enum {
  GHOSTTY_ACTION_QUIT,
  GHOSTTY_ACTION_NEW_WINDOW,
  GHOSTTY_ACTION_NEW_TAB,
  GHOSTTY_ACTION_CLOSE_TAB,
  GHOSTTY_ACTION_NEW_SPLIT,
  GHOSTTY_ACTION_CLOSE_ALL_WINDOWS,
  GHOSTTY_ACTION_TOGGLE_FULLSCREEN,
  GHOSTTY_ACTION_TOGGLE_TAB_OVERVIEW,
  GHOSTTY_ACTION_TOGGLE_WINDOW_DECORATIONS,
  GHOSTTY_ACTION_TOGGLE_QUICK_TERMINAL,
  GHOSTTY_ACTION_TOGGLE_VISIBILITY,
  GHOSTTY_ACTION_MOVE_TAB,
  GHOSTTY_ACTION_GOTO_TAB,
  GHOSTTY_ACTION_GOTO_SPLIT,
  GHOSTTY_ACTION_RESIZE_SPLIT,
  GHOSTTY_ACTION_EQUALIZE_SPLITS,
  GHOSTTY_ACTION_TOGGLE_SPLIT_ZOOM,
  GHOSTTY_ACTION_PRESENT_TERMINAL,
  GHOSTTY_ACTION_SIZE_LIMIT,
  GHOSTTY_ACTION_INITIAL_SIZE,
  GHOSTTY_ACTION_CELL_SIZE,
  GHOSTTY_ACTION_INSPECTOR,
  GHOSTTY_ACTION_RENDER_INSPECTOR,
  GHOSTTY_ACTION_DESKTOP_NOTIFICATION,
  GHOSTTY_ACTION_SET_TITLE,
  GHOSTTY_ACTION_PWD,
  GHOSTTY_ACTION_MOUSE_SHAPE,
  GHOSTTY_ACTION_MOUSE_VISIBILITY,
  GHOSTTY_ACTION_MOUSE_OVER_LINK,
  GHOSTTY_ACTION_RENDERER_HEALTH,
  GHOSTTY_ACTION_OPEN_CONFIG,
  GHOSTTY_ACTION_QUIT_TIMER,
  GHOSTTY_ACTION_SECURE_INPUT,
  GHOSTTY_ACTION_KEY_SEQUENCE,
  GHOSTTY_ACTION_COLOR_CHANGE,
  GHOSTTY_ACTION_RELOAD_CONFIG,
  GHOSTTY_ACTION_CONFIG_CHANGE,
} ghostty_action_tag_e;

typedef union {
  ghostty_action_split_direction_e new_split;
  ghostty_action_fullscreen_e toggle_fullscreen;
  ghostty_action_move_tab_s move_tab;
  ghostty_action_goto_tab_e goto_tab;
  ghostty_action_goto_split_e goto_split;
  ghostty_action_resize_split_s resize_split;
  ghostty_action_size_limit_s size_limit;
  ghostty_action_initial_size_s initial_size;
  ghostty_action_cell_size_s cell_size;
  ghostty_action_inspector_e inspector;
  ghostty_action_desktop_notification_s desktop_notification;
  ghostty_action_set_title_s set_title;
  ghostty_action_pwd_s pwd;
  ghostty_action_mouse_shape_e mouse_shape;
  ghostty_action_mouse_visibility_e mouse_visibility;
  ghostty_action_mouse_over_link_s mouse_over_link;
  ghostty_action_renderer_health_e renderer_health;
  ghostty_action_quit_timer_e quit_timer;
  ghostty_action_secure_input_e secure_input;
  ghostty_action_key_sequence_s key_sequence;
  ghostty_action_color_change_s color_change;
  ghostty_action_reload_config_s reload_config;
  ghostty_action_config_change_s config_change;
} ghostty_action_u;

typedef struct {
  ghostty_action_tag_e tag;
  ghostty_action_u action;
} ghostty_action_s;

typedef void (*ghostty_runtime_wakeup_cb)(void*);
typedef void (*ghostty_runtime_read_clipboard_cb)(void*,
                                                  ghostty_clipboard_e,
                                                  void*);
typedef void (*ghostty_runtime_confirm_read_clipboard_cb)(
    void*,
    const char*,
    void*,
    ghostty_clipboard_request_e);
typedef void (*ghostty_runtime_write_clipboard_cb)(void*,
                                                   const char*,
                                                   ghostty_clipboard_e,
                                                   bool);
typedef void (*ghostty_runtime_close_surface_cb)(void*, bool);
typedef void (*ghostty_runtime_action_cb)(ghostty_app_t,
                                          ghostty_target_s,
                                          ghostty_action_s);

typedef struct {
  void* userdata;
  bool supports_selection_clipboard;
  ghostty_runtime_wakeup_cb wakeup_cb;
  ghostty_runtime_action_cb action_cb;
  ghostty_runtime_read_clipboard_cb read_clipboard_cb;
  ghostty_runtime_confirm_read_clipboard_cb confirm_read_clipboard_cb;
  ghostty_runtime_write_clipboard_cb write_clipboard_cb;
  ghostty_runtime_close_surface_cb close_surface_cb;
} ghostty_runtime_config_s;

//-------------------------------------------------------------------
// Published API

int ghostty_init(void);
void ghostty_cli_main(uintptr_t, char**);
ghostty_info_s ghostty_info(void);

ghostty_config_t ghostty_config_new();
void ghostty_config_free(ghostty_config_t);
ghostty_config_t ghostty_config_clone(ghostty_config_t);
void ghostty_config_load_cli_args(ghostty_config_t);
void ghostty_config_load_default_files(ghostty_config_t);
void ghostty_config_load_recursive_files(ghostty_config_t);
void ghostty_config_finalize(ghostty_config_t);
bool ghostty_config_get(ghostty_config_t, void*, const char*, uintptr_t);
ghostty_input_trigger_s ghostty_config_trigger(ghostty_config_t,
                                               const char*,
                                               uintptr_t);
uint32_t ghostty_config_diagnostics_count(ghostty_config_t);
ghostty_diagnostic_s ghostty_config_get_diagnostic(ghostty_config_t, uint32_t);
void ghostty_config_open();

ghostty_app_t ghostty_app_new(const ghostty_runtime_config_s*,
                              ghostty_config_t);
void ghostty_app_free(ghostty_app_t);
void ghostty_app_tick(ghostty_app_t);
void* ghostty_app_userdata(ghostty_app_t);
void ghostty_app_set_focus(ghostty_app_t, bool);
bool ghostty_app_key(ghostty_app_t, ghostty_input_key_s);
bool ghostty_app_key_is_binding(ghostty_app_t, ghostty_input_key_s);
void ghostty_app_keyboard_changed(ghostty_app_t);
void ghostty_app_open_config(ghostty_app_t);
void ghostty_app_update_config(ghostty_app_t, ghostty_config_t);
bool ghostty_app_needs_confirm_quit(ghostty_app_t);
bool ghostty_app_has_global_keybinds(ghostty_app_t);
void ghostty_app_set_color_scheme(ghostty_app_t, ghostty_color_scheme_e);

ghostty_surface_config_s ghostty_surface_config_new();

ghostty_surface_t ghostty_surface_new(ghostty_app_t, ghostty_surface_config_s*);
void ghostty_surface_free(ghostty_surface_t);
void* ghostty_surface_userdata(ghostty_surface_t);
ghostty_app_t ghostty_surface_app(ghostty_surface_t);
ghostty_surface_config_s ghostty_surface_inherited_config(ghostty_surface_t);
void ghostty_surface_update_config(ghostty_surface_t, ghostty_config_t);
bool ghostty_surface_needs_confirm_quit(ghostty_surface_t);
void ghostty_surface_refresh(ghostty_surface_t);
void ghostty_surface_draw(ghostty_surface_t);
void ghostty_surface_set_content_scale(ghostty_surface_t, double, double);
void ghostty_surface_set_focus(ghostty_surface_t, bool);
void ghostty_surface_set_occlusion(ghostty_surface_t, bool);
void ghostty_surface_set_size(ghostty_surface_t, uint32_t, uint32_t);
ghostty_surface_size_s ghostty_surface_size(ghostty_surface_t);
void ghostty_surface_set_color_scheme(ghostty_surface_t,
                                      ghostty_color_scheme_e);
ghostty_input_mods_e ghostty_surface_key_translation_mods(ghostty_surface_t,
                                                          ghostty_input_mods_e);
bool ghostty_surface_key(ghostty_surface_t, ghostty_input_key_s);
bool ghostty_surface_key_is_binding(ghostty_surface_t, ghostty_input_key_s);
void ghostty_surface_text(ghostty_surface_t, const char*, uintptr_t);
bool ghostty_surface_mouse_captured(ghostty_surface_t);
bool ghostty_surface_mouse_button(ghostty_surface_t,
                                  ghostty_input_mouse_state_e,
                                  ghostty_input_mouse_button_e,
                                  ghostty_input_mods_e);
void ghostty_surface_mouse_pos(ghostty_surface_t,
                               double,
                               double,
                               ghostty_input_mods_e);
void ghostty_surface_mouse_scroll(ghostty_surface_t,
                                  double,
                                  double,
                                  ghostty_input_scroll_mods_t);
void ghostty_surface_mouse_pressure(ghostty_surface_t, uint32_t, double);
void ghostty_surface_ime_point(ghostty_surface_t, double*, double*);
void ghostty_surface_request_close(ghostty_surface_t);
void ghostty_surface_split(ghostty_surface_t, ghostty_action_split_direction_e);
void ghostty_surface_split_focus(ghostty_surface_t,
                                 ghostty_action_goto_split_e);
void ghostty_surface_split_resize(ghostty_surface_t,
                                  ghostty_action_resize_split_direction_e,
                                  uint16_t);
void ghostty_surface_split_equalize(ghostty_surface_t);
bool ghostty_surface_binding_action(ghostty_surface_t, const char*, uintptr_t);
void ghostty_surface_complete_clipboard_request(ghostty_surface_t,
                                                const char*,
                                                void*,
                                                bool);
bool ghostty_surface_has_selection(ghostty_surface_t);
uintptr_t ghostty_surface_selection(ghostty_surface_t, char*, uintptr_t);

#ifdef __APPLE__
void ghostty_surface_set_display_id(ghostty_surface_t, uint32_t);
void* ghostty_surface_quicklook_font(ghostty_surface_t);
uintptr_t ghostty_surface_quicklook_word(ghostty_surface_t,
                                         char*,
                                         uintptr_t,
                                         ghostty_selection_s*);
bool ghostty_surface_selection_info(ghostty_surface_t, ghostty_selection_s*);
#endif

ghostty_inspector_t ghostty_surface_inspector(ghostty_surface_t);
void ghostty_inspector_free(ghostty_surface_t);
void ghostty_inspector_set_focus(ghostty_inspector_t, bool);
void ghostty_inspector_set_content_scale(ghostty_inspector_t, double, double);
void ghostty_inspector_set_size(ghostty_inspector_t, uint32_t, uint32_t);
void ghostty_inspector_mouse_button(ghostty_inspector_t,
                                    ghostty_input_mouse_state_e,
                                    ghostty_input_mouse_button_e,
                                    ghostty_input_mods_e);
void ghostty_inspector_mouse_pos(ghostty_inspector_t, double, double);
void ghostty_inspector_mouse_scroll(ghostty_inspector_t,
                                    double,
                                    double,
                                    ghostty_input_scroll_mods_t);
void ghostty_inspector_key(ghostty_inspector_t,
                           ghostty_input_action_e,
                           ghostty_input_key_e,
                           ghostty_input_mods_e);
void ghostty_inspector_text(ghostty_inspector_t, const char*);

#ifdef __APPLE__
bool ghostty_inspector_metal_init(ghostty_inspector_t, void*);
void ghostty_inspector_metal_render(ghostty_inspector_t, void*, void*);
bool ghostty_inspector_metal_shutdown(ghostty_inspector_t);
#endif

// APIs I'd like to get rid of eventually but are still needed for now.
// Don't use these unless you know what you're doing.
void ghostty_set_window_background_blur(ghostty_app_t, void*);

#ifdef __cplusplus
}
#endif

#endif /* GHOSTTY_H */
